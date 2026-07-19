import Combine
import Foundation

protocol AppPreferenceStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: AppPreferenceStoring {}

@MainActor
final class AppModel: NSObject, ObservableObject {
    private enum Key {
        static let connectionMode = "QuotaPet.connectionMode"
        static let petVisible = "QuotaPet.petVisible"
    }

    @Published private(set) var snapshot: QuotaSnapshot
    @Published private(set) var connectionMode: ConnectionMode
    @Published private(set) var petVisible: Bool
    @Published private(set) var lastError: String?

    private let provider: any UsageProvider
    private let store: any AppPreferenceStoring
    private var lastSuccessful: QuotaSnapshot?
    private var snapshotTask: Task<Void, Never>?

    init(provider: any UsageProvider, store: any AppPreferenceStoring = UserDefaults.standard) {
        self.provider = provider
        self.store = store
        connectionMode = ConnectionMode(rawValue: store.object(forKey: Key.connectionMode) as? String ?? "") ?? .energySaver
        petVisible = store.object(forKey: Key.petVisible) as? Bool ?? true
        snapshot = QuotaSnapshot(planType: nil, windows: [], updatedAt: .distantPast, state: .loading)
        lastError = nil
        super.init()
    }

    deinit {
        snapshotTask?.cancel()
    }

    func start() async {
        startSnapshotTaskIfNeeded()
        await provider.start(mode: connectionMode)
    }

    func refresh() async {
        await provider.refresh()
    }

    func recoverAfterWake(mode: ConnectionMode) async {
        if connectionMode != mode {
            connectionMode = mode
            store.set(mode.rawValue, forKey: Key.connectionMode)
        }
        startSnapshotTaskIfNeeded()
        await provider.recover(mode: connectionMode, restartIfStopped: true)
    }

    func recoverAfterNetwork() async {
        await provider.recover(mode: connectionMode, restartIfStopped: false)
    }

    func setConnectionMode(_ mode: ConnectionMode) async {
        guard connectionMode != mode else { return }
        connectionMode = mode
        store.set(mode.rawValue, forKey: Key.connectionMode)
        await provider.start(mode: mode)
    }

    func setPetVisible(_ visible: Bool) {
        guard petVisible != visible else { return }
        petVisible = visible
        store.set(visible, forKey: Key.petVisible)
    }

    func togglePetVisible() {
        setPetVisible(!petVisible)
    }

    func stop() async {
        snapshotTask?.cancel()
        snapshotTask = nil
        await provider.stop()
    }

    private func startSnapshotTaskIfNeeded() {
        guard snapshotTask == nil else { return }
        let provider = provider
        snapshotTask = Task { [weak self, provider] in
            for await incoming in provider.snapshots {
                guard !Task.isCancelled else { return }
                self?.receive(incoming)
            }
        }
    }

    private func receive(_ incoming: QuotaSnapshot) {
        switch incoming.state {
        case .ready:
            snapshot = incoming
            lastSuccessful = incoming
            lastError = nil
        case let .stale(message), let .unavailable(message), let .incompatible(message):
            lastError = message
            guard let lastSuccessful else {
                snapshot = incoming
                return
            }
            snapshot = QuotaSnapshot(
                planType: lastSuccessful.planType,
                windows: lastSuccessful.windows,
                updatedAt: lastSuccessful.updatedAt,
                state: .stale(message)
            )
        case .loading:
            snapshot = incoming
            lastError = nil
        }
    }
}

final class UnavailableUsageProvider: UsageProvider {
    let snapshots: AsyncStream<QuotaSnapshot>
    private let continuation: AsyncStream<QuotaSnapshot>.Continuation
    private let message: String

    init(message: String) {
        self.message = message
        var savedContinuation: AsyncStream<QuotaSnapshot>.Continuation?
        snapshots = AsyncStream { savedContinuation = $0 }
        continuation = savedContinuation!
    }

    func start(mode _: ConnectionMode) async {
        continuation.yield(QuotaSnapshot(planType: nil, windows: [], updatedAt: .now, state: .unavailable(message)))
    }

    func refresh() async {
        continuation.yield(QuotaSnapshot(planType: nil, windows: [], updatedAt: .now, state: .unavailable(message)))
    }

    func recover(mode: ConnectionMode, restartIfStopped: Bool) async {
        if restartIfStopped {
            await start(mode: mode)
        } else {
            await refresh()
        }
    }

    func stop() async {}
}

protocol AppExecutableResolving: UsageExecutableResolving {
    func resolve(userSelectedURL: URL?, path: String?) -> [ExecutableResolution]
}

extension CodexExecutableResolver: AppExecutableResolving {}

@MainActor
final class AppComposition {
    let provider: any UsageProvider
    let model: AppModel

    init(
        resolver: any AppExecutableResolving = CodexExecutableResolver(),
        sessionFactory: any CodexAppServerSessionFactory = FoundationCodexAppServerSessionFactory(),
        store: any AppPreferenceStoring = UserDefaults.standard
    ) {
        let trustedCandidate = resolver.resolve(userSelectedURL: nil, path: ProcessInfo.processInfo.environment["PATH"]).compactMap { resolution -> ExecutableCandidate? in
            guard case let .accepted(candidate, trust) = resolution,
                  trust == .bundleAllowList || trust == .confirmed
            else { return nil }
            return candidate
        }.first

        if let trustedCandidate {
            provider = CodexAppServerStdioProvider(candidate: trustedCandidate, resolver: resolver, sessionFactory: sessionFactory)
        } else {
            provider = UnavailableUsageProvider(message: "未找到已信任的 Codex 可执行文件")
        }
        model = AppModel(provider: provider, store: store)
    }
}
