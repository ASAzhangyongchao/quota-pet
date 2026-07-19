import Foundation
import XCTest
@testable import QuotaPet

final class CodexAppServerStdioProviderTests: XCTestCase {
    func testRealtimePerformsOnlyTheRequiredHandshakeAndKeepsSessionOpen() async throws {
        let resolver = TestResolver(isTrusted: true)
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(
            candidate: testCandidate(), resolver: resolver, sessionFactory: factory, scheduler: scheduler, requestTimeout: 15
        )
        let snapshots = SnapshotRecorder(stream: provider.snapshots)

        await provider.start(mode: .realtime)
        try await eventually("realtime initialize request") { factory.sessions.count == 1 && factory.sessions[0].messages.count == 1 }
        let session = factory.sessions[0]
        XCTAssertEqual(factory.executables, [testCandidate().canonicalURL])
        XCTAssertEqual(factory.arguments, [["app-server", "--stdio"]])
        XCTAssertEqual(try session.method(at: 0), "initialize")
        XCTAssertEqual(try session.params(at: 0) as? [String: [String: String]], ["clientInfo": ["name": "quota_pet", "title": "QuotaPet", "version": "0.1.3"]])

        session.reply(id: 1, result: [:])
        try await eventually("initialized notification") { session.messages.count >= 2 }
        XCTAssertEqual(try session.method(at: 1), "initialized")
        XCTAssertEqual(try session.params(at: 1) as? [String: String], [:])

        try await eventually("rate-limits request") { session.messages.count >= 3 }
        XCTAssertEqual(try session.method(at: 2), "account/rateLimits/read")
        session.reply(id: 2, result: validRateLimits())
        try await eventually("ready snapshot") { snapshots.values.contains { $0.state == .ready } }
        XCTAssertFalse(session.terminated)
        XCTAssertFalse(session.messages.contains { ["experimentalApi", "account/read", "thread", "shell", "mcp", "purchase", "reset"].contains((try? session.method(for: $0)) ?? "") })
        try await stop(provider, session: session)
    }

