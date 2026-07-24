import XCTest
@testable import QuotaPet

final class LifecycleRecoveryPolicyTests: XCTestCase {
    func testSleepAndWakeRequestOneStopAndOneRecovery() {
        var policy = LifecycleRecoveryPolicy()

        XCTAssertTrue(policy.willSleep())
        XCTAssertFalse(policy.willSleep())
        XCTAssertTrue(policy.didWake())
        XCTAssertFalse(policy.didWake())
    }

    func testOnlyUnsatisfiedToSatisfiedNetworkTransitionRequestsRecovery() {
        var policy = LifecycleRecoveryPolicy()

        XCTAssertFalse(policy.networkChanged(isSatisfied: true))
        XCTAssertFalse(policy.networkChanged(isSatisfied: true))
        XCTAssertFalse(policy.networkChanged(isSatisfied: false))
        XCTAssertTrue(policy.networkChanged(isSatisfied: true))
    }

    func testNetworkRecoveryWhileSleepingIsDeferredToWake() {
        var policy = LifecycleRecoveryPolicy()
        _ = policy.networkChanged(isSatisfied: false)
        _ = policy.willSleep()

        XCTAssertFalse(policy.networkChanged(isSatisfied: true))
        XCTAssertTrue(policy.didWake())
    }

    func testProviderHealthRestartsOnTrustFailureAndThrottles() {
        var policy = ProviderHealthRecoveryPolicy()
        let language = AppLanguage.english
        let trust = L10n.text(.errorTrustValidation, language: language)
        let now = Date(timeIntervalSince1970: 1_000)

        let incompatible = QuotaSnapshot(planType: nil, windows: [], updatedAt: now, state: .incompatible(trust))
        XCTAssertTrue(policy.shouldRestartProvider(for: incompatible, language: language, now: now))
        XCTAssertFalse(policy.shouldRestartProvider(for: incompatible, language: language, now: now.addingTimeInterval(10)))
        XCTAssertTrue(policy.shouldRestartProvider(for: incompatible, language: language, now: now.addingTimeInterval(31)))
    }

    func testProviderHealthRestartsAfterRepeatedAppServerExits() {
        var policy = ProviderHealthRecoveryPolicy()
        let language = AppLanguage.english
        let exited = L10n.text(.errorAppServerExited, language: language)
        let now = Date(timeIntervalSince1970: 2_000)
        let snapshot = QuotaSnapshot(planType: nil, windows: [], updatedAt: now, state: .unavailable(exited))

        XCTAssertFalse(policy.shouldRestartProvider(for: snapshot, language: language, now: now))
        XCTAssertTrue(policy.shouldRestartProvider(for: snapshot, language: language, now: now.addingTimeInterval(1)))
    }

    func testProviderHealthRestartsAfterRepeatedTimeouts() {
        var policy = ProviderHealthRecoveryPolicy()
        let language = AppLanguage.english
        let timedOut = L10n.text(.errorRequestTimedOut, language: language)
        let now = Date(timeIntervalSince1970: 2_500)
        let snapshot = QuotaSnapshot(planType: nil, windows: [], updatedAt: now, state: .unavailable(timedOut))

        XCTAssertFalse(policy.shouldRestartProvider(for: snapshot, language: language, now: now))
        XCTAssertTrue(policy.shouldRestartProvider(for: snapshot, language: language, now: now.addingTimeInterval(1)))
    }

    func testTrustedCodexSelectionSkipsFailedPathsWhenAlternativesExist() {
        let chatGPT = makeTrustedCandidate(
            path: "/Applications/ChatGPT.app/Contents/Resources/codex",
            source: .chatGPTBundle
        )
        let brew = makeTrustedCandidate(
            path: "/opt/homebrew/bin/codex",
            source: .homebrew
        )
        let resolutions: [ExecutableResolution] = [
            .accepted(chatGPT, trust: .bundleAllowList),
            .accepted(brew, trust: .confirmed),
        ]

        let skipped = TrustedCodexSelection.trustedCandidates(
            from: resolutions,
            skippingPaths: [chatGPT.canonicalURL.path]
        )
        XCTAssertEqual(skipped.map(\.canonicalURL.path), [brew.canonicalURL.path])

        let fallback = TrustedCodexSelection.trustedCandidates(from: resolutions, skippingPaths: [
            chatGPT.canonicalURL.path,
            brew.canonicalURL.path,
        ])
        XCTAssertTrue(fallback.isEmpty)
    }

    func testProviderHealthResetsExitCountOnReady() {
        var policy = ProviderHealthRecoveryPolicy()
        let language = AppLanguage.english
        let exited = L10n.text(.errorAppServerExited, language: language)
        let now = Date(timeIntervalSince1970: 3_000)
        let bad = QuotaSnapshot(planType: nil, windows: [], updatedAt: now, state: .stale(exited))
        let good = QuotaSnapshot(planType: nil, windows: [], updatedAt: now, state: .ready)

        XCTAssertFalse(policy.shouldRestartProvider(for: bad, language: language, now: now))
        policy.noteReady()
        _ = policy.shouldRestartProvider(for: good, language: language, now: now)
        XCTAssertFalse(policy.shouldRestartProvider(for: bad, language: language, now: now.addingTimeInterval(1)))
    }

    @MainActor
    func testWakeWaitsForInterruptedSleepStopToComplete() async {
        let coordinator = LifecycleRecoveryCoordinator()
        let gate = AsyncGate()
        let events = EventRecorder()

        coordinator.interrupt {
            await events.append("stop-begin")
            await gate.wait()
            await events.append("stop-end")
        }
        coordinator.enqueue { await events.append("wake") }

        await eventuallyLifecycle { await events.values == ["stop-begin"] }
        let beforeOpen = await events.values
        XCTAssertEqual(beforeOpen, ["stop-begin"])
        await gate.open()
        await eventuallyLifecycle { await events.values == ["stop-begin", "stop-end", "wake"] }
    }

    @MainActor
    func testSleepInterruptDoesNotWaitForCancelledRecovery() async {
        let coordinator = LifecycleRecoveryCoordinator()
        let recoveryGate = AsyncGate()
        let events = EventRecorder()

        coordinator.enqueue {
            await events.append("recovery-begin")
            await recoveryGate.wait()
        }
        await eventuallyLifecycle { await events.values == ["recovery-begin"] }
        coordinator.interrupt { await events.append("sleep-stop") }

        await eventuallyLifecycle { await events.values.contains("sleep-stop") }
        await recoveryGate.open()
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor EventRecorder {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private func eventuallyLifecycle(_ condition: @escaping () async -> Bool) async {
    for _ in 0..<1_000 {
        if await condition() { return }
        await Task.yield()
    }
    XCTFail("lifecycle condition timed out")
}

private func makeTrustedCandidate(path: String, source: ExecutableCandidate.Source) -> ExecutableCandidate {
    let url = URL(fileURLWithPath: path)
    return ExecutableCandidate(
        canonicalURL: url,
        source: source,
        ownerUID: 501,
        mode: 0o755,
        signingIdentifier: "com.openai.codex",
        teamIdentifier: "2DC432GLL2",
        codeHash: "abc",
        deviceID: 1,
        inode: 2,
        inputURL: url
    )
}
