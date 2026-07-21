import Foundation
import XCTest

final class ReleasePreparationContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPublicIdentityLegalDocumentsAndLinksStayUnofficial() throws {
        let legal = try XCTUnwrap(requiredContents(of: "LEGAL.md"))
        let legalChinese = try XCTUnwrap(requiredContents(of: "LEGAL.zh-CN.md"))
        let contributing = try XCTUnwrap(requiredContents(of: "CONTRIBUTING.md"))
        let contributingChinese = try XCTUnwrap(requiredContents(of: "CONTRIBUTING.zh-CN.md"))

        for required in [
            "unofficial", "not affiliated", "third-party marks", "Codex App Server",
            "rate limit", "interface", "responsibility", "MIT", "not legal advice",
            "Q-shaped mascot", "generated application icon", "openai.com/brand",
        ] {
            XCTAssertTrue(legal.localizedCaseInsensitiveContains(required), "Missing English legal concept: \(required)")
        }
        for required in [
            "非官方", "无隶属关系", "第三方商标", "Codex App Server", "速率限制",
            "接口", "用户责任", "MIT", "不构成法律意见", "Q 形桌宠", "生成的应用图标",
            "openai.com/brand",
        ] {
            XCTAssertTrue(legalChinese.localizedCaseInsensitiveContains(required), "缺少中文法律概念：\(required)")
        }
        for document in [contributing, contributingChinese] {
            for asset in ["code", "font", "image", "icon", "sound", "screenshot", "dependency"] {
                XCTAssertTrue(document.localizedCaseInsensitiveContains(asset), "Missing provenance category: \(asset)")
            }
        }

        let englishEntries = ["README.md", "docs/USER_GUIDE.md"]
        let chineseEntries = ["README.zh-CN.md", "docs/USER_GUIDE.zh-CN.md"]
        for path in englishEntries {
            XCTAssertTrue(try XCTUnwrap(requiredContents(of: path)).contains("LEGAL.md"), "Missing English legal link in \(path)")
        }
        for path in chineseEntries {
            XCTAssertTrue(try XCTUnwrap(requiredContents(of: path)).contains("LEGAL.zh-CN.md"), "Missing Chinese legal link in \(path)")
        }

