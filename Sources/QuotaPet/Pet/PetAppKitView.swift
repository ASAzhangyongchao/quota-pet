import AppKit
import QuartzCore

struct PetPointerInteractionState {
    private var mouseDownPoint: CGPoint?
    private var dragged = false

    mutating func mouseDown(at point: CGPoint) {
        mouseDownPoint = point
        dragged = false
    }

    mutating func mouseDragged(at point: CGPoint, dragThreshold: CGFloat) -> Bool {
        guard let mouseDownPoint else { return false }
        if hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > dragThreshold {
            dragged = true
        }
        return dragged
    }

    mutating func mouseUp(at point: CGPoint, dragThreshold: CGFloat) -> Bool {
        guard let mouseDownPoint else { return false }
        let shouldClick = !dragged && hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) <= dragThreshold
        self.mouseDownPoint = nil
        dragged = false
        return shouldClick
    }

    mutating func cancel() {
        mouseDownPoint = nil
        dragged = false
    }
}

@MainActor
final class PetAppKitView: NSView {
    static let interactionAnimationKey = "QuotaPet.interaction"

    private(set) var renderState: PetRenderState
    private let onClick: () -> Void
    private let onHover: () -> Void
    private var pointerState = PetPointerInteractionState()
    private var trackingArea: NSTrackingArea?
    private var layerReleaseWorkItem: DispatchWorkItem?

    init(renderState: PetRenderState, onClick: @escaping () -> Void, onHover: @escaping () -> Void) {
        self.renderState = renderState
        self.onClick = onClick
        self.onHover = onHover
        super.init(frame: NSRect(origin: .zero, size: FloatingPetPanelContract.visiblePetSize))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func update(renderState: PetRenderState) {
        guard self.renderState != renderState else { return }
        self.renderState = renderState
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    func play(event: PetAnimationEvent, durationMilliseconds: Int, mood: PetMood = .content) {
        layerReleaseWorkItem?.cancel()
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        guard let layer else { return }

        // Idle "blinkOnly" is eyes-only (handled by redraw); skip body motion to stay calm.
        if event == .idleBlink, mood.idleMotion == .blinkOnly {
            scheduleLayerRelease(afterMilliseconds: durationMilliseconds)
            return
        }

        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = transformValues(for: event, mood: mood)
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = Double(durationMilliseconds) / 1_000
        animation.repeatCount = 0
        animation.autoreverses = false
        animation.isRemovedOnCompletion = true
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.removeAnimation(forKey: Self.interactionAnimationKey)
        layer.add(animation, forKey: Self.interactionAnimationKey)
        scheduleLayerRelease(afterMilliseconds: durationMilliseconds)
    }

    private func scheduleLayerRelease(afterMilliseconds durationMilliseconds: Int) {
        let release = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.layer?.removeAnimation(forKey: Self.interactionAnimationKey)
            self.wantsLayer = false
            self.needsDisplay = true
        }
        layerReleaseWorkItem = release
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(durationMilliseconds + 30), execute: release)
    }

