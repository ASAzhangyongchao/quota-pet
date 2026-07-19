import Foundation

struct QuotaRGBA: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

enum QuotaSemanticColor: Equatable {
    case used
    case remaining
    case track

    var rgba: QuotaRGBA {
        switch self {
        case .used:
            QuotaRGBA(red: 0.96, green: 0.39, blue: 0.24, alpha: 1)
        case .remaining:
            QuotaRGBA(red: 0.15, green: 0.88, blue: 0.68, alpha: 1)
        case .track:
            QuotaRGBA(red: 0.10, green: 0.13, blue: 0.16, alpha: 0.46)
        }
    }
}

enum QuotaHaloKind: Equatable {
    case ready
    case warning
    case depleted
    case unavailable
}

struct QuotaVisualStyle: Equatable {
    let usedFraction: Double?
    let remainingFraction: Double?
    let usedColor: QuotaSemanticColor
    let remainingColor: QuotaSemanticColor
    let haloKind: QuotaHaloKind
    let haloOpacity: Double
    let contentOpacity: Double

    init(snapshot: QuotaSnapshot, connectionMode: ConnectionMode) {
        usedColor = .used
        remainingColor = .remaining

        switch snapshot.state {
        case .loading, .unavailable, .incompatible:
            usedFraction = nil
            remainingFraction = nil
            haloKind = .unavailable
            contentOpacity = 1
            haloOpacity = Self.haloOpacity(base: 0.20, connectionMode: connectionMode)
        case .stale:
            usedFraction = snapshot.primary.map { Self.clampFraction($0.usedPercent / 100) }
            remainingFraction = snapshot.primary.map { Self.clampFraction($0.remainingPercent / 100) }
            haloKind = .unavailable
            contentOpacity = 0.55
            haloOpacity = Self.haloOpacity(base: 0.18, connectionMode: connectionMode)
        case .ready:
            guard let window = snapshot.primary else {
                usedFraction = nil
                remainingFraction = nil
                haloKind = .unavailable
                contentOpacity = 1
                haloOpacity = Self.haloOpacity(base: 0.20, connectionMode: connectionMode)
                return
            }
            usedFraction = Self.clampFraction(window.usedPercent / 100)
            remainingFraction = Self.clampFraction(window.remainingPercent / 100)
            haloKind = Self.haloKind(remainingPercent: window.remainingPercent)
            contentOpacity = 1
            haloOpacity = Self.haloOpacity(base: 0.34, connectionMode: connectionMode)
        }
    }

    private static func clampFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func haloKind(remainingPercent: Double) -> QuotaHaloKind {
        if remainingPercent <= 5 { return .depleted }
        if remainingPercent <= 20 { return .warning }
        return .ready
    }

    private static func haloOpacity(base: Double, connectionMode: ConnectionMode) -> Double {
        connectionMode == .energySaver ? base * 0.62 : base
    }
}
