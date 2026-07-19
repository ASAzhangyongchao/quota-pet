import AppKit

enum UsageRingColorSemantic: Equatable {
    case ready
    case stale
    case unavailable
}

struct UsageRingStyle: Equatable {
    let usedFraction: Double?
    let remainingFraction: Double?
    let startAngle: CGFloat
    let colorSemantic: UsageRingColorSemantic
    let lineWidth: CGFloat
    let isDashed: Bool
    let staleOpacity: CGFloat
    let accessibilityLabel: String

    init(snapshot: QuotaSnapshot, lineWidth: CGFloat = 2.4, language: AppLanguage = .current) {
        self.lineWidth = lineWidth
        startAngle = -.pi / 2

        let semantic: UsageRingColorSemantic
        let opacity: CGFloat
        switch snapshot.state {
        case .ready:
            semantic = .ready
            opacity = 1
        case .stale:
            semantic = .stale
            opacity = 0.55
        case .loading, .unavailable, .incompatible:
            usedFraction = nil
            remainingFraction = nil
            colorSemantic = .unavailable
            isDashed = true
            staleOpacity = 1
            accessibilityLabel = L10n.text(.ringUnavailable, language: language)
            return
        }

        guard let window = snapshot.primary else {
            usedFraction = nil
            remainingFraction = nil
            colorSemantic = .unavailable
            isDashed = true
            staleOpacity = 1
            accessibilityLabel = L10n.text(.ringUnavailable, language: language)
            return
        }

        let used = min(max(window.usedPercent / 100, 0), 1)
        usedFraction = used
        remainingFraction = min(max(window.remainingPercent / 100, 0), 1)
        colorSemantic = semantic
        isDashed = false
        staleOpacity = opacity
        accessibilityLabel = Self.accessibilityLabel(for: window, language: language)
    }

    private static func accessibilityLabel(for window: QuotaWindow, language: AppLanguage) -> String {
        let remaining = Int(window.remainingPercent.rounded())
        guard let reset = window.resetsAt else { return L10n.text(.ringRemaining, language: language, arguments: [remaining]) }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = .current
        formatter.dateFormat = language == .simplifiedChinese ? "M月d日" : "MMM d"
        return L10n.text(.ringRemainingReset, language: language, arguments: [remaining, formatter.string(from: reset)])
    }
}

final class UsageRingView: NSView {
    private var snapshot = QuotaSnapshot(planType: nil, windows: [], updatedAt: .distantPast, state: .loading)

    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 18) }

    func setSnapshot(_ snapshot: QuotaSnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let style = UsageRingStyle(snapshot: snapshot)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: style.lineWidth / 2, dy: style.lineWidth / 2)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(0, min(rect.width, rect.height) / 2)

        context.setLineWidth(style.lineWidth)
        context.setLineCap(.round)
        context.setAlpha(style.staleOpacity)

        guard let used = style.usedFraction, let remaining = style.remainingFraction else {
            context.setStrokeColor(NSColor.tertiaryLabelColor.cgColor)
            context.setLineDash(phase: 0, lengths: [2, 1.5])
            context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            context.strokePath()
            return
        }

        let start = style.startAngle
        let fullCircle = CGFloat.pi * 2
        let usedEnd = start + fullCircle * used
        if used > 0 {
            context.setStrokeColor(NSColor.systemOrange.cgColor)
            context.addArc(center: center, radius: radius, startAngle: start, endAngle: usedEnd, clockwise: false)
            context.strokePath()
        }
        if remaining > 0 {
            context.setStrokeColor(NSColor.systemGreen.cgColor)
            context.addArc(center: center, radius: radius, startAngle: usedEnd, endAngle: start + fullCircle, clockwise: false)
            context.strokePath()
        }
    }

    override func accessibilityLabel() -> String? {
        UsageRingStyle(snapshot: snapshot).accessibilityLabel
    }

    override func accessibilityValue() -> Any? {
        guard let remaining = UsageRingStyle(snapshot: snapshot).remainingFraction else { return nil }
        return "\(Int((remaining * 100).rounded()))%"
    }
}
