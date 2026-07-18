import Foundation

protocol UsageExecutableResolving: AnyObject {
    func revalidate(_ candidate: ExecutableCandidate) -> Bool
}

extension CodexExecutableResolver: UsageExecutableResolving {}

protocol CodexAppServerSession: AnyObject {
    func write(_ data: Data) throws
    func closeInput()
    func terminate()
    func forceTerminate()
}

protocol CodexAppServerSessionFactory: AnyObject {
    func start(
        executableURL: URL,
        arguments: [String],
        onStandardOutput: @escaping (Data) -> Void,
        onStandardError: @escaping (Data) -> Void,
        onExit: @escaping () -> Void
    ) throws -> any CodexAppServerSession
}

final class CodexAppServerStdioProvider: UsageProvider {
    let snapshots: AsyncStream<QuotaSnapshot>
    private let coordinator: UsageCoordinator

    init(
        candidate: ExecutableCandidate,
        resolver: any UsageExecutableResolving,
        sessionFactory: any CodexAppServerSessionFactory,
        scheduler: any UsageScheduling = DispatchUsageScheduler(),
        requestTimeout: TimeInterval = 15
    ) {
        var continuation: AsyncStream<QuotaSnapshot>.Continuation?
        snapshots = AsyncStream { continuation = $0 }
        coordinator = UsageCoordinator(
            candidate: candidate,
            resolver: resolver,
            sessionFactory: sessionFactory,
            scheduler: scheduler,
            requestTimeout: requestTimeout,
            publish: { snapshot in continuation?.yield(snapshot) }
        )
    }

    deinit {
        let coordinator = coordinator
        Task { await coordinator.stop() }
    }

    func start(mode: ConnectionMode) async { await coordinator.start(mode: mode) }
    func refresh() async { await coordinator.refresh() }
    func stop() async { await coordinator.stop() }
    func wake() async { await coordinator.refresh() }
}

