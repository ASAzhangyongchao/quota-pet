import AppKit
import XCTest
@testable import QuotaPet

@MainActor
final class PreferencesTests: XCTestCase {
    func testDefaultsAndWhitelistPersistenceAvoidUsageData() {
        let store = makeStore()
        let preferences = Preferences(store: store)

        XCTAssertTrue(preferences.petVisible)
        XCTAssertTrue(preferences.alwaysOnTop)
        XCTAssertFalse(preferences.ignoresMouseEvents)
        XCTAssertEqual(preferences.connectionMode, .realtime)
        XCTAssertEqual(preferences.hotKey, .optionCommandU)
        XCTAssertFalse(preferences.notificationsEnabled)

        preferences.petVisible = false
        preferences.normalizedPosition = NormalizedScreenPosition(x: 1.4, y: -0.2, screenIdentifier: "display")
        preferences.confirmedFingerprints = [fingerprint()]
        let restored = Preferences(store: store)

        XCTAssertFalse(restored.petVisible)
        XCTAssertEqual(restored.normalizedPosition, NormalizedScreenPosition(x: 1, y: 0, screenIdentifier: "display"))
        XCTAssertEqual(restored.confirmedFingerprints, [fingerprint()])
        XCTAssertNil(store.object(forKey: "QuotaPet.snapshot"))
        XCTAssertNil(store.object(forKey: "QuotaPet.email"))
        XCTAssertNil(store.object(forKey: "QuotaPet.used"))
    }

    func testNormalizedPositionRoundTripsAndKeepsPanelFullyVisibleOnNegativeOriginScreen() {
        let visible = CGRect(x: -1440, y: 23, width: 1440, height: 877)
        let panel = CGSize(width: 72, height: 72)
        let position = NormalizedScreenPosition(panelOrigin: CGPoint(x: -1300, y: 700), panelSize: panel, visibleFrame: visible, screenIdentifier: "left")

        XCTAssertEqual(position.screenIdentifier, "left")
        XCTAssertEqual(position.panelOrigin(panelSize: panel, visibleFrame: visible), CGPoint(x: -1300, y: 700))
        XCTAssertTrue(visible.contains(CGRect(origin: position.panelOrigin(panelSize: panel, visibleFrame: visible), size: panel)))

        let moved = NormalizedScreenPosition(x: 1, y: 1, screenIdentifier: "missing").panelOrigin(panelSize: panel, visibleFrame: CGRect(x: 0, y: 0, width: 60, height: 60))
        XCTAssertEqual(moved, CGPoint(x: 0, y: 0))
    }

    func testFloatingContractAndPassthroughRecoveryArePure() {
        XCTAssertEqual(FloatingPetPanelContract.default.size, CGSize(width: 72, height: 72))
        XCTAssertEqual(FloatingPetPanelContract.default.levelName, .floating)
        XCTAssertTrue(FloatingPetPanelContract.default.joinsAllSpaces)
        XCTAssertEqual(FloatingPetPanelContract(alwaysOnTop: false).levelName, .normal)
        XCTAssertFalse(FloatingPetPanelContract(alwaysOnTop: false).joinsAllSpaces)

        var interaction = FloatingPetInteractionState(ignoresMouseEvents: true, visible: false)
        interaction.recoverForMenuOrHotKey()
        XCTAssertFalse(interaction.ignoresMouseEvents)
        XCTAssertTrue(interaction.visible)
    }

    func testTrustFingerprintChangedHashStopsBeingConfirmedAfterRestoration() {
        let store = makeStore()
        let saved = fingerprint()
        Preferences(store: store).confirmedFingerprints = [saved]
        let resolver = CodexExecutableResolver(inspector: TrustInspector(candidate: candidate(hash: "different")), confirmedFingerprints: Preferences(store: store).confirmedFingerprints)

        let result = resolver.inspect([ExecutablePathInput(url: URL(fileURLWithPath: "/input/codex"), source: .userSelected)])
        XCTAssertTrue(result.first?.requiresConfirmation == true)
    }

    private func makeStore() -> UserDefaults {
        let suite = "QuotaPetTests.Preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private func fingerprint() -> TrustFingerprint { TrustFingerprint(candidate: candidate(hash: "safe")) }

private func candidate(hash: String) -> ExecutableCandidate {
    ExecutableCandidate(canonicalURL: URL(fileURLWithPath: "/safe/codex"), source: .userSelected, ownerUID: 0, mode: 0o755, signingIdentifier: "com.example.codex", teamIdentifier: nil, codeHash: hash, deviceID: 1, inode: 2, inputURL: URL(fileURLWithPath: "/input/codex"))
}

private final class TrustInspector: CodexExecutableInspecting {
    let inspected: StaticExecutableInspection
    init(candidate: ExecutableCandidate) { inspected = StaticExecutableInspection(candidate: candidate, signatureIsValid: false, bundleIdentifier: nil) }
    func inspect(url: URL, source: ExecutableCandidate.Source) throws -> StaticExecutableInspection { inspected }
}
