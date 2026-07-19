import Foundation
import XCTest
@testable import QuotaPet

final class UsageDetailsTests: XCTestCase {
    func testDetailFormattingIncludesWindowsResetTimezoneAndStaleStatus() {
        let reset = ISO8601DateFormatter().date(from: "2026-07-20T01:00:00Z")!
        let snapshot = QuotaSnapshot(planType: "Plus", windows: [QuotaWindow(id: "codex", bucketID: "codex", displayName: "Codex", usedPercent: 18, remainingPercent: 82, windowDurationMinutes: 300, resetsAt: reset, isReached: false)], updatedAt: ISO8601DateFormatter().date(from: "2026-07-19T12:00:00Z")!, state: .stale("连接中断"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let details = UsageDetailsPresentation(snapshot: snapshot, now: ISO8601DateFormatter().date(from: "2026-07-19T23:00:00Z")!, calendar: calendar)

        XCTAssertEqual(details.primaryText, "剩余 82% · 已用 18%")
        XCTAssertEqual(details.windows.first?.durationText, "5小时")
        XCTAssertEqual(details.windows.first?.resetText, "2026/7/20 09:00 GMT+8")
        XCTAssertEqual(details.statusText, "数据已过期：连接中断")
        XCTAssertEqual(details.updatedText, "更新于 2026/7/19 20:00 GMT+8")
        XCTAssertEqual(details.windows.first?.countdownText, "距重置 2小时")
    }
}
