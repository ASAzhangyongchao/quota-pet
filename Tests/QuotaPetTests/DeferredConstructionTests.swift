import XCTest
@testable import QuotaPet

final class DeferredConstructionTests: XCTestCase {
    func testFactoryIsLazyAndRunsOnlyOnce() {
        var creationCount = 0
        let deferred = DeferredConstruction {
            creationCount += 1
            return NSObject()
        }

        XCTAssertEqual(creationCount, 0)
        XCTAssertFalse(deferred.isConstructed)
        let first = deferred.value
        let second = deferred.value

        XCTAssertEqual(creationCount, 1)
        XCTAssertTrue(deferred.isConstructed)
        XCTAssertTrue(first === second)
    }
}
