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
}
