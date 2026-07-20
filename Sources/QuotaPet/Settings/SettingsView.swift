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
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, resolution in
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

                Section(L10n.text(.settingsAboutLegal, language: language)) {
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
        HStack(alignment: .center, spacing: 8) {
            Text(title)
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .help(L10n.text(help, language: language))
                .accessibilityLabel(L10n.text(help, language: language))
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
    }
}
