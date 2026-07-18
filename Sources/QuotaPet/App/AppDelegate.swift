import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: AppComposition?
    private var statusController: StatusItemController?
    private var terminationCoordinator: TerminationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let composition = AppComposition()
        self.composition = composition
        statusController = StatusItemController(
            model: composition.model,
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { [weak self] in self?.stopAndQuit() }
        )
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
        statusController = nil
    }

    private func showSettings() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func stopAndQuit() {
        NSApp.terminate(nil)
    }
}
