import Foundation
import Darwin

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

enum CodexAppServerSessionError: Error {
    case inputClosed
}

final class FoundationCodexAppServerSessionFactory: CodexAppServerSessionFactory {
    func start(
        executableURL: URL,
        arguments: [String],
        onStandardOutput: @escaping (Data) -> Void,
        onStandardError: @escaping (Data) -> Void,
        onExit: @escaping () -> Void
    ) throws -> any CodexAppServerSession {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        let session = FoundationCodexAppServerSession(
            process: process,
            input: input.fileHandleForWriting,
            output: output.fileHandleForReading,
            error: error.fileHandleForReading,
            onStandardOutput: onStandardOutput,
            onStandardError: onStandardError,
            onExit: onExit
        )
        session.installHandlers()
        try process.run()
        return session
    }
}

final class FoundationCodexAppServerSession: CodexAppServerSession, @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let error: FileHandle
    private let onStandardOutput: (Data) -> Void
    private let onStandardError: (Data) -> Void
    private let onExit: () -> Void
    private var inputClosed = false
    private var terminationQueued = false
    private let ioQueue: DispatchQueue

    init(process: Process, input: FileHandle, output: FileHandle, error: FileHandle, onStandardOutput: @escaping (Data) -> Void, onStandardError: @escaping (Data) -> Void, onExit: @escaping () -> Void, ioQueue: DispatchQueue = DispatchQueue(label: "QuotaPet.CodexAppServerSession.io")) {
        self.process = process
        self.input = input
        self.output = output
        self.error = error
        self.onStandardOutput = onStandardOutput
        self.onStandardError = onStandardError
        self.onExit = onExit
        self.ioQueue = ioQueue
    }

    func installHandlers() {
        output.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.consumeReadableEvent(handle, deliver: self.onStandardOutput)
        }
        error.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.consumeReadableEvent(handle, deliver: self.onStandardError)
        }
        process.terminationHandler = { [weak self] _ in self?.finishExit() }
    }

    func write(_ data: Data) throws {
        try lock.withLock {
            guard !inputClosed else { throw CodexAppServerSessionError.inputClosed }
            try input.write(contentsOf: data)
        }
    }

    func closeInput() {
        lock.withLock {
            guard !inputClosed else { return }
            inputClosed = true
            try? input.close()
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func forceTerminate() {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    private func consumeReadableEvent(_ handle: FileHandle, deliver: @escaping (Data) -> Void) {
        let data = handle.availableData
        guard !data.isEmpty else {
            handle.readabilityHandler = nil
            return
        }
        ioQueue.async { deliver(data) }
    }

    private func finishExit() {
        let shouldDrain = lock.withLock { () -> Bool in
            guard !terminationQueued else { return false }
            terminationQueued = true
            inputClosed = true
            return true
        }
        guard shouldDrain else { return }
        ioQueue.async { [weak self] in self?.drainAndNotifyExit() }
    }

    private func drainAndNotifyExit() {
        output.readabilityHandler = nil
        error.readabilityHandler = nil
        process.terminationHandler = nil
        deliver(output.readDataToEndOfFile(), to: onStandardOutput)
        deliver(error.readDataToEndOfFile(), to: onStandardError)
        try? input.close()
        onExit()
    }

    private func deliver(_ data: Data, to callback: (Data) -> Void) {
        guard !data.isEmpty else { return }
        callback(data)
    }
}

final class CodexAppServerStdioProvider: UsageProvider {
    let snapshots: AsyncStream<QuotaSnapshot>
    private let continuation: AsyncStream<QuotaSnapshot>.Continuation
    private let coordinator: UsageCoordinator

    init(
        candidate: ExecutableCandidate,
        resolver: any UsageExecutableResolving,
        sessionFactory: any CodexAppServerSessionFactory,
        scheduler: any UsageScheduling = DispatchUsageScheduler(),
        requestTimeout: TimeInterval = 15
    ) {
        var savedContinuation: AsyncStream<QuotaSnapshot>.Continuation?
        snapshots = AsyncStream { savedContinuation = $0 }
        continuation = savedContinuation!
        coordinator = UsageCoordinator(
            candidate: candidate,
            resolver: resolver,
            sessionFactory: sessionFactory,
            scheduler: scheduler,
            requestTimeout: requestTimeout,
            publish: { snapshot in savedContinuation?.yield(snapshot) }
        )
        savedContinuation?.onTermination = { [weak coordinator] _ in
            Task { await coordinator?.stop() }
        }
    }

    deinit {
        let coordinator = coordinator
        continuation.finish()
        Task { await coordinator.stop() }
    }

    func start(mode: ConnectionMode) async { await coordinator.start(mode: mode) }
    func refresh() async { await coordinator.refresh() }
    func recover(mode: ConnectionMode, restartIfStopped: Bool) async { await coordinator.recover(mode: mode, restartIfStopped: restartIfStopped) }
    func stop() async { await coordinator.stop() }
    func standardErrorTail() async -> Data { await coordinator.standardErrorTail() }
}

private actor UsageCoordinator {
    private struct Connection {
        let generation: UInt64
        let session: any CodexAppServerSession
        let client: CodexRPCClient
    }

    private struct Operation {
        let id: UInt64
        let task: Task<Void, Never>
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
    private var handshaking = false
    private var reading = false
    private var retryTask: (any UsageScheduledTask)?
    private var periodicTask: (any UsageScheduledTask)?
    private var forceTasks: [UInt64: any UsageScheduledTask] = [:]
    private var terminationWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]
    private var operation: Operation?
    private var nextOperationID: UInt64 = 0
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
        if mode == newMode, (connection != nil || connecting || operation != nil) { return }
        retryTask?.cancel()
        retryTask = nil
        await stopCurrentConnection()
        guard !Task.isCancelled else { return }
        mode = newMode
        schedulePeriodicRefresh()
        beginConnect()
    }

    func refresh() async {
        guard mode != nil else { return }
        if let task = operation?.task {
            guard mode == .energySaver, connection == nil else { return }
            await task.value
        }
        guard !Task.isCancelled, mode != nil else { return }
        await waitForTerminations()
        guard !Task.isCancelled, mode != nil else { return }
        if let connection, mode == .realtime {
            guard !handshaking, !reading else { return }
            reading = true
            beginRead(connection)
        } else if !connecting {
            beginConnect()
        }
    }

    func recover(mode newMode: ConnectionMode, restartIfStopped: Bool) async {
        if mode == nil {
            guard restartIfStopped else { return }
            mode = newMode
            schedulePeriodicRefresh()
        } else if mode != newMode {
            await start(mode: newMode)
        }

        if let task = operation?.task {
            await task.value
        }
        guard !Task.isCancelled, mode != nil else { return }

        await waitForTerminations()
        guard !Task.isCancelled, mode != nil else { return }
        if let connection, mode == .realtime {
            guard !handshaking, !reading else { return }
            reading = true
            beginRead(connection)
        } else if !connecting {
            beginConnect()
        }
        await operation?.task.value
    }

    func stop() async {
        mode = nil
        retryTask?.cancel()
        periodicTask?.cancel()
        retryTask = nil
        periodicTask = nil
        await stopCurrentConnection()
    }

    private func beginConnect() {
        guard operation == nil else { return }
        nextOperationID += 1
        let id = nextOperationID
        let task = Task { [weak self] in
            await self?.connect()
            await self?.operationCompleted(id: id)
        }
        operation = Operation(id: id, task: task)
    }

    private func beginRead(_ connection: Connection) {
        guard operation == nil else { return }
        nextOperationID += 1
        let id = nextOperationID
        let task = Task { [weak self] in
            await self?.readRateLimits(connection)
            await self?.operationCompleted(id: id)
        }
        operation = Operation(id: id, task: task)
    }

    private func operationCompleted(id: UInt64) {
        guard operation?.id == id else { return }
        operation = nil
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
            handshaking = true
            _ = try await client.request(method: "initialize", params: [
                "clientInfo": ["name": "quota_pet", "title": "QuotaPet", "version": "0.1.0"],
            ])
            guard connection?.generation == currentGeneration else { return }
            try await client.sendInitialized(params: [:])
            handshaking = false
            reading = true
            await readRateLimits(newConnection)
        } catch {
            connecting = false
            handshaking = false
            await fail(error, generation: currentGeneration)
        }
    }

    private func readRateLimits(_ connection: Connection) async {
        defer { reading = false }
        do {
            let data = try await connection.client.request(method: "account/rateLimits/read")
            guard self.connection?.generation == connection.generation else { return }
            publishParsed(data)
            if mode == .energySaver { await closeEnergyConnection(connection) }
        } catch {
            await fail(error, generation: connection.generation)
        }
    }

    private func receiveStandardOutput(_ data: Data, generation: UInt64) async {
        guard let connection, connection.generation == generation else { return }
        do {
            try await connection.client.receive(data)
        } catch {
            publishState(.unavailable("Codex app-server response was invalid"))
            scheduleRetry()
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

    private func sessionExited(generation: UInt64) async {
        completeTermination(generation: generation)
        guard let exited = connection, exited.generation == generation else { return }
        connection = nil
        handshaking = false
        reading = false
        await exited.client.cancelPending()
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

    private func fail(_ error: Error, generation: UInt64) async {
        guard connection?.generation == generation || connecting else { return }
        let shouldClose = connection?.generation == generation
        connecting = false
        handshaking = false
        reading = false
        let state: ConnectionState
        if let error = error as? CodexRPCClientError, error == .requestTimedOut {
            state = .unavailable("Codex app-server request timed out")
        } else {
            state = .unavailable("Codex app-server request failed")
        }
        publishState(state)
        if shouldClose { await closeConnection() }
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard mode != nil else { return }
        retryTask?.cancel()
        let delay = policy.recordFailure()
        retryTask = scheduler.schedule(after: delay) { [weak self] in
            Task { await self?.scheduledRecovery() }
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
        await scheduledRecovery()
    }

    private func scheduledRecovery() async {
        guard let mode else { return }
        await recover(mode: mode, restartIfStopped: false)
    }

    private func closeEnergyConnection(_ current: Connection) async {
        guard connection?.generation == current.generation else { return }
        connection = nil
        await gracefullyTerminate(current)
    }

    private func stopCurrentConnection() async {
        generation += 1
        operation?.task.cancel()
        operation = nil
        connecting = false
        handshaking = false
        reading = false
        await closeConnection()
        await waitForTerminations()
    }

    private func closeConnection() async {
        guard let current = connection else { return }
        connection = nil
        await gracefullyTerminate(current)
    }

    private func gracefullyTerminate(_ connection: Connection) async {
        let generation = connection.generation
        await withCheckedContinuation { continuation in
            terminationWaiters[generation, default: []].append(continuation)
            guard forceTasks[generation] == nil else { return }
            connection.session.closeInput()
            connection.session.terminate()
            forceTasks[generation] = scheduler.schedule(after: 1) { [weak self, weak session = connection.session] in
                session?.forceTerminate()
                Task { await self?.forceDeadlineReached(generation: generation) }
            }
        }
    }

    private func forceDeadlineReached(generation: UInt64) {
        completeTermination(generation: generation)
    }

    private func completeTermination(generation: UInt64) {
        forceTasks.removeValue(forKey: generation)?.cancel()
        let waiters = terminationWaiters.removeValue(forKey: generation) ?? []
        waiters.forEach { $0.resume() }
    }

    private func waitForTerminations() async {
        for generation in Array(terminationWaiters.keys) {
            await withCheckedContinuation { continuation in
                guard terminationWaiters[generation] != nil else {
                    continuation.resume()
                    return
                }
                terminationWaiters[generation, default: []].append(continuation)
            }
        }
    }

    func standardErrorTail() async -> Data {
        guard let connection else { return Data() }
        return await connection.client.standardErrorTail()
    }

    private func publishState(_ state: ConnectionState) {
        publish(QuotaSnapshot(planType: nil, windows: [], updatedAt: Date(), state: state))
    }
}
