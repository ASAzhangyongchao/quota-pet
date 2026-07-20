import SwiftUI

struct CodexConnectionOffer {
    let displayPath: String
    let confirm: () -> Void
}

enum RefreshFeedbackState: Equatable {
    case idle
    case refreshing
    case timeoutNotice
    case recovering
    case succeeded
    case failed
}

@MainActor
final class UsageDetailsViewModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot
    @Published private(set) var presentation: UsageDetailsPresentation
    @Published private(set) var refreshFeedback: RefreshFeedbackState = .idle
    @Published private(set) var language: AppLanguage
    private(set) var updateCount = 0
    private let successFeedbackDurationNanoseconds: UInt64
    private let refreshTimeoutNanoseconds: UInt64
    private let recoverNoticeNanoseconds: UInt64
    private var feedbackResetTask: Task<Void, Never>?
    private var refreshWatchdogTask: Task<Void, Never>?
    private var autoRecoverUsed = false
    private var pendingRecover: (() -> Void)?

    init(
        snapshot: QuotaSnapshot,
        language: AppLanguage = .current,
        successFeedbackDurationNanoseconds: UInt64 = 1_000_000_000,
        refreshTimeoutNanoseconds: UInt64 = 20_000_000_000,
        recoverNoticeNanoseconds: UInt64 = 2_500_000_000
    ) {
        self.snapshot = snapshot
        self.language = language
        self.successFeedbackDurationNanoseconds = successFeedbackDurationNanoseconds
        self.refreshTimeoutNanoseconds = refreshTimeoutNanoseconds
        self.recoverNoticeNanoseconds = recoverNoticeNanoseconds
        presentation = UsageDetailsPresentation(snapshot: snapshot, language: language)
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        presentation = UsageDetailsPresentation(snapshot: snapshot, language: language)
        objectWillChange.send()
    }

    func beginRefresh(onRecover: (() -> Void)? = nil) {
        feedbackResetTask?.cancel()
        refreshWatchdogTask?.cancel()
        autoRecoverUsed = false
        pendingRecover = onRecover
        refreshFeedback = .refreshing
        scheduleRefreshWatchdog()
    }

    func update(_ snapshot: QuotaSnapshot) {
        self.snapshot = snapshot
        presentation = UsageDetailsPresentation(snapshot: snapshot, language: language)
        updateCount += 1
        switch refreshFeedback {
        case .refreshing, .timeoutNotice, .recovering:
            break
        case .idle, .succeeded, .failed:
            return
        }
        switch snapshot.state {
        case .loading:
            break
        case .ready:
            refreshWatchdogTask?.cancel()
            refreshWatchdogTask = nil
            pendingRecover = nil
            refreshFeedback = .succeeded
            schedulePetRestoration()
        case .stale, .unavailable, .incompatible:
            refreshWatchdogTask?.cancel()
            refreshWatchdogTask = nil
            pendingRecover = nil
            refreshFeedback = .failed
        }
    }

    private func scheduleRefreshWatchdog() {
        let timeout = refreshTimeoutNanoseconds
        let notice = recoverNoticeNanoseconds
        refreshWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled, let self, self.refreshFeedback == .refreshing else { return }
            self.refreshFeedback = .timeoutNotice
            try? await Task.sleep(nanoseconds: notice)
            guard !Task.isCancelled else { return }
            guard self.refreshFeedback == .timeoutNotice, !self.autoRecoverUsed else { return }
            self.autoRecoverUsed = true
            self.refreshFeedback = .recovering
            let recover = self.pendingRecover
            self.pendingRecover = nil
            recover?()
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
        let summaryText: String
        let usedFraction: Double
        let remainingFraction: Double
        let meterAccessibilityText: String
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

    init(snapshot: QuotaSnapshot, now: Date = .now, calendar: Calendar = .current, language: AppLanguage = .current) {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = language.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = language == .simplifiedChinese ? "yyyy年M月d日 HH:mm" : "MMM d, yyyy HH:mm"

        let primary = snapshot.primary
        primaryText = primary.map {
            L10n.text(.remainingUsedSummary, language: language, arguments: [Int($0.remainingPercent.rounded()), Int($0.usedPercent.rounded())])
        } ?? L10n.text(.usageUnavailable, language: language)
        connectionActionTitle = primary == nil ? L10n.text(.confirmAndReadUsage, language: language) : nil
        windows = snapshot.windows.map { window in
            let reset = window.resetsAt.map { L10n.text(.resetAt, language: language, arguments: [formatter.string(from: $0)]) } ?? L10n.text(.resetUnavailable, language: language)
            let countdown = window.resetsAt.map { Self.countdown(until: $0, now: now, language: language) } ?? L10n.text(.resetCountdownUnavailable, language: language)
            let duration = window.windowDurationMinutes.map { Self.durationText(minutes: $0, language: language) }
            let display = Self.displayInfo(for: window, language: language)
            let used = L10n.text(.usedPercent, language: language, arguments: [Int(window.usedPercent.rounded())])
            return Window(
                name: display.name,
                noteText: display.note,
                usedText: used,
                remainingText: L10n.text(.remainingPercent, language: language, arguments: [Int(window.remainingPercent.rounded())]),
                durationText: duration,
                resetText: reset,
                countdownText: countdown,
                summaryText: duration.map { L10n.text(.cycleSummary, language: language, arguments: [used, $0]) } ?? used,
                usedFraction: Self.clampFraction(window.usedPercent / 100),
                remainingFraction: Self.clampFraction(window.remainingPercent / 100),
                meterAccessibilityText: L10n.text(
                    .meterAccessibility,
                    language: language,
                    arguments: [Int(window.usedPercent.rounded()), Int(window.remainingPercent.rounded())]
                )
            )
        }
        updatedText = snapshot.windows.isEmpty ? nil : L10n.text(.updatedAt, language: language, arguments: [formatter.string(from: snapshot.updatedAt)])
        switch snapshot.state {
        case .ready:
            statusText = L10n.text(.dataHealthy, language: language)
            statusKind = .healthy
        case .loading:
            statusText = L10n.text(.readingUsage, language: language)
            statusKind = .loading
        case let .stale(message):
            statusText = L10n.text(.dataStale, language: language, arguments: [message])
            statusKind = .warning
        case let .unavailable(message), let .incompatible(message):
            statusText = message
            statusKind = .warning
        }
    }

    private static func countdown(until date: Date, now: Date, language: AppLanguage) -> String {
        let remainingSeconds = max(date.timeIntervalSince(now), 0)
        if remainingSeconds >= 24 * 60 * 60 {
            return L10n.text(.countdownDays, language: language, arguments: [Int(ceil(remainingSeconds / (24 * 60 * 60)))])
        }
        if remainingSeconds >= 60 * 60 {
            return L10n.text(.countdownHours, language: language, arguments: [Int(ceil(remainingSeconds / (60 * 60)))])
        }
        return L10n.text(.countdownMinutes, language: language, arguments: [Int(ceil(remainingSeconds / 60))])
    }

    private static func durationText(minutes: Int, language: AppLanguage) -> String {
        if minutes % (24 * 60) == 0 { return L10n.text(.durationDays, language: language, arguments: [minutes / (24 * 60)]) }
        if minutes % 60 == 0 { return L10n.text(.durationHours, language: language, arguments: [minutes / 60]) }
        return L10n.text(.durationMinutes, language: language, arguments: [minutes])
    }

    private static func clampFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func displayInfo(for window: QuotaWindow, language: AppLanguage) -> (name: String, note: String?) {
        if window.bucketID == "codex" {
            return (L10n.text(.generalUsageLimit, language: language), nil)
        }
        if window.bucketID == "codex_bengalfox" {
            return (L10n.text(.sparkUsageLimit, language: language), nil)
        }
        return (window.displayName, nil)
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
                    .accessibilityLabel(L10n.text(.collapseDetails, language: viewModel.language))
                } else {
                    RefreshAvatar(feedback: viewModel.refreshFeedback, snapshot: viewModel.snapshot)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(.codexUsage, language: viewModel.language))
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
                    Text(L10n.text(.willReadPath, language: viewModel.language, arguments: [connectionOffer.displayPath]))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Button(title, action: connectionOffer.confirm)
                        .accessibilityLabel(L10n.text(.confirmLocalCodex, language: viewModel.language))
                }
            }

            Button {
                viewModel.beginRefresh {
                    onRefresh()
                }
                onRefresh()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.refreshFeedback == .refreshing || viewModel.refreshFeedback == .recovering {
                        ProgressView().controlSize(.small)
                    } else if viewModel.refreshFeedback == .timeoutNotice {
                        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    } else {
                        Image(systemName: viewModel.refreshFeedback == .succeeded ? "checkmark" : "arrow.clockwise")
                    }
                    Text(refreshButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.refreshFeedback == .refreshing
                || viewModel.refreshFeedback == .timeoutNotice
                || viewModel.refreshFeedback == .recovering)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(Color.clear)
    }

    private var refreshButtonTitle: String {
        switch viewModel.refreshFeedback {
        case .idle, .failed: L10n.text(.refreshNow, language: viewModel.language)
        case .refreshing: L10n.text(.refreshing, language: viewModel.language)
        case .timeoutNotice: L10n.text(.refreshTimeoutNotice, language: viewModel.language)
        case .recovering: L10n.text(.refreshRecovering, language: viewModel.language)
        case .succeeded: L10n.text(.refreshSucceeded, language: viewModel.language)
        }
    }
}

private struct UsageWindowCard: View {
    let window: UsageDetailsPresentation.Window
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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
            QuotaSplitMeter(
                usedFraction: window.usedFraction,
                remainingFraction: window.remainingFraction,
                accessibilityText: window.meterAccessibilityText
            )
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
                .fill(Color.primary.opacity(reduceTransparency ? 0.12 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.primary.opacity(colorSchemeContrast == .increased ? 0.34 : 0.16),
                    lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.8
                )
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
            case .refreshing, .recovering:
                Circle().fill(Color.accentColor.opacity(0.14))
                ProgressView().controlSize(.small)
            case .timeoutNotice:
                Circle().fill(Color.orange.opacity(0.16))
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
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
