import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let hosting: NSHostingController<SettingsView>
    private let preferences: Preferences
    private let onPreferChannel: (PreferredCodexChannel) -> Void
    private let onRescan: () -> Void
    private let onPickTerminalCodex: () -> Void
    private let onRegisterHotKey: () -> Void
    private let onSetLaunchAtLogin: (Bool) -> Void
    private var latestCandidates: [ExecutableResolution]
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: Preferences,
        candidates: [ExecutableResolution],
        onPreferChannel: @escaping (PreferredCodexChannel) -> Void,
        onRescan: @escaping () -> Void,
        onPickTerminalCodex: @escaping () -> Void,
        onRegisterHotKey: @escaping () -> Void,
        onSetLaunchAtLogin: @escaping (Bool) -> Void
    ) {
        self.preferences = preferences
        self.onPreferChannel = onPreferChannel
        self.onRescan = onRescan
        self.onPickTerminalCodex = onPickTerminalCodex
        self.onRegisterHotKey = onRegisterHotKey
        self.onSetLaunchAtLogin = onSetLaunchAtLogin
        latestCandidates = candidates
        let view = SettingsView(
            preferences: preferences,
            candidates: candidates,
            onPreferChannel: onPreferChannel,
            onRescan: onRescan,
            onPickTerminalCodex: onPickTerminalCodex,
            onRegisterHotKey: onRegisterHotKey,
            onSetLaunchAtLogin: onSetLaunchAtLogin
        )
        hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.text(.settingsTitle, language: preferences.resolvedLanguage)
        window.styleMask.insert(.resizable)
        window.setContentSize(NSSize(width: 560, height: 640))
        window.minSize = NSSize(width: 520, height: 420)
        super.init(window: window)
        preferences.$languagePreference.sink { [weak self] _ in
            guard let self else { return }
            self.reload(candidates: self.latestCandidates)
        }.store(in: &cancellables)
    }

    required init?(coder: NSCoder) { nil }

    func show(candidates: [ExecutableResolution]? = nil) {
        if let candidates {
            reload(candidates: candidates)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reload(candidates: [ExecutableResolution]) {
        latestCandidates = candidates
        window?.title = L10n.text(.settingsTitle, language: preferences.resolvedLanguage)
        hosting.rootView = SettingsView(
            preferences: preferences,
            candidates: candidates,
            onPreferChannel: onPreferChannel,
            onRescan: onRescan,
            onPickTerminalCodex: onPickTerminalCodex,
            onRegisterHotKey: onRegisterHotKey,
            onSetLaunchAtLogin: onSetLaunchAtLogin
        )
    }
}

private struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let candidates: [ExecutableResolution]
    let onPreferChannel: (PreferredCodexChannel) -> Void
    let onRescan: () -> Void
    let onPickTerminalCodex: () -> Void
    let onRegisterHotKey: () -> Void
    let onSetLaunchAtLogin: (Bool) -> Void

    private var language: AppLanguage { preferences.resolvedLanguage }

    var body: some View {
        ScrollView {
            Form {
                Section(L10n.text(.settingsSectionAppearance, language: language)) {
                    helpToggle(L10n.text(.settingsShowPet, language: language), help: .settingsShowPetHelp, isOn: $preferences.petVisible)
                    helpToggle(L10n.text(.settingsAlwaysOnTop, language: language), help: .settingsAlwaysOnTopHelp, isOn: $preferences.alwaysOnTop)
                    helpToggle(L10n.text(.settingsMousePassthrough, language: language), help: .settingsMousePassthroughHelp, isOn: $preferences.ignoresMouseEvents)
                }

                Section(L10n.text(.settingsSectionConnection, language: language)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text(.settingsConnectionMode, language: language))
                            .font(.body)
                        Picker("", selection: $preferences.connectionMode) {
                            Text(L10n.text(.settingsRealtime, language: language)).tag(ConnectionMode.realtime)
                            Text(L10n.text(.settingsEnergySaver, language: language)).tag(ConnectionMode.energySaver)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        Text(L10n.text(.settingsModeHelp, language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text(L10n.text(.settingsShortcut, language: language))
                        if let message = preferences.hotKeyStatusMessage {
                            Text(message).foregroundStyle(.red)
                        }
                    }
                    Button(L10n.text(.settingsResetShortcut, language: language)) {
                        preferences.hotKey = .optionCommandU
                        onRegisterHotKey()
                    }
                }

                Section(L10n.text(.settingsSectionNotifications, language: language)) {
                    helpToggle(L10n.text(.settingsNotifications, language: language), help: .settingsNotificationsHelp, isOn: $preferences.notificationsEnabled)
                    helpToggle(
                        L10n.text(.settingsLaunchAtLogin, language: language),
                        help: .settingsLaunchAtLoginHelp,
                        isOn: Binding(
                            get: { preferences.launchAtLoginEnabled },
                            set: onSetLaunchAtLogin
                        )
                    )
                    if let message = preferences.launchAtLoginErrorMessage {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }

                Section(L10n.text(.settingsSectionLanguage, language: language)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text(.settingsLanguage, language: language))
                            .font(.body)
                        Picker("", selection: $preferences.languagePreference) {
                            Text(L10n.text(.settingsLanguageSystem, language: language)).tag(LanguagePreference.system)
                            Text(L10n.text(.settingsLanguageChinese, language: language)).tag(LanguagePreference.simplifiedChinese)
                            Text(L10n.text(.settingsLanguageEnglish, language: language)).tag(LanguagePreference.english)
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                    }
                }

                Section(L10n.text(.settingsCodexTrust, language: language)) {
                    CodexChannelSettingsSection(
                        language: language,
                        preferredChannel: preferences.preferredCodexChannel,
                        candidates: candidates,
                        onPreferChannel: onPreferChannel,
                        onRescan: onRescan,
                        onPickTerminalCodex: onPickTerminalCodex
                    )
                }

                Section(L10n.text(.settingsAboutLegal, language: language)) {
                    UpdateCheckSettingsSection(language: language)
                    Text(L10n.text(.settingsUnofficialNotice, language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text(.settingsMarksNotice, language: language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
    }

    @ViewBuilder
    private func helpToggle(_ title: String, help: L10n.Key, isOn: Binding<Bool>) -> some View {
        HelpToggleRow(
            title: title,
            helpText: L10n.text(help, language: language),
            isOn: isOn
        )
    }
}

private struct HelpToggleRow: View {
    let title: String
    let helpText: String
    @Binding var isOn: Bool
    @State private var showingHelp = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
            Button {
                showingHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                Text(helpText)
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: 280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityLabel(helpText)
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
    }
}

enum CodexChannelPresentation {
    enum CardStatus: Equatable {
        case missing
        case pending
        case ready
        case active
    }

    struct Card: Equatable {
        let channel: PreferredCodexChannel
        let status: CardStatus
        let path: String?
        let candidate: ExecutableCandidate?
    }

    struct Model: Equatable {
        let activeChannel: PreferredCodexChannel?
        let chatGPT: Card
        let terminal: Card
        let rejectedCount: Int
    }

    static func model(
        from resolutions: [ExecutableResolution],
        preferredChannel: PreferredCodexChannel
    ) -> Model {
        let trusted = TrustedCodexSelection.trustedCandidates(
            from: resolutions,
            preferredChannel: preferredChannel
        )
        let activePath = trusted.first?.canonicalURL.path
        let activeChannel = trusted.first.map { PreferredCodexChannel.channel(for: $0.source) }

        func best(for channel: PreferredCodexChannel) -> (ExecutableCandidate, ExecutableTrust)? {
            var pending: (ExecutableCandidate, ExecutableTrust)?
            for resolution in resolutions {
                guard case let .accepted(candidate, trust) = resolution else { continue }
                guard PreferredCodexChannel.channel(for: candidate.source) == channel else { continue }
                if trust == .bundleAllowList || trust == .confirmed {
                    return (candidate, trust)
                }
                if pending == nil {
                    pending = (candidate, trust)
                }
            }
            return pending
        }

        func card(for channel: PreferredCodexChannel) -> Card {
            guard let best = best(for: channel) else {
                return Card(channel: channel, status: .missing, path: nil, candidate: nil)
            }
            let isActive = best.0.canonicalURL.path == activePath
            let status: CardStatus
            if best.1 == .requiresConfirmation {
                status = .pending
            } else if isActive {
                status = .active
            } else {
                status = .ready
            }
            return Card(
                channel: channel,
                status: status,
                path: best.0.canonicalURL.path,
                candidate: best.0
            )
        }

        let rejectedCount = resolutions.reduce(into: 0) { count, resolution in
            if case .rejected = resolution { count += 1 }
        }

        return Model(
            activeChannel: activeChannel,
            chatGPT: card(for: .chatGPT),
            terminal: card(for: .terminal),
            rejectedCount: rejectedCount
        )
    }
}

private struct CodexChannelSettingsSection: View {
    let language: AppLanguage
    let preferredChannel: PreferredCodexChannel
    let candidates: [ExecutableResolution]
    let onPreferChannel: (PreferredCodexChannel) -> Void
    let onRescan: () -> Void
    let onPickTerminalCodex: () -> Void

    private var model: CodexChannelPresentation.Model {
        CodexChannelPresentation.model(from: candidates, preferredChannel: preferredChannel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(.settingsCodexTrustHelp, language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(summaryText)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            CodexChannelCardView(
                language: language,
                card: model.chatGPT,
                title: L10n.text(.settingsCodexChannelChatGPTTitle, language: language),
                missingText: L10n.text(.settingsCodexChannelChatGPTMissing, language: language),
                onUse: { onPreferChannel(.chatGPT) },
                onRescan: onRescan,
                showsPickFile: false,
                onPickFile: nil,
                tip: nil
            )

            CodexChannelCardView(
                language: language,
                card: model.terminal,
                title: L10n.text(.settingsCodexChannelTerminalTitle, language: language),
                missingText: L10n.text(.settingsCodexChannelTerminalMissing, language: language),
                onUse: { onPreferChannel(.terminal) },
                onRescan: onRescan,
                showsPickFile: true,
                onPickFile: onPickTerminalCodex,
                tip: L10n.text(.settingsCodexChannelTerminalTip, language: language)
            )

            if model.rejectedCount > 0 {
                Text(L10n.text(.settingsTrustIgnoredNoise, language: language, arguments: [model.rejectedCount]))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryText: String {
        switch model.activeChannel {
        case .chatGPT:
            L10n.text(.settingsCodexListeningChatGPT, language: language)
        case .terminal:
            L10n.text(.settingsCodexListeningTerminal, language: language)
        case nil:
            L10n.text(.settingsCodexListeningNone, language: language)
        }
    }
}

private struct CodexChannelCardView: View {
    let language: AppLanguage
    let card: CodexChannelPresentation.Card
    let title: String
    let missingText: String
    let onUse: () -> Void
    let onRescan: () -> Void
    let showsPickFile: Bool
    let onPickFile: (() -> Void)?
    let tip: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Text(statusTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }

            if let path = card.path {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(missingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tip {
                Text(tip)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(L10n.text(.settingsCodexUseThis, language: language), action: onUse)
                    .disabled(card.status == .missing || card.status == .active)
                Button(L10n.text(.settingsCodexRescan, language: language), action: onRescan)
                if showsPickFile, let onPickFile {
                    Button(L10n.text(.settingsCodexPickFile, language: language), action: onPickFile)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var statusTitle: String {
        switch card.status {
        case .missing: L10n.text(.settingsCodexStatusMissing, language: language)
        case .pending: L10n.text(.settingsCodexStatusPending, language: language)
        case .ready: L10n.text(.settingsCodexStatusReady, language: language)
        case .active: L10n.text(.settingsCodexStatusActive, language: language)
        }
    }

    private var statusColor: Color {
        switch card.status {
        case .missing: .secondary
        case .pending: .orange
        case .ready: .blue
        case .active: .green
        }
    }
}

private struct UpdateCheckSettingsSection: View {
    let language: AppLanguage
    private let versionInfo = AppVersionInfo.fromBundle()
    @State private var isChecking = false
    @State private var statusMessage: String?
    @State private var downloadURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(.settingsCurrentVersion, language: language, arguments: [versionInfo.displayLabel]))
                .font(.body)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button(isChecking
                    ? L10n.text(.settingsCheckingForUpdates, language: language)
                    : L10n.text(.settingsCheckForUpdates, language: language)
                ) {
                    Task { await checkForUpdates() }
                }
                .disabled(isChecking)

                if let downloadURL {
                    Button(L10n.text(.settingsOpenDownloadPage, language: language)) {
                        NSWorkspace.shared.open(downloadURL)
                    }
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func checkForUpdates() async {
        isChecking = true
        downloadURL = nil
        statusMessage = nil
        let outcome = await UpdateCheckService(currentMarketingVersion: versionInfo.marketing).check()
        isChecking = false
        switch outcome {
        case .upToDate:
            downloadURL = nil
            statusMessage = L10n.text(.settingsUpdateUpToDate, language: language)
        case let .updateAvailable(version, releaseURL):
            downloadURL = releaseURL
            statusMessage = L10n.text(
                .settingsUpdateAvailable,
                language: language,
                arguments: [version.displayString]
            )
        case .noPublicRelease:
            downloadURL = nil
            statusMessage = L10n.text(.settingsUpdateNoRelease, language: language)
        case .failed:
            downloadURL = nil
            statusMessage = L10n.text(.settingsUpdateFailed, language: language)
        }
    }
}
