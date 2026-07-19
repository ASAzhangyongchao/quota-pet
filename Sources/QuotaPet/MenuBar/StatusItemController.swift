import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let ringView = UsageRingView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
    private let popover = NSPopover()
    private let popoverContent: DeferredConstruction<NSViewController>
    private let summaryField = NSTextField(labelWithString: "Codex 用量暂不可用")
    private let detailsViewModel: UsageDetailsViewModel
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private let onRecoverInteraction: () -> Void
    private let preferences: Preferences?
    private var snapshotSubscription: AnyCancellable?

    init(model: AppModel, preferences: Preferences? = nil, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void, onRecoverInteraction: @escaping () -> Void = {}, connectionOffer: CodexConnectionOffer? = nil) {
        self.model = model
        self.onSettings = onSettings
        self.onQuit = onQuit
        self.onRecoverInteraction = onRecoverInteraction
        self.preferences = preferences
        let detailsViewModel = UsageDetailsViewModel(snapshot: model.snapshot)
        self.detailsViewModel = detailsViewModel
        popoverContent = DeferredConstruction {
            NSHostingController(rootView: UsagePopoverView(viewModel: detailsViewModel, connectionOffer: connectionOffer, onRefresh: { [weak model] in
                Task { await model?.refresh() }
            }))
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusButton()
        popover.behavior = .transient
        configureMenu()
        snapshotSubscription = model.$snapshot.sink { [weak self] snapshot in
            self?.ringView.setSnapshot(snapshot)
            self?.summaryField.stringValue = UsageRingStyle(snapshot: snapshot).accessibilityLabel
            self?.detailsViewModel.update(snapshot)
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
        if let preferences { preferences.petVisible.toggle() } else { model.togglePetVisible() }
    }

    @objc private func useRealtime(_ sender: Any?) {
        preferences?.connectionMode = .realtime
        Task { await model.setConnectionMode(.realtime) }
    }

    @objc private func useEnergySaver(_ sender: Any?) {
        preferences?.connectionMode = .energySaver
        Task { await model.setConnectionMode(.energySaver) }
    }

    @objc private func showSettings(_ sender: Any?) {
        onSettings()
    }

    @objc private func recoverInteraction(_ sender: Any?) { onRecoverInteraction() }

    @objc private func quit(_ sender: Any?) {
        onQuit()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == self.menu else { return }
        menu.item(withTag: 1)?.state = (preferences?.petVisible ?? model.petVisible) ? .on : .off
        menu.item(withTag: 2)?.state = (preferences?.connectionMode ?? model.connectionMode) == .realtime ? .on : .off
        menu.item(withTag: 3)?.state = (preferences?.connectionMode ?? model.connectionMode) == .energySaver ? .on : .off
        menu.item(withTag: 4)?.isHidden = !(preferences?.ignoresMouseEvents ?? false)
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
        let recover = menu.addItem(withTitle: "恢复桌宠交互", action: #selector(recoverInteraction(_:)), keyEquivalent: "")
        recover.target = self
        recover.tag = 4
        menu.addItem(withTitle: "设置", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "退出", action: #selector(quit(_:)), keyEquivalent: "q").target = self
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if popover.contentViewController == nil {
                popover.contentViewController = popoverContent.value
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
}
