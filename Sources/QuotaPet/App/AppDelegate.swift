import AppKit
import Combine
import Network

struct LifecycleRecoveryPolicy {
    private(set) var isSleeping = false
    private var lastNetworkSatisfied: Bool?

    mutating func willSleep() -> Bool {
        guard !isSleeping else { return false }
        isSleeping = true
        return true
    }

    mutating func didWake() -> Bool {
        guard isSleeping else { return false }
        isSleeping = false
        return true
    }

    mutating func networkChanged(isSatisfied: Bool) -> Bool {
        defer { lastNetworkSatisfied = isSatisfied }
        guard let previous = lastNetworkSatisfied else { return false }
        return !previous && isSatisfied && !isSleeping
    }
}

@MainActor
final class LifecycleRecoveryCoordinator {
    private var transitionTask: Task<Void, Never>?

    func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let predecessor = transitionTask
        transitionTask = Task {
            await predecessor?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    func interrupt(_ operation: @escaping @MainActor () async -> Void) {
        transitionTask?.cancel()
        transitionTask = Task { await operation() }
    }

    func interruptAndWait(_ operation: @escaping @MainActor () async -> Void) async {
        interrupt(operation)
        await transitionTask?.value
    }

    func cancel() {
        transitionTask?.cancel()
        transitionTask = nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: AppComposition?
    private var statusController: StatusItemController?
    private var terminationCoordinator: TerminationCoordinator?
    private var preferences: Preferences?
    private var floatingPetController: FloatingPetController?
    private var settingsController: DeferredConstruction<SettingsWindowController>?
    private var globalHotKey: GlobalHotKey?
    private var launchAtLogin: LaunchAtLogin?
    private var localNotifications: LocalNotificationController?
    private var notificationPolicy = NotificationPolicy()
    private var notificationSubscription: AnyCancellable?
    private var preferenceSubscriptions = Set<AnyCancellable>()
    private let lifecycleCoordinator = LifecycleRecoveryCoordinator()
    private var recoveryQueued = false
    private var recoveryGeneration: UInt64 = 0
    private var recoveryPolicy = LifecycleRecoveryPolicy()
    private var isTerminating = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var networkMonitor: NWPathMonitor?
    private let networkQueue = DispatchQueue(label: "QuotaPet.NetworkRecovery", qos: .utility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences()
        let resolver = CodexExecutableResolver(confirmedFingerprints: preferences.confirmedFingerprints)
        let composition = AppComposition(resolver: resolver)
        self.composition = composition
        self.preferences = preferences
        let launchAtLogin = LaunchAtLogin()
        self.launchAtLogin = launchAtLogin
        preferences.setLaunchAtLoginState(enabled: launchAtLogin.isEnabled, errorMessage: nil)
        localNotifications = LocalNotificationController()
        let connectionOffer = makeConnectionOffer(
            composition: composition,
            resolver: resolver,
            preferences: preferences
        )
        statusController = StatusItemController(
            model: composition.model,
            preferences: preferences,
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { [weak self] in self?.stopAndQuit() },
            onRecoverInteraction: { [weak self] in self?.floatingPetController?.showAndRecoverInteraction() },
            connectionOffer: connectionOffer
        )
        floatingPetController = FloatingPetController(
            model: composition.model,
            preferences: preferences,
            connectionOffer: connectionOffer
        )
        settingsController = DeferredConstruction { [weak self, weak resolver] in
            SettingsWindowController(preferences: preferences, candidates: resolver?.resolve() ?? [], onConfirm: { [weak self, weak resolver] candidate in
                guard let self, let resolver, resolver.confirm(candidate) else { return }
                preferences.confirmedFingerprints.insert(TrustFingerprint(candidate: candidate))
                self.restartProvider(resolver: resolver)
            }, onRegisterHotKey: { [weak self] in self?.registerHotKey() }, onSetLaunchAtLogin: { [weak self] enabled in
                self?.setLaunchAtLogin(enabled)
            })
        }
        globalHotKey = GlobalHotKey { [weak self] in
            DispatchQueue.main.async { self?.floatingPetController?.showAndRecoverInteraction() }
        }
        registerHotKey()
        preferences.$connectionMode.dropFirst().sink { [weak self] mode in self?.applyConnectionMode(mode) }.store(in: &preferenceSubscriptions)
        preferences.$petVisible.dropFirst().sink { [weak self] visible in
            Task { @MainActor in self?.composition?.model.setPetVisible(visible) }
        }.store(in: &preferenceSubscriptions)
        preferences.$hotKey.dropFirst().sink { [weak self] _ in self?.registerHotKey() }.store(in: &preferenceSubscriptions)
        preferences.$notificationsEnabled.dropFirst().sink { [weak self] enabled in
            if enabled { self?.localNotifications?.requestAuthorization() }
        }.store(in: &preferenceSubscriptions)
        subscribeToSnapshots(composition.model)
        terminationCoordinator = makeTerminationCoordinator()
        startLifecycleObservers()
        enqueueProviderTransition { [weak model = composition.model] in await model?.start() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminationCoordinator else { return .terminateNow }
        return terminationCoordinator.requestTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        stopLifecycleObservers()
        globalHotKey?.invalidate()
        lifecycleCoordinator.cancel()
        notificationSubscription?.cancel()
        preferenceSubscriptions.removeAll()
        floatingPetController?.invalidate()
        floatingPetController = nil
        settingsController = nil
        statusController = nil
    }

    private func showSettings() {
        settingsController?.value.show()
    }

    private func stopAndQuit() {
        NSApp.terminate(nil)
    }

    private func restartProvider(resolver: CodexExecutableResolver) {
        enqueueProviderTransition { [weak self] in
            guard let self, let previous = self.composition else { return }
            await previous.model.stop()
            guard !Task.isCancelled, let preferences = self.preferences else { return }
            self.floatingPetController?.invalidate()
            let replacement = AppComposition(resolver: resolver)
            let connectionOffer = self.makeConnectionOffer(
                composition: replacement,
                resolver: resolver,
                preferences: preferences
            )
            self.composition = replacement
            self.statusController = StatusItemController(model: replacement.model, preferences: preferences, onSettings: { [weak self] in self?.showSettings() }, onQuit: { [weak self] in self?.stopAndQuit() }, onRecoverInteraction: { [weak self] in self?.floatingPetController?.showAndRecoverInteraction() }, connectionOffer: connectionOffer)
            self.floatingPetController = FloatingPetController(model: replacement.model, preferences: preferences, connectionOffer: connectionOffer)
            self.subscribeToSnapshots(replacement.model)
            self.terminationCoordinator = self.makeTerminationCoordinator()
            if !self.isTerminating, !self.recoveryPolicy.isSleeping { await replacement.model.start() }
        }
    }

    private func makeConnectionOffer(
        composition: AppComposition,
        resolver: CodexExecutableResolver,
        preferences: Preferences
    ) -> CodexConnectionOffer? {
        guard let candidate = composition.pendingConfirmationCandidate else { return nil }
        return CodexConnectionOffer(
            displayPath: candidate.canonicalURL.path,
            confirm: { [weak self, weak resolver, weak preferences] in
                guard let self, let resolver, let preferences, resolver.confirm(candidate) else { return }
                preferences.confirmedFingerprints.insert(TrustFingerprint(candidate: candidate))
                self.restartProvider(resolver: resolver)
            }
        )
    }

    private func registerHotKey() {
        guard let preferences else { return }
        preferences.setHotKeyRegistration(globalHotKey?.register(preferences.hotKey) ?? .failure(.registrationFailed))
    }

    private func applyConnectionMode(_ mode: ConnectionMode) {
        enqueueProviderTransition { [weak self] in
            guard let self, !self.isTerminating, !self.recoveryPolicy.isSleeping else { return }
            await self.composition?.model.setConnectionMode(mode)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard let launchAtLogin, let preferences else { return }
        let update = launchAtLogin.setEnabled(enabled)
        preferences.setLaunchAtLoginState(enabled: update.isEnabled, errorMessage: update.errorMessage)
    }

    private func subscribeToSnapshots(_ model: AppModel) {
        notificationSubscription?.cancel()
        notificationSubscription = model.$snapshot.dropFirst().sink { [weak self] snapshot in
            guard let self, self.preferences?.notificationsEnabled == true,
                  let notification = self.notificationPolicy.evaluate(snapshot)
            else { return }
            self.localNotifications?.deliver(notification)
        }
    }

    private func makeTerminationCoordinator() -> TerminationCoordinator {
        TerminationCoordinator { [weak self] in
            await self?.prepareForTermination()
        }
    }

    private func prepareForTermination() async {
        guard !isTerminating else { return }
        isTerminating = true
        stopLifecycleObservers()
        recoveryGeneration += 1
        recoveryQueued = false
        await lifecycleCoordinator.interruptAndWait { [weak self] in
            await self?.composition?.model.stop()
        }
    }

    private func enqueueProviderTransition(_ operation: @escaping @MainActor () async -> Void) {
        lifecycleCoordinator.enqueue(operation)
    }

    private func startLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleWake() }
            },
        ]

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.handleNetworkChange(isSatisfied: path.status == .satisfied) }
        }
        networkMonitor = monitor
        monitor.start(queue: networkQueue)
    }

    private func stopLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        networkMonitor?.pathUpdateHandler = nil
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    private func handleSleep() {
        guard !isTerminating, recoveryPolicy.willSleep() else { return }
        recoveryGeneration += 1
        recoveryQueued = false
        lifecycleCoordinator.interrupt { [weak self] in await self?.composition?.model.stop() }
    }

    private func handleWake() {
        guard !isTerminating, recoveryPolicy.didWake() else { return }
        queueRecovery(.wake)
    }

    private func handleNetworkChange(isSatisfied: Bool) {
        guard !isTerminating else { return }
        if recoveryPolicy.networkChanged(isSatisfied: isSatisfied) { queueRecovery(.network) }
    }

    private enum RecoveryKind {
        case wake
        case network
    }

    private func queueRecovery(_ kind: RecoveryKind) {
        guard !recoveryQueued, !isTerminating else { return }
        recoveryGeneration += 1
        let generation = recoveryGeneration
        recoveryQueued = true
        enqueueProviderTransition { [weak self] in
            guard let self else { return }
            defer {
                if self.recoveryGeneration == generation { self.recoveryQueued = false }
            }
            guard !self.isTerminating, !self.recoveryPolicy.isSleeping else { return }
            guard let model = self.composition?.model else { return }
            switch kind {
            case .wake:
                await model.recoverAfterWake(mode: self.preferences?.connectionMode ?? model.connectionMode)
            case .network:
                await model.recoverAfterNetwork()
            }
            guard !self.isTerminating, !self.recoveryPolicy.isSleeping else {
                await model.stop()
                return
            }
        }
    }
}