    func testEnergySaverTerminatesAfterReadAndWakeCreatesNewSession() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)

        await provider.start(mode: .energySaver)
        let first = try await completeHandshake(factory: factory, expectsTermination: true)
        first.exit()

        let recovered = LockedFlag()
        Task { await provider.recover(mode: .energySaver, restartIfStopped: true); recovered.set() }
        let second = try await completeHandshake(factory: factory, index: 1, expectsTermination: true)
        second.exit()
        try await eventually("energy wake completion") { recovered.value }
        XCTAssertEqual(factory.sessions.count, 2)
        await provider.stop()
    }

    func testRejectsUntrustedCandidateWithoutStartingProcess() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: false), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)

        await provider.start(mode: .realtime)
        try await eventually("untrusted snapshot") { snapshots.values.contains { $0.state == .incompatible(L10n.text(.errorTrustValidation)) } }
        XCTAssertEqual(factory.sessions.count, 0)
    }

    func testLateExitFromOldGenerationCannotTerminateReplacement() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)

        await provider.start(mode: .realtime)
        let first = try await completeHandshake(factory: factory)
        XCTAssertFalse(first.terminated)
        let switched = LockedFlag()
        Task { await provider.start(mode: .energySaver); switched.set() }
        try await eventually("old generation termination") { first.terminated }
        XCTAssertEqual(factory.sessions.count, 1)
        first.exit()
        let second = try await completeHandshake(factory: factory, index: 1, expectsTermination: true)
        first.exit()
        try await eventually("replacement termination") { second.terminated }
        second.exit()
        try await eventually("mode switch completion") { switched.value }
        XCTAssertEqual(factory.sessions.count, 2)
        await provider.stop()
    }

    func testRealtimeNotificationPublishesReadyWithoutClosingSession() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)
        await provider.start(mode: .realtime)
        let session = try await completeHandshake(factory: factory)
        let countBeforeNotification = snapshots.values.count

        session.notify(method: "account/rateLimits/updated", params: validRateLimits())
        try await eventually("notification snapshot") { snapshots.values.count > countBeforeNotification && snapshots.values.last?.state == .ready }
        XCTAssertFalse(session.terminated)
        try await stop(provider, session: session)
    }

    func testInvalidResponseSchedulesFiveSecondRetryAndReadyResetsBackoff() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 15)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)
        await provider.start(mode: .realtime)
        let session = try await completeHandshake(factory: factory, response: ["unexpected": true])
        try await eventually("invalid response state") { snapshots.values.contains { $0.state == .unavailable(L10n.text(.errorNoUsageWindows)) } }
        XCTAssertTrue(scheduler.delays.contains(5))

        await provider.refresh()
        try await eventually("manual rate-limits read") { session.messages.count >= 4 }
        session.reply(id: 3, result: validRateLimits())
        try await eventually("ready reset") { snapshots.values.last?.state == .ready }
        session.exit()
        try await eventually("retry after reset") { scheduler.delays.filter { $0 == 5 }.count >= 2 }
    }

    func testStopCancelsPeriodicAndRetryAndKeepsEachForceTimerIndependent() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 15)
        await provider.start(mode: .realtime)
        let first = try await completeHandshake(factory: factory)
        Task { await provider.start(mode: .energySaver) }
        try await eventually("first mode termination") { first.terminated }
        first.exit()
        let second = try await completeHandshake(factory: factory, index: 1, expectsTermination: true)
        let stopped = LockedFlag()
        Task { await provider.stop(); stopped.set() }

        XCTAssertTrue(scheduler.tasks(withDelay: 600).allSatisfy(\.cancelled))
        let forceTasks = scheduler.tasks(withDelay: 1)
        XCTAssertGreaterThanOrEqual(forceTasks.count, 2)
        XCTAssertTrue(forceTasks[0].cancelled)
        XCTAssertFalse(forceTasks[1].cancelled)
        forceTasks[1].fire()
        try await eventually("stop after energy force fallback") { stopped.value }
        XCTAssertFalse(first.forced)
        XCTAssertTrue(second.forced)
    }

    func testFoundationFactoryIsInstantiableWithoutShellAPI() {
        _ = FoundationCodexAppServerSessionFactory()
    }

    func testStopReturnsOnlyAfterSessionExit() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        await provider.start(mode: .realtime)
        let session = try await completeHandshake(factory: factory)
        let stopped = LockedFlag()

        Task { await provider.stop(); stopped.set() }
        try await eventually("graceful termination request") { session.terminated }
        try await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertFalse(stopped.value)

        session.exit()
        try await eventually("stop completion after exit") { stopped.value }
    }

    func testStopForceFallbackCompletesAndLateExitIsHarmless() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 15)
        await provider.start(mode: .realtime)
        let session = try await completeHandshake(factory: factory)
        let stopped = LockedFlag()

        Task { await provider.stop(); stopped.set() }
        try await eventually("force fallback") { scheduler.tasks(withDelay: 1).count == 1 }
        XCTAssertFalse(stopped.value)
        scheduler.tasks(withDelay: 1)[0].fire()

        try await eventually("forced stop completion") { session.forced && stopped.value }
        session.exit()
        try await Task.sleep(nanoseconds: 1_000_000)
        XCTAssertTrue(stopped.value)
    }

    func testModeSwitchDoesNotStartReplacementBeforeOldSessionExits() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        await provider.start(mode: .realtime)
        let first = try await completeHandshake(factory: factory)

        Task { await provider.start(mode: .energySaver) }
        try await eventually("old session termination") { first.terminated }
        try await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertEqual(factory.sessions.count, 1)

        first.exit()
        let second = try await completeHandshake(factory: factory, index: 1, expectsTermination: true)
        XCTAssertEqual(factory.sessions.count, 2)
        try await stop(provider, session: second)
    }

    func testWakeRecoveryAwaitsExactlyOneInitialRead() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        await provider.start(mode: .realtime)
        let first = try await completeHandshake(factory: factory)
        let stopped = LockedFlag()
        Task { await provider.stop(); stopped.set() }
        try await eventually("sleep termination") { first.terminated }
        first.exit()
        try await eventually("sleep stop completion") { stopped.value }

        let recovered = LockedFlag()
        Task {
            await provider.recover(mode: .realtime, restartIfStopped: true)
            recovered.set()
        }
        try await eventually("wake initialize") { factory.session(at: 1)?.messages.count == 1 }
        let second = try XCTUnwrap(factory.session(at: 1))
        second.reply(id: 1, result: [:])
        try await eventually("wake rate-limit read") { second.messages.count == 3 }
        XCTAssertFalse(recovered.value)
        second.reply(id: 2, result: validRateLimits())
        try await eventually("wake recovery completion") { recovered.value }

        XCTAssertEqual(second.messages.compactMap { try? second.method(for: $0) }.filter { $0 == "account/rateLimits/read" }.count, 1)
        XCTAssertEqual(factory.sessions.count, 2)
        try await stop(provider, session: second)
    }

    func testNetworkRecoveryAwaitsExactlyOneReadWithoutNewSession() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        await provider.start(mode: .realtime)
        let session = try await completeHandshake(factory: factory)
        let recovered = LockedFlag()

        Task {
            await provider.recover(mode: .realtime, restartIfStopped: false)
            recovered.set()
        }
        try await eventually("network recovery read") { session.messages.count == 4 }
        XCTAssertFalse(recovered.value)
        session.reply(id: 3, result: validRateLimits())
        try await eventually("network recovery completion") { recovered.value }

        XCTAssertEqual(session.messages.compactMap { try? session.method(for: $0) }.filter { $0 == "account/rateLimits/read" }.count, 2)
        XCTAssertEqual(factory.sessions.count, 1)
        try await stop(provider, session: session)
    }

    func testExitRetryAndPeriodicEnergyRefreshCreateNewSessions() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 15)
        await provider.start(mode: .realtime)
        let first = try await completeHandshake(factory: factory)
        first.exit()
        try await eventually("exit retry task") { scheduler.tasks(withDelay: 5).count == 1 }
        scheduler.tasks(withDelay: 5)[0].fire()
        try await eventually("reconnected session") { factory.sessions.count == 2 }

        let retry = try XCTUnwrap(factory.session(at: 1))
        Task { await provider.start(mode: .energySaver) }
        try await eventually("retry session termination for mode switch") { retry.terminated }
        retry.exit()
        _ = try await completeHandshake(factory: factory, index: 2, expectsTermination: true)
        factory.session(at: 2)?.exit()
        let periodic = try XCTUnwrap(scheduler.tasks(withDelay: 600).last)
        periodic.fire()
        try await eventually("periodic energy session") { factory.sessions.count == 4 }
        try await stop(provider, session: try XCTUnwrap(factory.session(at: 3)))
    }

    func testConcurrentStartAndRefreshUseAtMostOneSession() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)

        async let first: Void = provider.start(mode: .realtime)
        async let second: Void = provider.start(mode: .realtime)
        async let manual: Void = provider.refresh()
        _ = await (first, second, manual)
        try await eventually("single initial session") { factory.sessions.count == 1 }
        try await stop(provider, session: try XCTUnwrap(factory.session(at: 0)))
    }

    func testStandardErrorTailAndMalformedStdoutUseProviderFailurePath() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)
        await provider.start(mode: .realtime)
        let session = try await completeHandshake(factory: factory)
        let suffix = Data(repeating: 66, count: 65_536)
        session.standardError(Data(repeating: 65, count: 1024) + suffix)
        try await eventuallyAsync("stderr tail") { await provider.standardErrorTail() == suffix }
        session.standardOutput(Data("not json\n".utf8))
        try await eventually("malformed stdout state") { snapshots.values.contains { $0.state == .unavailable(L10n.text(.errorInvalidAppServerResponse)) } }
        session.notify(method: "account/rateLimits/updated", params: validRateLimits())
        try await eventually("valid frame after malformed stdout") { snapshots.values.last?.state == .ready }
        try await stop(provider, session: session)
    }

    func testStandardErrorTailRemainsAvailableAfterUnexpectedExit() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)
        await provider.start(mode: .realtime)
        let session = try await completeHandshake(factory: factory)
        let diagnostic = Data("sanitized diagnostic".utf8)

        session.standardError(diagnostic)
        try await eventuallyAsync("stderr received") { await provider.standardErrorTail() == diagnostic }
        session.exit()

        try await eventually("unexpected exit observed") { snapshots.values.last?.state == .unavailable(L10n.text(.errorAppServerExited)) }
        try await eventuallyAsync("stderr retained after exit") { await provider.standardErrorTail() == diagnostic }
        await provider.stop()
    }

    func testRequestTimeoutPublishesUnavailableAndSchedulesFiveSecondRetry() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 0.01)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)
        await provider.start(mode: .realtime)

        try await eventually("request timeout") { snapshots.values.contains { $0.state == .unavailable(L10n.text(.errorRequestTimedOut)) } }
        try await eventually("timeout force fallback") { scheduler.tasks(withDelay: 1).count == 1 }
        scheduler.tasks(withDelay: 1)[0].fire()
        try await eventually("retry after timeout process exit") { scheduler.delays.contains(5) }
        XCTAssertTrue(scheduler.delays.contains(5))
    }

    func testRealtimeManualAndPeriodicRefreshReuseSessionForRead() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 15)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)
        await provider.start(mode: .realtime)
        let session = try await completeHandshake(factory: factory)
        try await eventually("initial realtime ready") { snapshots.values.last?.state == .ready }

        await provider.refresh()
        try await eventually("manual realtime read") { session.messages.count >= 4 }
        XCTAssertEqual(try session.method(at: 3), "account/rateLimits/read")
        let readyCountBeforeManualResponse = snapshots.values.count
        session.reply(id: 3, result: validRateLimits())
        try await eventually("manual realtime ready") { snapshots.values.count > readyCountBeforeManualResponse && snapshots.values.last?.state == .ready }
        let periodic = try XCTUnwrap(scheduler.tasks(withDelay: 600).last)
        periodic.fire()
        try await eventually("periodic realtime read") { session.messages.count >= 5 }
        XCTAssertEqual(factory.sessions.count, 1)
        XCTAssertEqual(try session.method(at: 4), "account/rateLimits/read")
        try await stop(provider, session: session)
    }

    func testEnergySaverManualAndPeriodicRefreshCreateNewSessions() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 15)
        await provider.start(mode: .energySaver)
        let first = try await completeHandshake(factory: factory, expectsTermination: true)
        first.exit()

        await provider.refresh()
        let second = try await completeHandshake(factory: factory, index: 1, expectsTermination: true)
        second.exit()
        let periodic = try XCTUnwrap(scheduler.tasks(withDelay: 600).last)
        periodic.fire()
        try await eventually("periodic energy connect") { factory.sessions.count == 3 }
        XCTAssertEqual(factory.sessions.count, 3)
        try await stop(provider, session: try XCTUnwrap(factory.session(at: 2)))
    }

    func testRefreshDuringInitializeDoesNotSendRateLimitsReadEarly() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        await provider.start(mode: .realtime)
        try await eventually("initialize request") { factory.session(at: 0)?.messages.count == 1 }
        let session = try XCTUnwrap(factory.session(at: 0))

        await provider.refresh()
        await provider.refresh()
        XCTAssertEqual(session.messages.count, 1)
        session.reply(id: 1, result: [:])
        try await eventually("post-handshake read") { session.messages.count >= 3 }
        XCTAssertEqual(try session.method(at: 1), "initialized")
        XCTAssertEqual(try session.method(at: 2), "account/rateLimits/read")
        try await stop(provider, session: session)
    }

    func testFoundationSessionDrainsImmediateStdoutBeforeSingleExitCallback() async throws {
        let factory = FoundationCodexAppServerSessionFactory()
        let events = LockedEvents()
        let session = try factory.start(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["final-jsonl"],
            onStandardOutput: { events.append("stdout:\(String(decoding: $0, as: UTF8.self))") },
            onStandardError: { events.append("stderr:\(String(decoding: $0, as: UTF8.self))") },
            onExit: { events.append("exit") }
        )

        try await eventually("process exit") { events.values.contains("exit") }
        XCTAssertEqual(events.values.filter { $0 == "exit" }.count, 1)
        XCTAssertEqual(events.values.last, "exit")
        XCTAssertTrue(events.values.contains("stdout:final-jsonl"))
        withExtendedLifetime(session) {}
    }

    func testFoundationSessionConsumesReadableBytesBeforeQueueingDelivery() async throws {
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let events = LockedEvents()
        let deliveryQueue = DispatchQueue(label: "QuotaPetTests.suspendedDelivery")
        deliveryQueue.suspend()
        var queueResumed = false
        defer {
            if !queueResumed { deliveryQueue.resume() }
            output.fileHandleForReading.readabilityHandler = nil
            error.fileHandleForReading.readabilityHandler = nil
        }
        let session = FoundationCodexAppServerSession(
            process: Process(),
            input: input.fileHandleForWriting,
            output: output.fileHandleForReading,
            error: error.fileHandleForReading,
            onStandardOutput: { events.append("stdout:\(String(decoding: $0, as: UTF8.self))") },
            onStandardError: { _ in },
            onExit: {},
            ioQueue: deliveryQueue
        )
        session.installHandlers()
        let handler = try XCTUnwrap(output.fileHandleForReading.readabilityHandler)
        try output.fileHandleForWriting.write(contentsOf: Data("single-readable-event".utf8))
        try output.fileHandleForWriting.close()

        handler(output.fileHandleForReading)

        XCTAssertTrue(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
        XCTAssertFalse(events.values.contains("stdout:single-readable-event"))
        deliveryQueue.resume()
        queueResumed = true
        try await eventually("queued stdout delivery") {
            events.values.contains("stdout:single-readable-event")
        }
        withExtendedLifetime(session) {}
    }

    private func completeHandshake(factory: TestSessionFactory, index: Int = 0, expectsTermination: Bool = false, response: [String: Any]? = nil) async throws -> TestSession {
        try await eventually("initialize request") { factory.session(at: index)?.messages.count == 1 }
        let session = try XCTUnwrap(factory.session(at: index))
        session.reply(id: 1, result: [:])
        try await eventually("rate-limits request") { session.messages.count >= 3 }
        session.reply(id: 2, result: response ?? validRateLimits())
        if expectsTermination { try await eventually("energy session termination") { session.terminated } }
        return session
    }

    private func validRateLimits() -> [String: Any] {
        ["rateLimits": ["codex": ["primary": ["usedPercent": 42, "windowDurationMinutes": 300, "resetsAt": 1_700_000_000]]]]
    }

    private func testCandidate() -> ExecutableCandidate {
        ExecutableCandidate(canonicalURL: URL(fileURLWithPath: "/trusted/codex"), source: .path, ownerUID: 0, mode: 0o755, signingIdentifier: nil, teamIdentifier: nil, codeHash: "hash", deviceID: 1, inode: 1, inputURL: URL(fileURLWithPath: "/trusted/codex"))
    }

    private func stop(_ provider: CodexAppServerStdioProvider, session: TestSession) async throws {
        let stopped = LockedFlag()
        Task { await provider.stop(); stopped.set() }
        try await eventually("test session termination") { stopped.value || session.terminated }
        if !stopped.value {
            session.exit()
            try await eventually("test provider stop") { stopped.value }
        }
    }
}

