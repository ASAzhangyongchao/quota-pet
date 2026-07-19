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
    }

    func testExecutableInspectionErrorsAreFriendlyInBothLanguages() {
        XCTAssertEqual(CodexExecutableInspectionError.worldWritable.localizedMessage(language: .english), "The file can be modified by any user")
        XCTAssertEqual(CodexExecutableInspectionError.worldWritable.localizedMessage(language: .simplifiedChinese), "该文件可被任意用户修改")
        XCTAssertFalse(L10n.text(.settingsCandidateDetails, language: .simplifiedChinese).contains("owner"))
    }
}
