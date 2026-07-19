import Foundation

protocol UsageProvider: AnyObject {
    var snapshots: AsyncStream<QuotaSnapshot> { get }
    func start(mode: ConnectionMode) async
    func refresh() async
    func recover(mode: ConnectionMode, restartIfStopped: Bool) async
    func stop() async
}

enum ConnectionMode: String, Codable {
    case realtime
    case energySaver
}

protocol UsageScheduledTask: AnyObject {
    func cancel()
}

protocol UsageScheduling: AnyObject {
    func schedule(after: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any UsageScheduledTask
}

final class DispatchUsageScheduler: UsageScheduling {
    func schedule(after: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any UsageScheduledTask {
        let task = DispatchWorkItem(block: action)
        DispatchQueue.global().asyncAfter(deadline: .now() + after, execute: task)
        return task
    }
}

extension DispatchWorkItem: UsageScheduledTask {}
