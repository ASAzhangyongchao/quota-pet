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

    func testRingAndTailStayInsideSafeBoundsAtEveryQuarterTurn() {
        for size in [CGFloat(72), 48] {
            let canvasSize = CGSize(width: size, height: size)
            let safeBounds = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)

            XCTAssertTrue(safeBounds.contains(PetDrawingPlan.renderedRingBounds(in: canvasSize)))
            for usedFraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let tail = PetTailGeometry(usedFraction: usedFraction, canvasSize: canvasSize)

                for point in tail.points {
                    XCTAssertTrue(safeBounds.contains(point), "\(size)pt / \(usedFraction) tail point escaped: \(point)")
                }
                XCTAssertTrue(safeBounds.contains(tail.renderedBounds), "\(size)pt / \(usedFraction) tail bounds escaped: \(tail.renderedBounds)")
            }
        }
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
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 60, state: .ready), language: .simplifiedChinese).accessibilityLabel, "额度充足")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 59, state: .ready), language: .simplifiedChinese).accessibilityLabel, "正常")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 29, state: .ready), language: .simplifiedChinese).accessibilityLabel, "注意")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 9, state: .ready), language: .simplifiedChinese).accessibilityLabel, "即将耗尽")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 0, state: .ready), language: .simplifiedChinese).accessibilityLabel, "等待重置")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 29, state: .ready), language: .simplifiedChinese).accessibilityValue, "剩余 29%")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 29, state: .ready)).remainingPercentText, "29%")
        XCTAssertEqual(PetRenderState(snapshot: renderSnapshot(remaining: 70, state: .unavailable("未连接"))).remainingPercentText, "--")
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
