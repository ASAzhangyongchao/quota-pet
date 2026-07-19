import Foundation
import XCTest
@testable import QuotaPet

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testRegistrationFailureRestoresActualStateAndExposesSystemError() {
        let service = TestLaunchAtLoginService(isEnabled: false)
        service.registerError = NSError(domain: "SMAppService", code: 1, userInfo: [NSLocalizedDescriptionKey: "registration denied"])
        let launchAtLogin = LaunchAtLogin(service: service)

        let update = launchAtLogin.setEnabled(true)

        XCTAssertFalse(update.isEnabled)
        XCTAssertEqual(update.errorMessage, "registration denied")
    }

    func testSuccessfulRegistrationAndUnregistrationReflectServiceState() {
        let service = TestLaunchAtLoginService(isEnabled: false)
        let launchAtLogin = LaunchAtLogin(service: service)

        XCTAssertTrue(launchAtLogin.setEnabled(true).isEnabled)
        XCTAssertFalse(launchAtLogin.setEnabled(false).isEnabled)
        XCTAssertNil(launchAtLogin.setEnabled(false).errorMessage)
    }
}

private final class TestLaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled: Bool
    var registerError: Error?
    var unregisterError: Error?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func register() throws {
        if let registerError { throw registerError }
        isEnabled = true
    }

    func unregister() throws {
        if let unregisterError { throw unregisterError }
        isEnabled = false
    }
}
