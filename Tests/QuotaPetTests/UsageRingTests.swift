import XCTest
@testable import QuotaPet

final class UsageRingTests: XCTestCase {
    func testReadyFractionsHaveExactBoundaryValues() {
        for (used, expectedRemaining) in [(0.0, 1.0), (1.0, 0.99), (50.0, 0.5), (99.0, 0.01), (100.0, 0.0)] {
            let style = UsageRingStyle(snapshot: ringSnapshot(used: used, state: .ready))

            XCTAssertEqual(try? XCTUnwrap(style.usedFraction), used / 100)
            XCTAssertEqual(try? XCTUnwrap(style.remainingFraction), expectedRemaining)
            XCTAssertEqual(style.startAngle, -.pi / 2)
            XCTAssertFalse(style.isDashed)
        }
    }

    func testUnavailableUsesDashesWithoutInventingFractions() {
        let style = UsageRingStyle(snapshot: QuotaSnapshot(planType: nil, windows: [], updatedAt: .now, state: .unavailable("未连接")))

        XCTAssertNil(style.usedFraction)
        XCTAssertNil(style.remainingFraction)
        XCTAssertTrue(style.isDashed)
        XCTAssertEqual(style.colorSemantic, .unavailable)
    }

    func testStaleKeepsLastRealFractionsAtReducedOpacity() {
        let style = UsageRingStyle(snapshot: ringSnapshot(used: 18, state: .stale("连接中断")))

        XCTAssertEqual(try? XCTUnwrap(style.usedFraction), 0.18)
        XCTAssertEqual(try? XCTUnwrap(style.remainingFraction), 0.82)
        XCTAssertEqual(style.staleOpacity, 0.55)
        XCTAssertEqual(style.colorSemantic, .stale)
    }

    func testAccessibilityIncludesChineseResetDateWhenPresent() {
        let style = UsageRingStyle(snapshot: ringSnapshot(used: 18, state: .ready, reset: ringDate("2026-07-25T12:00:00Z")), language: .simplifiedChinese)

        XCTAssertEqual(style.accessibilityLabel, "Codex 剩余 82%，7月25日重置")
    }

    func testAccessibilityOmitsResetWhenAbsentAndExplainsUnavailable() {
        XCTAssertEqual(UsageRingStyle(snapshot: ringSnapshot(used: 18, state: .ready), language: .simplifiedChinese).accessibilityLabel, "Codex 剩余 82%")
        XCTAssertEqual(UsageRingStyle(snapshot: QuotaSnapshot(planType: nil, windows: [], updatedAt: .now, state: .unavailable("未连接")), language: .simplifiedChinese).accessibilityLabel, "Codex 用量暂不可用")
        XCTAssertEqual(UsageRingStyle(snapshot: ringSnapshot(used: 18, state: .ready), language: .english).accessibilityLabel, "Codex remaining 82%")
    }
}

private func ringSnapshot(used: Double, state: ConnectionState, reset: Date? = nil) -> QuotaSnapshot {
    QuotaSnapshot(
        planType: "Plus",
        windows: [QuotaWindow(id: "codex.primary", bucketID: "codex", displayName: "Codex", usedPercent: used, remainingPercent: 100 - used, windowDurationMinutes: 300, resetsAt: reset, isReached: used >= 100)],
        updatedAt: ringDate("2026-07-19T12:00:00Z"),
        state: state
    )
}

private func ringDate(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
