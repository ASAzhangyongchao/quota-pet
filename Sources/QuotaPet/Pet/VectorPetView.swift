import SwiftUI

public struct VectorPetView: View {
    private let renderState: PetRenderState
    private let size: CGFloat

    init(renderState: PetRenderState, size: CGFloat = 72) {
        self.renderState = renderState
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            PetCanvasDrawing.draw(renderState, in: &context, size: canvasSize)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(renderState.accessibilityLabel))
        .accessibilityValue(Text(renderState.accessibilityValue))
    }
}

enum PetDrawingPlan {
    static let maximumPathCount = 9
    static let maximumGradientCount = 0
    static let bodyMaxDimension = 60
    static let ringRadius: CGFloat = 28
    static let ringLineWidth: CGFloat = 3

    static func scale(in size: CGSize) -> CGFloat { min(size.width, size.height) / 72 }

    static func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    static func ringBounds(in size: CGSize) -> CGRect {
        let scale = scale(in: size)
        let center = center(in: size)
        let radius = ringRadius * scale
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    static func renderedRingBounds(in size: CGSize) -> CGRect {
        ringBounds(in: size).insetBy(dx: -ringLineWidth * scale(in: size) / 2, dy: -ringLineWidth * scale(in: size) / 2)
    }
}

struct PetTailGeometry: Equatable {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
    let strokeWidth: CGFloat

    init(usedFraction: Double, canvasSize: CGSize) {
        let scale = PetDrawingPlan.scale(in: canvasSize)
        let center = PetDrawingPlan.center(in: canvasSize)
        let angle = -CGFloat.pi / 2 + .pi * 2 * min(max(usedFraction, 0), 1)
        let radial = CGPoint(x: cos(angle), y: sin(angle))
        let tangent = CGPoint(x: -radial.y, y: radial.x)
        let radius = PetDrawingPlan.ringRadius * scale

        start = CGPoint(x: center.x + radial.x * radius, y: center.y + radial.y * radius)
        control = CGPoint(
            x: start.x + tangent.x * 5 * scale - radial.x * scale,
            y: start.y + tangent.y * 5 * scale - radial.y * scale
        )
        end = CGPoint(
            x: start.x + tangent.x * 8 * scale - radial.x * 4 * scale,
            y: start.y + tangent.y * 8 * scale - radial.y * 4 * scale
        )
        strokeWidth = PetDrawingPlan.ringLineWidth * scale
    }

    var points: [CGPoint] { [start, control, end] }

    var renderedBounds: CGRect {
        let minX = points.map(\.x).min() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -strokeWidth / 2, dy: -strokeWidth / 2)
    }
}

private enum PetCanvasDrawing {
    static func draw(_ state: PetRenderState, in context: inout GraphicsContext, size: CGSize) {
        let scale = PetDrawingPlan.scale(in: size)
        let center = PetDrawingPlan.center(in: size)
        let body = CGRect(x: center.x - 26 * scale, y: center.y - 22 * scale, width: 52 * scale, height: 48 * scale)
        let feature = Color.primary.opacity(0.86 * state.staleOpacity)
        let palette = state.palette

        var shadow = Path()
        shadow.addEllipse(in: body.offsetBy(dx: 0, dy: 2 * scale))
        context.fill(shadow, with: .color(.black.opacity(0.10 * state.staleOpacity)))

        var bodyPath = Path()
        bodyPath.addEllipse(in: body)
        context.fill(bodyPath, with: .color(palette.bodyColor.opacity(state.staleOpacity)))

        var ring = Path()
        ring.addEllipse(in: PetDrawingPlan.ringBounds(in: size))
        let ringStyle = StrokeStyle(lineWidth: PetDrawingPlan.ringLineWidth * scale, lineCap: .round, dash: state.dashedRing ? [3 * scale, 2 * scale] : [])
        context.stroke(ring, with: .color(palette.ringColor.opacity(0.28 * state.staleOpacity)), style: ringStyle)

        let startAngle = -CGFloat.pi / 2
        let used = state.usedFraction ?? 0
        let endAngle = startAngle + .pi * 2 * used
        if used > 0 {
            var usedRing = Path()
            usedRing.addArc(center: center, radius: PetDrawingPlan.ringRadius * scale, startAngle: .radians(startAngle), endAngle: .radians(endAngle), clockwise: false)
            context.stroke(usedRing, with: .color(palette.ringColor.opacity(state.staleOpacity)), style: StrokeStyle(lineWidth: PetDrawingPlan.ringLineWidth * scale, lineCap: .round))
        }
        drawTail(PetTailGeometry(usedFraction: used, canvasSize: size), color: palette.ringColor.opacity(state.staleOpacity), in: &context)
        drawFace(state, center: center, scale: scale, color: feature, in: &context)
    }

    private static func drawTail(_ geometry: PetTailGeometry, color: Color, in context: inout GraphicsContext) {
        var tail = Path()
        tail.move(to: geometry.start)
        tail.addQuadCurve(to: geometry.end, control: geometry.control)
        context.stroke(tail, with: .color(color), style: StrokeStyle(lineWidth: geometry.strokeWidth, lineCap: .round))
    }