private actor UsageCoordinator {
    private struct Connection {
        let generation: UInt64
        let session: any CodexAppServerSession
        let client: CodexRPCClient
    }

    private let candidate: ExecutableCandidate
    private let resolver: any UsageExecutableResolving
    private let sessionFactory: any CodexAppServerSessionFactory
    private let scheduler: any UsageScheduling
    private let requestTimeout: TimeInterval
    private let publish: (QuotaSnapshot) -> Void
    private var mode: ConnectionMode?
    private var generation: UInt64 = 0
    private var connection: Connection?
    private var connecting = false
    private var reading = false
    private var retryTask: (any UsageScheduledTask)?
    private var periodicTask: (any UsageScheduledTask)?
    private var terminationTask: (any UsageScheduledTask)?
    private var policy = RefreshPolicy()

    init(candidate: ExecutableCandidate, resolver: any UsageExecutableResolving, sessionFactory: any CodexAppServerSessionFactory, scheduler: any UsageScheduling, requestTimeout: TimeInterval, publish: @escaping (QuotaSnapshot) -> Void) {
        self.candidate = candidate
        self.resolver = resolver
        self.sessionFactory = sessionFactory
        self.scheduler = scheduler
        self.requestTimeout = requestTimeout
        self.publish = publish
    }

    func start(mode newMode: ConnectionMode) async {
        if mode == newMode, (connection != nil || connecting) { return }
        stopCurrentConnection()
        mode = newMode
        schedulePeriodicRefresh()
        Task { await self.connect() }
    }

    func refresh() async {
        guard mode != nil else { return }
        if let connection, mode == .realtime {
            guard !reading else { return }
            reading = true
            Task { await self.readRateLimits(connection) }
        } else if !connecting {
            Task { await self.connect() }
        }
    }

    func stop() {
        mode = nil
        retryTask?.cancel()
        periodicTask?.cancel()
        terminationTask?.cancel()
        retryTask = nil
        periodicTask = nil
        terminationTask = nil
        stopCurrentConnection()
    }

    private func connect() async {
        guard mode != nil, !connecting, connection == nil else { return }
        connecting = true
        generation += 1
        let currentGeneration = generation
        guard resolver.revalidate(candidate) else {
            connecting = false
            publishState(.incompatible("Codex executable trust validation failed"))
            scheduleRetry()
            return
        }

        do {
            let session = try sessionFactory.start(
                executableURL: candidate.canonicalURL,
                arguments: ["app-server", "--stdio"],
                onStandardOutput: { [weak self] data in
                    Task { await self?.receiveStandardOutput(data, generation: currentGeneration) }
                },
                onStandardError: { [weak self] data in
                    Task { await self?.receiveStandardError(data, generation: currentGeneration) }
                },
                onExit: { [weak self] in
                    Task { await self?.sessionExited(generation: currentGeneration) }
                }
            )
            let client = CodexRPCClient(
                send: { try session.write($0) },
                onRateLimitsUpdated: { [weak self] data in
                    Task { await self?.receiveRateLimitUpdate(data, generation: currentGeneration) }
                },
                requestTimeout: requestTimeout
            )
            let newConnection = Connection(generation: currentGeneration, session: session, client: client)
            connection = newConnection
            connecting = false
            _ = try await client.request(method: "initialize", params: [
                "clientInfo": ["name": "quota_pet", "title": "QuotaPet", "version": "0.1.0"],
            ])
            guard connection?.generation == currentGeneration else { return }
            try await client.sendInitialized(params: [:])
            reading = true
            await readRateLimits(newConnection)
        } catch {
            connecting = false
            fail(error, generation: currentGeneration)
        }
    }

    private func readRateLimits(_ connection: Connection) async {
        defer { reading = false }
        do {
            let data = try await connection.client.request(method: "account/rateLimits/read")
            guard self.connection?.generation == connection.generation else { return }
            publishParsed(data)
            if mode == .energySaver { closeEnergyConnection(connection) }
        } catch {
            fail(error, generation: connection.generation)
        }
    }

    private func receiveStandardOutput(_ data: Data, generation: UInt64) async {
        guard let connection, connection.generation == generation else { return }
        do {
            try await connection.client.receive(data)
        } catch {
            fail(error, generation: generation)
        }
    }

    private func receiveStandardError(_ data: Data, generation: UInt64) async {
        guard let connection, connection.generation == generation else { return }
        await connection.client.appendStandardError(data)
    }

    private func receiveRateLimitUpdate(_ data: Data, generation: UInt64) {
        guard connection?.generation == generation, mode == .realtime else { return }
        publishParsed(data)
    }

    private func sessionExited(generation: UInt64) {
        guard connection?.generation == generation else { return }
        connection = nil
        reading = false
        publishState(.unavailable("Codex app-server exited"))
        scheduleRetry()
    }

    private func publishParsed(_ data: Data) {
        do {
            let snapshot = try QuotaParser.parse(data: data)
            publish(snapshot)
            if snapshot.state == .ready, !snapshot.windows.isEmpty {
                policy.record(snapshot: snapshot)
                retryTask?.cancel()
                retryTask = nil
            } else {
                scheduleRetry()
            }
        } catch {
            publishState(.unavailable("Invalid Codex usage response"))
            scheduleRetry()
        }
    }

    private func fail(_ error: Error, generation: UInt64) {
        guard connection?.generation == generation || connecting else { return }
        if connection?.generation == generation {
            closeConnection()
        }
        connecting = false
        reading = false
        let state: ConnectionState
        if let error = error as? CodexRPCClientError, error == .requestTimedOut {
            state = .unavailable("Codex app-server request timed out")
        } else {
            state = .unavailable("Codex app-server request failed")
        }
        publishState(state)
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard mode != nil else { return }
        retryTask?.cancel()
        let delay = policy.recordFailure()
        retryTask = scheduler.schedule(after: delay) { [weak self] in
            Task { await self?.refresh() }
        }
    }

    private func schedulePeriodicRefresh() {
        periodicTask?.cancel()
        periodicTask = scheduler.schedule(after: RefreshPolicy.periodicRefreshInterval) { [weak self] in
            Task { await self?.periodicRefreshFired() }
        }
    }

    private func periodicRefreshFired() async {
        schedulePeriodicRefresh()
        await refresh()
    }

    private func closeEnergyConnection(_ current: Connection) {
        guard connection?.generation == current.generation else { return }
        connection = nil
        gracefullyTerminate(current.session)
    }

    private func stopCurrentConnection() {
        generation += 1
        closeConnection()
        connecting = false
        reading = false
    }

    private func closeConnection() {
        guard let current = connection else { return }
        connection = nil
        gracefullyTerminate(current.session)
    }

    private func gracefullyTerminate(_ session: any CodexAppServerSession) {
        session.closeInput()
        session.terminate()
        terminationTask?.cancel()
        terminationTask = scheduler.schedule(after: 1) { [weak session] in
            session?.forceTerminate()
        }
    }

    private func publishState(_ state: ConnectionState) {
        publish(QuotaSnapshot(planType: nil, windows: [], updatedAt: Date(), state: state))
    }
}
