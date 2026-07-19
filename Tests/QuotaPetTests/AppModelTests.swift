import Foundation
import XCTest
@testable import QuotaPet

@MainActor
final class AppModelTests: XCTestCase {
    func testLastGoodSnapshotBecomesStaleWhenProviderFails() async {
        let provider = TestUsageProvider()
        let model = AppModel(provider: provider, store: makeStore())
        let ready = snapshot(used: 18, plan: "Plus", reset: date("2026-07-25T12:00:00Z"), state: .ready)

        await model.start()
        provider.emit(ready)
        await eventually("ready snapshot") { model.snapshot == ready }
        provider.emit(QuotaSnapshot(planType: nil, windows: [], updatedAt: .now, state: .unavailable("连接中断")))
        await eventually("stale snapshot") { model.snapshot.state == .stale("连接中断") }

        XCTAssertEqual(model.snapshot.planType, "Plus")
        XCTAssertEqual(model.snapshot.windows, ready.windows)
        XCTAssertEqual(model.snapshot.updatedAt, ready.updatedAt)
        XCTAssertEqual(model.snapshot.state, .stale("连接中断"))
        XCTAssertEqual(model.lastError, "连接中断")
    }

    func testFirstFailureKeepsEmptyWindowsAndOriginalFailureState() async {
        let provider = TestUsageProvider()
        let model = AppModel(provider: provider, store: makeStore())

        await model.start()
        provider.emit(QuotaSnapshot(planType: nil, windows: [], updatedAt: .now, state: .incompatible("尚未确认 Codex")))
        await eventually("incompatible snapshot") { model.snapshot.state == .incompatible("尚未确认 Codex") }

        XCTAssertTrue(model.snapshot.windows.isEmpty)
        XCTAssertNil(model.snapshot.planType)
        XCTAssertEqual(model.snapshot.state, .incompatible("尚未确认 Codex"))
        XCTAssertEqual(model.lastError, "尚未确认 Codex")
    }

    func testReadySnapshotRecoversAfterStaleFailure() async {
        let provider = TestUsageProvider()
        let model = AppModel(provider: provider, store: makeStore())

        await model.start()
        provider.emit(snapshot(used: 18, plan: "Plus", reset: nil, state: .ready))
        await eventually("initial ready snapshot") { model.snapshot.state == .ready }
        provider.emit(QuotaSnapshot(planType: nil, windows: [], updatedAt: .now, state: .unavailable("连接中断")))
        await eventually("stale snapshot") { model.snapshot.state == .stale("连接中断") }
        let recovered = snapshot(used: 31, plan: "Pro", reset: nil, state: .ready)
        provider.emit(recovered)
        await eventually("recovered snapshot") { model.snapshot == recovered }

        XCTAssertEqual(model.snapshot, recovered)
        XCTAssertNil(model.lastError)
    }

    func testModeSwitchRestartsProviderWithNewMode() async {
        let provider = TestUsageProvider()
        let model = AppModel(provider: provider, store: makeStore())

        await model.start()
        await model.setConnectionMode(.realtime)

        XCTAssertEqual(provider.startedModes, [.energySaver, .realtime])
        XCTAssertEqual(model.connectionMode, .realtime)
    }

    func testPreferencesPersistInAnIsolatedUserDefaultsSuite() async {
        let store = makeStore()
        let provider = TestUsageProvider()
        let model = AppModel(provider: provider, store: store)

        await model.setConnectionMode(.realtime)
        model.setPetVisible(false)
        let restored = AppModel(provider: TestUsageProvider(), store: store)

        XCTAssertEqual(restored.connectionMode, .realtime)
        XCTAssertFalse(restored.petVisible)
    }

