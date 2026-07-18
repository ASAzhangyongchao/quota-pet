import Darwin
import Foundation
import XCTest
@testable import QuotaPet

final class CodexExecutableResolverTests: XCTestCase {
    func testCandidateInputsPreservePriorityAndLimitPathEntries() {
        let userURL = URL(fileURLWithPath: "/custom/codex")
        let homeURL = URL(fileURLWithPath: "/Users/tester")
        let path = (0..<70).map { "/tools/\($0)" }.joined(separator: ":")

        let inputs = CodexExecutableResolver.candidateInputs(
            userSelectedURL: userURL,
            path: path,
            homeDirectory: homeURL
        )

        XCTAssertEqual(inputs.first?.url, userURL)
        XCTAssertEqual(inputs.first?.source, .userSelected)
        XCTAssertEqual(inputs.dropFirst().prefix(4).map(\.source), [
            .chatGPTBundle,
            .codexBundle,
            .homeChatGPTBundle,
            .homeCodexBundle,
        ])
        XCTAssertEqual(inputs[5].url.path, "/opt/homebrew/bin/codex")
        XCTAssertEqual(inputs[6].url.path, "/usr/local/bin/codex")
        XCTAssertEqual(inputs.filter { $0.source == .path }.count, 64)
    }

    func testInspectionDeduplicatesCanonicalPathsWithoutChangingPriority() {
        let canonical = URL(fileURLWithPath: "/safe/codex")
        let inspector = FakeInspector([
            "/first/codex": inspection(canonicalURL: canonical),
            "/second/codex": inspection(canonicalURL: canonical),
        ])
        let resolver = CodexExecutableResolver(inspector: inspector)

        let results = resolver.inspect([
            .init(url: URL(fileURLWithPath: "/first/codex"), source: .userSelected),
            .init(url: URL(fileURLWithPath: "/second/codex"), source: .path),
        ])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.candidate?.source, .userSelected)
        XCTAssertEqual(results.first?.candidate?.canonicalURL, canonical)
    }

    func testRealpathIsUsedForSymbolicLinks() throws {
        let fixture = try ExecutableFixture()
        let target = try fixture.makeExecutable(named: "target", contents: "v1")
        let link = fixture.directory.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let resolver = CodexExecutableResolver()

        let result = try XCTUnwrap(resolver.inspect([.init(url: link, source: .userSelected)]).first)

        XCTAssertNotEqual(result.candidate?.canonicalURL.path, link.path)
        XCTAssertEqual(result.candidate?.canonicalURL.lastPathComponent, target.lastPathComponent)
    }

    func testWorldWritableCandidateIsRejectedBeforeExecution() throws {
        let fixture = try ExecutableFixture()
        let marker = fixture.directory.appendingPathComponent("executed")
        let candidate = try fixture.makeExecutable(
            named: "codex",
            contents: "#!/bin/sh\ntouch '\(marker.path)'\n",
            mode: 0o777
        )
        let resolver = CodexExecutableResolver()

        let result = try XCTUnwrap(resolver.inspect([.init(url: candidate, source: .userSelected)]).first)

        XCTAssertEqual(result, .rejected(.worldWritable))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testNonExecutableCandidateIsRejected() throws {
        let fixture = try ExecutableFixture()
        let candidate = try fixture.makeExecutable(named: "codex", contents: "v1", mode: 0o644)
        let resolver = CodexExecutableResolver()

        XCTAssertEqual(
            resolver.inspect([.init(url: candidate, source: .userSelected)]),
            [.rejected(.notExecutable)]
        )
    }

    func testUserCandidateRequiresConfirmationThenBecomesTrusted() {
        let candidate = inspection(canonicalURL: URL(fileURLWithPath: "/safe/codex")).candidate
        let resolver = CodexExecutableResolver(inspector: FakeInspector(["/input/codex": inspection(canonicalURL: candidate.canonicalURL)]))
        let input = ExecutablePathInput(url: URL(fileURLWithPath: "/input/codex"), source: .userSelected)

        let first = try! XCTUnwrap(resolver.inspect([input]).first?.candidate)
        XCTAssertTrue(resolver.inspect([input]).first?.requiresConfirmation == true)
        XCTAssertTrue(resolver.confirm(first))

        XCTAssertEqual(resolver.inspect([input]).first?.trust, .confirmed)
    }

    func testHashChangeInvalidatesConfirmation() {
        let input = ExecutablePathInput(url: URL(fileURLWithPath: "/input/codex"), source: .path)
        let inspector = FakeInspector(["/input/codex": inspection(canonicalURL: URL(fileURLWithPath: "/safe/codex"), codeHash: "one")])
        let resolver = CodexExecutableResolver(inspector: inspector)
        let first = try! XCTUnwrap(resolver.inspect([input]).first?.candidate)
        XCTAssertTrue(resolver.confirm(first))
        inspector.set(inspection(canonicalURL: URL(fileURLWithPath: "/safe/codex"), codeHash: "two"), for: input.url.path)

        XCTAssertTrue(resolver.inspect([input]).first?.requiresConfirmation == true)
    }

    func testSigningMetadataChangeInvalidatesConfirmation() {
        let input = ExecutablePathInput(url: URL(fileURLWithPath: "/input/codex"), source: .path)
        let inspector = FakeInspector(["/input/codex": inspection(
            canonicalURL: URL(fileURLWithPath: "/safe/codex"),
            signingIdentifier: "first"
        )])
        let resolver = CodexExecutableResolver(inspector: inspector)
        let first = try! XCTUnwrap(resolver.inspect([input]).first?.candidate)
        XCTAssertTrue(resolver.confirm(first))
        inspector.set(inspection(
            canonicalURL: URL(fileURLWithPath: "/safe/codex"),
            signingIdentifier: "second"
        ), for: input.url.path)

        XCTAssertTrue(resolver.inspect([input]).first?.requiresConfirmation == true)
    }

    func testSymbolicLinkTargetChangeInvalidatesConfirmation() throws {
        let fixture = try ExecutableFixture()
        let firstTarget = try fixture.makeExecutable(named: "first", contents: "one")
        let secondTarget = try fixture.makeExecutable(named: "second", contents: "two")
        let link = fixture.directory.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: firstTarget)
        let resolver = CodexExecutableResolver()
        let input = ExecutablePathInput(url: link, source: .userSelected)
        let first = try XCTUnwrap(resolver.inspect([input]).first?.candidate)
        XCTAssertTrue(resolver.confirm(first))
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secondTarget)

        XCTAssertTrue(resolver.inspect([input]).first?.requiresConfirmation == true)
    }

    func testBundleAllowListRequiresValidSignatureIdentifierAndTeam() {
        let input = ExecutablePathInput(url: URL(fileURLWithPath: "/bundle/codex"), source: .chatGPTBundle)
        let trusted = inspection(
            canonicalURL: URL(fileURLWithPath: "/bundle/codex"),
            signingIdentifier: "com.openai.codex",
            teamIdentifier: "2DC432GLL2",
            signatureIsValid: true,
            bundleIdentifier: "com.openai.codex"
        )
        let resolver = CodexExecutableResolver(inspector: FakeInspector([input.url.path: trusted]))

        XCTAssertEqual(resolver.inspect([input]).first?.trust, .bundleAllowList)
    }

    func testBundleMismatchRequiresConfirmation() {
        let input = ExecutablePathInput(url: URL(fileURLWithPath: "/bundle/codex"), source: .codexBundle)
        let untrusted = inspection(
            canonicalURL: input.url,
            signingIdentifier: "com.example.codex",
            teamIdentifier: "2DC432GLL2",
            signatureIsValid: true
        )
        let resolver = CodexExecutableResolver(inspector: FakeInspector([input.url.path: untrusted]))

        XCTAssertTrue(resolver.inspect([input]).first?.requiresConfirmation == true)
    }
}

