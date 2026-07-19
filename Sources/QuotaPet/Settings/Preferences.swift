import AppKit
import Combine
import Foundation

struct NormalizedScreenPosition: Codable, Equatable {
    let x: CGFloat
    let y: CGFloat
    let screenIdentifier: String?

    init(x: CGFloat, y: CGFloat, screenIdentifier: String?) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.screenIdentifier = screenIdentifier
    }

    init(panelOrigin: CGPoint, panelSize: CGSize, visibleFrame: CGRect, screenIdentifier: String?) {
        let availableWidth = max(visibleFrame.width - panelSize.width, 0)
        let availableHeight = max(visibleFrame.height - panelSize.height, 0)
        self.init(
            x: availableWidth == 0 ? 0 : (panelOrigin.x - visibleFrame.minX) / availableWidth,
            y: availableHeight == 0 ? 0 : (panelOrigin.y - visibleFrame.minY) / availableHeight,
            screenIdentifier: screenIdentifier
        )
    }

    func panelOrigin(panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let width = max(visibleFrame.width - panelSize.width, 0)
        let height = max(visibleFrame.height - panelSize.height, 0)
        return CGPoint(x: visibleFrame.minX + x * width, y: visibleFrame.minY + y * height)
    }
}

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let petVisible = "QuotaPet.petVisible"
        static let alwaysOnTop = "QuotaPet.alwaysOnTop"
        static let ignoresMouseEvents = "QuotaPet.ignoresMouseEvents"
        static let connectionMode = "QuotaPet.connectionMode"
        static let hotKey = "QuotaPet.hotKey"
        static let notificationsEnabled = "QuotaPet.notificationsEnabled"
        static let launchAtLoginEnabled = "QuotaPet.launchAtLoginEnabled"
        static let position = "QuotaPet.normalizedPosition"
        static let fingerprints = "QuotaPet.confirmedFingerprints"
    }

    private let store: any AppPreferenceStoring
    private let language: AppLanguage
    @Published var petVisible: Bool { didSet { store.set(petVisible, forKey: Key.petVisible) } }
    @Published var alwaysOnTop: Bool { didSet { store.set(alwaysOnTop, forKey: Key.alwaysOnTop) } }
    @Published var ignoresMouseEvents: Bool { didSet { store.set(ignoresMouseEvents, forKey: Key.ignoresMouseEvents) } }
    @Published var connectionMode: ConnectionMode { didSet { store.set(connectionMode.rawValue, forKey: Key.connectionMode) } }
    @Published var hotKey: HotKeyShortcut { didSet { persist(hotKey, key: Key.hotKey) } }
    @Published private(set) var hotKeyStatusMessage: String?
    @Published var notificationsEnabled: Bool { didSet { store.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginErrorMessage: String?
    @Published var normalizedPosition: NormalizedScreenPosition? { didSet { persist(normalizedPosition, key: Key.position) } }
    @Published var confirmedFingerprints: Set<TrustFingerprint> { didSet { persist(confirmedFingerprints, key: Key.fingerprints) } }

    init(store: any AppPreferenceStoring = UserDefaults.standard, language: AppLanguage = .current) {
        self.store = store
        self.language = language
        petVisible = store.object(forKey: Key.petVisible) as? Bool ?? true
        alwaysOnTop = store.object(forKey: Key.alwaysOnTop) as? Bool ?? true
        ignoresMouseEvents = store.object(forKey: Key.ignoresMouseEvents) as? Bool ?? false
        connectionMode = ConnectionMode(rawValue: store.object(forKey: Key.connectionMode) as? String ?? "") ?? .energySaver
        hotKey = Self.load(HotKeyShortcut.self, from: store, key: Key.hotKey) ?? .optionCommandU
        hotKeyStatusMessage = nil
        notificationsEnabled = store.object(forKey: Key.notificationsEnabled) as? Bool ?? false
        launchAtLoginEnabled = store.object(forKey: Key.launchAtLoginEnabled) as? Bool ?? false
        launchAtLoginErrorMessage = nil
        normalizedPosition = Self.load(NormalizedScreenPosition.self, from: store, key: Key.position)
        confirmedFingerprints = Self.load(Set<TrustFingerprint>.self, from: store, key: Key.fingerprints) ?? []
    }

    func setHotKeyRegistration(_ result: Result<Void, GlobalHotKeyError>) {
        switch result {
        case .success: hotKeyStatusMessage = nil
        case .failure(.occupied): hotKeyStatusMessage = L10n.text(.hotkeyOccupied, language: language)
        case .failure: hotKeyStatusMessage = L10n.text(.hotkeyRegistrationFailed, language: language)
        }
    }

    func setLaunchAtLoginState(enabled: Bool, errorMessage: String?) {
        launchAtLoginEnabled = enabled
        launchAtLoginErrorMessage = errorMessage
        store.set(enabled, forKey: Key.launchAtLoginEnabled)
    }

    private func persist<T: Encodable>(_ value: T?, key: String) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, from store: any AppPreferenceStoring, key: String) -> T? {
        guard let data = store.object(forKey: key) as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
