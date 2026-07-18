import Foundation

struct RefreshPolicy {
    static let periodicRefreshInterval: TimeInterval = 10 * 60
    static let maximumRetryDelay: TimeInterval = 15 * 60
    private static let retryDelays: [TimeInterval] = [5, 30, 60, 300, 900]
    private var failures = 0

    mutating func recordFailure() -> TimeInterval {
        let delay = min(Self.retryDelays[min(failures, Self.retryDelays.count - 1)], Self.maximumRetryDelay)
        failures += 1
        return delay
    }

    mutating func record(snapshot: QuotaSnapshot) {
        guard snapshot.state == .ready, !snapshot.windows.isEmpty else { return }
        failures = 0
    }
}
