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
