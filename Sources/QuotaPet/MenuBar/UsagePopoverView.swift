import SwiftUI

struct CodexConnectionOffer {
    let displayPath: String
    let confirm: () -> Void
}

enum RefreshFeedbackState: Equatable {
    case idle
    case refreshing
    case succeeded
    case failed
}

@MainActor
final class UsageDetailsViewModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot
    @Published private(set) var presentation: UsageDetailsPresentation
    @Published private(set) var refreshFeedback: RefreshFeedbackState = .idle
    private(set) var updateCount = 0
    private let successFeedbackDurationNanoseconds: UInt64
    private var feedbackResetTask: Task<Void, Never>?

    init(snapshot: QuotaSnapshot, successFeedbackDurationNanoseconds: UInt64 = 1_000_000_000) {
        self.snapshot = snapshot
        self.successFeedbackDurationNanoseconds = successFeedbackDurationNanoseconds
        presentation = UsageDetailsPresentation(snapshot: snapshot)
    }

    func beginRefresh() {
        feedbackResetTask?.cancel()
        refreshFeedback = .refreshing
    }

    func update(_ snapshot: QuotaSnapshot) {
        self.snapshot = snapshot
        presentation = UsageDetailsPresentation(snapshot: snapshot)
        updateCount += 1
        guard refreshFeedback == .refreshing else { return }
        switch snapshot.state {
        case .loading:
            break
        case .ready:
            refreshFeedback = .succeeded
            schedulePetRestoration()
        case .stale, .unavailable, .incompatible:
            refreshFeedback = .failed
        }
    }

    private func schedulePetRestoration() {
        feedbackResetTask?.cancel()
        let delay = successFeedbackDurationNanoseconds
        feedbackResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.refreshFeedback == .succeeded else { return }
            self.refreshFeedback = .idle
        }
    }
}

struct UsageDetailsPresentation: Equatable {
    struct Window: Equatable {
        let name: String
        let noteText: String?
        let usedText: String
        let remainingText: String
        let durationText: String?
        let resetText: String
        let countdownText: String
        var summaryText: String { "\(usedText)\(durationText.map { " · \($0)周期" } ?? "")" }
    }

    enum StatusKind: Equatable {
        case healthy
        case loading
        case warning
    }

    let primaryText: String
    let windows: [Window]
    let updatedText: String?
    let statusText: String
    let statusKind: StatusKind
    let connectionActionTitle: String?

    init(snapshot: QuotaSnapshot, now: Date = .now, calendar: Calendar = .current) {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy年M月d日 HH:mm"

        let primary = snapshot.primary
        primaryText = primary.map { "剩余 \(Int($0.remainingPercent.rounded()))% · 已用 \(Int($0.usedPercent.rounded()))%" } ?? "用量暂不可用"
        connectionActionTitle = primary == nil ? "确认并读取用量" : nil
        windows = snapshot.windows.map { window in
            let reset = window.resetsAt.map { "重置于 \(formatter.string(from: $0))" } ?? "未提供重置时间"
            let countdown = window.resetsAt.map { Self.countdown(until: $0, now: now) } ?? "距重置时间未提供"
            let duration = window.windowDurationMinutes.map(Self.durationText(minutes:))
            let display = Self.displayInfo(for: window)
            return Window(
                name: display.name,
                noteText: display.note,
                usedText: "已用 \(Int(window.usedPercent.rounded()))%",
                remainingText: "剩余 \(Int(window.remainingPercent.rounded()))%",
                durationText: duration,
                resetText: reset,
                countdownText: countdown
            )
        }
        updatedText = snapshot.windows.isEmpty ? nil : "更新于 \(formatter.string(from: snapshot.updatedAt))"
        switch snapshot.state {
        case .ready:
            statusText = "数据正常"
            statusKind = .healthy
        case .loading:
            statusText = "正在读取 Codex 用量"
            statusKind = .loading
        case let .stale(message):
            statusText = "数据已过期：\(message)"
            statusKind = .warning
        case let .unavailable(message), let .incompatible(message):
            statusText = message
            statusKind = .warning
        }
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

    private static func displayInfo(for window: QuotaWindow) -> (name: String, note: String?) {
        let internalNames = ["primary", "secondary"]
        guard internalNames.contains(window.displayName.lowercased()) else {
            return (window.displayName, nil)
        }
        if window.bucketID == "codex" {
            return ("Codex 主额度", nil)
        }
        return ("其他 Codex 额度", "服务端未提供公开名称")
    }
}

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageDetailsViewModel
    var onPetTap: (() -> Void)? = nil
    var connectionOffer: CodexConnectionOffer? = nil
    let onRefresh: () -> Void

