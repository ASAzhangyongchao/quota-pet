import Foundation
import XCTest
@testable import QuotaPet

final class NotificationPolicyTests: XCTestCase {
    func testNotifiesTwentyTenAndZeroOnceForTheSameWindow() {
        let store = makeStore()
        var policy = NotificationPolicy(store: store)
        let reset = date("2026-07-20T00:00:00Z")
        let now = date("2026-07-19T12:00:00Z")

        XCTAssertEqual(policy.evaluate(snapshot(remaining: 20, reset: reset), now: now)?.threshold, 20)
        policy = NotificationPolicy(store: store)
        XCTAssertNil(policy.evaluate(snapshot(remaining: 20, reset: reset), now: now))
        XCTAssertEqual(policy.evaluate(snapshot(remaining: 10, reset: reset), now: now)?.threshold, 10)
        XCTAssertNil(policy.evaluate(snapshot(remaining: 10, reset: reset), now: now))
        XCTAssertEqual(policy.evaluate(snapshot(remaining: 0, reset: reset), now: now)?.threshold, 0)
        XCTAssertNil(policy.evaluate(snapshot(remaining: 0, reset: reset), now: now))
    }

    func testNewResetWindowCanNotifyTheSameThresholdAgain() {
        let store = makeStore()
        var policy = NotificationPolicy(store: store)
        let now = date("2026-07-19T12:00:00Z")

        XCTAssertEqual(policy.evaluate(snapshot(remaining: 20, reset: date("2026-07-20T00:00:00Z")), now: now)?.threshold, 20)
        XCTAssertEqual(policy.evaluate(snapshot(remaining: 20, reset: date("2026-07-27T00:00:00Z")), now: now)?.threshold, 20)
    }

    func testExpiredUnavailableAndStaleSnapshotsDoNotNotify() {
        let now = date("2026-07-19T12:00:00Z")
        var policy = NotificationPolicy(store: makeStore())

        XCTAssertNil(policy.evaluate(snapshot(remaining: 0, reset: date("2026-07-19T11:59:59Z")), now: now))
        XCTAssertNil(policy.evaluate(snapshot(remaining: 0, reset: date("2026-07-20T00:00:00Z"), state: .unavailable("offline")), now: now))
        XCTAssertNil(policy.evaluate(snapshot(remaining: 0, reset: date("2026-07-20T00:00:00Z"), state: .stale("old")), now: now))
    }

    func testCrossingMultipleThresholdsEmitsOnlyMostUrgentAndMarksAllCrossed() {
        let store = makeStore()
        var policy = NotificationPolicy(store: store)
        let reset = date("2026-07-20T00:00:00Z")
        let now = date("2026-07-19T12:00:00Z")

        XCTAssertEqual(policy.evaluate(snapshot(remaining: 8, reset: reset), now: now)?.threshold, 10)
        XCTAssertNil(policy.evaluate(snapshot(remaining: 8, reset: reset), now: now))
        XCTAssertEqual(policy.evaluate(snapshot(remaining: 0, reset: reset), now: now)?.threshold, 0)
    }

    func testPersistenceContainsOnlyBucketResetAndThresholdBitmap() throws {
        let store = makeStore()
        var policy = NotificationPolicy(store: store)
        _ = policy.evaluate(
            snapshot(remaining: 20, reset: date("2026-07-20T00:00:00Z")),
            now: date("2026-07-19T12:00:00Z")
        )

        let data = try XCTUnwrap(store.data(forKey: NotificationPolicy.storageKey))
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(Set(records[0].keys), ["bucketID", "resetsAt", "thresholdMask"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-project-name"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("test-plan-must-not-be-persisted"))
    }

    private func makeStore() -> UserDefaults {
        let suite = "QuotaPetTests.NotificationPolicy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private func snapshot(remaining: Double, reset: Date, state: ConnectionState = .ready) -> QuotaSnapshot {
    QuotaSnapshot(
        planType: "test-plan-must-not-be-persisted",
        windows: [QuotaWindow(
            id: "private-window-id",
            bucketID: "codex",
            displayName: "private-project-name",
            usedPercent: 100 - remaining,
            remainingPercent: remaining,
            windowDurationMinutes: 300,
            resetsAt: reset,
            isReached: remaining <= 0
        )],
        updatedAt: date("2026-07-19T12:00:00Z"),
        state: state
    )
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
