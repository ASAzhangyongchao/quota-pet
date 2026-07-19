import XCTest
@testable import QuotaPet

final class PetDetailInteractionTests: XCTestCase {
    func testClickDefersDetailUntilAnimationCompletesAndCancelsReplacement() {
        var state = PetDetailInteractionState()
        XCTAssertEqual(state.tap(animationEnabled: true), .playThenExpand)
        XCTAssertFalse(state.detailVisible)
        XCTAssertTrue(state.pendingExpansion)
        XCTAssertEqual(state.tap(animationEnabled: true), .playThenExpand)
        XCTAssertFalse(state.detailVisible)
        state.animationCompleted()
        XCTAssertTrue(state.detailVisible)
        XCTAssertFalse(state.pendingExpansion)
    }

    func testDisabledAnimationExpandsImmediatelyAndDetailPetCollapses() {
        var state = PetDetailInteractionState()
        XCTAssertEqual(state.tap(animationEnabled: false), .expandImmediately)
        XCTAssertTrue(state.detailVisible)
        state.tapDetailPet()
        XCTAssertFalse(state.detailVisible)
    }
}
