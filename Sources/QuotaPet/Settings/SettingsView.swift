import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let hosting: NSHostingController<SettingsView>
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: Preferences,
        candidates: [ExecutableResolution],
        onConfirm: @escaping (ExecutableCandidate) -> Void,
        onRegisterHotKey: @escaping () -> Void,
        onSetLaunchAtLogin: @escaping (Bool) -> Void
    ) {
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
        window.setContentSize(NSSize(width: 560, height: 560))
        window.minSize = NSSize(width: 520, height: 360)
        super.init(window: window)
        preferences.$languagePreference.sink { [weak self, weak preferences] _ in
            guard let self, let preferences else { return }
            self.window?.title = L10n.text(.settingsTitle, language: preferences.resolvedLanguage)
            self.hosting.rootView = SettingsView(
                preferences: preferences,
                candidates: candidates,
                onConfirm: onConfirm,
                onRegisterHotKey: onRegisterHotKey,
                onSetLaunchAtLogin: onSetLaunchAtLogin
            )
        }.store(in: &cancellables)
    }

    required init?(coder: NSCoder) { nil }
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    static let previewLimit = 3

    /// Prefers actionable / trusted rows for the compact Settings preview.
    static func preview(from candidates: [ExecutableResolution], limit: Int = previewLimit) -> [ExecutableResolution] {
        guard candidates.count > limit else { return candidates }
        var selected: [ExecutableResolution] = []
        var used = Set<Int>()

        func take(where predicate: (ExecutableResolution) -> Bool) {
            for (index, candidate) in candidates.enumerated() where !used.contains(index) && predicate(candidate) {
                selected.append(candidate)
                used.insert(index)
                if selected.count == limit { return }
            }
        }

        take { $0.requiresConfirmation }
        take { $0.candidate != nil }
        take { _ in true }
        return selected
    }
}

private struct CodexTrustSettingsSection: View {
    let language: AppLanguage
    let candidates: [ExecutableResolution]
    let onConfirm: (ExecutableCandidate) -> Void
    @State private var showingAll = false

    private var preview: [ExecutableResolution] {
        CodexTrustListPresentation.preview(from: candidates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(preview.enumerated()), id: \.offset) { _, resolution in
                CodexTrustResolutionRow(language: language, resolution: resolution, onConfirm: onConfirm)
            }

            if candidates.count > CodexTrustListPresentation.previewLimit {
                Button(L10n.text(.settingsTrustMore, language: language, arguments: [candidates.count])) {
                    showingAll = true
                }
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
    }
}

private struct CodexTrustAllCandidatesSheet: View {
    let language: AppLanguage
    let candidates: [ExecutableResolution]
    let onConfirm: (ExecutableCandidate) -> Void
    let onClose: () -> Void

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
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, resolution in
                        CodexTrustResolutionRow(language: language, resolution: resolution, onConfirm: onConfirm)
                        Divider()
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 360, idealHeight: 480)
    }
}

private struct CodexTrustResolutionRow: View {
    let language: AppLanguage
    let resolution: ExecutableResolution
    let onConfirm: (ExecutableCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let candidate = resolution.candidate {
                Text(candidate.inputURL.path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    L10n.text(
                        .settingsCandidateDetails,
                        language: language,
                        arguments: [
                            candidate.ownerUID,
                            String(candidate.mode, radix: 8),
                            candidate.signingIdentifier ?? L10n.text(.settingsNone, language: language),
                            candidate.teamIdentifier ?? L10n.text(.settingsNone, language: language),
                            String(candidate.codeHash.prefix(12)),
                        ]
                    )
                )
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
                if resolution.requiresConfirmation {
                    Text(L10n.text(.settingsReviewTrust, language: language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.text(.settingsConfirmTrust, language: language)) { onConfirm(candidate) }
                } else {
                    Text(L10n.text(.settingsTrusted, language: language)).font(.caption).foregroundStyle(.green)
                }
            } else if case let .rejected(error) = resolution {
                Text(L10n.text(.settingsRejected, language: language, arguments: [error.localizedMessage(language: language)]))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        statusMessage = L10n.text(.settingsCheckingForUpdates, language: language)
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
