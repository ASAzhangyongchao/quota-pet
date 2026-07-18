import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let ringView = UsageRingView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
    private let popover = NSPopover()
    private let summaryField = NSTextField(labelWithString: "Codex 用量暂不可用")
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private var snapshotSubscription: AnyCancellable?

    init(model: AppModel, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.model = model
        self.onSettings = onSettings
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusButton()
        configurePopover()
        configureMenu()
        snapshotSubscription = model.$snapshot.sink { [weak self] snapshot in
            self?.ringView.setSnapshot(snapshot)
            self?.summaryField.stringValue = UsageRingStyle(snapshot: snapshot).accessibilityLabel
        }
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    @objc private func refresh(_ sender: Any?) {
        Task { await model.refresh() }
    }

    @objc private func togglePet(_ sender: Any?) {
        model.togglePetVisible()
    }

    @objc private func useRealtime(_ sender: Any?) {
        Task { await model.setConnectionMode(.realtime) }
    }

    @objc private func useEnergySaver(_ sender: Any?) {
        Task { await model.setConnectionMode(.energySaver) }
    }

    @objc private func showSettings(_ sender: Any?) {
        onSettings()
    }

    @objc private func quit(_ sender: Any?) {
        onQuit()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == self.menu else { return }
        menu.item(withTag: 1)?.state = model.petVisible ? .on : .off
        menu.item(withTag: 2)?.state = model.connectionMode == .realtime ? .on : .off
        menu.item(withTag: 3)?.state = model.connectionMode == .energySaver ? .on : .off
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.frame.size = NSSize(width: 24, height: 22)
        ringView.frame = button.bounds.insetBy(dx: 3, dy: 2)
        ringView.autoresizingMask = [.width, .height]
        button.addSubview(ringView)
    }

    private func configurePopover() {
        let controller = NSViewController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 48))
        summaryField.frame = NSRect(x: 12, y: 14, width: 196, height: 20)
        summaryField.lineBreakMode = .byTruncatingTail
        view.addSubview(summaryField)
        controller.view = view
        popover.behavior = .transient
        popover.contentViewController = controller
    }

    private func configureMenu() {
        menu.delegate = self
        menu.addItem(withTitle: "立即刷新", action: #selector(refresh(_:)), keyEquivalent: "").target = self
        let pet = menu.addItem(withTitle: "显示桌宠", action: #selector(togglePet(_:)), keyEquivalent: "")
        pet.target = self
        pet.tag = 1
        let realtime = menu.addItem(withTitle: "实时模式", action: #selector(useRealtime(_:)), keyEquivalent: "")
        realtime.target = self
        realtime.tag = 2
        let saver = menu.addItem(withTitle: "节能模式", action: #selector(useEnergySaver(_:)), keyEquivalent: "")
        saver.target = self
        saver.tag = 3
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "退出", action: #selector(quit(_:)), keyEquivalent: "q").target = self
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
}