    init(snapshot: QuotaSnapshot, onPetTap: (() -> Void)? = nil, connectionOffer: CodexConnectionOffer? = nil, onRefresh: @escaping () -> Void) {
        viewModel = UsageDetailsViewModel(snapshot: snapshot)
        self.onPetTap = onPetTap
        self.connectionOffer = connectionOffer
        self.onRefresh = onRefresh
    }

    init(viewModel: UsageDetailsViewModel, onPetTap: (() -> Void)? = nil, connectionOffer: CodexConnectionOffer? = nil, onRefresh: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onPetTap = onPetTap
        self.connectionOffer = connectionOffer
        self.onRefresh = onRefresh
    }

    var body: some View {
        let presentation = viewModel.presentation
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let onPetTap {
                    Button(action: onPetTap) {
                        RefreshAvatar(feedback: viewModel.refreshFeedback, snapshot: viewModel.snapshot)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("收起用量详情")
                } else {
                    RefreshAvatar(feedback: viewModel.refreshFeedback, snapshot: viewModel.snapshot)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex 用量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(presentation.primaryText)
                        .font(.title3.weight(.semibold))
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(Array(presentation.windows.enumerated()), id: \.offset) { _, window in
                    UsageWindowCard(window: window)
                }
            }

            Divider().opacity(0.5)

            HStack(alignment: .top, spacing: 8) {
                StatusSymbol(kind: presentation.statusKind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.statusText)
                        .font(.caption.weight(.medium))
                    if let updatedText = presentation.updatedText {
                        Text(updatedText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let title = presentation.connectionActionTitle, let connectionOffer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("将读取：\(connectionOffer.displayPath)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Button(title, action: connectionOffer.confirm)
                        .accessibilityLabel("确认并读取本机 Codex 用量")
                }
            }

            Button {
                viewModel.beginRefresh()
                onRefresh()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.refreshFeedback == .refreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: viewModel.refreshFeedback == .succeeded ? "checkmark" : "arrow.clockwise")
                    }
                    Text(refreshButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.refreshFeedback == .refreshing)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(Color.clear)
    }

    private var refreshButtonTitle: String {
        switch viewModel.refreshFeedback {
        case .idle, .failed: "立即刷新"
        case .refreshing: "刷新中…"
        case .succeeded: "刷新成功"
        }
    }
}

private struct UsageWindowCard: View {
    let window: UsageDetailsPresentation.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                Text(window.remainingText).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
            }
            if let note = window.noteText {
                Label(note, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(window.summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(window.resetText)
                Spacer(minLength: 6)
                Text(window.countdownText).fontWeight(.medium)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        )
    }
}

private struct RefreshAvatar: View {
    let feedback: RefreshFeedbackState
    let snapshot: QuotaSnapshot

    var body: some View {
        ZStack {
            switch feedback {
            case .idle:
                VectorPetView(renderState: PetRenderState(snapshot: snapshot), size: 42)
            case .refreshing:
                Circle().fill(Color.accentColor.opacity(0.14))
                ProgressView().controlSize(.small)
            case .succeeded:
                Circle().fill(Color.green.opacity(0.16))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)
            case .failed:
                Circle().fill(Color.orange.opacity(0.16))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 42, height: 42)
    }
}

private struct StatusSymbol: View {
    let kind: UsageDetailsPresentation.StatusKind

    var body: some View {
        switch kind {
        case .healthy:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .loading:
            ProgressView().controlSize(.small)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
