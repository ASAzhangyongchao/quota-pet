import AppKit

@MainActor
final class TerminationCoordinator {
    private let stop: () async -> Void
    private var terminationRequested = false
    private var replied = false

    init(stop: @escaping () async -> Void) {
        self.stop = stop
    }

    func requestTermination(reply: @escaping @MainActor () -> Void) -> NSApplication.TerminateReply {
        guard !terminationRequested else { return .terminateLater }
        terminationRequested = true
        Task { [weak self] in
            guard let self else { return }
            await stop()
            guard !replied else { return }
            replied = true
            reply()
        }
        return .terminateLater
    }
}