private final class TestResolver: UsageExecutableResolving {
    let isTrusted: Bool
    init(isTrusted: Bool) { self.isTrusted = isTrusted }
    func revalidate(_ candidate: ExecutableCandidate) -> Bool { isTrusted }
}

private final class TestSessionFactory: CodexAppServerSessionFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSessions: [TestSession] = []
    private var storedExecutables: [URL] = []
    private var storedArguments: [[String]] = []

    var sessions: [TestSession] { lock.withLock { storedSessions } }
    var executables: [URL] { lock.withLock { storedExecutables } }
    var arguments: [[String]] { lock.withLock { storedArguments } }
    func session(at index: Int) -> TestSession? { lock.withLock { storedSessions.indices.contains(index) ? storedSessions[index] : nil } }

    func start(executableURL: URL, arguments: [String], onStandardOutput: @escaping (Data) -> Void, onStandardError: @escaping (Data) -> Void, onExit: @escaping () -> Void) throws -> any CodexAppServerSession {
        lock.withLock {
            storedExecutables.append(executableURL)
            storedArguments.append(arguments)
        }
        let session = TestSession(onOutput: onStandardOutput, onError: onStandardError, onExit: onExit)
        lock.withLock { storedSessions.append(session) }
        return session
    }
}

private final class TestSession: CodexAppServerSession, @unchecked Sendable {
    private let lock = NSLock()
    private let onOutput: (Data) -> Void
    private let onError: (Data) -> Void
    private let onExit: () -> Void
    private var storedMessages: [Data] = []
    private var storedTerminated = false
    private var storedForced = false
    var messages: [Data] { lock.withLock { storedMessages } }
    var terminated: Bool { lock.withLock { storedTerminated } }
    var forced: Bool { lock.withLock { storedForced } }

