import XCTest
@testable import QuotaPet

final class GlobalHotKeyTests: XCTestCase {
    func testDefaultEncodingUsesOptionCommandU() {
        XCTAssertEqual(HotKeyShortcut.optionCommandU.keyCode, 32)
        XCTAssertEqual(HotKeyShortcut.optionCommandU.carbonModifiers, HotKeyShortcut.commandModifier | HotKeyShortcut.optionModifier)
    }

    func testInstallFailureDoesNotAttemptRegistration() {
        let backend = FailedInstallBackend()
        let hotKey = GlobalHotKey(backend: backend) {}
        XCTAssertThrowsError(try hotKey.register(.optionCommandU).get()) { XCTAssertEqual($0 as? GlobalHotKeyError, .registrationFailed) }
        XCTAssertEqual(backend.registerCount, 0)
    }

    func testConflictLeavesHotKeyUnregisteredAndReplacingUnregistersOldHandle() {
        let backend = FakeHotKeyBackend(results: [.success(1), .failure(.occupied), .success(2)])
        let hotKey = GlobalHotKey(backend: backend) {}
        XCTAssertNoThrow(try hotKey.register(.optionCommandU).get())
        XCTAssertThrowsError(try hotKey.register(.optionCommandU).get()) { XCTAssertEqual($0 as? GlobalHotKeyError, .occupied) }
        XCTAssertEqual(backend.unregistered, [1])
        XCTAssertNoThrow(try hotKey.register(.optionCommandU).get())
        hotKey.invalidate()
        XCTAssertEqual(backend.unregistered, [1, 2])
        XCTAssertEqual(backend.removeHandlerCount, 1)
    }

    @MainActor
    func testPreferencesExposeChineseRegistrationFailureAndClearItOnSuccess() {
        let preferences = Preferences(store: makeStore())
        preferences.setHotKeyRegistration(.failure(.occupied))
        XCTAssertEqual(preferences.hotKeyStatusMessage, "快捷键已被其他应用占用")
        preferences.setHotKeyRegistration(.success(()))
        XCTAssertNil(preferences.hotKeyStatusMessage)
    }
}

@MainActor
private func makeStore() -> UserDefaults {
    let suite = "QuotaPetTests.HotKey.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private final class FakeHotKeyBackend: GlobalHotKeyBackend {
    var results: [Result<Int, GlobalHotKeyError>]
    var unregistered: [Int] = []
    var removeHandlerCount = 0
    init(results: [Result<Int, GlobalHotKeyError>]) { self.results = results }
    func installHandler(_ callback: @escaping () -> Void) -> Result<Int, GlobalHotKeyError> { .success(9) }
    func removeHandler(_ handle: Int) { removeHandlerCount += 1 }
    func register(_ shortcut: HotKeyShortcut, handler: Int) -> Result<Int, GlobalHotKeyError> { results.removeFirst() }
    func unregister(_ handle: Int) { unregistered.append(handle) }
}

private final class FailedInstallBackend: GlobalHotKeyBackend {
    var registerCount = 0
    func installHandler(_ callback: @escaping () -> Void) -> Result<Int, GlobalHotKeyError> { .failure(.registrationFailed) }
    func removeHandler(_ handle: Int) {}
    func register(_ shortcut: HotKeyShortcut, handler: Int) -> Result<Int, GlobalHotKeyError> { registerCount += 1; return .failure(.registrationFailed) }
    func unregister(_ handle: Int) {}
}
