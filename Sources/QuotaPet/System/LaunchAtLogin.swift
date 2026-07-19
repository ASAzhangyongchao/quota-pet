import Foundation
import ServiceManagement

protocol LaunchAtLoginServicing: AnyObject {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

private final class MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        switch service.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

struct LaunchAtLoginUpdate: Equatable {
    let isEnabled: Bool
    let errorMessage: String?
}

@MainActor
final class LaunchAtLogin {
    private let service: any LaunchAtLoginServicing

    init(service: any LaunchAtLoginServicing = MainAppLaunchAtLoginService()) {
        self.service = service
    }

    var isEnabled: Bool { service.isEnabled }

    func setEnabled(_ enabled: Bool) -> LaunchAtLoginUpdate {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            return LaunchAtLoginUpdate(isEnabled: service.isEnabled, errorMessage: nil)
        } catch {
            return LaunchAtLoginUpdate(isEnabled: service.isEnabled, errorMessage: error.localizedDescription)
        }
    }
}
