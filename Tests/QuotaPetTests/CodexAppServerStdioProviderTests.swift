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

    private func completeHandshake(factory: TestSessionFactory, index: Int = 0, expectsTermination: Bool = false) async throws -> TestSession {
        try await eventually("initialize request") { factory.session(at: index)?.messages.count == 1 }
        let session = try XCTUnwrap(factory.session(at: index))
        session.reply(id: 1, result: [:])
        try await eventually("rate-limits request") { session.messages.count >= 3 }
        session.reply(id: 2, result: validRateLimits())
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
        let session = TestSession(onOutput: onStandardOutput, onExit: onExit)
        lock.withLock { storedSessions.append(session) }
        return session
    }
}

private final class TestSession: CodexAppServerSession, @unchecked Sendable {
    private let lock = NSLock()
    private let onOutput: (Data) -> Void
    private let onExit: () -> Void
    private var storedMessages: [Data] = []
    private var storedTerminated = false
    var messages: [Data] { lock.withLock { storedMessages } }
    var terminated: Bool { lock.withLock { storedTerminated } }

    init(onOutput: @escaping (Data) -> Void, onExit: @escaping () -> Void) { self.onOutput = onOutput; self.onExit = onExit }
    func write(_ data: Data) throws { lock.withLock { storedMessages.append(data) } }
    func closeInput() {}
    func terminate() { lock.withLock { storedTerminated = true } }
    func forceTerminate() { lock.withLock { storedTerminated = true } }
    func exit() { onExit() }
    func reply(id: Int, result: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result]) + Data([10])
        onOutput(data)
    }
    func method(at index: Int) throws -> String { try method(for: try XCTUnwrap(lock.withLock { storedMessages.indices.contains(index) ? storedMessages[index] : nil })) }
    func method(for data: Data) throws -> String { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])["method"] as? String ?? "" }
    func params(at index: Int) throws -> Any { try XCTUnwrap(JSONSerialization.jsonObject(with: messages[index]) as? [String: Any])["params"] as Any }
}

private final class TestScheduler: UsageScheduling {
    func schedule(after: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any UsageScheduledTask { TestScheduledTask() }
}
private final class TestScheduledTask: UsageScheduledTask { func cancel() {} }

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
