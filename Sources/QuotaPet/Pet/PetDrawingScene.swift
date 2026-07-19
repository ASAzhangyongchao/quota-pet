import CoreGraphics

enum PetDrawingColor {
    case fixed(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)
    case label(alpha: CGFloat)
}

enum PetDrawingOperation {
    case fill(path: CGPath, color: PetDrawingColor)
    case stroke(path: CGPath, color: PetDrawingColor, lineWidth: CGFloat, dash: [CGFloat])
}

struct PetDrawingScene {
    let operations: [PetDrawingOperation]
}

extension PetDrawingPlan {
    static func scene(for state: PetRenderState, size: CGSize) -> PetDrawingScene {
        let scale = scale(in: size)
        let center = center(in: size)
        let body = CGRect(x: center.x - 26 * scale, y: center.y - 22 * scale, width: 52 * scale, height: 48 * scale)
        let opacity = CGFloat(state.staleOpacity)
        let colors = paletteColors(state.palette)
        let feature = PetDrawingColor.label(alpha: 0.86 * opacity)
        var operations: [PetDrawingOperation] = [
            .fill(path: ellipse(in: body.offsetBy(dx: 0, dy: 2 * scale)), color: .fixed(red: 0, green: 0, blue: 0, alpha: 0.10 * opacity)),
            .fill(path: ellipse(in: body), color: colors.body.withAlpha(opacity)),
            .stroke(
                path: ellipse(in: ringBounds(in: size)),
                color: colors.ring.withAlpha(0.28 * opacity),
                lineWidth: ringLineWidth * scale,
                dash: state.dashedRing ? [3 * scale, 2 * scale] : []
            ),
        ]

        let used = min(max(state.usedFraction ?? 0, 0), 1)
        if used > 0 {
            let usedRing = CGMutablePath()
            usedRing.addArc(
                center: center,
                radius: ringRadius * scale,
                startAngle: -.pi / 2,
                endAngle: -.pi / 2 + .pi * 2 * CGFloat(used),
                clockwise: false
            )
            operations.append(.stroke(path: usedRing, color: colors.ring.withAlpha(opacity), lineWidth: ringLineWidth * scale, dash: []))
        }

        let tailGeometry = PetTailGeometry(usedFraction: used, canvasSize: size)
        let tail = CGMutablePath()
        tail.move(to: tailGeometry.start)
        tail.addQuadCurve(to: tailGeometry.end, control: tailGeometry.control)
        operations.append(.stroke(path: tail, color: colors.ring.withAlpha(opacity), lineWidth: tailGeometry.strokeWidth, dash: []))
        operations.append(eyeOperation(state.eyeShape, center: center, scale: scale, color: feature))

        if state.browShape == .concerned {
            operations.append(.stroke(
                path: linePath([
                    CGPoint(x: center.x - 12 * scale, y: center.y - 7 * scale), CGPoint(x: center.x - 7 * scale, y: center.y - 9 * scale),
                    CGPoint(x: center.x + 7 * scale, y: center.y - 9 * scale), CGPoint(x: center.x + 12 * scale, y: center.y - 7 * scale),
                ]),
                color: feature,
                lineWidth: 1.4 * scale,
                dash: []
            ))
        }

        operations.append(.stroke(path: mouthPath(state.mouthShape, center: center, scale: scale), color: feature, lineWidth: 1.8 * scale, dash: []))
        if state.showsSweat {
            let sweat = CGMutablePath()
            sweat.move(to: CGPoint(x: center.x + 17 * scale, y: center.y - 7 * scale))
            sweat.addQuadCurve(to: CGPoint(x: center.x + 20 * scale, y: center.y - scale), control: CGPoint(x: center.x + 22 * scale, y: center.y - 4 * scale))
            sweat.addQuadCurve(to: CGPoint(x: center.x + 17 * scale, y: center.y - 7 * scale), control: CGPoint(x: center.x + 17 * scale, y: center.y + scale))
            operations.append(.fill(path: sweat, color: feature))
        } else if state.showsSleepMark {
            operations.append(.stroke(
                path: linePath([
                    CGPoint(x: center.x + 14 * scale, y: center.y - 12 * scale), CGPoint(x: center.x + 19 * scale, y: center.y - 12 * scale),
                    CGPoint(x: center.x + 16 * scale, y: center.y - 16 * scale), CGPoint(x: center.x + 21 * scale, y: center.y - 16 * scale),
                    CGPoint(x: center.x + 18 * scale, y: center.y - 20 * scale), CGPoint(x: center.x + 22 * scale, y: center.y - 20 * scale),
                ]),
                color: feature,
                lineWidth: 1.4 * scale,
                dash: []
            ))
        }
        return PetDrawingScene(operations: operations)
    }

