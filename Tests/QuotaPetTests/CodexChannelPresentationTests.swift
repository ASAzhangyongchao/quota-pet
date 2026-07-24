import XCTest
@testable import QuotaPet

final class CodexChannelPresentationTests: XCTestCase {
    func testDualCardsAlwaysExistEvenWhenTerminalMissing() {
        let chatGPT = makeCandidate(
            path: "/Applications/ChatGPT.app/Contents/Resources/codex",
            source: .chatGPTBundle
        )
        let resolutions: [ExecutableResolution] = [
            .accepted(chatGPT, trust: .bundleAllowList),
            .rejected(.realpathFailed),
            .rejected(.realpathFailed),
        ]

        let model = CodexChannelPresentation.model(from: resolutions, preferredChannel: .chatGPT)

        XCTAssertEqual(model.activeChannel, .chatGPT)
        XCTAssertEqual(model.chatGPT.status, .active)
        XCTAssertEqual(model.chatGPT.path, chatGPT.canonicalURL.path)
        XCTAssertEqual(model.terminal.status, .missing)
        XCTAssertNil(model.terminal.path)
        XCTAssertEqual(model.rejectedCount, 2)
    }

    func testPreferredTerminalSortsTrustedTerminalFirst() {
        let chatGPT = makeCandidate(
            path: "/Applications/ChatGPT.app/Contents/Resources/codex",
            source: .chatGPTBundle
        )
        let brew = makeCandidate(path: "/opt/homebrew/bin/codex", source: .homebrew)
        let resolutions: [ExecutableResolution] = [
            .accepted(chatGPT, trust: .bundleAllowList),
            .accepted(brew, trust: .confirmed),
        ]

        let trusted = TrustedCodexSelection.trustedCandidates(
            from: resolutions,
            preferredChannel: .terminal
        )
        XCTAssertEqual(trusted.first?.canonicalURL.path, brew.canonicalURL.path)

        let model = CodexChannelPresentation.model(from: resolutions, preferredChannel: .terminal)
        XCTAssertEqual(model.activeChannel, .terminal)
        XCTAssertEqual(model.terminal.status, .active)
        XCTAssertEqual(model.chatGPT.status, .ready)
    }

    func testPendingTerminalShowsNeedsConfirmation() {
        let brew = makeCandidate(path: "/opt/homebrew/bin/codex", source: .homebrew)
        let resolutions: [ExecutableResolution] = [
            .accepted(brew, trust: .requiresConfirmation),
        ]
        let model = CodexChannelPresentation.model(from: resolutions, preferredChannel: .terminal)
        XCTAssertEqual(model.terminal.status, .pending)
        XCTAssertNil(model.activeChannel)
    }

    func testScanSummaryExplainsOnlyChatGPTWhenTerminalMissing() {
        let chatGPT = makeCandidate(
            path: "/Applications/ChatGPT.app/Contents/Resources/codex",
            source: .chatGPTBundle
        )
        let resolutions: [ExecutableResolution] = [
            .accepted(chatGPT, trust: .bundleAllowList),
            .rejected(.realpathFailed),
        ]
        let summary = CodexChannelPresentation.scanSummary(
            from: resolutions,
            preferredChannel: .chatGPT,
            language: .simplifiedChinese
        )
        XCTAssertTrue(summary.contains("ChatGPT"))
        XCTAssertTrue(summary.contains("没有独立终端") || summary.contains("扫描完成"))
    }

    func testScanSummaryReportsTerminalWhenFound() {
        let brew = makeCandidate(path: "/opt/homebrew/bin/codex", source: .homebrew)
        let summary = CodexChannelPresentation.scanSummary(
            from: [.accepted(brew, trust: .confirmed)],
            preferredChannel: .terminal,
            language: .english
        )
        XCTAssertTrue(summary.lowercased().contains("terminal"))
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