        let package = try XCTUnwrap(requiredContents(of: "Package.swift"))
        let plistData = try Data(contentsOf: repositoryRoot.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])
        let publicNames = [
            "QuotaPet",
            plist["CFBundleName"] as? String ?? "",
            plist["CFBundleDisplayName"] as? String ?? "",
        ]
        XCTAssertTrue(package.contains("name: \"QuotaPet\""))
        for name in publicNames {
            for forbidden in ["openai", "chatgpt", "gpt", "codex"] {
                XCTAssertFalse(name.localizedCaseInsensitiveContains(forbidden), "Public app title contains third-party mark: \(name)")
            }
        }
    }

    func testReleaseGuidesRequireBrandAssetPrivacyAndTrademarkReview() throws {
        let english = try XCTUnwrap(requiredContents(of: "docs/RELEASING.md"))
        let chinese = try XCTUnwrap(requiredContents(of: "docs/RELEASING.zh-CN.md"))
        let guides = english + chinese
        for required in [
            "name conflict", "OpenAI brand", "asset provenance", "dependency license",
            "privacy change", "formal trademark clearance", "Global Brand Database", "CNIPA",
        ] {
            XCTAssertTrue(guides.localizedCaseInsensitiveContains(required), "Missing release legal gate: \(required)")
        }
    }

    func testSettingsSourceContainsLocalizedUnofficialDisclosureWithoutRemoteLegalRequest() throws {
        let settings = try XCTUnwrap(requiredContents(of: "Sources/QuotaPet/Settings/SettingsView.swift"))
        XCTAssertTrue(settings.contains("settingsAboutLegal"))
        XCTAssertTrue(settings.contains("settingsUnofficialNotice"))
        XCTAssertTrue(settings.contains("settingsMarksNotice"))
        XCTAssertTrue(settings.contains("UpdateCheckSettingsSection"))
        // Legal copy stays local; network for update checks lives in UpdateCheckService, not SettingsView.
        XCTAssertFalse(settings.contains("URLSession"))
        XCTAssertFalse(settings.contains("api.github.com"))

        let updateCheck = try XCTUnwrap(requiredContents(of: "Sources/QuotaPet/System/UpdateCheckService.swift"))
        XCTAssertTrue(updateCheck.contains("releases.atom"))
        XCTAssertTrue(updateCheck.contains("URLSession"))
        XCTAssertFalse(updateCheck.contains("api.github.com/repos/ASAzhangyongchao/quota-pet/releases/latest"))
    }

    func testCIUsesNoReleaseSecretsOrRealCodexIntegration() throws {
        guard let workflow = try requiredContents(of: ".github/workflows/ci.yml") else { return }

        for required in [
            "pull_request:", "push:", "contents: read", "runs-on: macos-15",
            "git diff --check", "test -s DEPENDENCIES.md", "swift test --disable-sandbox",
            "./scripts/build-app.sh", "./scripts/verify-package.sh",
            "QUOTAPET_CODEX_INTEGRATION: \"0\"",
            "actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5",
        ] {
            XCTAssertTrue(workflow.contains(required), "Missing CI contract: \(required)")
        }
        XCTAssertFalse(workflow.contains("secrets."))
        XCTAssertFalse(workflow.contains("QUOTAPET_CODEX_INTEGRATION=1"))
    }

    func testReleaseWorkflowIsTagAndEnvironmentGated() throws {
        guard let workflow = try requiredContents(of: ".github/workflows/release.yml") else { return }

        for required in [
            "tags:", "'v*.*.*'", "environment: release", "contents: write",
            "id-token: write", "attestations: write", "scripts/sign-and-notarize.sh",
            "scripts/update-cask.sh",
            "actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5",
            "anchore/sbom-action@e22c389904149dbc22b58101806040fa8d37a610",
            "actions/attest@36051bcae73b7c2a8a6945a48cbf80953c6baa35",
            "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
            "subject-checksums:", "subject-path:", "sbom-path:", "SHA256SUMS", "gh release create",
            "QuotaPet-${VERSION}.zip", "QuotaPet-${VERSION}.dmg",
        ] {
            XCTAssertTrue(workflow.contains(required), "Missing release contract: \(required)")
        }
        for secret in [
            "BUILD_CERTIFICATE_BASE64", "P12_PASSWORD", "KEYCHAIN_PASSWORD",
            "SIGNING_IDENTITY", "APPLE_API_KEY_BASE64", "APPLE_API_KEY_ID",
            "APPLE_API_ISSUER_ID",
        ] {
            XCTAssertTrue(workflow.contains("secrets.\(secret)"), "Missing release secret: \(secret)")
        }
        XCTAssertGreaterThanOrEqual(
            workflow.components(separatedBy: "uses: actions/attest@36051bcae73b7c2a8a6945a48cbf80953c6baa35").count - 1,
            2
        )
    }

    func testSigningScriptBuildsUniversalAndFailsClosed() throws {
        guard let script = try requiredContents(of: "scripts/sign-and-notarize.sh") else { return }

        for required in [
            "set -euo pipefail", "--arch arm64", "--arch x86_64",
            "Developer ID Application:", "--options runtime", "--timestamp",
            "xcrun --find stapler", "xcrun notarytool submit", "xcrun stapler staple", "xcrun stapler validate",
            "spctl", "lipo \"$BIN_DIR/QuotaPet\" -verify_arch arm64 x86_64",
            "lipo \"$APP/Contents/MacOS/QuotaPet\" -verify_arch arm64 x86_64",
            "plutil -replace CFBundleShortVersionString",
            "QuotaPet_QuotaPet.bundle",
            "ditto \"$BIN_DIR/QuotaPet_QuotaPet.bundle\" \"$APP/Contents/Resources/QuotaPet_QuotaPet.bundle\"",
            "trap cleanup EXIT", "trap 'exit 130' INT", "trap 'exit 143' TERM",
            "QuotaPet-$VERSION.zip", "QuotaPet-$VERSION.dmg",
        ] {
            XCTAssertTrue(script.contains(required), "Missing signing contract: \(required)")
        }
        XCTAssertFalse(script.contains("xcrun stapler help"))
        XCTAssertFalse(script.contains("plutil -replace CFBundleVersion"))

        let result = try runScript("sign-and-notarize.sh", arguments: ["0.1.0"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.error.localizedCaseInsensitiveContains("prerequisite"))
        XCTAssertFalse(result.error.contains("BEGIN PRIVATE KEY"))
    }

    func testCaskGeneratorPinsVersionSHAAndReleaseURL() throws {
        guard let script = try requiredContents(of: "scripts/update-cask.sh") else { return }
        for required in ["trap cleanup EXIT", "trap 'exit 130' INT", "trap 'exit 143' TERM"] {
            XCTAssertTrue(script.contains(required), "Missing cask cleanup contract: \(required)")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaPet-cask-tests-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("quotapet.rb")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sha = String(repeating: "a", count: 64)

        let result = try runScript("update-cask.sh", arguments: ["0.1.0", sha, output.path])

        XCTAssertEqual(result.status, 0, result.error)
        let cask = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(cask.contains("version \"0.1.0\""))
        XCTAssertTrue(cask.contains("sha256 \"\(sha)\""))
        XCTAssertTrue(cask.contains("https://github.com/ASAzhangyongchao/quota-pet/releases/download/v#{version}/QuotaPet-#{version}.dmg"))
        XCTAssertFalse(cask.contains("latest"))
    }

    func testCaskGeneratorRejectsNonSHA256Input() throws {
        guard try requiredContents(of: "scripts/update-cask.sh") != nil else { return }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaPet-invalid-cask-\(UUID().uuidString).rb")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runScript("update-cask.sh", arguments: ["0.1.0", "not-a-sha", output.path])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testReleaseDocumentationStatesPreparationOnlyAndFailClosedGates() throws {
        let readme = try String(contentsOf: repositoryRoot.appendingPathComponent("README.md"), encoding: .utf8)
        let security = try String(contentsOf: repositoryRoot.appendingPathComponent("SECURITY.md"), encoding: .utf8)
        let combined = readme + security

        for required in [
            "preparation-only", "Developer ID Application", "release environment",
            "notarytool", "Gatekeeper", "SBOM", "attestation", "Homebrew",
        ] {
            XCTAssertTrue(combined.localizedCaseInsensitiveContains(required), "Missing release documentation: \(required)")
        }
    }

    func testEnglishAndChineseDocumentationAreIndependentAndComplete() throws {
        let requiredPaths = [
            "README.md", "README.zh-CN.md",
            "docs/USER_GUIDE.md", "docs/USER_GUIDE.zh-CN.md",
            "CHANGELOG.md", "CHANGELOG.zh-CN.md",
            "docs/RELEASING.md", "docs/RELEASING.zh-CN.md",
        ]
        let documents = try Dictionary(uniqueKeysWithValues: requiredPaths.map { path in
            (path, try XCTUnwrap(requiredContents(of: path)))
        })

        XCTAssertTrue(documents["README.md"]?.contains("README.zh-CN.md") == true)
        XCTAssertTrue(documents["README.zh-CN.md"]?.contains("README.md") == true)
        XCTAssertTrue(documents["docs/USER_GUIDE.md"]?.contains("After installation") == false)
        XCTAssertTrue(documents["docs/USER_GUIDE.md"]?.contains("First launch") == true)
        XCTAssertTrue(documents["docs/USER_GUIDE.md"]?.contains("Updating") == true)
        XCTAssertTrue(documents["docs/USER_GUIDE.md"]?.contains("Uninstall") == true)
        XCTAssertTrue(documents["docs/USER_GUIDE.zh-CN.md"]?.contains("第一次打开") == true)
        XCTAssertTrue(documents["docs/USER_GUIDE.zh-CN.md"]?.contains("更新") == true)
        XCTAssertTrue(documents["docs/USER_GUIDE.zh-CN.md"]?.contains("卸载") == true)
        XCTAssertTrue(documents["CHANGELOG.md"]?.contains("[0.1.4] - 2026-07-21") == true)
        XCTAssertTrue(documents["CHANGELOG.zh-CN.md"]?.contains("[0.1.4] - 2026-07-21") == true)

        let releasePair = (documents["docs/RELEASING.md"] ?? "") + (documents["docs/RELEASING.zh-CN.md"] ?? "")
        for marker in ["Semantic Versioning", "GitHub", "Homebrew", "Rollback", "Developer ID", "notarytool", "SHA256", "attest"] {
            XCTAssertTrue(releasePair.localizedCaseInsensitiveContains(marker), "Missing bilingual release marker: \(marker)")
        }
    }

    private func requiredContents(of path: String) throws -> String? {
        let url = repositoryRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Missing required file: \(path)")
            return nil
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func runScript(_ name: String, arguments: [String]) throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repositoryRoot.appendingPathComponent("scripts/\(name)").path] + arguments
        var environment = ProcessInfo.processInfo.environment
        for key in [
            "SIGNING_IDENTITY", "APPLE_API_PRIVATE_KEY", "APPLE_API_KEY_ID", "APPLE_API_ISSUER_ID",
        ] {
            environment.removeValue(forKey: key)
        }
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
