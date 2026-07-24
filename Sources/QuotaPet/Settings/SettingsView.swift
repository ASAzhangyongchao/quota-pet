import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let hosting: NSHostingController<SettingsView>
    private let preferences: Preferences
    private let onConfirm: (ExecutableCandidate) -> Void
    private let onRegisterHotKey: () -> Void
    private let onSetLaunchAtLogin: (Bool) -> Void
    private var latestCandidates: [ExecutableResolution]
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: Preferences,
        candidates: [ExecutableResolution],
        onConfirm: @escaping (ExecutableCandidate) -> Void,
        onRegisterHotKey: @escaping () -> Void,
        onSetLaunchAtLogin: @escaping (Bool) -> Void
    ) {
        self.preferences = preferences
        self.onConfirm = onConfirm
        self.onRegisterHotKey = onRegisterHotKey
        self.onSetLaunchAtLogin = onSetLaunchAtLogin
        latestCandidates = candidates
        let view = SettingsView(
            preferences: preferences,
            candidates: candidates,
            onConfirm: onConfirm,
            onRegisterHotKey: onRegisterHotKey,
            onSetLaunchAtLogin: onSetLaunchAtLogin
        )
        hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.text(.settingsTitle, language: preferences.resolvedLanguage)
        window.styleMask.insert(.resizable)
        window.setContentSize(NSSize(width: 560, height: 620))
        window.minSize = NSSize(width: 520, height: 400)
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
            onConfirm: onConfirm,
            onRegisterHotKey: onRegisterHotKey,
            onSetLaunchAtLogin: onSetLaunchAtLogin
        )
    }
}

private struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let candidates: [ExecutableResolution]
    let onConfirm: (ExecutableCandidate) -> Void
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
                    CodexTrustSettingsSection(
                        language: language,
                        candidates: candidates,
                        onConfirm: onConfirm
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

enum CodexTrustListPresentation {
    enum Badge: Equatable {
        case primary
        case trustedBackup
        case pending
    }

    struct AcceptedItem: Equatable {
        let resolution: ExecutableResolution
        let candidate: ExecutableCandidate
        let badge: Badge
    }

    struct Model: Equatable {
        let primary: AcceptedItem?
        let alternatives: [AcceptedItem]
        let rejectedCount: Int
        let rejected: [ExecutableResolution]
    }

    static func model(from resolutions: [ExecutableResolution]) -> Model {
        let trusted = TrustedCodexSelection.trustedCandidates(from: resolutions)
        let primaryPath = trusted.first?.canonicalURL.path
        var primary: AcceptedItem?
        var alternatives: [AcceptedItem] = []
        var rejected: [ExecutableResolution] = []

        for resolution in resolutions {
            switch resolution {
            case let .accepted(candidate, trust):
                let badge: Badge
                if trust == .requiresConfirmation {
                    badge = .pending
                } else if candidate.canonicalURL.path == primaryPath, primary == nil {
                    badge = .primary
                } else {
                    badge = .trustedBackup
                }
                let item = AcceptedItem(resolution: resolution, candidate: candidate, badge: badge)
                if badge == .primary {
                    primary = item
                } else {
                    alternatives.append(item)
                }
            case .rejected:
                rejected.append(resolution)
            }
        }

        return Model(primary: primary, alternatives: alternatives, rejectedCount: rejected.count, rejected: rejected)
    }

    static func sourceTitle(_ source: ExecutableCandidate.Source, language: AppLanguage) -> String {
        switch source {
        case .chatGPTBundle: L10n.text(.settingsCodexSourceChatGPT, language: language)
        case .codexBundle: L10n.text(.settingsCodexSourceCodexApp, language: language)
        case .homeChatGPTBundle: L10n.text(.settingsCodexSourceHomeChatGPT, language: language)
        case .homeCodexBundle: L10n.text(.settingsCodexSourceHomeCodex, language: language)
        case .homebrew: L10n.text(.settingsCodexSourceHomebrew, language: language)
        case .local: L10n.text(.settingsCodexSourceLocal, language: language)
        case .path: L10n.text(.settingsCodexSourcePath, language: language)
        case .userSelected: L10n.text(.settingsCodexSourceUser, language: language)
        }
    }

    static func badgeTitle(_ badge: Badge, language: AppLanguage) -> String {
        switch badge {
        case .primary: L10n.text(.settingsCodexBadgePrimary, language: language)
        case .trustedBackup: L10n.text(.settingsCodexBadgeTrusted, language: language)
        case .pending: L10n.text(.settingsCodexBadgePending, language: language)
        }
    }
}

private struct CodexTrustSettingsSection: View {
    let language: AppLanguage
    let candidates: [ExecutableResolution]
    let onConfirm: (ExecutableCandidate) -> Void
    @State private var showingAll = false
    @State private var showingNoise = false

    private var model: CodexTrustListPresentation.Model {
        CodexTrustListPresentation.model(from: candidates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(.settingsCodexTrustHelp, language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let primary = model.primary {
                Text(L10n.text(.settingsCodexTrustCurrent, language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                CodexTrustAcceptedRow(language: language, item: primary, onConfirm: onConfirm)
            } else {
                Text(L10n.text(.settingsCodexTrustNoneTrusted, language: language))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.alternatives.isEmpty {
                Text(L10n.text(.settingsCodexTrustAlternatives, language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(model.alternatives.enumerated()), id: \.offset) { _, item in
                    CodexTrustAcceptedRow(language: language, item: item, onConfirm: onConfirm)
                }
            }

            if model.rejectedCount > 0 {
                Text(L10n.text(.settingsTrustIgnoredNoise, language: language, arguments: [model.rejectedCount]))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.text(.settingsTrustShowNoise, language: language)) {
                    showingNoise = true
                }
                .font(.caption)
            }

            if candidates.count > 4 {
                Button(L10n.text(.settingsTrustMore, language: language, arguments: [candidates.count])) {
                    showingAll = true
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingAll) {
            CodexTrustAllCandidatesSheet(
                language: language,
                candidates: candidates,
                onConfirm: onConfirm,
                onClose: { showingAll = false }
            )
        }
        .sheet(isPresented: $showingNoise) {
            CodexTrustNoiseSheet(
                language: language,
                rejected: model.rejected,
                onClose: { showingNoise = false }
            )
        }
    }
}

private struct CodexTrustAllCandidatesSheet: View {
    let language: AppLanguage
    let candidates: [ExecutableResolution]
    let onConfirm: (ExecutableCandidate) -> Void
    let onClose: () -> Void

    private var model: CodexTrustListPresentation.Model {
        CodexTrustListPresentation.model(from: candidates)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text(.settingsTrustAllTitle, language: language))
                    .font(.headline)
                Spacer()
                Button(L10n.text(.settingsTrustClose, language: language), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let primary = model.primary {
                        sectionTitle(L10n.text(.settingsCodexTrustCurrent, language: language))
                        CodexTrustAcceptedRow(language: language, item: primary, onConfirm: onConfirm)
                    }
                    if !model.alternatives.isEmpty {
                        sectionTitle(L10n.text(.settingsCodexTrustAlternatives, language: language))
                        ForEach(Array(model.alternatives.enumerated()), id: \.offset) { _, item in
                            CodexTrustAcceptedRow(language: language, item: item, onConfirm: onConfirm)
                        }
                    }
                    if !model.rejected.isEmpty {
                        sectionTitle(L10n.text(.settingsTrustShowNoise, language: language))
                        ForEach(Array(model.rejected.enumerated()), id: \.offset) { _, resolution in
                            CodexTrustRejectedRow(language: language, resolution: resolution)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 360, idealHeight: 480)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct CodexTrustNoiseSheet: View {
    let language: AppLanguage
    let rejected: [ExecutableResolution]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text(.settingsTrustShowNoise, language: language))
                    .font(.headline)
                Spacer()
                Button(L10n.text(.settingsTrustClose, language: language), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rejected.enumerated()), id: \.offset) { _, resolution in
                        CodexTrustRejectedRow(language: language, resolution: resolution)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 280, idealHeight: 360)
    }
}

private struct CodexTrustAcceptedRow: View {
    let language: AppLanguage
    let item: CodexTrustListPresentation.AcceptedItem
    let onConfirm: (ExecutableCandidate) -> Void
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CodexTrustListPresentation.sourceTitle(item.candidate.source, language: language))
                    .font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Text(CodexTrustListPresentation.badgeTitle(item.badge, language: language))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.12), in: Capsule())
            }

            Text(item.candidate.canonicalURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if item.badge == .pending {
                Text(L10n.text(.settingsReviewTrust, language: language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.text(.settingsConfirmTrust, language: language)) {
                    onConfirm(item.candidate)
                }
            }

            DisclosureGroup(L10n.text(.settingsTrustShowDetails, language: language), isExpanded: $showDetails) {
                Text(
                    L10n.text(
                        .settingsCandidateDetails,
                        language: language,
                        arguments: [
                            item.candidate.ownerUID,
                            String(item.candidate.mode, radix: 8),
                            item.candidate.signingIdentifier ?? L10n.text(.settingsNone, language: language),
                            item.candidate.teamIdentifier ?? L10n.text(.settingsNone, language: language),
                            String(item.candidate.codeHash.prefix(12)),
                        ]
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var badgeColor: Color {
        switch item.badge {
        case .primary: .green
        case .trustedBackup: .blue
        case .pending: .orange
        }
    }
}

private struct CodexTrustRejectedRow: View {
    let language: AppLanguage
    let resolution: ExecutableResolution

    var body: some View {
        if case let .rejected(error) = resolution {
            Text(L10n.text(.settingsRejected, language: language, arguments: [error.localizedMessage(language: language)]))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        // Checking state lives on the button only — avoid duplicating "正在检查…" underneath.
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
