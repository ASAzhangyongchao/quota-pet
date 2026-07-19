import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: AppComposition?
    private var statusController: StatusItemController?
    private var terminationCoordinator: TerminationCoordinator?
    private var preferences: Preferences?
    private var floatingPetController: FloatingPetController?
    private var settingsController: SettingsWindowController?
    private var globalHotKey: GlobalHotKey?
    private var preferenceSubscriptions = Set<AnyCancellable>()
    private var restartTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences()
        let resolver = CodexExecutableResolver(confirmedFingerprints: preferences.confirmedFingerprints)
        let composition = AppComposition(resolver: resolver)
        self.composition = composition
        self.preferences = preferences
        statusController = StatusItemController(
            model: composition.model,
            preferences: preferences,
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { [weak self] in self?.stopAndQuit() },
            onRecoverInteraction: { [weak self] in self?.floatingPetController?.showAndRecoverInteraction() }
        )
        floatingPetController = FloatingPetController(model: composition.model, preferences: preferences)
        settingsController = SettingsWindowController(preferences: preferences, candidates: { resolver.resolve() }, onConfirm: { [weak self, weak resolver] candidate in
            guard let self, let resolver, resolver.confirm(candidate) else { return }
            preferences.confirmedFingerprints.insert(TrustFingerprint(candidate: candidate))
            self.restartProvider(resolver: resolver)
        }, onRegisterHotKey: { [weak self] in self?.registerHotKey() })
        globalHotKey = GlobalHotKey { [weak self] in
            DispatchQueue.main.async { self?.floatingPetController?.showAndRecoverInteraction() }
        }
        registerHotKey()
        preferences.$connectionMode.dropFirst().sink { [weak self] mode in Task { await self?.composition?.model.setConnectionMode(mode) } }.store(in: &preferenceSubscriptions)
        preferences.$hotKey.dropFirst().sink { [weak self] _ in self?.registerHotKey() }.store(in: &preferenceSubscriptions)
        terminationCoordinator = TerminationCoordinator { [weak model = composition.model] in
            await model?.stop()
        }
        Task { await composition.model.start() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminationCoordinator else { return .terminateNow }
        return terminationCoordinator.requestTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKey?.invalidate()
        restartTask?.cancel()
        preferenceSubscriptions.removeAll()
        floatingPetController = nil
        settingsController = nil
        statusController = nil
    }

    private func showSettings() {
        settingsController?.show()
    }

    private func stopAndQuit() {
        NSApp.terminate(nil)
    }

    private func restartProvider(resolver: CodexExecutableResolver) {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            guard let self, let previous = self.composition else { return }
            await previous.model.stop()
            guard !Task.isCancelled, let preferences = self.preferences else { return }
            let replacement = AppComposition(resolver: resolver)
            self.composition = replacement
            self.statusController = StatusItemController(model: replacement.model, preferences: preferences, onSettings: { [weak self] in self?.showSettings() }, onQuit: { [weak self] in self?.stopAndQuit() }, onRecoverInteraction: { [weak self] in self?.floatingPetController?.showAndRecoverInteraction() })
            self.floatingPetController = FloatingPetController(model: replacement.model, preferences: preferences)
            self.terminationCoordinator = TerminationCoordinator { [weak model = replacement.model] in await model?.stop() }
            await replacement.model.start()
        }
    }

    private func registerHotKey() {
        guard let preferences else { return }
        preferences.setHotKeyRegistration(globalHotKey?.register(preferences.hotKey) ?? .failure(.registrationFailed))
    }
}
