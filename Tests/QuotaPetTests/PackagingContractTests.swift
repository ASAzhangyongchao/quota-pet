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
        XCTAssertTrue(script.contains("original-app-present"))
        XCTAssertTrue(script.contains("QuotaPet.previous.app"))
        XCTAssertTrue(script.contains("trap 'exit 130' INT"))
        XCTAssertTrue(script.contains("trap 'exit 143' TERM"))
    }

    func testBuildBackupFailureAndPartialReplacementRestoreMatchingOldPair() throws {
        guard try scriptsExposeSafeTransactionHarness() else { return }
        for hook in [
            "fail:before_backup_app", "fail:after_backup_app",
            "fail:before_backup_zip", "fail:after_backup_zip",
            "fail:after_new_app", "fail:after_new_zip",
        ] {
            let fixture = try TransactionFixture(hasOldApplication: true, hasOldZip: true)
            let result = try runScript("build-app.sh", fixture: fixture, hook: hook)
            XCTAssertEqual(result, 97, "Hook should preserve injected failure status: \(hook)")
            XCTAssertEqual(try fixture.applicationVersion(), "old-app", hook)
            XCTAssertEqual(try fixture.zipVersion(), "old-zip", hook)
        }
    }

    func testInstallerSignalsAfterOldAndNewMoveRestoreOldApplication() throws {
        guard try scriptsExposeSafeTransactionHarness() else { return }
        for (hook, expectedStatus): (String, Int32) in [("int:after_backup_app", 130), ("term:after_new_app", 143)] {
            let fixture = try TransactionFixture(hasOldApplication: true, hasOldZip: true)
            let result = try runScript("install-local.sh", fixture: fixture, hook: hook)
            XCTAssertEqual(result, expectedStatus, "Hook should preserve signal exit status: \(hook)")
            XCTAssertEqual(try fixture.installedApplicationVersion(), "old-app", hook)
        }
    }

    func testInstallerFailureAfterNewMoveLeavesNoApplicationWhenNoneExisted() throws {
        guard try scriptsExposeSafeTransactionHarness() else { return }
        let fixture = try TransactionFixture(hasOldApplication: false, hasOldZip: true)
        let result = try runScript("install-local.sh", fixture: fixture, hook: "fail:after_new_app")
        XCTAssertEqual(result, 97)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installedApplicationURL.path))
    }

    func testBuildCommittedTransactionSurvivesKillAndRepeatedRecovery() throws {
        guard try scriptsExposeSafeTransactionHarness() else { return }
        let fixture = try TransactionFixture(hasOldApplication: false, hasOldZip: false)

        XCTAssertEqual(try runScript("build-app.sh", fixture: fixture, hook: "kill:after_commit_marker_before_cleanup"), 9)
        for _ in 0..<2 {
            XCTAssertEqual(try runScript("build-app.sh", fixture: fixture, hook: "fail:before_backup_zip"), 97)
        }

        XCTAssertEqual(try fixture.applicationVersion(), "new-app")
        XCTAssertEqual(try fixture.zipVersion(), "new-zip")
    }

    func testBuildCommittedPartialMetadataNeverRestoresOnlyOneBackup() throws {
        guard try scriptsExposeSafeTransactionHarness() else { return }
        let fixture = try TransactionFixture(hasOldApplication: true, hasOldZip: true)
        try fixture.setBuildFinal(application: "committed-app", zip: "committed-zip")
        try fixture.prepareCommittedBuildTransactionWithOnlyApplicationBackup()

        XCTAssertEqual(try runScript("build-app.sh", fixture: fixture, hook: "fail:before_backup_app"), 97)
        XCTAssertEqual(try fixture.applicationVersion(), "committed-app")
        XCTAssertEqual(try fixture.zipVersion(), "committed-zip")
    }

    func testInstallerCommittedTransactionSurvivesKillAndRecovery() throws {
        guard try scriptsExposeSafeTransactionHarness() else { return }
        let fixture = try TransactionFixture(hasOldApplication: true, hasOldZip: true)

        XCTAssertEqual(try runScript("install-local.sh", fixture: fixture, hook: "kill:after_commit_marker_before_cleanup"), 9)
        XCTAssertEqual(try runScript("install-local.sh", fixture: fixture, hook: "fail:before_backup_app"), 97)
        XCTAssertEqual(try fixture.installedApplicationVersion(), "new-app")
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

    private func scriptsExposeSafeTransactionHarness() throws -> Bool {
        let scripts = try ["scripts/build-app.sh", "scripts/install-local.sh"].map(contents(of:))
        guard scripts.allSatisfy({ $0.contains("QUOTAPET_TEST_MODE") && $0.contains("run_test_hook") }) else {
            XCTFail("Transaction scripts must expose the temporary-directory-only failure harness")
            return false
        }
        return true
    }

    private func runScript(_ name: String, fixture: TransactionFixture, hook: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repositoryRoot.appendingPathComponent("scripts/\(name)").path]
        var environment = ProcessInfo.processInfo.environment
        environment["QUOTAPET_TEST_MODE"] = "1"
        environment["QUOTAPET_TEST_ROOT"] = fixture.root.path
        environment["QUOTAPET_TEST_HOOK"] = hook
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

private final class TransactionFixture {
    let root: URL
    let installedApplicationURL: URL

    init(hasOldApplication: Bool, hasOldZip: Bool) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaPet-transaction-tests-\(UUID().uuidString)", isDirectory: true)
        installedApplicationURL = root.appendingPathComponent("Applications/QuotaPet.app", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Applications"), withIntermediateDirectories: true)
        try writeVersion("new-app", at: root.appendingPathComponent("fixture/QuotaPet.app/version"))
        try writeVersion("new-zip", at: root.appendingPathComponent("fixture/QuotaPet.zip"))
        try writeVersion("new-app", at: root.appendingPathComponent("source/QuotaPet.app/version"))
        if hasOldApplication {
            try writeVersion("old-app", at: root.appendingPathComponent("dist/QuotaPet.app/version"))
            try writeVersion("old-app", at: installedApplicationURL.appendingPathComponent("version"))
        }
        if hasOldZip {
            try writeVersion("old-zip", at: root.appendingPathComponent("dist/QuotaPet.zip"))
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func applicationVersion() throws -> String {
        try readVersion(at: root.appendingPathComponent("dist/QuotaPet.app/version"))
    }

    func installedApplicationVersion() throws -> String {
        try readVersion(at: installedApplicationURL.appendingPathComponent("version"))
    }

    func zipVersion() throws -> String {
        try readVersion(at: root.appendingPathComponent("dist/QuotaPet.zip"))
    }

    func setBuildFinal(application: String, zip: String) throws {
        try writeVersion(application, at: root.appendingPathComponent("dist/QuotaPet.app/version"))
        try writeVersion(zip, at: root.appendingPathComponent("dist/QuotaPet.zip"))
    }

    func prepareCommittedBuildTransactionWithOnlyApplicationBackup() throws {
        let transaction = root.appendingPathComponent("dist/.transaction-committed-partial", isDirectory: true)
        try writeVersion("old-app", at: transaction.appendingPathComponent("QuotaPet.previous.app/version"))
        for marker in ["committed", "original-app-present", "original-zip-present", "app-install-intent", "zip-install-intent"] {
            try writeVersion("", at: transaction.appendingPathComponent(marker))
        }
    }

    private func writeVersion(_ value: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }

    private func readVersion(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
