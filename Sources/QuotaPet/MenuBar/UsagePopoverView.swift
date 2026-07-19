import SwiftUI

struct CodexConnectionOffer {
    let displayPath: String
    let confirm: () -> Void
}

@MainActor
final class UsageDetailsViewModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot
    @Published private(set) var presentation: UsageDetailsPresentation
    private(set) var updateCount = 0
    init(snapshot: QuotaSnapshot) { self.snapshot = snapshot; presentation = UsageDetailsPresentation(snapshot: snapshot) }
    func update(_ snapshot: QuotaSnapshot) { self.snapshot = snapshot; presentation = UsageDetailsPresentation(snapshot: snapshot); updateCount += 1 }
}

struct UsageDetailsPresentation: Equatable {
    struct Window: Equatable {
        let name: String
        let usedText: String
        let remainingText: String
        let durationText: String?
        let resetText: String
        let countdownText: String
        var summaryText: String { "\(usedText) · \(remainingText)\(durationText.map { " · \($0)" } ?? "")" }
    }
    let primaryText: String
    let windows: [Window]
    let updatedText: String?
    let statusText: String
    let connectionActionTitle: String?

    init(snapshot: QuotaSnapshot, now: Date = .now, calendar: Calendar = .current) {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy年M月d日 HH:mm"
        let primary = snapshot.primary
        primaryText = primary.map { "剩余 \(Int($0.remainingPercent.rounded()))% · 已用 \(Int($0.usedPercent.rounded()))%" } ?? "用量暂不可用"
        connectionActionTitle = primary == nil ? "确认并读取用量" : nil
        windows = snapshot.windows.enumerated().map { index, window in
            let reset = window.resetsAt.map { "重置时间：\(formatter.string(from: $0))" } ?? "重置时间：未提供"
            let countdown: String
            if let date = window.resetsAt { countdown = Self.countdown(until: date, now: now) } else { countdown = "未提供" }
            let duration = window.windowDurationMinutes.map(Self.durationText(minutes:))
            return Window(name: Self.displayName(for: window, index: index, total: snapshot.windows.count), usedText: "已用 \(Int(window.usedPercent.rounded()))%", remainingText: "剩余 \(Int(window.remainingPercent.rounded()))%", durationText: duration, resetText: reset, countdownText: countdown)
        }
        updatedText = snapshot.windows.isEmpty ? nil : "数据更新：\(formatter.string(from: snapshot.updatedAt))"
        switch snapshot.state { case .ready: statusText = "数据正常"; case .loading: statusText = "正在加载"; case let .stale(message): statusText = "数据已过期：\(message)"; case let .unavailable(message), let .incompatible(message): statusText = message }
    }

    private static func countdown(until date: Date, now: Date) -> String {
        let remainingSeconds = max(date.timeIntervalSince(now), 0)
        if remainingSeconds >= 24 * 60 * 60 {
            return "距重置 \(Int(ceil(remainingSeconds / (24 * 60 * 60))))天"
        }
        if remainingSeconds >= 60 * 60 {
            return "距重置 \(Int(ceil(remainingSeconds / (60 * 60))))小时"
        }
        return "距重置 \(Int(ceil(remainingSeconds / 60)))分钟"
    }

    private static func durationText(minutes: Int) -> String {
        if minutes % (24 * 60) == 0 { return "\(minutes / (24 * 60))天" }
        if minutes % 60 == 0 { return "\(minutes / 60)小时" }
        return "\(minutes)分钟"
    }

    private static func displayName(for window: QuotaWindow, index: Int, total: Int) -> String {
        let internalNames = ["primary", "secondary"]
        if !internalNames.contains(window.displayName.lowercased()) {
            return window.displayName
        }
        if let minutes = window.windowDurationMinutes {
            return "\(durationText(minutes: minutes))额度"
        }
        return total > 1 ? "Codex 用量 \(index + 1)" : "Codex 用量"
    }
}

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageDetailsViewModel
    var onPetTap: (() -> Void)? = nil
    var connectionOffer: CodexConnectionOffer? = nil
    let onRefresh: () -> Void
    init(snapshot: QuotaSnapshot, onPetTap: (() -> Void)? = nil, connectionOffer: CodexConnectionOffer? = nil, onRefresh: @escaping () -> Void) { viewModel = UsageDetailsViewModel(snapshot: snapshot); self.onPetTap = onPetTap; self.connectionOffer = connectionOffer; self.onRefresh = onRefresh }
    init(viewModel: UsageDetailsViewModel, onPetTap: (() -> Void)? = nil, connectionOffer: CodexConnectionOffer? = nil, onRefresh: @escaping () -> Void) { self.viewModel = viewModel; self.onPetTap = onPetTap; self.connectionOffer = connectionOffer; self.onRefresh = onRefresh }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.name)
                    Text(window.summaryText).font(.caption)
                    Text("\(window.resetText)（\(window.countdownText)）").font(.caption)
                }
            }
            if let updatedText = presentation.updatedText {
                Text(updatedText).font(.caption)
            }
            Text(presentation.statusText).font(.caption)
            if let title = presentation.connectionActionTitle, let connectionOffer {
                Text("将读取：\(connectionOffer.displayPath)")
                    .font(.caption2)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Button(title, action: connectionOffer.confirm)
                    .accessibilityLabel("确认并读取本机 Codex 用量")
            }
            Button("立即刷新", action: onRefresh)
        }.padding(12).frame(width: 280, alignment: .leading)
    }
}
