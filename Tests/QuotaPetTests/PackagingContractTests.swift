import Foundation
import XCTest

final class PackagingContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testInfoPlistDefinesMinimalMenuBarBundle() throws {
        let plistURL = repositoryRoot.appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "io.github.asazhangyongchao.quotapet")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "QuotaPet")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "0.1.0")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "1")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")

        let forbiddenKeys = [
            "NSCameraUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSScreenCaptureUsageDescription",
            "NSAppleEventsUsageDescription",
            "NSSystemAdministrationUsageDescription",
            "NSNetworkExtensionUsageDescription",
        ]
        XCTAssertTrue(forbiddenKeys.allSatisfy { plist[$0] == nil })
    }

    func testBuildScriptUsesStagingAndSignatureVerification() throws {
        let script = try contents(of: "scripts/build-app.sh")
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("swift build -c release"))
        XCTAssertTrue(script.contains(".staging-"))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(script.contains("ditto -c -k --sequesterRsrc --keepParent"))
        XCTAssertFalse(script.contains("/Users/"))
    }

    func testGeneratedIconIsAnICNSContainer() throws {
        let iconURL = repositoryRoot.appendingPathComponent("Resources/AppIcon.icns")
        let data = try Data(contentsOf: iconURL)
        XCTAssertGreaterThan(data.count, 1_024)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "icns")
    }

    func testInstallerVerifiesBundleBeforeReplacingApplication() throws {
        let script = try contents(of: "scripts/install-local.sh")
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(script.contains("io.github.asazhangyongchao.quotapet"))
        XCTAssertTrue(script.contains("/Applications/QuotaPet.app"))
        XCTAssertFalse(script.contains("Preferences"))
        XCTAssertFalse(script.contains("sudo"))
        XCTAssertFalse(script.contains("pkill"))
        XCTAssertFalse(script.contains("killall"))
    }

    func testInstallerTracksNewMoveForRollbackWithoutPreviousApplication() throws {
        let script = try contents(of: "scripts/install-local.sh")
        XCTAssertTrue(script.contains("NEW_MOVED=0"))
        XCTAssertTrue(script.contains("NEW_MOVED=1"))
        XCTAssertTrue(script.contains("\"$status\" -ne 0 && \"$NEW_MOVED\" -eq 1"))
    }

    func testPublicFilesDoNotContainPrivateWorkspacePaths() throws {
        let publicFiles = [
            "README.md", "AGENTS.md", "PRIVACY.md", "SECURITY.md",
            "THREAT_MODEL.md", "DEPENDENCIES.md", "LICENSE",
            "scripts/build-app.sh", "scripts/generate-icon.swift", "scripts/install-local.sh",
        ]
        let privateWorkspaceName = ["knowledge", "system"].joined(separator: "-")
        for path in publicFiles {
            let value = try contents(of: path)
            XCTAssertFalse(value.contains("/Users/"), "Private absolute path in \(path)")
            XCTAssertFalse(value.contains(privateWorkspaceName), "Knowledge-base reference in \(path)")
        }
    }

    func testMaintenanceAndPrivacyDocumentsStatePortableSecurityModel() throws {
        let agents = try contents(of: "AGENTS.md")
        XCTAssertTrue(agents.contains("GitHub"))
        XCTAssertTrue(agents.contains("standard Git"))
        XCTAssertTrue(agents.contains("`gh`"))
        XCTAssertTrue(agents.contains("web interface"))
        XCTAssertTrue(agents.contains("AI client"))

        let privacy = try contents(of: "PRIVACY.md")
        XCTAssertTrue(privacy.contains("Codex App Server"))
        XCTAssertTrue(privacy.contains("credentials"))
        XCTAssertTrue(privacy.contains("usage history"))

        let threatModel = try contents(of: "THREAT_MODEL.md")
        for threat in ["path hijacking", "forged JSONL", "oversized frame", "orphaned child process", "supply chain", "hotkey conflict"] {
            XCTAssertTrue(threatModel.localizedCaseInsensitiveContains(threat), "Missing threat: \(threat)")
        }

        let dependencies = try contents(of: "DEPENDENCIES.md")
        XCTAssertTrue(dependencies.contains("No third-party runtime dependencies"))
    }

    private func contents(of path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
