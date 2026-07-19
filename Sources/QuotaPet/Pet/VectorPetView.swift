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
        for operation in PetDrawingPlan.scene(for: state, size: size).operations {
            switch operation {
            case let .fill(path, color):
                context.fill(Path(path), with: .color(color.swiftUIColor))
            case let .stroke(path, color, lineWidth, dash):
                context.stroke(Path(path), with: .color(color.swiftUIColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash))
            }
        }
    }
}

private extension PetDrawingColor {
    var swiftUIColor: Color {
        switch self {
        case let .fixed(red, green, blue, alpha): Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
        case let .label(alpha): Color.primary.opacity(Double(alpha))
        }
    }
}