final class CodexExecutableResolverIntegrationTests: XCTestCase {
    func testChatGPTBundleProbeIsReadOnlyAndDoesNotLaunchCodex() throws {
        let url = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("ChatGPT Codex bundle is not installed")
        }

        let inspection = try CodexStaticExecutableInspector().inspect(url: url, source: .chatGPTBundle)

        XCTAssertEqual(inspection.candidate.source, .chatGPTBundle)
        XCTAssertEqual(inspection.candidate.signingIdentifier, "com.openai.codex")
        XCTAssertEqual(inspection.candidate.teamIdentifier, "2DC432GLL2")
    }
}

private final class FakeInspector: CodexExecutableInspecting {
    private var inspections: [String: StaticExecutableInspection]

    init(_ inspections: [String: StaticExecutableInspection]) {
        self.inspections = inspections
    }

    func inspect(url: URL, source: ExecutableCandidate.Source) throws -> StaticExecutableInspection {
        guard let inspection = inspections[url.path] else {
            throw CodexExecutableInspectionError.realpathFailed
        }
        return inspection
    }

    func set(_ inspection: StaticExecutableInspection, for path: String) {
        inspections[path] = inspection
    }
}

private func inspection(
    canonicalURL: URL,
    codeHash: String = "hash",
    signingIdentifier: String? = nil,
    teamIdentifier: String? = nil,
    signatureIsValid: Bool = false,
    bundleIdentifier: String? = nil
) -> StaticExecutableInspection {
    .init(
        candidate: .init(
            canonicalURL: canonicalURL,
            source: .userSelected,
            ownerUID: getuid(),
            mode: 0o755,
            signingIdentifier: signingIdentifier,
            teamIdentifier: teamIdentifier,
            codeHash: codeHash
        ),
        signatureIsValid: signatureIsValid,
        bundleIdentifier: bundleIdentifier
    )
}

private final class ExecutableFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeExecutable(named: String, contents: String, mode: mode_t = 0o755) throws -> URL {
        let url = directory.appendingPathComponent(named)
        try Data(contents.utf8).write(to: url)
        guard chmod(url.path, mode) == 0 else {
            throw POSIXError(.EPERM)
        }
        return url
    }
}