    private static func eyeOperation(_ shape: PetEyeShape, center: CGPoint, scale: CGFloat, color: PetDrawingColor) -> PetDrawingOperation {
        let path = CGMutablePath()
        switch shape {
        case .dot:
            path.addEllipse(in: CGRect(x: center.x - 11 * scale, y: center.y - 3 * scale, width: 3.5 * scale, height: 4.5 * scale))
            path.addEllipse(in: CGRect(x: center.x + 7.5 * scale, y: center.y - 3 * scale, width: 3.5 * scale, height: 4.5 * scale))
            return .fill(path: path, color: color)
        case .line:
            return .stroke(
                path: linePath([
                    CGPoint(x: center.x - 11 * scale, y: center.y), CGPoint(x: center.x - 7 * scale, y: center.y),
                    CGPoint(x: center.x + 7 * scale, y: center.y), CGPoint(x: center.x + 11 * scale, y: center.y),
                ]),
                color: color,
                lineWidth: 1.8 * scale,
                dash: []
            )
        case .closed:
            path.move(to: CGPoint(x: center.x - 12 * scale, y: center.y - scale))
            path.addQuadCurve(to: CGPoint(x: center.x - 7 * scale, y: center.y - scale), control: CGPoint(x: center.x - 9.5 * scale, y: center.y + 2 * scale))
            path.move(to: CGPoint(x: center.x + 7 * scale, y: center.y - scale))
            path.addQuadCurve(to: CGPoint(x: center.x + 12 * scale, y: center.y - scale), control: CGPoint(x: center.x + 9.5 * scale, y: center.y + 2 * scale))
            return .stroke(path: path, color: color, lineWidth: 1.8 * scale, dash: [])
        }
    }

    private static func mouthPath(_ shape: PetMouthShape, center: CGPoint, scale: CGFloat) -> CGPath {
        let path = CGMutablePath()
        switch shape {
        case .smile:
            path.move(to: CGPoint(x: center.x - 6 * scale, y: center.y + 7 * scale))
            path.addQuadCurve(to: CGPoint(x: center.x + 6 * scale, y: center.y + 7 * scale), control: CGPoint(x: center.x, y: center.y + 12 * scale))
        case .flat:
            path.move(to: CGPoint(x: center.x - 5 * scale, y: center.y + 9 * scale))
            path.addLine(to: CGPoint(x: center.x + 5 * scale, y: center.y + 9 * scale))
        case .frown:
            path.move(to: CGPoint(x: center.x - 6 * scale, y: center.y + 11 * scale))
            path.addQuadCurve(to: CGPoint(x: center.x + 6 * scale, y: center.y + 11 * scale), control: CGPoint(x: center.x, y: center.y + 6 * scale))
        case .sleep:
            path.move(to: CGPoint(x: center.x - 4 * scale, y: center.y + 8 * scale))
            path.addQuadCurve(to: CGPoint(x: center.x + 4 * scale, y: center.y + 8 * scale), control: CGPoint(x: center.x, y: center.y + 10 * scale))
        }
        return path
    }

    private static func ellipse(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: rect)
        return path
    }

    private static func linePath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        for index in stride(from: 0, to: points.count, by: 2) {
            path.move(to: points[index])
            path.addLine(to: points[index + 1])
        }
        return path
    }

    private static func paletteColors(_ palette: PetPalette) -> (body: PetDrawingColor, ring: PetDrawingColor) {
        switch palette {
        case .mint: (.fixed(red: 0.29, green: 0.78, blue: 0.62, alpha: 1), .fixed(red: 0.10, green: 0.65, blue: 0.49, alpha: 1))
        case .clearBlue: (.fixed(red: 0.31, green: 0.66, blue: 0.91, alpha: 1), .fixed(red: 0.16, green: 0.50, blue: 0.83, alpha: 1))
        case .amber: (.fixed(red: 0.94, green: 0.64, blue: 0.23, alpha: 1), .fixed(red: 0.82, green: 0.42, blue: 0.08, alpha: 1))
        case .warningRed: (.fixed(red: 0.91, green: 0.31, blue: 0.29, alpha: 1), .fixed(red: 0.77, green: 0.16, blue: 0.16, alpha: 1))
        case .grayRed: (.fixed(red: 0.57, green: 0.39, blue: 0.41, alpha: 1), .fixed(red: 0.47, green: 0.24, blue: 0.27, alpha: 1))
        case .neutralGray: (.fixed(red: 0.50, green: 0.53, blue: 0.58, alpha: 1), .fixed(red: 0.36, green: 0.39, blue: 0.44, alpha: 1))
        }
    }
}

private extension PetDrawingColor {
    func withAlpha(_ alpha: CGFloat) -> PetDrawingColor {
        switch self {
        case let .fixed(red, green, blue, _): .fixed(red: red, green: green, blue: blue, alpha: alpha)
        case .label: .label(alpha: alpha)
        }
    }
}
