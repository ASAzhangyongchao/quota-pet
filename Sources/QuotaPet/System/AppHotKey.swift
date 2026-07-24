import Foundation

/// All user-configurable global shortcuts in QuotaPet.
/// Add a new case when introducing another assignable hotkey.
enum AppHotKey: String, CaseIterable, Codable, Equatable, Identifiable, Hashable {
    case restorePet

    var id: String { rawValue }

    var defaultShortcut: HotKeyShortcut {
        switch self {
        case .restorePet: .optionCommandU
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .restorePet: L10n.text(.hotkeyRestorePetTitle, language: language)
        }
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .restorePet: L10n.text(.hotkeyRestorePetDetail, language: language)
        }
    }
}
