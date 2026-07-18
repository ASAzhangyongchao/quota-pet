import Foundation

enum ConnectionState: Equatable {
    case loading
    case ready
    case stale(String)
    case unavailable(String)
    case incompatible(String)
}

struct QuotaWindow: Equatable, Identifiable {
    let id: String
    let bucketID: String
    let displayName: String
    let usedPercent: Double
    let remainingPercent: Double
    let windowDurationMinutes: Int
    let resetsAt: Date?
    let isReached: Bool
}

struct QuotaSnapshot: Equatable {
    let planType: String?
    let windows: [QuotaWindow]
    let updatedAt: Date
    let state: ConnectionState

    var primary: QuotaWindow? {
        let codexWindows = windows.filter { $0.bucketID == "codex" }
        return (codexWindows.isEmpty ? windows : codexWindows)
            .max { $0.usedPercent < $1.usedPercent }
    }
}
