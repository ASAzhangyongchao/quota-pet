import AppKit
import XCTest
@testable import QuotaPet

@MainActor
final class TerminationCoordinatorTests: XCTestCase {
    func testReturnsLaterRepliesOnlyAfterStopAndDeduplicatesRequests() async {
        let stop = ControlledStop()
        var replyCount = 0
        let coordinator = TerminationCoordinator(stop: { await stop.run() })

        XCTAssertEqual(coordinator.requestTermination { replyCount += 1 }, .terminateLater)
        XCTAssertEqual(coordinator.requestTermination { replyCount += 1 }, .terminateLater)
        await drainTerminationTasks()

        XCTAssertEqual(stop.callCount, 1)
        XCTAssertEqual(replyCount, 0)

        stop.finish()
        await drainTerminationTasks()

        XCTAssertEqual(replyCount, 1)
        XCTAssertEqual(stop.callCount, 1)
    }
}

@MainActor
private final class ControlledStop {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0

    func run() async {
        callCount += 1
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private func drainTerminationTasks() async {
    for _ in 0..<10 { await Task.yield() }
}
