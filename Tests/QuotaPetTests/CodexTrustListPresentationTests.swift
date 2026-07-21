import XCTest
@testable import QuotaPet

final class CodexTrustListPresentationTests: XCTestCase {
    func testPreviewKeepsShortListsIntact() {
        let items = [
            ExecutableResolution.rejected(.realpathFailed),
            ExecutableResolution.rejected(.notExecutable),
        ]
        XCTAssertEqual(CodexTrustListPresentation.preview(from: items), items)
    }

    func testPreviewPrefersActionableAndTrustedOverRejected() {
        let trusted = ExecutableResolution.accepted(sampleCandidate(path: "/trusted"), trust: .confirmed)
        let pending = ExecutableResolution.accepted(sampleCandidate(path: "/pending"), trust: .requiresConfirmation)
        let rejected = (0..<6).map { _ in ExecutableResolution.rejected(.realpathFailed) }
        let all = rejected + [trusted, pending] + rejected

        let preview = CodexTrustListPresentation.preview(from: all, limit: 3)
        XCTAssertEqual(preview.count, 3)
        XCTAssertEqual(preview[0], pending)
        XCTAssertEqual(preview[1], trusted)
        XCTAssertEqual(preview[2], .rejected(.realpathFailed))
    }

    private func sampleCandidate(path: String) -> ExecutableCandidate {
        ExecutableCandidate(
            canonicalURL: URL(fileURLWithPath: path),
            source: .userSelected,
            ownerUID: 0,
            mode: 0o755,
            signingIdentifier: nil,
            teamIdentifier: nil,
            codeHash: "hash",
            deviceID: 1,
            inode: 1,
            inputURL: URL(fileURLWithPath: path)
        )
    }
}
