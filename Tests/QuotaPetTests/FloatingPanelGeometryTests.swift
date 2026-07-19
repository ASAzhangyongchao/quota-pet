import AppKit
import XCTest
@testable import QuotaPet

final class FloatingPanelGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    func testPanelContractKeepsVisibleContentInsideSixPointGlowMargin() {
        XCTAssertEqual(FloatingPetPanelContract.glowInset, 6)
        XCTAssertEqual(FloatingPetPanelContract.visiblePetSize, CGSize(width: 72, height: 72))
        XCTAssertEqual(FloatingPetPanelContract.default.size, CGSize(width: 84, height: 84))
        XCTAssertEqual(FloatingPetPanelContract.detailContentSize, CGSize(width: 320, height: 354))
        XCTAssertEqual(FloatingPetPanelContract.expandedSize, CGSize(width: 332, height: 366))
    }

    func testExpansionKeepsTheCollapsedPetAtTheDetailTopLeft() {
        let collapsed = CGRect(x: 100, y: 600, width: 84, height: 84)

        let expanded = FloatingPanelGeometry.resizedFrame(
            from: collapsed,
            to: FloatingPetPanelContract.expandedSize,
            within: screen
        )

        XCTAssertEqual(expanded, CGRect(x: 100, y: 318, width: 332, height: 366))
        XCTAssertEqual(FloatingPanelGeometry.topLeft(of: expanded), FloatingPanelGeometry.topLeft(of: collapsed))
    }

    func testExpansionNearScreenEdgesMovesTheWholeWindowInside() {
        let collapsed = CGRect(x: 950, y: 16, width: 84, height: 84)

        let expanded = FloatingPanelGeometry.resizedFrame(
            from: collapsed,
            to: FloatingPetPanelContract.expandedSize,
            within: screen
        )

        XCTAssertEqual(expanded, CGRect(x: 668, y: 0, width: 332, height: 366))
    }

    func testCollapseUsesTheMovedDetailTopLeftAsItsAnchor() {
        let movedDetail = CGRect(x: 200, y: 150, width: 332, height: 366)

        let collapsed = FloatingPanelGeometry.resizedFrame(
            from: movedDetail,
            to: FloatingPetPanelContract.default.size,
            within: screen
        )

        XCTAssertEqual(collapsed, CGRect(x: 200, y: 432, width: 84, height: 84))
        XCTAssertEqual(FloatingPanelGeometry.topLeft(of: collapsed), FloatingPanelGeometry.topLeft(of: movedDetail))
    }

    func testDraggingCanTouchButNeverCrossAnyVisibleEdge() {
        XCTAssertEqual(
            FloatingPanelGeometry.clamped(frame: CGRect(x: -30, y: 790, width: 84, height: 84), within: screen),
            CGRect(x: 0, y: 716, width: 84, height: 84)
        )
        XCTAssertEqual(
            FloatingPanelGeometry.clamped(frame: CGRect(x: 990, y: -40, width: 332, height: 366), within: screen),
            CGRect(x: 668, y: 0, width: 332, height: 366)
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
