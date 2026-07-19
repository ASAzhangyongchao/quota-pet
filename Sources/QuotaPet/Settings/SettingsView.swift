import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(preferences: Preferences, candidates: [ExecutableResolution], onConfirm: @escaping (ExecutableCandidate) -> Void, onRegisterHotKey: @escaping () -> Void, onSetLaunchAtLogin: @escaping (Bool) -> Void) {
        let view = SettingsView(preferences: preferences, candidates: candidates, onConfirm: onConfirm, onRegisterHotKey: onRegisterHotKey, onSetLaunchAtLogin: onSetLaunchAtLogin)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.text(.settingsTitle)
        window.setContentSize(NSSize(width: 420, height: 370))
        super.init(window: window)
    }
    required init?(coder: NSCoder) { nil }
    func show() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}

private struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let candidates: [ExecutableResolution]
    let onConfirm: (ExecutableCandidate) -> Void
    let onRegisterHotKey: () -> Void
    let onSetLaunchAtLogin: (Bool) -> Void
    var body: some View {
        Form {
            Toggle(L10n.text(.settingsShowPet), isOn: $preferences.petVisible)
            Toggle(L10n.text(.settingsAlwaysOnTop), isOn: $preferences.alwaysOnTop)
            Toggle(L10n.text(.settingsMousePassthrough), isOn: $preferences.ignoresMouseEvents)
            VStack(alignment: .leading, spacing: 4) {
                Picker(L10n.text(.settingsConnectionMode), selection: $preferences.connectionMode) { Text(L10n.text(.settingsRealtime)).tag(ConnectionMode.realtime); Text(L10n.text(.settingsEnergySaver)).tag(ConnectionMode.energySaver) }.pickerStyle(.segmented)
                Text(L10n.text(.settingsModeHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack { Text(L10n.text(.settingsShortcut)); if let message = preferences.hotKeyStatusMessage { Text(message).foregroundStyle(.red) } }
            Button(L10n.text(.settingsResetShortcut)) { preferences.hotKey = .optionCommandU; onRegisterHotKey() }
            Toggle(L10n.text(.settingsNotifications), isOn: $preferences.notificationsEnabled)
            Toggle(L10n.text(.settingsLaunchAtLogin), isOn: Binding(
                get: { preferences.launchAtLoginEnabled },
                set: onSetLaunchAtLogin
            ))
            if let message = preferences.launchAtLoginErrorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            Section(L10n.text(.settingsCodexTrust)) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { _, resolution in
                    VStack(alignment: .leading) {
                        if let candidate = resolution.candidate {
                            Text(candidate.inputURL.path).font(.caption)
                            Text(L10n.text(.settingsCandidateDetails, arguments: [candidate.ownerUID, String(candidate.mode, radix: 8), candidate.signingIdentifier ?? L10n.text(.settingsNone), candidate.teamIdentifier ?? L10n.text(.settingsNone), String(candidate.codeHash.prefix(12))])).font(.caption2)
                            if resolution.requiresConfirmation {
                                Text(L10n.text(.settingsReviewTrust)).font(.caption2).foregroundStyle(.secondary)
                                Button(L10n.text(.settingsConfirmTrust)) { onConfirm(candidate) }
                            } else { Text(L10n.text(.settingsTrusted)).font(.caption).foregroundStyle(.green) }
                        } else if case let .rejected(error) = resolution { Text(L10n.text(.settingsRejected, arguments: [error.localizedMessage()])).font(.caption).foregroundStyle(.red) }
                    }
                }
            }
        }.padding()
    }
}
