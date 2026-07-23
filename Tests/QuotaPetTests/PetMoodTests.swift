import XCTest
@testable import QuotaPet

final class PetMoodTests: XCTestCase {
    func testMoodThresholdsIncludeEveryBoundary() {
        XCTAssertEqual(PetMood(remainingPercent: 100), .thriving)
        XCTAssertEqual(PetMood(remainingPercent: 60), .thriving)
        XCTAssertEqual(PetMood(remainingPercent: 59), .content)
        XCTAssertEqual(PetMood(remainingPercent: 30), .content)
        XCTAssertEqual(PetMood(remainingPercent: 29), .concerned)
        XCTAssertEqual(PetMood(remainingPercent: 10), .concerned)
        XCTAssertEqual(PetMood(remainingPercent: 9), .critical)
        XCTAssertEqual(PetMood(remainingPercent: 1), .critical)
        XCTAssertEqual(PetMood(remainingPercent: 0), .sleeping)
        XCTAssertEqual(PetMood(remainingPercent: -4), .sleeping)
    }

    func testRenderStateClampsRealQuotaValues() {
        let state = PetRenderState(snapshot: snapshot(used: 130, remaining: 130, state: .ready), language: .simplifiedChinese)

        XCTAssertEqual(state.mood, .thriving)
        XCTAssertEqual(state.usedFraction, 1)
        XCTAssertEqual(state.accessibilityValue, "剩余 100%")
    }

    func testUsedFractionIncludesZeroAndOneBoundaries() {
        XCTAssertEqual(PetRenderState(snapshot: snapshot(used: 0, remaining: 100, state: .ready)).usedFraction, 0)
        XCTAssertEqual(PetRenderState(snapshot: snapshot(used: 100, remaining: 0, state: .ready)).usedFraction, 1)
    }

    func testUnavailableLoadingAndIncompatibleAreOfflineWithoutFractions() {
        for connectionState in [
            ConnectionState.loading,
            .unavailable("未连接"),
            .incompatible("版本不兼容"),
        ] {
            let state = PetRenderState(snapshot: snapshot(used: 20, remaining: 80, state: connectionState), language: .simplifiedChinese)

            XCTAssertEqual(state.mood, .offline)
            XCTAssertNil(state.usedFraction)
            XCTAssertTrue(state.dashedRing)
            XCTAssertEqual(state.accessibilityLabel, "离线")
        }
    }

    func testStaleUsesLastRealRemainingWithReducedOpacity() {
        let state = PetRenderState(snapshot: snapshot(used: 72, remaining: 28, state: .stale("连接中断")), language: .simplifiedChinese)

        XCTAssertEqual(state.mood, .concerned)
        XCTAssertEqual(state.usedFraction, 0.72)
        XCTAssertEqual(state.staleOpacity, 0.55)
        XCTAssertFalse(state.dashedRing)
        XCTAssertEqual(state.accessibilityValue, "剩余 28%，数据已过期")
    }

    func testEnglishAccessibilityIsAvailable() {
        let state = PetRenderState(snapshot: snapshot(used: 72, remaining: 28, state: .ready), language: .english)

        XCTAssertEqual(state.accessibilityLabel, "Low quota")
        XCTAssertEqual(state.accessibilityValue, "Remaining 28%")
    }

    func testAnimationOnlySchedulesBoundedOneShotEvents() {
        for event in [PetAnimationEvent.stateChange, .click, .hover] {
            let policy = PetAnimationPolicy(event: event, reduceMotion: false, petVisible: true, connectionMode: .realtime)

            XCTAssertTrue(policy.animationEnabled)
            XCTAssertTrue((180...260).contains(policy.durationMilliseconds!))
            XCTAssertNil(policy.idleBlinkDelayRangeSeconds)
            XCTAssertNil(policy.nextIdleBlinkDelay(randomUnit: 0.5))
        }
    }

    func testIdleBlinkIsOneShotWithInjectableNextDelayRange() {
        let policy = PetAnimationPolicy(event: .idleBlink, reduceMotion: false, petVisible: true, connectionMode: .realtime)

        XCTAssertTrue(policy.animationEnabled)
        XCTAssertEqual(policy.durationMilliseconds, 280)
        XCTAssertEqual(policy.idleBlinkDelayRangeSeconds, 8...16)
        XCTAssertEqual(policy.nextIdleBlinkDelay(randomUnit: 0), 8)
        XCTAssertEqual(policy.nextIdleBlinkDelay(randomUnit: 0.5), 12)
        XCTAssertEqual(policy.nextIdleBlinkDelay(randomUnit: 1), 16)
    }