    func testCompositionDoesNotStartRequiresConfirmationCandidate() async {
        let factory = CompositionSessionFactory()
        let composition = AppComposition(
            resolver: CompositionResolver(resolution: .accepted(compositionCandidate(), trust: .requiresConfirmation)),
            sessionFactory: factory,
            store: makeStore()
        )

        await composition.model.start()
        await eventually("unavailable composition snapshot") { composition.model.snapshot.state == .unavailable(L10n.text(.errorNoTrustedCodex)) }

        XCTAssertEqual(factory.startCount, 0)
        XCTAssertEqual(composition.model.snapshot.state, .unavailable(L10n.text(.errorNoTrustedCodex)))
    }

    func testCompositionExposesRequiresConfirmationCandidate() {
        let candidate = compositionCandidate()
        let composition = AppComposition(
            resolver: CompositionResolver(resolution: .accepted(candidate, trust: .requiresConfirmation)),
            sessionFactory: CompositionSessionFactory(),
            store: makeStore()
        )

        XCTAssertEqual(composition.pendingConfirmationCandidate, candidate)
        XCTAssertTrue(composition.provider is UnavailableUsageProvider)
    }

    func testCompositionBuildsTrustedProviderWithInjectedFoundationFactory() {
        let composition = AppComposition(
            resolver: CompositionResolver(resolution: .accepted(compositionCandidate(), trust: .confirmed)),
            sessionFactory: FoundationCodexAppServerSessionFactory(),
            store: makeStore()
        )

        XCTAssertTrue(composition.provider is CodexAppServerStdioProvider)
    }

    private func makeStore() -> UserDefaults {
        let suite = "QuotaPetTests.AppModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class TestUsageProvider: UsageProvider {
    let snapshots: AsyncStream<QuotaSnapshot>
    private let continuation: AsyncStream<QuotaSnapshot>.Continuation
    private(set) var startedModes: [ConnectionMode] = []

    init() {
        var savedContinuation: AsyncStream<QuotaSnapshot>.Continuation?
        snapshots = AsyncStream { savedContinuation = $0 }
        continuation = savedContinuation!
    }

    func emit(_ snapshot: QuotaSnapshot) { continuation.yield(snapshot) }
    func start(mode: ConnectionMode) async { startedModes.append(mode) }
    func refresh() async {}
    func recover(mode: ConnectionMode, restartIfStopped: Bool) async {
        if restartIfStopped { await start(mode: mode) } else { await refresh() }
    }
    func stop() async {}
}

private func snapshot(used: Double, plan: String?, reset: Date?, state: ConnectionState) -> QuotaSnapshot {
    QuotaSnapshot(
        planType: plan,
        windows: [QuotaWindow(id: "codex.primary", bucketID: "codex", displayName: "Codex", usedPercent: used, remainingPercent: 100 - used, windowDurationMinutes: 300, resetsAt: reset, isReached: used >= 100)],
        updatedAt: date("2026-07-19T12:00:00Z"),
        state: state
    )
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}

private func eventually(_ description: String, condition: @escaping () -> Bool) async {
    for _ in 0..<1_000 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("等待 \(description) 超时")
}

private final class CompositionResolver: AppExecutableResolving {
    let resolution: ExecutableResolution
    init(resolution: ExecutableResolution) { self.resolution = resolution }
    func resolve(userSelectedURL: URL? = nil, path: String? = nil) -> [ExecutableResolution] { [resolution] }
    func revalidate(_ candidate: ExecutableCandidate) -> Bool { true }
}

private final class CompositionSessionFactory: CodexAppServerSessionFactory {
    private(set) var startCount = 0
    func start(executableURL: URL, arguments: [String], onStandardOutput: @escaping (Data) -> Void, onStandardError: @escaping (Data) -> Void, onExit: @escaping () -> Void) throws -> any CodexAppServerSession {
        startCount += 1
        fatalError("requiresConfirmation candidates must never start")
    }
}

private func compositionCandidate() -> ExecutableCandidate {
    ExecutableCandidate(canonicalURL: URL(fileURLWithPath: "/trusted/codex"), source: .userSelected, ownerUID: 0, mode: 0o755, signingIdentifier: nil, teamIdentifier: nil, codeHash: "hash", deviceID: 1, inode: 1, inputURL: URL(fileURLWithPath: "/trusted/codex"))
}
