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

/// Decides when Codex trust / process death should rebuild AppComposition (e.g. after ChatGPT updates).
struct ProviderHealthRecoveryPolicy: Equatable {
    static let minimumRestartInterval: TimeInterval = 30
    static let softFailureThreshold = 2

    private(set) var consecutiveSoftFailures = 0
    private var lastRestartAt: Date?

    mutating func noteReady() {
        consecutiveSoftFailures = 0
    }

    /// Returns true when the host should call `restartProvider` (throttled).
    mutating func shouldRestartProvider(
        for snapshot: QuotaSnapshot,
        language: AppLanguage,
        now: Date = .now
    ) -> Bool {
        if case .ready = snapshot.state {
            noteReady()
            return false
        }

        let trustMessage = L10n.text(.errorTrustValidation, language: language)
        let exitedMessage = L10n.text(.errorAppServerExited, language: language)
        let timedOutMessage = L10n.text(.errorRequestTimedOut, language: language)
        let requestFailedMessage = L10n.text(.errorRequestFailed, language: language)
        let message: String?
        switch snapshot.state {
        case let .incompatible(value), let .unavailable(value), let .stale(value):
            message = value
        case .loading, .ready:
            message = nil
        }

        let isTrustFailure = snapshot.state.isIncompatible || message == trustMessage
        let isSoftFailure =
            message == exitedMessage
            || message == timedOutMessage
            || message == requestFailedMessage

        if isSoftFailure {
            consecutiveSoftFailures += 1
        } else if isTrustFailure {
            consecutiveSoftFailures = 0
        }

        let shouldAttempt =
            isTrustFailure
            || (isSoftFailure && consecutiveSoftFailures >= Self.softFailureThreshold)

        guard shouldAttempt else { return false }
        if let lastRestartAt, now.timeIntervalSince(lastRestartAt) < Self.minimumRestartInterval {
            return false
        }
        lastRestartAt = now
        consecutiveSoftFailures = 0
        return true
    }
}

