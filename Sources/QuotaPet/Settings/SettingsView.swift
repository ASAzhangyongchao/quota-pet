import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(preferences: Preferences, candidates: @escaping () -> [ExecutableResolution], onConfirm: @escaping (ExecutableCandidate) -> Void, onRegisterHotKey: @escaping () -> Void) {
        let view = SettingsView(preferences: preferences, candidates: candidates, onConfirm: onConfirm, onRegisterHotKey: onRegisterHotKey)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "QuotaPet 设置"
        window.setContentSize(NSSize(width: 420, height: 330))
        super.init(window: window)
    }
    required init?(coder: NSCoder) { nil }
    func show() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}

private struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let candidates: () -> [ExecutableResolution]
    let onConfirm: (ExecutableCandidate) -> Void
    let onRegisterHotKey: () -> Void
    var body: some View {
        Form {
            Toggle("显示桌宠", isOn: $preferences.petVisible)
            Toggle("始终置顶", isOn: $preferences.alwaysOnTop)
            Toggle("鼠标穿透", isOn: $preferences.ignoresMouseEvents)
            Picker("连接模式", selection: $preferences.connectionMode) { Text("实时").tag(ConnectionMode.realtime); Text("节能").tag(ConnectionMode.energySaver) }.pickerStyle(.segmented)
            HStack { Text("快捷键：⌥⌘U"); if let message = preferences.hotKeyStatusMessage { Text(message).foregroundStyle(.red) } }
            Button("恢复默认⌥⌘U并重新注册") { preferences.hotKey = .optionCommandU; onRegisterHotKey() }
            Toggle("通知（仅保存，尚不请求权限）", isOn: $preferences.notificationsEnabled)
            Section("Codex 信任") {
                ForEach(Array(candidates().enumerated()), id: \.offset) { _, resolution in
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
