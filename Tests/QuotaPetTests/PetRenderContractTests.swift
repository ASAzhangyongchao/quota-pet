import XCTest
@testable import QuotaPet

final class PetRenderContractTests: XCTestCase {
    func testRenderContractKeepsTheLightweightDrawingBudget() {
        XCTAssertLessThanOrEqual(PetRenderContract.pathBudget, 16)
        XCTAssertLessThanOrEqual(PetRenderContract.gradientBudget, 2)
        XCTAssertEqual(PetRenderContract.bodyMaxDimension, 60)
        XCTAssertFalse(PetRenderContract.usesContinuousTimeline)
        XCTAssertEqual(PetRenderContract.externalAssetCount, 0)
        XCTAssertEqual(PetRenderContract.emojiGlyphCount, 0)
    }

    func testMoodExpressionAndStatusSignalsAreSemantic() {
        let critical = PetRenderState(snapshot: renderSnapshot(remaining: 9, state: .ready))
        XCTAssertEqual(critical.eyeShape, .line)
        XCTAssertEqual(critical.mouthShape, .frown)
        XCTAssertTrue(critical.showsSweat)

        let sleeping = PetRenderState(snapshot: renderSnapshot(remaining: 0, state: .ready))
        XCTAssertEqual(sleeping.eyeShape, .closed)
        XCTAssertEqual(sleeping.mouthShape, .sleep)
        XCTAssertTrue(sleeping.showsSleepMark)

        let offline = PetRenderState(snapshot: renderSnapshot(remaining: 70, state: .unavailable("未连接")))
        XCTAssertTrue(offline.dashedRing)
        XCTAssertFalse(offline.showsSweat)
        XCTAssertFalse(offline.showsSleepMark)
    }

    func testAccessibilityCommunicatesEachMoodWithoutRelyingOnColor() {
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 60, state: .ready)).accessibilityLabel, "额度充足")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 59, state: .ready)).accessibilityLabel, "正常")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 29, state: .ready)).accessibilityLabel, "注意")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 9, state: .ready)).accessibilityLabel, "即将耗尽")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 0, state: .ready)).accessibilityLabel, "等待重置")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 29, state: .ready)).accessibilityValue, "剩余 29%")
    }
}

private func renderSnapshot(remaining: Double, state: ConnectionState) -> QuotaSnapshot {
    QuotaSnapshot(
        planType: "Plus",
        windows: [QuotaWindow(id: "codex.primary", bucketID: "codex", displayName: "Codex", usedPercent: 100 - remaining, remainingPercent: remaining, windowDurationMinutes: 300, resetsAt: nil, isReached: remaining <= 0)],
        updatedAt: .now,
        state: state
    )
}