    private func transformValues(for event: PetAnimationEvent, mood: PetMood) -> [NSValue] {
        switch event {
        case .stateChange:
            // Soft settle — just enough to notice a mood swap.
            return [
                NSValue(caTransform3D: CATransform3DIdentity),
                NSValue(caTransform3D: CATransform3DMakeScale(1.04, 1.04, 1)),
                NSValue(caTransform3D: CATransform3DIdentity),
            ]
        case .click:
            return [
                NSValue(caTransform3D: CATransform3DIdentity),
                NSValue(caTransform3D: CATransform3DMakeScale(1.08, 1.08, 1)),
                NSValue(caTransform3D: CATransform3DIdentity),
            ]
        case .hover:
            return [
                NSValue(caTransform3D: CATransform3DIdentity),
                NSValue(caTransform3D: CATransform3DMakeRotation(3 * .pi / 180, 0, 0, 1)),
                NSValue(caTransform3D: CATransform3DIdentity),
            ]
        case .idleBlink:
            switch mood.idleMotion {
            case .softBreathBlink:
                // Visible soft squash while blinking — still one-shot, not continuous.
                return [
                    NSValue(caTransform3D: CATransform3DIdentity),
                    NSValue(caTransform3D: CATransform3DMakeScale(1.05, 0.96, 1)),
                    NSValue(caTransform3D: CATransform3DIdentity),
                ]
            case .nervousWobbleBlink:
                // Small lean — uneasy, not a shake.
                var lean = CATransform3DIdentity
                lean = CATransform3DTranslate(lean, -3.0, 0, 0)
                return [
                    NSValue(caTransform3D: CATransform3DIdentity),
                    NSValue(caTransform3D: lean),
                    NSValue(caTransform3D: CATransform3DIdentity),
                ]
            case .sleepBreath:
                return [
                    NSValue(caTransform3D: CATransform3DIdentity),
                    NSValue(caTransform3D: CATransform3DMakeScale(1.03, 0.97, 1)),
                    NSValue(caTransform3D: CATransform3DIdentity),
                ]
            case .blinkOnly:
                return [NSValue(caTransform3D: CATransform3DIdentity)]
            }
        }
    }

    func cancelAnimation() {
        layerReleaseWorkItem?.cancel()
        layerReleaseWorkItem = nil
        layer?.removeAnimation(forKey: Self.interactionAnimationKey)
        wantsLayer = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        PetAppKitDrawing.draw(renderState, in: context, size: bounds.size)
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let replacement = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(replacement)
        trackingArea = replacement
        super.updateTrackingAreas()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        onHover()
    }

    override func mouseDown(with event: NSEvent) {
        pointerState.mouseDown(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard pointerState.mouseDragged(at: point, dragThreshold: 4), let window else { return }
        var origin = window.frame.origin
        origin.x += event.deltaX
        origin.y -= event.deltaY
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if pointerState.mouseUp(at: point, dragThreshold: 4) { onClick() }
    }

    override func accessibilityLabel() -> String? { renderState.accessibilityLabel }
    override func accessibilityValue() -> Any? { renderState.accessibilityValue }
    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }
}

private enum PetAppKitDrawing {
    static func draw(_ state: PetRenderState, in context: CGContext, size: CGSize) {
        context.saveGState()
        context.setLineCap(.round)
        for operation in PetDrawingPlan.scene(for: state, size: size).operations {
            switch operation {
            case let .fill(path, color):
                context.addPath(path)
                context.setFillColor(color.nsColor.cgColor)
                context.fillPath()
            case let .stroke(path, color, lineWidth, dash):
                context.addPath(path)
                context.setStrokeColor(color.nsColor.cgColor)
                context.setLineWidth(lineWidth)
                context.setLineDash(phase: 0, lengths: dash)
                context.strokePath()
            }
        }
        drawRemainingBadge(state.remainingPercentText, in: context, size: size)
        context.restoreGState()
    }

    private static func drawRemainingBadge(_ text: String, in context: CGContext, size: CGSize) {
        let scale = min(size.width, size.height) / 72
        let badgeRect = CGRect(
            x: size.width / 2 - 14 * scale,
            y: size.height / 2 + 13 * scale,
            width: 28 * scale,
            height: 13 * scale
        )
        let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 6.5 * scale, cornerHeight: 6.5 * scale, transform: nil)
        context.addPath(badgePath)
        context.setFillColor(NSColor.black.withAlphaComponent(0.24).cgColor)
        context.fillPath()

        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5 * scale, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        attributed.draw(
            with: badgeRect.insetBy(dx: 1.5 * scale, dy: 1.2 * scale),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
    }
}

private extension PetDrawingColor {
    var nsColor: NSColor {
        switch self {
        case let .fixed(red, green, blue, alpha): NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
        case let .label(alpha): NSColor.labelColor.withAlphaComponent(alpha)
        }
    }
}
