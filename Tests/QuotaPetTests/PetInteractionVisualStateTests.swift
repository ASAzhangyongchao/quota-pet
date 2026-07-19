import XCTest
@testable import QuotaPet

@MainActor
final class PetInteractionVisualStateTests: XCTestCase {
    func testClickHoverAndBlinkProduceRealVisualStateThenReset() {
        let state = PetInteractionVisualState()
        state.activate(.click)
        XCTAssertGreaterThan(state.scale, 1)
        state.reset()
        XCTAssertEqual(state.scale, 1)
        state.activate(.hover)
        XCTAssertNotEqual(state.rotation, .zero)
        state.activate(.idleBlink)
        XCTAssertTrue(state.isBlinking)
        state.reset()
        XCTAssertFalse(state.isBlinking)
        XCTAssertEqual(state.rotation, .zero)
    }

    func testCancelledResetGenerationCannotAffectNewAnimation() {
        var generation = AnimationResetGeneration()
        let old = generation.begin()
        generation.cancel()
        let current = generation.begin()
        XCTAssertFalse(generation.accepts(old))
        XCTAssertTrue(generation.accepts(current))
    }
}
