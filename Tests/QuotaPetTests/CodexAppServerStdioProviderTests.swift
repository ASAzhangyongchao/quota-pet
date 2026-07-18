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
        XCTAssertEqual(try session.params(at: 0) as? [String: [String: String]], ["clientInfo": ["name": "quota_pet", "title": "QuotaPet", "version": "0.1.0"]])

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
    }

    func testEnergySaverTerminatesAfterReadAndWakeCreatesNewSession() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)

        await provider.start(mode: .energySaver)
        _ = try await completeHandshake(factory: factory, expectsTermination: true)

        await provider.wake()
        _ = try await completeHandshake(factory: factory, index: 1, expectsTermination: true)
        XCTAssertEqual(factory.sessions.count, 2)
    }

    func testRejectsUntrustedCandidateWithoutStartingProcess() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: false), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)

        await provider.start(mode: .realtime)
        try await eventually("untrusted snapshot") { snapshots.values.contains { $0.state == .incompatible("Codex executable trust validation failed") } }
        XCTAssertEqual(factory.sessions.count, 0)
    }

    func testLateExitFromOldGenerationCannotTerminateReplacement() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)

        await provider.start(mode: .realtime)
        let first = try await completeHandshake(factory: factory)
        XCTAssertFalse(first.terminated)
        await provider.start(mode: .energySaver)
        XCTAssertTrue(first.terminated)
        let second = try await completeHandshake(factory: factory, index: 1, expectsTermination: true)
        first.exit()
        try await eventually("replacement termination") { second.terminated }
        XCTAssertEqual(factory.sessions.count, 2)
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
    }

    func testInvalidResponseSchedulesFiveSecondRetryAndReadyResetsBackoff() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 15)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)
        await provider.start(mode: .realtime)
        let session = try await completeHandshake(factory: factory, response: ["unexpected": true])
        try await eventually("invalid response state") { snapshots.values.contains { $0.state == .unavailable("未返回 Codex 用量窗口") } }
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
        await provider.start(mode: .energySaver)
        let second = try await completeHandshake(factory: factory, index: 1, expectsTermination: true)
        await provider.stop()

        XCTAssertTrue(scheduler.tasks(withDelay: 600).allSatisfy(\.cancelled))
        let forceTasks = scheduler.tasks(withDelay: 1)
        XCTAssertGreaterThanOrEqual(forceTasks.count, 2)
        XCTAssertFalse(forceTasks[0].cancelled)
        XCTAssertFalse(forceTasks[1].cancelled)
        forceTasks.forEach { $0.fire() }
        XCTAssertTrue(first.forced)
        XCTAssertTrue(second.forced)
    }

    func testFoundationFactoryIsInstantiableWithoutShellAPI() {
        _ = FoundationCodexAppServerSessionFactory()
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

        await provider.start(mode: .energySaver)
        _ = try await completeHandshake(factory: factory, index: 2, expectsTermination: true)
        let periodic = try XCTUnwrap(scheduler.tasks(withDelay: 600).last)
        periodic.fire()
        try await eventually("periodic energy session") { factory.sessions.count == 4 }
    }

    func testConcurrentStartAndRefreshUseAtMostOneSession() async throws {
        let factory = TestSessionFactory()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: TestScheduler(), requestTimeout: 15)

        async let first: Void = provider.start(mode: .realtime)
        async let second: Void = provider.start(mode: .realtime)
        async let manual: Void = provider.refresh()
        _ = await (first, second, manual)
        try await eventually("single initial session") { factory.sessions.count == 1 }
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
        try await eventually("malformed stdout state") { snapshots.values.contains { $0.state == .unavailable("Codex app-server response was invalid") } }
        session.notify(method: "account/rateLimits/updated", params: validRateLimits())
        try await eventually("valid frame after malformed stdout") { snapshots.values.last?.state == .ready }
    }

    func testRequestTimeoutPublishesUnavailableAndSchedulesFiveSecondRetry() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 0.01)
        let snapshots = SnapshotRecorder(stream: provider.snapshots)
        await provider.start(mode: .realtime)

        try await eventually("request timeout") { snapshots.values.contains { $0.state == .unavailable("Codex app-server request timed out") } }
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
    }

    func testEnergySaverManualAndPeriodicRefreshCreateNewSessions() async throws {
        let factory = TestSessionFactory()
        let scheduler = TestScheduler()
        let provider = CodexAppServerStdioProvider(candidate: testCandidate(), resolver: TestResolver(isTrusted: true), sessionFactory: factory, scheduler: scheduler, requestTimeout: 15)
        await provider.start(mode: .energySaver)
        _ = try await completeHandshake(factory: factory, expectsTermination: true)

        await provider.refresh()
        _ = try await completeHandshake(factory: factory, index: 1, expectsTermination: true)
        let periodic = try XCTUnwrap(scheduler.tasks(withDelay: 600).last)
        periodic.fire()
        try await eventually("periodic energy connect") { factory.sessions.count == 3 }
        XCTAssertEqual(factory.sessions.count, 3)
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
