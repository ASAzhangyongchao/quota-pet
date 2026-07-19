import AppKit
import XCTest
@testable import QuotaPet

final class FloatingPanelGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    func testExpansionKeepsTheCollapsedPetAtTheDetailTopLeft() {
        let collapsed = CGRect(x: 100, y: 600, width: 72, height: 72)

        let expanded = FloatingPanelGeometry.resizedFrame(
            from: collapsed,
            to: CGSize(width: 320, height: 354),
            within: screen
        )

        XCTAssertEqual(expanded, CGRect(x: 100, y: 318, width: 320, height: 354))
        XCTAssertEqual(FloatingPanelGeometry.topLeft(of: expanded), FloatingPanelGeometry.topLeft(of: collapsed))
    }

    func testExpansionNearScreenEdgesMovesTheWholeWindowInside() {
        let collapsed = CGRect(x: 950, y: 28, width: 72, height: 72)

        let expanded = FloatingPanelGeometry.resizedFrame(
            from: collapsed,
            to: CGSize(width: 320, height: 354),
            within: screen
        )

        XCTAssertEqual(expanded, CGRect(x: 680, y: 0, width: 320, height: 354))
    }

    func testCollapseUsesTheMovedDetailTopLeftAsItsAnchor() {
        let movedDetail = CGRect(x: 200, y: 150, width: 320, height: 354)

        let collapsed = FloatingPanelGeometry.resizedFrame(
            from: movedDetail,
            to: CGSize(width: 72, height: 72),
            within: screen
        )

        XCTAssertEqual(collapsed, CGRect(x: 200, y: 432, width: 72, height: 72))
        XCTAssertEqual(FloatingPanelGeometry.topLeft(of: collapsed), FloatingPanelGeometry.topLeft(of: movedDetail))
    }

    func testDraggingCanTouchButNeverCrossAnyVisibleEdge() {
        XCTAssertEqual(
            FloatingPanelGeometry.clamped(frame: CGRect(x: -30, y: 790, width: 72, height: 72), within: screen),
            CGRect(x: 0, y: 728, width: 72, height: 72)
        )
        XCTAssertEqual(
            FloatingPanelGeometry.clamped(frame: CGRect(x: 990, y: -40, width: 320, height: 354), within: screen),
            CGRect(x: 680, y: 0, width: 320, height: 354)
        )
    }

    func testPointerSelectsTheDestinationDisplayDuringCrossScreenDrag() {
        let displays = [
            CGRect(x: 0, y: 0, width: 1_000, height: 800),
            CGRect(x: 1_000, y: -100, width: 1_200, height: 900),
        ]

        XCTAssertEqual(
            FloatingPanelGeometry.displayFrame(containing: CGPoint(x: 1_040, y: 400), from: displays),
            displays[1]
        )
        XCTAssertNil(FloatingPanelGeometry.displayFrame(containing: CGPoint(x: 4_000, y: 400), from: displays))
    }
}
