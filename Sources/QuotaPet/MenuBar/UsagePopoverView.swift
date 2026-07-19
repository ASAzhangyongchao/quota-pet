import SwiftUI

@MainActor
final class UsageDetailsViewModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot
    @Published private(set) var presentation: UsageDetailsPresentation
    private(set) var updateCount = 0
    init(snapshot: QuotaSnapshot) { self.snapshot = snapshot; presentation = UsageDetailsPresentation(snapshot: snapshot) }
    func update(_ snapshot: QuotaSnapshot) { self.snapshot = snapshot; presentation = UsageDetailsPresentation(snapshot: snapshot); updateCount += 1 }
}

struct UsageDetailsPresentation: Equatable {
    struct Window: Equatable { let name: String; let usedText: String; let remainingText: String; let durationText: String; let resetText: String; let countdownText: String }
    let primaryText: String
    let windows: [Window]
    let updatedText: String
    let statusText: String

    init(snapshot: QuotaSnapshot, now: Date = .now, calendar: Calendar = .current) {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy/M/d HH:mm zzz"
        let primary = snapshot.primary
        primaryText = primary.map { "剩余 \(Int($0.remainingPercent.rounded()))% · 已用 \(Int($0.usedPercent.rounded()))%" } ?? "用量暂不可用"
        windows = snapshot.windows.map { window in
            let reset = window.resetsAt.map(formatter.string(from:)) ?? "未提供"
            let countdown: String
            if let date = window.resetsAt { countdown = Self.countdown(until: date, now: now, calendar: calendar) } else { countdown = "未提供" }
            let duration = window.windowDurationMinutes.map { $0 % 60 == 0 ? "\($0 / 60)小时" : "\($0)分钟" } ?? "未提供"
            return Window(name: window.displayName, usedText: "已用 \(Int(window.usedPercent.rounded()))%", remainingText: "剩余 \(Int(window.remainingPercent.rounded()))%", durationText: duration, resetText: reset, countdownText: countdown)
        }
        updatedText = "更新于 \(formatter.string(from: snapshot.updatedAt))"
        switch snapshot.state { case .ready: statusText = "数据正常"; case .loading: statusText = "正在加载"; case let .stale(message): statusText = "数据已过期：\(message)"; case let .unavailable(message), let .incompatible(message): statusText = message }
    }

    private static func countdown(until date: Date, now: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: now, to: date)
        if let hour = components.hour, hour > 0 { return "距重置 \(hour)小时" }
        return "距重置 \(max(components.minute ?? 0, 0))分钟"
    }
}

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageDetailsViewModel
    var onPetTap: (() -> Void)? = nil
    let onRefresh: () -> Void
    init(snapshot: QuotaSnapshot, onPetTap: (() -> Void)? = nil, onRefresh: @escaping () -> Void) { viewModel = UsageDetailsViewModel(snapshot: snapshot); self.onPetTap = onPetTap; self.onRefresh = onRefresh }
    init(viewModel: UsageDetailsViewModel, onPetTap: (() -> Void)? = nil, onRefresh: @escaping () -> Void) { self.viewModel = viewModel; self.onPetTap = onPetTap; self.onRefresh = onRefresh }
    var body: some View {
        let presentation = viewModel.presentation
        VStack(alignment: .leading, spacing: 8) {
            if let onPetTap {
                Button(action: onPetTap) { VectorPetView(renderState: PetRenderState(snapshot: viewModel.snapshot), size: 36) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("收起用量详情")
            }
            Text(presentation.primaryText).font(.headline)
            ForEach(Array(presentation.windows.enumerated()), id: \.offset) { _, window in
                VStack(alignment: .leading, spacing: 2) { Text(window.name); Text("\(window.usedText) · \(window.remainingText) · \(window.durationText)").font(.caption); Text("\(window.resetText)（\(window.countdownText)）").font(.caption) }
            }
            Text(presentation.updatedText).font(.caption)
            Text(presentation.statusText).font(.caption)
            Button("立即刷新", action: onRefresh)
        }.padding(12).frame(width: 280, alignment: .leading)
    }
}
