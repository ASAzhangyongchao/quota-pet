import XCTest
@testable import QuotaPet

final class AppSmokeTests: XCTestCase {
    func testProductIdentity() {
        XCTAssertEqual(ProductInfo.name, "QuotaPet")
        XCTAssertEqual(ProductInfo.bundleIdentifier, "io.github.asazhangyongchao.quotapet")
    }
}
