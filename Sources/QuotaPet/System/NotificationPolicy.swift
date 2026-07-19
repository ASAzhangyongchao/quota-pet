import Foundation
import UserNotifications

struct QuotaNotification: Equatable {
    let bucketID: String
    let resetsAt: Date
    let threshold: Int
}

struct NotificationPolicy {
    static let storageKey = "QuotaPet.notificationPolicy"

    private struct Record: Codable {
        let bucketID: String
        let resetsAt: Date
        var thresholdMask: UInt8
    }

    private static let thresholds = [20, 10, 0]
    private let store: any AppPreferenceStoring
    private var records: [Record]

    init(store: any AppPreferenceStoring = UserDefaults.standard) {
        self.store = store
        if let data = store.object(forKey: Self.storageKey) as? Data,
           let decoded = try? JSONDecoder().decode([Record].self, from: data)
        {
            records = decoded
        } else {
            records = []
        }
    }

    mutating func evaluate(_ snapshot: QuotaSnapshot, now: Date = .now) -> QuotaNotification? {
        guard snapshot.state == .ready else { return nil }

        var changed = removeExpiredRecords(now: now)
        var candidates: [QuotaNotification] = []
        for window in snapshot.windows.sorted(by: Self.stableWindowOrder) {
            guard let resetsAt = window.resetsAt, resetsAt > now, window.remainingPercent.isFinite else { continue }
            let crossedMask = Self.crossedMask(remainingPercent: window.remainingPercent)
            guard crossedMask != 0 else { continue }

            let index = records.firstIndex { $0.bucketID == window.bucketID && $0.resetsAt == resetsAt }
            let previousMask = index.map { records[$0].thresholdMask } ?? 0
            let newMask = crossedMask & ~previousMask
            guard newMask != 0 else { continue }

            if let index {
                records[index].thresholdMask |= crossedMask
            } else {
                records.append(Record(bucketID: window.bucketID, resetsAt: resetsAt, thresholdMask: crossedMask))
            }
            changed = true

            if let threshold = Self.mostUrgentThreshold(in: newMask) {
                candidates.append(QuotaNotification(bucketID: window.bucketID, resetsAt: resetsAt, threshold: threshold))
            }
        }

        if changed { persist() }
        return candidates.min {
            if $0.threshold != $1.threshold { return $0.threshold < $1.threshold }
            if $0.bucketID != $1.bucketID { return $0.bucketID < $1.bucketID }
            return $0.resetsAt < $1.resetsAt
        }
    }

    private mutating func removeExpiredRecords(now: Date) -> Bool {
        let previousCount = records.count
        records.removeAll { $0.resetsAt <= now }
        return records.count != previousCount
    }

    private func persist() {
        store.set(try? JSONEncoder().encode(records), forKey: Self.storageKey)
    }

    private static func crossedMask(remainingPercent: Double) -> UInt8 {
        thresholds.enumerated().reduce(0) { mask, item in
            remainingPercent <= Double(item.element) ? mask | (1 << item.offset) : mask
        }
    }

    private static func mostUrgentThreshold(in mask: UInt8) -> Int? {
        thresholds.enumerated().reversed().first { mask & (1 << $0.offset) != 0 }?.element
    }

    private static func stableWindowOrder(_ lhs: QuotaWindow, _ rhs: QuotaWindow) -> Bool {
        if lhs.bucketID != rhs.bucketID { return lhs.bucketID < rhs.bucketID }
        return (lhs.resetsAt ?? .distantPast) < (rhs.resetsAt ?? .distantPast)
    }
}

@MainActor
final class LocalNotificationController {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(_ notification: QuotaNotification) {
        let content = UNMutableNotificationContent()
        content.title = "QuotaPet 用量提醒"
        if notification.threshold == 0 {
            content.body = "本地读取的剩余额度已用尽。"
        } else {
            content.body = "本地读取的剩余额度已降至 \(notification.threshold)% 或以下。"
        }
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