    init(onOutput: @escaping (Data) -> Void, onError: @escaping (Data) -> Void, onExit: @escaping () -> Void) { self.onOutput = onOutput; self.onError = onError; self.onExit = onExit }
    func write(_ data: Data) throws { lock.withLock { storedMessages.append(data) } }
    func closeInput() {}
    func terminate() { lock.withLock { storedTerminated = true } }
    func forceTerminate() { lock.withLock { storedTerminated = true; storedForced = true } }
    func exit() { onExit() }
    func reply(id: Int, result: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result]) + Data([10])
        onOutput(data)
    }
    func notify(method: String, params: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": method, "params": params]) + Data([10])
        onOutput(data)
    }
    func standardOutput(_ data: Data) { onOutput(data) }
    func standardError(_ data: Data) { onError(data) }
    func method(at index: Int) throws -> String { try method(for: try XCTUnwrap(lock.withLock { storedMessages.indices.contains(index) ? storedMessages[index] : nil })) }
    func method(for data: Data) throws -> String { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])["method"] as? String ?? "" }
    func params(at index: Int) throws -> Any { try XCTUnwrap(JSONSerialization.jsonObject(with: messages[index]) as? [String: Any])["params"] as Any }
}

private final class TestScheduler: UsageScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var storedTasks: [TestScheduledTask] = []
    var delays: [TimeInterval] { lock.withLock { storedTasks.map(\.delay) } }
    func tasks(withDelay delay: TimeInterval) -> [TestScheduledTask] { lock.withLock { storedTasks.filter { $0.delay == delay } } }
    func schedule(after: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any UsageScheduledTask {
        let task = TestScheduledTask(delay: after, action: action)
        lock.withLock { storedTasks.append(task) }
        return task
    }
}
private final class TestScheduledTask: UsageScheduledTask, @unchecked Sendable {
    let delay: TimeInterval
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?
    private(set) var cancelled = false
    init(delay: TimeInterval, action: @escaping @Sendable () -> Void) { self.delay = delay; self.action = action }
    func cancel() { lock.withLock { cancelled = true; action = nil } }
    func fire() { lock.withLock { action }?() }
}

private final class SnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [QuotaSnapshot] = []
    var values: [QuotaSnapshot] { lock.withLock { storedValues } }
    init(stream: AsyncStream<QuotaSnapshot>) {
        Task { for await value in stream { lock.withLock { storedValues.append(value) } } }
    }
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []
    var values: [String] { lock.withLock { storedValues } }
    func append(_ value: String) { lock.withLock { storedValues.append(value) } }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false
    var value: Bool { lock.withLock { storedValue } }
    func set() { lock.withLock { storedValue = true } }
}

private enum TestWaitError: Error { case timedOut }

private func eventually(_ label: String, _ condition: @escaping () -> Bool) async throws {
    for _ in 0..<100 { if condition() { return }; try await Task.sleep(nanoseconds: 1_000_000) }
    XCTFail("Timed out waiting for \(label)")
    throw TestWaitError.timedOut
}

private func eventuallyAsync(_ label: String, _ condition: @escaping () async -> Bool) async throws {
    for _ in 0..<100 { if await condition() { return }; try await Task.sleep(nanoseconds: 1_000_000) }
    XCTFail("Timed out waiting for \(label)")
    throw TestWaitError.timedOut
}
