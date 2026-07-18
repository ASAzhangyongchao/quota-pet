import Foundation
import XCTest
@testable import QuotaPet

final class QuotaParserTests: XCTestCase {
    func testParsesCodexWindowsAndSelectsMostUsedAsPrimary() throws {
        let snapshot = try parse([
            "planType": "pro",
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": window(usedPercent: 18, durationMinutes: 300, resetsAt: 1_700_000_000),
                    "secondary": window(usedPercent: 72, durationMinutes: 10_080, resetsAt: 1_700_000_600),
                ],
            ],
        ])

        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.primary?.usedPercent, 72)
        XCTAssertEqual(snapshot.primary?.remainingPercent, 28)
        XCTAssertEqual(snapshot.windows[0].resetsAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(snapshot.windows[1].resetsAt, Date(timeIntervalSince1970: 1_700_000_600))
    }

    func testFallsBackToTopLevelRateLimits() throws {
        let snapshot = try parse([
            "rateLimits": [
                "codex": [
                    "primary": window(usedPercent: 41, durationMinutes: 300, resetsAt: 1_700_000_000),
                ],
            ],
        ])

        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.primary?.bucketID, "codex")
        XCTAssertEqual(snapshot.primary?.usedPercent, 41)
    }

    func testFallsBackWhenRateLimitsByLimitIDHasNoValidWindows() throws {
        let snapshot = try parse([
            "rateLimitsByLimitId": ["codex": ["primary": ["used_percent": false]]],
            "rateLimits": [
                "codex": [
                    "primary": window(usedPercent: 41, durationMinutes: 300, resetsAt: 1_700_000_000),
                ],
            ],
        ])

        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.primary?.usedPercent, 41)
    }

    func testSelectsCodexBucketBeforeMoreUsedNonCodexBuckets() throws {
        let snapshot = try parse([
            "rateLimitsByLimitId": [
                "gpt": ["primary": window(usedPercent: 99, durationMinutes: 60, resetsAt: 1_700_000_000)],
                "codex": ["primary": window(usedPercent: 48, durationMinutes: 300, resetsAt: 1_700_000_000)],
                "other": ["primary": window(usedPercent: 88, durationMinutes: 60, resetsAt: 1_700_000_000)],
            ],
        ])

        XCTAssertEqual(snapshot.primary?.bucketID, "codex")
        XCTAssertEqual(snapshot.primary?.usedPercent, 48)
    }

    func testSelectsMostUsedWindowWhenCodexBucketIsAbsent() throws {
        let snapshot = try parse([
            "rateLimitsByLimitId": [
                "gpt": ["primary": window(usedPercent: 48, durationMinutes: 60, resetsAt: 1_700_000_000)],
                "other": ["secondary": window(usedPercent: 88, durationMinutes: 60, resetsAt: 1_700_000_000)],
            ],
        ])

        XCTAssertEqual(snapshot.primary?.bucketID, "other")
        XCTAssertEqual(snapshot.primary?.usedPercent, 88)
    }

    func testClampsPercentagesAndComputesRemaining() throws {
        let snapshot = try parse([
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": window(usedPercent: -4, durationMinutes: 300, resetsAt: 1_700_000_000),
                    "secondary": window(usedPercent: 120, durationMinutes: 10_080, resetsAt: 1_700_000_000),
                ],
            ],
        ])

        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [0, 100])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [100, 0])
        XCTAssertEqual(snapshot.windows.map(\.isReached), [false, true])
    }

    func testThrowsForInvalidJSONAndReturnsUnavailableForNoValidWindows() throws {
        XCTAssertThrowsError(try QuotaParser.parse(data: Data("not json".utf8)))

        let snapshot = try parse([
            "rateLimitsByLimitId": ["codex": ["primary": ["window_duration_mins": 50]]],
        ])

        XCTAssertEqual(snapshot, QuotaSnapshot(
            planType: nil,
            windows: [],
            updatedAt: snapshot.updatedAt,
            state: .unavailable("未返回 Codex 用量窗口")
        ))
    }

    func testRejectsBooleanValuesForNumericQuotaFields() throws {
        let unavailable = try parse([
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": ["used_percent": false, "window_duration_mins": 300],
                ],
            ],
        ])
        XCTAssertEqual(unavailable.state, .unavailable("未返回 Codex 用量窗口"))

        let snapshot = try parse([
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": [
                        "used_percent": 42,
                        "window_duration_mins": true,
                        "resets_at": false,
                    ],
                ],
            ],
        ])

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercent, 42)
        XCTAssertNil(snapshot.windows[0].windowDurationMinutes)
        XCTAssertNil(snapshot.windows[0].resetsAt)
    }

    func testGeneratesStableDistinctWindowIDs() throws {
        let payload: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": window(usedPercent: 10, durationMinutes: 300, resetsAt: 1_700_000_000),
                    "secondary": window(usedPercent: 10, durationMinutes: 300, resetsAt: 1_700_000_000),
                ],
            ],
        ]

        let first = try parse(payload)
        let second = try parse(payload)

        XCTAssertEqual(first.windows.map(\.id), second.windows.map(\.id))
        XCTAssertNotEqual(first.windows[0].id, first.windows[1].id)
    }

    func testBoundsBucketsAndExternalDisplayStrings() throws {
        var buckets: [String: Any] = [:]
        for index in 0..<130 {
            buckets["bucket-\(index)"] = [
                "primary": window(usedPercent: Double(index), durationMinutes: 60, resetsAt: 1_700_000_000),
            ]
        }
        let longDisplayName = String(repeating: "👩🏽‍💻", count: 300)
        let longBucketID = String(repeating: "b", count: 300)
        buckets[longBucketID] = [
            "primary": window(usedPercent: 49, durationMinutes: 60, resetsAt: 1_700_000_000),
        ]
        buckets["codex"] = [
            "primary": [
                "usedPercent": 50,
                "windowDurationMinutes": 300,
                "resetsAt": 1_700_000_000,
                "displayName": longDisplayName,
            ],
        ]

        let snapshot = try parse([
            "planType": String(repeating: "p", count: 300),
            "rateLimitsByLimitId": buckets,
        ])

        XCTAssertLessThanOrEqual(snapshot.windows.count, 128)
        XCTAssertEqual(snapshot.primary?.bucketID, "codex")
        XCTAssertEqual(snapshot.planType?.unicodeScalars.count, 256)
        XCTAssertEqual(snapshot.primary?.displayName.unicodeScalars.count, 256)
        XCTAssertTrue(snapshot.windows.contains { $0.bucketID.unicodeScalars.count == 256 })
    }

    private func parse(_ object: [String: Any]) throws -> QuotaSnapshot {
        try QuotaParser.parse(data: try JSONSerialization.data(withJSONObject: object))
    }

    private func window(usedPercent: Double, durationMinutes: Int, resetsAt: TimeInterval) -> [String: Any] {
        [
            "used_percent": usedPercent,
            "window_duration_mins": durationMinutes,
            "resets_at": resetsAt,
        ]
    }
}