private extension ConnectionState {
    var isIncompatible: Bool {
        if case .incompatible = self { return true }
        return false
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
    private var executableResolver: CodexExecutableResolver?
    private var floatingPetController: FloatingPetController?
    private var settingsController: DeferredConstruction<SettingsWindowController>?
    private var globalHotKey: GlobalHotKey?
    private var launchAtLogin: LaunchAtLogin?
    private var localNotifications: LocalNotificationController?
    private var notificationPolicy = NotificationPolicy()
    private var notificationSubscription: AnyCancellable?
    private var healthSubscription: AnyCancellable?
    private var preferenceSubscriptions = Set<AnyCancellable>()
    private let lifecycleCoordinator = LifecycleRecoveryCoordinator()
    private var recoveryQueued = false
    private var recoveryGeneration: UInt64 = 0
    private var recoveryPolicy = LifecycleRecoveryPolicy()
    private var providerHealthPolicy = ProviderHealthRecoveryPolicy()
    private var skippedCodexPaths: [String: Date] = [:]
    private static let skippedCodexPathTTL: TimeInterval = 15 * 60
    private var isTerminating = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var networkMonitor: NWPathMonitor?
    private let networkQueue = DispatchQueue(label: "QuotaPet.NetworkRecovery", qos: .utility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences()
        let resolver = CodexExecutableResolver(confirmedFingerprints: preferences.confirmedFingerprints) { [weak preferences] fingerprints in
            preferences?.confirmedFingerprints = fingerprints
        }
        self.executableResolver = resolver
        self.preferences = preferences
        let composition = makeComposition(resolver: resolver)
        self.composition = composition
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
            SettingsWindowController(
                preferences: preferences,
                candidates: self?.resolveCandidates() ?? [],
                onPreferChannel: { [weak self] channel in
                    self?.preferCodexChannel(channel)
                },
                onRescan: { [weak self] in
                    self?.refreshSettingsCandidates()
                },
                onPickTerminalCodex: { [weak self] in
                    self?.pickTerminalCodex()
                },
                onRegisterHotKey: { [weak self] in self?.registerHotKey() },
                onSetLaunchAtLogin: { [weak self] enabled in
                    self?.setLaunchAtLogin(enabled)
                }
            )
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
        healthSubscription?.cancel()
        healthSubscription = nil
        executableResolver = nil
    }

    private func showSettings() {
        refreshSettingsCandidates()
        settingsController?.value.show(candidates: resolveCandidates())
    }

    private func resolveCandidates() -> [ExecutableResolution] {
        executableResolver?.resolve(
            userSelectedURL: preferences?.userSelectedCodexURL,
            path: ProcessInfo.processInfo.environment["PATH"]
        ) ?? []
    }

    private func refreshSettingsCandidates() {
        settingsController?.value.show(candidates: resolveCandidates())
    }

    private func makeComposition(
        resolver: CodexExecutableResolver,
        skippingPaths: Set<String> = []
    ) -> AppComposition {
        AppComposition(
            resolver: resolver,
            skippingPaths: skippingPaths,
            preferredChannel: preferences?.preferredCodexChannel ?? .chatGPT,
            userSelectedURL: preferences?.userSelectedCodexURL
        )
    }

    private func preferCodexChannel(_ channel: PreferredCodexChannel) {
        guard let preferences, let resolver = executableResolver else { return }
        preferences.preferredCodexChannel = channel
        let resolutions = resolveCandidates()
        let model = CodexChannelPresentation.model(from: resolutions, preferredChannel: channel)
        let card = channel == .chatGPT ? model.chatGPT : model.terminal
        if let candidate = card.candidate {
            if resolver.confirm(candidate) {
                preferences.confirmedFingerprints.insert(TrustFingerprint(candidate: candidate))
            }
        }
        restartProvider(resolver: resolver)
        refreshSettingsCandidates()
    }

    private func pickTerminalCodex() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.text(.settingsCodexPickFile, language: preferences?.resolvedLanguage ?? .current)
        panel.prompt = L10n.text(.settingsCodexUseThis, language: preferences?.resolvedLanguage ?? .current)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let preferences, let resolver = executableResolver else { return }
        preferences.userSelectedCodexPath = url.path
        preferences.preferredCodexChannel = .terminal
        let resolutions = resolveCandidates()
        if let candidate = resolutions.compactMap(\.candidate).first(where: {
            $0.canonicalURL.path == url.path || $0.inputURL.path == url.path
        }) ?? resolutions.compactMap(\.candidate).first(where: {
            PreferredCodexChannel.channel(for: $0.source) == .terminal
        }) {
            if resolver.confirm(candidate) {
                preferences.confirmedFingerprints.insert(TrustFingerprint(candidate: candidate))
            }
        }
        restartProvider(resolver: resolver)
        refreshSettingsCandidates()
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
            let replacement = self.makeComposition(
                resolver: resolver,
                skippingPaths: self.activeSkippedCodexPaths()
            )
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

    private func activeSkippedCodexPaths(now: Date = .now) -> Set<String> {
        skippedCodexPaths = skippedCodexPaths.filter {
            now.timeIntervalSince($0.value) < Self.skippedCodexPathTTL
        }
        return Set(skippedCodexPaths.keys)
    }

    private func noteSkippedCodexPath(_ path: String, resolver: CodexExecutableResolver) {
        let allTrusted = TrustedCodexSelection.trustedCandidates(
            from: resolveCandidates(),
            preferredChannel: preferences?.preferredCodexChannel ?? .chatGPT
        )
        // Only demote a path when another trusted binary exists; otherwise keep retrying it.
        guard allTrusted.contains(where: { $0.canonicalURL.path != path }) else { return }
        skippedCodexPaths[path] = .now
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
        healthSubscription?.cancel()
        notificationSubscription = model.$snapshot.dropFirst().sink { [weak self] snapshot in
            guard let self, self.preferences?.notificationsEnabled == true,
                  let notification = self.notificationPolicy.evaluate(snapshot)
            else { return }
            self.localNotifications?.deliver(notification)
        }
        healthSubscription = model.$snapshot.dropFirst().sink { [weak self] snapshot in
            self?.evaluateProviderHealth(snapshot)
        }
    }

    private func evaluateProviderHealth(_ snapshot: QuotaSnapshot) {
        guard !isTerminating, let resolver = executableResolver, let preferences else { return }
        let language = preferences.resolvedLanguage
        guard providerHealthPolicy.shouldRestartProvider(for: snapshot, language: language) else { return }
        if let failedPath = composition?.trustedCandidates.first?.canonicalURL.path {
            noteSkippedCodexPath(failedPath, resolver: resolver)
        }
        restartProvider(resolver: resolver)
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
