import XCTest
@testable import QuotaPet

final class RefreshPolicyTests: XCTestCase {
    func testUsesBoundedBackoffAndResetsOnlyForReadySnapshot() {
        var policy = RefreshPolicy()

        XCTAssertEqual((0..<7).map { _ in policy.recordFailure() }, [5, 30, 60, 300, 900, 900, 900])
        policy.record(snapshot: QuotaSnapshot(planType: nil, windows: [], updatedAt: .now, state: .unavailable("none")))
        XCTAssertEqual(policy.recordFailure(), 900)

        policy.record(snapshot: QuotaSnapshot(
            planType: "pro",
            windows: [QuotaWindow(id: "codex|primary", bucketID: "codex", displayName: "primary", usedPercent: 20, remainingPercent: 80, windowDurationMinutes: 300, resetsAt: .now, isReached: false)],
            updatedAt: .now,
            state: .ready
        ))
        XCTAssertEqual(policy.recordFailure(), 5)
    }

    func testHasTenMinutePeriodicRefreshInterval() {
        XCTAssertEqual(RefreshPolicy.periodicRefreshInterval, 600)
    }
}
