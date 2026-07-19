import XCTest
@testable import QuotaPet

final class QuotaVisualStyleTests: XCTestCase {
    func testReadyStyleUsesDistinctUsedAndRemainingSegments() throws {
        let style = QuotaVisualStyle(
            snapshot: visualSnapshot(used: 38, state: .ready),
            connectionMode: .realtime
        )

        XCTAssertEqual(try XCTUnwrap(style.usedFraction), 0.38, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(style.remainingFraction), 0.62, accuracy: 0.0001)
        XCTAssertEqual(style.usedColor, .used)
        XCTAssertEqual(style.remainingColor, .remaining)
        XCTAssertNotEqual(style.usedColor.rgba, style.remainingColor.rgba)
        XCTAssertEqual(style.haloKind, .ready)
        XCTAssertEqual(style.contentOpacity, 1)
    }

    func testFractionsAreClampedAndLowQuotaChangesHaloSemantic() throws {
        let warning = QuotaVisualStyle(
            snapshot: visualSnapshot(used: 88, remaining: 12, state: .ready),
            connectionMode: .realtime
        )
        let depleted = QuotaVisualStyle(
            snapshot: visualSnapshot(used: 130, remaining: -30, state: .ready),
            connectionMode: .realtime
        )

        XCTAssertEqual(warning.haloKind, .warning)
        XCTAssertEqual(depleted.haloKind, .depleted)
        XCTAssertEqual(try XCTUnwrap(depleted.usedFraction), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(depleted.remainingFraction), 0, accuracy: 0.0001)
    }

    func testStaleStyleRetainsFractionsAtReducedOpacity() throws {
        let style = QuotaVisualStyle(
            snapshot: visualSnapshot(used: 38, state: .stale("offline")),
            connectionMode: .realtime
        )

        XCTAssertEqual(try XCTUnwrap(style.usedFraction), 0.38, accuracy: 0.0001)
        XCTAssertEqual(style.contentOpacity, 0.55)
        XCTAssertEqual(style.haloKind, .unavailable)
        XCTAssertLessThan(style.haloOpacity, 0.3)
    }

    func testUnavailableStyleUsesNoInventedFractions() {
        let style = QuotaVisualStyle(
            snapshot: QuotaSnapshot(planType: nil, windows: [], updatedAt: .now, state: .unavailable("offline")),
            connectionMode: .realtime
        )

        XCTAssertNil(style.usedFraction)
        XCTAssertNil(style.remainingFraction)
        XCTAssertEqual(style.haloKind, .unavailable)
    }

    func testEnergySaverReducesStaticHaloOpacity() {
        let snapshot = visualSnapshot(used: 38, state: .ready)
        let realtime = QuotaVisualStyle(snapshot: snapshot, connectionMode: .realtime)
        let energySaver = QuotaVisualStyle(snapshot: snapshot, connectionMode: .energySaver)

        XCTAssertLessThan(energySaver.haloOpacity, realtime.haloOpacity)
    }
}

private func visualSnapshot(
    used: Double,
    remaining: Double? = nil,
    state: ConnectionState
) -> QuotaSnapshot {
    QuotaSnapshot(
        planType: "Plus",
        windows: [
            QuotaWindow(
                id: "codex.primary",
                bucketID: "codex",
                displayName: "Codex",
                usedPercent: used,
                remainingPercent: remaining ?? 100 - used,
                windowDurationMinutes: 300,
                resetsAt: nil,
                isReached: (remaining ?? 100 - used) <= 0
            ),
        ],
        updatedAt: .now,
        state: state
    )
}
