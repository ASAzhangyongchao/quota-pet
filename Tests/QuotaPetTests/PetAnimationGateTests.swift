import XCTest
@testable import QuotaPet

final class PetAnimationGateTests: XCTestCase {
    func testGateConsumesOneShotAndCancelsWhenHiddenOrReduceMotion() {
        var gate = PetAnimationGate()
        XCTAssertEqual(gate.consume(.click, reduceMotion: false, petVisible: true, connectionMode: .realtime)?.durationMilliseconds, 200)
        XCTAssertNil(gate.consume(.click, reduceMotion: false, petVisible: true, connectionMode: .realtime))
        gate.complete()
        XCTAssertNotNil(gate.consume(.stateChange, reduceMotion: false, petVisible: true, connectionMode: .realtime))
        gate.cancel()
        XCTAssertFalse(gate.isActive)
        XCTAssertNil(gate.consume(.idleBlink, reduceMotion: false, petVisible: false, connectionMode: .realtime))
        XCTAssertNil(gate.consume(.idleBlink, reduceMotion: true, petVisible: true, connectionMode: .energySaver))
        XCTAssertNotNil(gate.consume(.idleBlink, reduceMotion: false, petVisible: true, connectionMode: .energySaver))
    }
}
