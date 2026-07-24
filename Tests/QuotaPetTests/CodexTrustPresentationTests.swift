import XCTest
@testable import QuotaPet

final class CodexTrustPresentationTests: XCTestCase {
    func testModelSeparatesPrimaryTrustedPendingAndRejectedNoise() {
        let chatGPT = makeCandidate(
            path: "/Applications/ChatGPT.app/Contents/Resources/codex",
            source: .chatGPTBundle
        )
        let brew = makeCandidate(path: "/opt/homebrew/bin/codex", source: .homebrew)
        let pathCodex = makeCandidate(path: "/tmp/codex", source: .path)
        let resolutions: [ExecutableResolution] = [
            .accepted(chatGPT, trust: .bundleAllowList),
            .accepted(brew, trust: .requiresConfirmation),
            .accepted(pathCodex, trust: .confirmed),
            .rejected(.realpathFailed),
            .rejected(.realpathFailed),
        ]

        let model = CodexTrustListPresentation.model(from: resolutions)

        XCTAssertEqual(model.primary?.candidate.canonicalURL.path, chatGPT.canonicalURL.path)
        XCTAssertEqual(model.primary?.badge, .primary)
        XCTAssertEqual(model.alternatives.count, 2)
        XCTAssertEqual(model.alternatives.map(\.badge), [.pending, .trustedBackup])
        XCTAssertEqual(model.rejectedCount, 2)
    }

    func testSourceTitlesAreHumanReadable() {
        XCTAssertEqual(
            CodexTrustListPresentation.sourceTitle(.chatGPTBundle, language: .simplifiedChinese),
            "ChatGPT 应用自带"
        )
        XCTAssertEqual(
            CodexTrustListPresentation.sourceTitle(.homebrew, language: .simplifiedChinese),
            "Homebrew 终端 Codex"
        )
        XCTAssertEqual(
            CodexTrustListPresentation.sourceTitle(.path, language: .english),
            "Codex on your PATH"
        )
    }
}

private func makeCandidate(path: String, source: ExecutableCandidate.Source) -> ExecutableCandidate {
    let url = URL(fileURLWithPath: path)
    return ExecutableCandidate(
        canonicalURL: url,
        source: source,
        ownerUID: 501,
        mode: 0o755,
        signingIdentifier: "com.openai.codex",
        teamIdentifier: "2DC432GLL2",
        codeHash: "abc",
        deviceID: 1,
        inode: 2,
        inputURL: url
    )
}
