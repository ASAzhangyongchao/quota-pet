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
        let state = PetRenderState(snapshot: snapshot(used: 130, remaining: 130, state: .ready))

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
            let state = PetRenderState(snapshot: snapshot(used: 20, remaining: 80, state: connectionState))

            XCTAssertEqual(state.mood, .offline)
            XCTAssertNil(state.usedFraction)
            XCTAssertTrue(state.dashedRing)
            XCTAssertEqual(state.accessibilityLabel, "离线")
        }
    }

    func testStaleUsesLastRealRemainingWithReducedOpacity() {
        let state = PetRenderState(snapshot: snapshot(used: 72, remaining: 28, state: .stale("连接中断")))

        XCTAssertEqual(state.mood, .concerned)
        XCTAssertEqual(state.usedFraction, 0.72)
        XCTAssertEqual(state.staleOpacity, 0.55)
        XCTAssertFalse(state.dashedRing)
        XCTAssertEqual(state.accessibilityValue, "剩余 28%")
    }

    func testAnimationOnlySchedulesBoundedOneShotEvents() {
        for event in [PetAnimationEvent.stateChange, .click, .hover] {
            let policy = PetAnimationPolicy(event: event, reduceMotion: false, petVisible: true, connectionMode: .realtime)

            XCTAssertTrue(policy.animationEnabled)
            XCTAssertTrue((180...260).contains(policy.durationMilliseconds!))
            XCTAssertNil(policy.idleBlinkIntervalSeconds)
        }
    }

    func testIdleBlinkIsRareAndShort() {
        let policy = PetAnimationPolicy(event: .idleBlink, reduceMotion: false, petVisible: true, connectionMode: .realtime)

        XCTAssertTrue(policy.animationEnabled)
        XCTAssertTrue((45...90).contains(policy.idleBlinkIntervalSeconds!))
        XCTAssertLessThanOrEqual(policy.durationMilliseconds!, 160)
    }

    func testAnimationIsDisabledForEveryGate() {
        let blockedPolicies = [
            PetAnimationPolicy(event: .idleBlink, reduceMotion: true, petVisible: true, connectionMode: .realtime),
            PetAnimationPolicy(event: .idleBlink, reduceMotion: false, petVisible: false, connectionMode: .realtime),
            PetAnimationPolicy(event: .idleBlink, reduceMotion: false, petVisible: true, connectionMode: .energySaver),
        ]

        for policy in blockedPolicies {
            XCTAssertFalse(policy.animationEnabled)
            XCTAssertNil(policy.durationMilliseconds)
            XCTAssertNil(policy.idleBlinkIntervalSeconds)
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
