import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: AppComposition?
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let composition = AppComposition()
        self.composition = composition
        statusController = StatusItemController(
            model: composition.model,
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { [weak self] in self?.stopAndQuit() }
        )
        Task { await composition.model.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let model = composition?.model else { return }
        Task { await model.stop() }
    }

    private func showSettings() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func stopAndQuit() {
        guard let model = composition?.model else {
            NSApp.terminate(nil)
            return
        }
        Task {
            await model.stop()
            NSApp.terminate(nil)
        }
    }
}
