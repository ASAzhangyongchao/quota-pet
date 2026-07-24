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

enum PreferredCodexChannel: String, Codable, CaseIterable, Equatable {
    case chatGPT
    case terminal

    static func channel(for source: ExecutableCandidate.Source) -> PreferredCodexChannel {
        switch source {
        case .chatGPTBundle, .codexBundle, .homeChatGPTBundle, .homeCodexBundle:
            .chatGPT
        case .homebrew, .local, .path, .userSelected:
            .terminal
        }
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
        static let languagePreference = "QuotaPet.languagePreference"
        static let position = "QuotaPet.normalizedPosition"
        static let fingerprints = "QuotaPet.confirmedFingerprints"
        static let preferredCodexChannel = "QuotaPet.preferredCodexChannel"
        static let userSelectedCodexPath = "QuotaPet.userSelectedCodexPath"
    }

    private let store: any AppPreferenceStoring
    @Published var petVisible: Bool {
        didSet { store.set(petVisible, forKey: Key.petVisible) }
    }
    @Published var alwaysOnTop: Bool { didSet { store.set(alwaysOnTop, forKey: Key.alwaysOnTop) } }
    @Published var ignoresMouseEvents: Bool { didSet { store.set(ignoresMouseEvents, forKey: Key.ignoresMouseEvents) } }
    @Published var connectionMode: ConnectionMode { didSet { store.set(connectionMode.rawValue, forKey: Key.connectionMode) } }
    @Published var hotKey: HotKeyShortcut { didSet { persist(hotKey, key: Key.hotKey) } }
    @Published private(set) var hotKeyStatusByAction: [AppHotKey: String] = [:]
    @Published var notificationsEnabled: Bool { didSet { store.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginErrorMessage: String?
    @Published var languagePreference: LanguagePreference {
        didSet { store.set(languagePreference.rawValue, forKey: Key.languagePreference) }
    }
    @Published var normalizedPosition: NormalizedScreenPosition? { didSet { persist(normalizedPosition, key: Key.position) } }
    @Published var confirmedFingerprints: Set<TrustFingerprint> { didSet { persist(confirmedFingerprints, key: Key.fingerprints) } }
    @Published var preferredCodexChannel: PreferredCodexChannel {
        didSet { store.set(preferredCodexChannel.rawValue, forKey: Key.preferredCodexChannel) }
    }
    @Published var userSelectedCodexPath: String? {
        didSet { store.set(userSelectedCodexPath, forKey: Key.userSelectedCodexPath) }
    }

    var resolvedLanguage: AppLanguage {
        AppLanguage.resolve(preference: languagePreference)
    }

    var userSelectedCodexURL: URL? {
        guard let userSelectedCodexPath, !userSelectedCodexPath.isEmpty else { return nil }
        return URL(fileURLWithPath: userSelectedCodexPath)
    }

    init(store: any AppPreferenceStoring = UserDefaults.standard) {
        self.store = store
        petVisible = Self.boolValue(from: store, key: Key.petVisible, default: true)
        alwaysOnTop = Self.boolValue(from: store, key: Key.alwaysOnTop, default: true)
        ignoresMouseEvents = Self.boolValue(from: store, key: Key.ignoresMouseEvents, default: false)
        connectionMode = ConnectionMode(rawValue: store.object(forKey: Key.connectionMode) as? String ?? "") ?? .energySaver
        hotKey = Self.load(HotKeyShortcut.self, from: store, key: Key.hotKey) ?? AppHotKey.restorePet.defaultShortcut
        hotKeyStatusByAction = [:]
        notificationsEnabled = store.object(forKey: Key.notificationsEnabled) as? Bool ?? false
        launchAtLoginEnabled = store.object(forKey: Key.launchAtLoginEnabled) as? Bool ?? false
        launchAtLoginErrorMessage = nil
        languagePreference = LanguagePreference(rawValue: store.object(forKey: Key.languagePreference) as? String ?? "") ?? .system
        normalizedPosition = Self.load(NormalizedScreenPosition.self, from: store, key: Key.position)
        confirmedFingerprints = Self.load(Set<TrustFingerprint>.self, from: store, key: Key.fingerprints) ?? []
        preferredCodexChannel = PreferredCodexChannel(
            rawValue: store.object(forKey: Key.preferredCodexChannel) as? String ?? ""
        ) ?? .chatGPT
        userSelectedCodexPath = store.object(forKey: Key.userSelectedCodexPath) as? String
    }

    func shortcut(for action: AppHotKey) -> HotKeyShortcut {
        switch action {
        case .restorePet: hotKey
        }
    }

    func setShortcut(_ shortcut: HotKeyShortcut, for action: AppHotKey) {
        switch action {
        case .restorePet: hotKey = shortcut
        }
    }

    func resetShortcut(for action: AppHotKey) {
        setShortcut(action.defaultShortcut, for: action)
    }

    func setHotKeyRegistration(_ result: Result<Void, GlobalHotKeyError>, for action: AppHotKey = .restorePet) {
        var next = hotKeyStatusByAction
        switch result {
        case .success:
            next.removeValue(forKey: action)
        case .failure(.occupied):
            next[action] = L10n.text(.hotkeyOccupied, language: resolvedLanguage)
        case .failure:
            next[action] = L10n.text(.hotkeyRegistrationFailed, language: resolvedLanguage)
        }
        hotKeyStatusByAction = next
    }

    /// Compatibility for older call sites / tests.
    var hotKeyStatusMessage: String? {
        hotKeyStatusByAction[.restorePet]
    }

    func setLaunchAtLoginState(enabled: Bool, errorMessage: String?) {
        launchAtLoginEnabled = enabled
        launchAtLoginErrorMessage = errorMessage
        store.set(enabled, forKey: Key.launchAtLoginEnabled)
    }

    private func persist<T: Encodable>(_ value: T?, key: String) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func boolValue(from store: any AppPreferenceStoring, key: String, default defaultValue: Bool) -> Bool {
        guard let value = store.object(forKey: key) else { return defaultValue }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return defaultValue
    }

    private static func load<T: Decodable>(_ type: T.Type, from store: any AppPreferenceStoring, key: String) -> T? {
        guard let data = store.object(forKey: key) as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
