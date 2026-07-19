import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(preferences: Preferences, candidates: [ExecutableResolution], onConfirm: @escaping (ExecutableCandidate) -> Void, onRegisterHotKey: @escaping () -> Void, onSetLaunchAtLogin: @escaping (Bool) -> Void) {
        let view = SettingsView(preferences: preferences, candidates: candidates, onConfirm: onConfirm, onRegisterHotKey: onRegisterHotKey, onSetLaunchAtLogin: onSetLaunchAtLogin)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "QuotaPet 设置"
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
            Toggle("显示桌宠", isOn: $preferences.petVisible)
            Toggle("始终置顶", isOn: $preferences.alwaysOnTop)
            Toggle("鼠标穿透", isOn: $preferences.ignoresMouseEvents)
            VStack(alignment: .leading, spacing: 4) {
                Picker("连接模式", selection: $preferences.connectionMode) { Text("实时").tag(ConnectionMode.realtime); Text("节能").tag(ConnectionMode.energySaver) }.pickerStyle(.segmented)
                Text("新安装默认节能；需要持续更新时可手动切换到实时。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack { Text("快捷键：⌥⌘U"); if let message = preferences.hotKeyStatusMessage { Text(message).foregroundStyle(.red) } }
            Button("恢复默认⌥⌘U并重新注册") { preferences.hotKey = .optionCommandU; onRegisterHotKey() }
            Toggle("本地用量通知", isOn: $preferences.notificationsEnabled)
            Toggle("登录时启动", isOn: Binding(
                get: { preferences.launchAtLoginEnabled },
                set: onSetLaunchAtLogin
            ))
            if let message = preferences.launchAtLoginErrorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            Section("Codex 信任") {
                ForEach(Array(candidates.enumerated()), id: \.offset) { _, resolution in
                    VStack(alignment: .leading) {
                        if let candidate = resolution.candidate {
                            Text(candidate.inputURL.path).font(.caption)
                            Text("owner \(candidate.ownerUID) · mode \(String(candidate.mode, radix: 8)) · signing \(candidate.signingIdentifier ?? "无") · team \(candidate.teamIdentifier ?? "无") · hash \(candidate.codeHash.prefix(12))").font(.caption2)
                            if resolution.requiresConfirmation {
                                Text("请核对路径和签名后再授权执行。").font(.caption2).foregroundStyle(.secondary)
                                Button("我已核对路径和签名，确认并启用") { onConfirm(candidate) }
                            } else { Text("已信任").font(.caption).foregroundStyle(.green) }
                        } else if case let .rejected(error) = resolution { Text("已拒绝：\(String(describing: error))").font(.caption).foregroundStyle(.red) }
                    }
                }
            }
        }.padding()
    }
}