    func testSleepingIdleUsesLongerSoftBreath() {
        let policy = PetAnimationPolicy(
            event: .idleBlink,
            reduceMotion: false,
            petVisible: true,
            connectionMode: .realtime,
            mood: .sleeping
        )
        XCTAssertEqual(policy.durationMilliseconds, 320)
        XCTAssertEqual(PetMood.sleeping.idleMotion, .sleepFaceBreath)
        XCTAssertEqual(PetMood.sleeping.idleFaceSequence, [PetIdleFaceFrame(atMilliseconds: 0, pose: .sleepInhale)])
    }

    func testMoodIdleMotionsStaySubtleAndMapped() {
        XCTAssertEqual(PetMood.thriving.idleMotion, .happyFaceBlink)
        XCTAssertEqual(PetMood.content.idleMotion, .happyFaceBlink)
        XCTAssertEqual(PetMood.concerned.idleMotion, .uneasyFaceBlink)
        XCTAssertEqual(PetMood.critical.idleMotion, .uneasyFaceBlink)
        XCTAssertEqual(PetMood.offline.idleMotion, .calmFaceBlink)
        XCTAssertEqual(PetMood.thriving.idleFaceSequence.first?.pose, .squint)
        XCTAssertEqual(PetMood.offline.idleFaceSequence.map(\.pose), [.squint, .blink, .squint])
    }

    func testIdleFacesAreFaceOnlyPosesNotBodyTransforms() {
        let happy = PetRenderState(snapshot: snapshot(used: 20, remaining: 80, state: .ready))
        XCTAssertEqual(happy.eyeShape, .dot)
        XCTAssertEqual(happy.mouthShape, .smile)
        XCTAssertEqual(happy.withIdleFace(.happyBlink).eyeShape, .closed)
        XCTAssertEqual(happy.withIdleFace(.happyBlink).mouthShape, .softSmile)

        let concerned = PetRenderState(snapshot: snapshot(used: 80, remaining: 20, state: .ready))
        XCTAssertEqual(concerned.eyeShape, .worried)
        XCTAssertEqual(concerned.withIdleFace(.uneasyBlink).mouthShape, .frown)

        let sleeping = PetRenderState(snapshot: snapshot(used: 100, remaining: 0, state: .ready))
        XCTAssertEqual(sleeping.eyeShape, .closed)
        XCTAssertEqual(sleeping.withIdleFace(.sleepInhale).mouthShape, .sleepOpen)
        XCTAssertEqual(sleeping.withIdleFace(.sleepInhale).eyeShape, .closed)
    }

    func testIdleMotionWorksInEnergySaverMode() {
        let policy = PetAnimationPolicy(
            event: .idleBlink,
            reduceMotion: false,
            petVisible: true,
            connectionMode: .energySaver
        )
        XCTAssertTrue(policy.animationEnabled)
        XCTAssertEqual(policy.durationMilliseconds, 280)
        XCTAssertEqual(policy.idleBlinkDelayRangeSeconds, 8...16)
    }

    func testAnimationIsDisabledForReduceMotionAndHiddenPet() {
        let blockedPolicies = [
            PetAnimationPolicy(event: .idleBlink, reduceMotion: true, petVisible: true, connectionMode: .realtime),
            PetAnimationPolicy(event: .idleBlink, reduceMotion: false, petVisible: false, connectionMode: .realtime),
            PetAnimationPolicy(event: .idleBlink, reduceMotion: true, petVisible: true, connectionMode: .energySaver),
        ]

        for policy in blockedPolicies {
            XCTAssertFalse(policy.animationEnabled)
            XCTAssertNil(policy.durationMilliseconds)
            XCTAssertNil(policy.idleBlinkDelayRangeSeconds)
            XCTAssertNil(policy.nextIdleBlinkDelay(randomUnit: 0.5))
        }
    }
}

private func snapshot(used: Double, remaining: Double, state: ConnectionState) -> QuotaSnapshot {
    QuotaSnapshot(
        planType: "Plus",
        windows: [QuotaWindow(id: "codex.primary", bucketID: "codex", displayName: "Codex", usedPercent: used, remainingPercent: remaining, windowDurationMinutes: 300, resetsAt: nil, isReached: used >= 100)],
        updatedAt: .now,
        state: state
    )
}
