import XCTest
@testable import QuotaPet

final class LocalizationTests: XCTestCase {
    func testEverySupportedLanguageContainsEveryLocalizedValue() {
        for language in AppLanguage.allCases {
            for key in L10n.Key.allCases {
                let value = L10n.text(key, language: language)
                XCTAssertFalse(value.isEmpty, "Empty \(language) localization for \(key.rawValue)")
                XCTAssertNotEqual(value, key.rawValue, "Missing \(language) localization for \(key.rawValue)")
            }
        }
    }

    func testUnsupportedLanguagesFallBackToEnglish() {
        XCTAssertEqual(AppLanguage.resolve(preferredLanguage: "fr-FR"), .english)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguage: "de-DE"), .english)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguage: "zh-Hans-CN"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguage: "zh-Hant-TW"), .english)
    }

    func testFormattingUsesTheRequestedCatalog() {
        XCTAssertEqual(L10n.text(.remainingPercent, language: .english, arguments: [62]), "Remaining 62%")
        XCTAssertEqual(L10n.text(.remainingPercent, language: .simplifiedChinese, arguments: [62]), "剩余 62%")
        XCTAssertEqual(L10n.text(.meterAccessibility, language: .english, arguments: [38, 62]), "Used 38%, remaining 62%")
        XCTAssertEqual(L10n.text(.meterAccessibility, language: .simplifiedChinese, arguments: [38, 62]), "已用 38%，剩余 62%")
    }

    func testExecutableInspectionErrorsAreFriendlyInBothLanguages() {
        XCTAssertEqual(CodexExecutableInspectionError.worldWritable.localizedMessage(language: .english), "The file can be modified by any user")
        XCTAssertEqual(CodexExecutableInspectionError.worldWritable.localizedMessage(language: .simplifiedChinese), "该文件可被任意用户修改")
        XCTAssertFalse(L10n.text(.settingsCandidateDetails, language: .simplifiedChinese).contains("owner"))
    }

    func testSettingsLegalDisclosureIsLocalized() {
        XCTAssertEqual(L10n.text(.settingsAboutLegal, language: .english), "About & Legal")
        XCTAssertEqual(
            L10n.text(.settingsUnofficialNotice, language: .english),
            "QuotaPet is an unofficial independent project and is not affiliated with or endorsed by OpenAI."
        )
        XCTAssertEqual(
            L10n.text(.settingsUnofficialNotice, language: .simplifiedChinese),
            "QuotaPet 是独立的非官方项目，与 OpenAI 无隶属关系，也未获其认可或赞助。"
        )
        XCTAssertFalse(L10n.text(.settingsMarksNotice, language: .simplifiedChinese).isEmpty)
    }
}
