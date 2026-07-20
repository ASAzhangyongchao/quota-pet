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
    private let summaryField = NSTextField(labelWithString: L10n.text(.ringUnavailable))
    private let detailsViewModel: UsageDetailsViewModel
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private let onRecoverInteraction: () -> Void
    private let preferences: Preferences?
    private let connectionOffer: CodexConnectionOffer?
    private var snapshotSubscription: AnyCancellable?
    private var languageSubscription: AnyCancellable?

    init(model: AppModel, preferences: Preferences? = nil, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void, onRecoverInteraction: @escaping () -> Void = {}, connectionOffer: CodexConnectionOffer? = nil) {
        self.model = model
        self.onSettings = onSettings
        self.onQuit = onQuit
        self.onRecoverInteraction = onRecoverInteraction
        self.preferences = preferences
        self.connectionOffer = connectionOffer
        let language = preferences?.resolvedLanguage ?? .current
        let detailsViewModel = UsageDetailsViewModel(snapshot: model.snapshot, language: language)
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
        rebuildMenu()
        snapshotSubscription = model.$snapshot.sink { [weak self] snapshot in
            self?.ringView.setSnapshot(snapshot)
            self?.summaryField.stringValue = UsageRingStyle(snapshot: snapshot, language: self?.resolvedLanguage ?? .current).accessibilityLabel
            self?.detailsViewModel.update(snapshot)
        }
        languageSubscription = preferences?.$languagePreference
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyLanguage()
            }
        applyLanguage()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private var resolvedLanguage: AppLanguage {
        preferences?.resolvedLanguage ?? .current
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
        detailsViewModel.beginRefresh { [weak self] in
            Task { await self?.model.refresh() }
        }
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

    @objc private func showHelp(_ sender: Any?) {
        UserGuide.open(language: resolvedLanguage)
    }

    @objc private func showAbout(_ sender: Any?) {
        let language = resolvedLanguage
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let alert = NSAlert()
        alert.messageText = L10n.text(.aboutTitle, language: language)
        alert.informativeText = [
            L10n.text(.aboutVersion, language: language, arguments: [version]),
            L10n.text(.settingsUnofficialNotice, language: language),
            L10n.text(.settingsMarksNotice, language: language),
        ].joined(separator: "\n\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text(.aboutOK, language: language))
        alert.runModal()
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

    private func applyLanguage() {
        let language = resolvedLanguage
        detailsViewModel.setLanguage(language)
        detailsViewModel.update(model.snapshot)
        summaryField.stringValue = UsageRingStyle(snapshot: model.snapshot, language: language).accessibilityLabel
        rebuildMenu()
        if let hosting = popover.contentViewController as? NSHostingController<UsagePopoverView> {
            hosting.rootView = UsagePopoverView(viewModel: detailsViewModel, connectionOffer: connectionOffer, onRefresh: { [weak self] in
                Task { await self?.model.refresh() }
            })
        }
    }

    private func rebuildMenu() {
        let language = resolvedLanguage
        menu.removeAllItems()
        menu.delegate = self
        menu.addItem(withTitle: L10n.text(.refreshNow, language: language), action: #selector(refresh(_:)), keyEquivalent: "").target = self
        let pet = menu.addItem(withTitle: L10n.text(.menuShowPet, language: language), action: #selector(togglePet(_:)), keyEquivalent: "")
        pet.target = self
        pet.tag = 1
        let realtime = menu.addItem(withTitle: L10n.text(.menuRealtime, language: language), action: #selector(useRealtime(_:)), keyEquivalent: "")
        realtime.target = self
        realtime.tag = 2
        let saver = menu.addItem(withTitle: L10n.text(.menuEnergySaver, language: language), action: #selector(useEnergySaver(_:)), keyEquivalent: "")
        saver.target = self
        saver.tag = 3
        menu.addItem(.separator())
        let recover = menu.addItem(withTitle: L10n.text(.menuRecoverInteraction, language: language), action: #selector(recoverInteraction(_:)), keyEquivalent: "")
        recover.target = self
        recover.tag = 4
        menu.addItem(withTitle: L10n.text(.menuSettings, language: language), action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text(.menuHelp, language: language), action: #selector(showHelp(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.text(.menuAbout, language: language), action: #selector(showAbout(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.text(.menuQuit, language: language), action: #selector(quit(_:)), keyEquivalent: "q").target = self
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if popover.contentViewController == nil {
                popover.contentViewController = popoverContent.value
            }
            // Keep the card below the menu bar instead of covering it.
            let anchor = button.bounds.insetBy(dx: 0, dy: -2)
            popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window, let screen = window.screen ?? NSScreen.main {
                var frame = window.frame
                let menuBarClearance: CGFloat = 28
                let maxY = screen.visibleFrame.maxY - menuBarClearance
                if frame.maxY > maxY {
                    frame.origin.y -= (frame.maxY - maxY)
                    window.setFrame(frame, display: true)
                }
            }
        }
    }

    private func showMenu() {
        applyLanguage()
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
}

enum UserGuide {
    static func remoteURL(language: AppLanguage) -> URL {
        language == .simplifiedChinese
            ? URL(string: "https://github.com/ASAzhangyongchao/quota-pet/blob/main/docs/USER_GUIDE.zh-CN.md")!
            : URL(string: "https://github.com/ASAzhangyongchao/quota-pet/blob/main/docs/USER_GUIDE.md")!
    }

    static func open(language: AppLanguage) {
        let fileName = language == .simplifiedChinese ? "USER_GUIDE.zh-CN.md" : "USER_GUIDE.md"
        let resourceName = language == .simplifiedChinese ? "USER_GUIDE.zh-CN" : "USER_GUIDE"
        let candidates = [
            Bundle.main.url(forResource: resourceName, withExtension: "md"),
            Bundle.main.url(forResource: resourceName, withExtension: "md", subdirectory: "docs"),
            Bundle.main.resourceURL?.appendingPathComponent("docs/\(fileName)"),
        ].compactMap { $0 }
        if let local = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(local)
            return
        }
        NSWorkspace.shared.open(remoteURL(language: language))
    }
}
