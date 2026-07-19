import Foundation
import XCTest
@testable import QuotaPet

final class UsageDetailsTests: XCTestCase {
    func testUnavailableDetailsOfferConfirmationAction() {
        let snapshot = QuotaSnapshot(
            planType: nil,
            windows: [],
            updatedAt: .now,
            state: .unavailable("未找到已信任的 Codex 可执行文件")
        )

        let details = UsageDetailsPresentation(snapshot: snapshot, language: .simplifiedChinese)

        XCTAssertEqual(details.connectionActionTitle, "确认并读取用量")
        XCTAssertNil(details.updatedText)
    }

    func testDetailFormattingIncludesWindowsResetTimezoneAndStaleStatus() throws {
        let reset = ISO8601DateFormatter().date(from: "2026-07-20T01:00:00Z")!
        let snapshot = QuotaSnapshot(planType: "Plus", windows: [QuotaWindow(id: "codex", bucketID: "codex", displayName: "Codex", usedPercent: 18, remainingPercent: 82, windowDurationMinutes: 300, resetsAt: reset, isReached: false)], updatedAt: ISO8601DateFormatter().date(from: "2026-07-19T12:00:00Z")!, state: .stale("连接中断"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let details = UsageDetailsPresentation(snapshot: snapshot, now: ISO8601DateFormatter().date(from: "2026-07-19T23:00:00Z")!, calendar: calendar, language: .simplifiedChinese)

        let window = try XCTUnwrap(details.windows.first)
        XCTAssertEqual(details.primaryText, "剩余 82% · 已用 18%")
        XCTAssertEqual(window.durationText, "5小时")
        XCTAssertEqual(window.usedFraction, 0.18, accuracy: 0.0001)
        XCTAssertEqual(window.remainingFraction, 0.82, accuracy: 0.0001)
        XCTAssertEqual(window.meterAccessibilityText, "已用 18%，剩余 82%")
        XCTAssertEqual(window.resetText, "重置于 2026年7月20日 09:00")
        XCTAssertEqual(details.statusText, "数据已过期：连接中断")
        XCTAssertEqual(details.updatedText, "更新于 2026年7月19日 20:00")
        XCTAssertEqual(window.countdownText, "距重置 2小时")
    }

    func testLongCountdownUsesDaysAndInternalPrimaryNamesAreHidden() {
        let reset = ISO8601DateFormatter().date(from: "2026-07-25T03:25:00Z")!
        let snapshot = QuotaSnapshot(
            planType: "Plus",
            windows: [
                QuotaWindow(id: "codex|primary", bucketID: "codex", displayName: "primary", usedPercent: 37, remainingPercent: 63, windowDurationMinutes: nil, resetsAt: reset, isReached: false),
                QuotaWindow(id: "codex_bengalfox|primary", bucketID: "codex_bengalfox", displayName: "primary", usedPercent: 0, remainingPercent: 100, windowDurationMinutes: nil, resetsAt: reset, isReached: false),
            ],
            updatedAt: reset,
            state: .ready
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

        let details = UsageDetailsPresentation(
            snapshot: snapshot,
            now: ISO8601DateFormatter().date(from: "2026-07-19T12:00:00Z")!,
            calendar: calendar,
            language: .simplifiedChinese
        )

        XCTAssertEqual(details.windows.map(\.name), ["通用使用限额", "GPT-5.3-Codex-Spark 使用限额"])
        XCTAssertTrue(details.windows.allSatisfy { $0.noteText == nil })
        XCTAssertEqual(details.windows.first?.countdownText, "距重置 6天")
        XCTAssertNil(details.windows.first?.durationText)
    }

    func testCountdownSwitchesFromHoursToDaysAt24Hours() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = QuotaSnapshot(
            planType: nil,
            windows: [
                QuotaWindow(id: "short", bucketID: "codex", displayName: "短周期", usedPercent: 0, remainingPercent: 100, windowDurationMinutes: nil, resetsAt: now.addingTimeInterval(23 * 60 * 60), isReached: false),
                QuotaWindow(id: "long", bucketID: "codex", displayName: "长周期", usedPercent: 0, remainingPercent: 100, windowDurationMinutes: nil, resetsAt: now.addingTimeInterval(25 * 60 * 60), isReached: false),
            ],
            updatedAt: now,
            state: .ready
        )

        let details = UsageDetailsPresentation(snapshot: snapshot, now: now, language: .simplifiedChinese)

        XCTAssertEqual(details.windows[0].countdownText, "距重置 23小时")
        XCTAssertEqual(details.windows[1].countdownText, "距重置 2天")
    }

    func testOfficialQuotaNamesHaveEnglishEquivalents() {
        let snapshot = QuotaSnapshot(
            planType: nil,
            windows: [
                QuotaWindow(id: "codex|primary", bucketID: "codex", displayName: "primary", usedPercent: 10, remainingPercent: 90, windowDurationMinutes: nil, resetsAt: nil, isReached: false),
                QuotaWindow(id: "codex_bengalfox|primary", bucketID: "codex_bengalfox", displayName: "primary", usedPercent: 20, remainingPercent: 80, windowDurationMinutes: nil, resetsAt: nil, isReached: false),
            ],
            updatedAt: .now,
            state: .ready
        )

        let details = UsageDetailsPresentation(snapshot: snapshot, language: .english)

        XCTAssertEqual(details.windows.map(\.name), ["General usage limit", "GPT-5.3-Codex-Spark usage limit"])
        XCTAssertTrue(details.windows.allSatisfy { $0.noteText == nil })
        XCTAssertEqual(details.windows.first?.meterAccessibilityText, "Used 10%, remaining 90%")
    }
}