    private static func drawFace(_ state: PetRenderState, center: CGPoint, scale: CGFloat, color: Color, in context: inout GraphicsContext) {
        var eyes = Path()
        switch state.eyeShape {
        case .dot:
            eyes.addEllipse(in: CGRect(x: center.x - 11 * scale, y: center.y - 3 * scale, width: 3.5 * scale, height: 4.5 * scale))
            eyes.addEllipse(in: CGRect(x: center.x + 7.5 * scale, y: center.y - 3 * scale, width: 3.5 * scale, height: 4.5 * scale))
            context.fill(eyes, with: .color(color))
        case .line:
            eyes.move(to: CGPoint(x: center.x - 11 * scale, y: center.y))
            eyes.addLine(to: CGPoint(x: center.x - 7 * scale, y: center.y))
            eyes.move(to: CGPoint(x: center.x + 7 * scale, y: center.y))
            eyes.addLine(to: CGPoint(x: center.x + 11 * scale, y: center.y))
            context.stroke(eyes, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
        case .closed:
            eyes.move(to: CGPoint(x: center.x - 12 * scale, y: center.y - 1 * scale))
            eyes.addQuadCurve(to: CGPoint(x: center.x - 7 * scale, y: center.y - 1 * scale), control: CGPoint(x: center.x - 9.5 * scale, y: center.y + 2 * scale))
            eyes.move(to: CGPoint(x: center.x + 7 * scale, y: center.y - 1 * scale))
            eyes.addQuadCurve(to: CGPoint(x: center.x + 12 * scale, y: center.y - 1 * scale), control: CGPoint(x: center.x + 9.5 * scale, y: center.y + 2 * scale))
            context.stroke(eyes, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
        }

        if state.browShape == .concerned {
            var brows = Path()
            brows.move(to: CGPoint(x: center.x - 12 * scale, y: center.y - 7 * scale))
            brows.addLine(to: CGPoint(x: center.x - 7 * scale, y: center.y - 9 * scale))
            brows.move(to: CGPoint(x: center.x + 7 * scale, y: center.y - 9 * scale))
            brows.addLine(to: CGPoint(x: center.x + 12 * scale, y: center.y - 7 * scale))
            context.stroke(brows, with: .color(color), style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round))
        }

        var mouth = Path()
        switch state.mouthShape {
        case .smile:
            mouth.move(to: CGPoint(x: center.x - 6 * scale, y: center.y + 7 * scale))
            mouth.addQuadCurve(to: CGPoint(x: center.x + 6 * scale, y: center.y + 7 * scale), control: CGPoint(x: center.x, y: center.y + 12 * scale))
        case .flat:
            mouth.move(to: CGPoint(x: center.x - 5 * scale, y: center.y + 9 * scale))
            mouth.addLine(to: CGPoint(x: center.x + 5 * scale, y: center.y + 9 * scale))
        case .frown:
            mouth.move(to: CGPoint(x: center.x - 6 * scale, y: center.y + 11 * scale))
            mouth.addQuadCurve(to: CGPoint(x: center.x + 6 * scale, y: center.y + 11 * scale), control: CGPoint(x: center.x, y: center.y + 6 * scale))
        case .sleep:
            mouth.move(to: CGPoint(x: center.x - 4 * scale, y: center.y + 8 * scale))
            mouth.addQuadCurve(to: CGPoint(x: center.x + 4 * scale, y: center.y + 8 * scale), control: CGPoint(x: center.x, y: center.y + 10 * scale))
        }
        context.stroke(mouth, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))

        if state.showsSweat {
            var sweat = Path()
            sweat.move(to: CGPoint(x: center.x + 17 * scale, y: center.y - 7 * scale))
            sweat.addQuadCurve(to: CGPoint(x: center.x + 20 * scale, y: center.y - 1 * scale), control: CGPoint(x: center.x + 22 * scale, y: center.y - 4 * scale))
            sweat.addQuadCurve(to: CGPoint(x: center.x + 17 * scale, y: center.y - 7 * scale), control: CGPoint(x: center.x + 17 * scale, y: center.y + 1 * scale))
            context.fill(sweat, with: .color(color))
        } else if state.showsSleepMark {
            var sleepMark = Path()
            sleepMark.move(to: CGPoint(x: center.x + 14 * scale, y: center.y - 12 * scale))
            sleepMark.addLine(to: CGPoint(x: center.x + 19 * scale, y: center.y - 12 * scale))
            sleepMark.move(to: CGPoint(x: center.x + 16 * scale, y: center.y - 16 * scale))
            sleepMark.addLine(to: CGPoint(x: center.x + 21 * scale, y: center.y - 16 * scale))
            sleepMark.move(to: CGPoint(x: center.x + 18 * scale, y: center.y - 20 * scale))
            sleepMark.addLine(to: CGPoint(x: center.x + 22 * scale, y: center.y - 20 * scale))
            context.stroke(sleepMark, with: .color(color), style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round))
        }
    }
}

private extension PetPalette {
    var bodyColor: Color {
        switch self {
        case .mint: Color(red: 0.29, green: 0.78, blue: 0.62)
        case .clearBlue: Color(red: 0.31, green: 0.66, blue: 0.91)
        case .amber: Color(red: 0.94, green: 0.64, blue: 0.23)
        case .warningRed: Color(red: 0.91, green: 0.31, blue: 0.29)
        case .grayRed: Color(red: 0.57, green: 0.39, blue: 0.41)
        case .neutralGray: Color(red: 0.50, green: 0.53, blue: 0.58)
        }
    }

    var ringColor: Color {
        switch self {
        case .mint: Color(red: 0.10, green: 0.65, blue: 0.49)
        case .clearBlue: Color(red: 0.16, green: 0.50, blue: 0.83)
        case .amber: Color(red: 0.82, green: 0.42, blue: 0.08)
        case .warningRed: Color(red: 0.77, green: 0.16, blue: 0.16)
        case .grayRed: Color(red: 0.47, green: 0.24, blue: 0.27)
        case .neutralGray: Color(red: 0.36, green: 0.39, blue: 0.44)
        }
    }
}
