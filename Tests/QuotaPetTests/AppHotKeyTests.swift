import XCTest
@testable import QuotaPet

final class AppHotKeyTests: XCTestCase {
    func testCatalogListsRestorePetWithDefaultShortcut() {
        XCTAssertEqual(AppHotKey.allCases, [.restorePet])
        XCTAssertEqual(AppHotKey.restorePet.defaultShortcut, .optionCommandU)
        XCTAssertFalse(AppHotKey.restorePet.title(language: .simplifiedChinese).isEmpty)
        XCTAssertFalse(AppHotKey.restorePet.detail(language: .simplifiedChinese).isEmpty)
    }

    @MainActor
    func testPreferencesShortcutAccessorsRoundTripPerAction() {
        let preferences = Preferences(store: makeStore())
        let custom = HotKeyShortcut(
            keyCode: 0, // A
            carbonModifiers: HotKeyShortcut.commandModifier | HotKeyShortcut.optionModifier
        )
        preferences.setShortcut(custom, for: .restorePet)
        XCTAssertEqual(preferences.shortcut(for: .restorePet), custom)
        preferences.resetShortcut(for: .restorePet)
        XCTAssertEqual(preferences.shortcut(for: .restorePet), AppHotKey.restorePet.defaultShortcut)
    }
}

@MainActor
private func makeStore() -> UserDefaults {
    let suite = "QuotaPetTests.AppHotKey.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
