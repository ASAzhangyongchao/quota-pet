import SwiftUI

struct QuotaSplitMeter: View {
    let usedFraction: Double
    let remainingFraction: Double
    let accessibilityText: String

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(QuotaSemanticColor.track.swiftUIColor)
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(QuotaSemanticColor.used.swiftUIColor)
                        .frame(width: width * clamped(usedFraction))
                    Rectangle()
                        .fill(QuotaSemanticColor.remaining.swiftUIColor)
                        .frame(width: width * clamped(remainingFraction))
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
        .transaction { transaction in transaction.animation = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func clamped(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0), 1))
    }
}

private extension QuotaSemanticColor {
    var swiftUIColor: Color {
        let color = rgba
        return Color(
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.alpha
        )
    }
}
