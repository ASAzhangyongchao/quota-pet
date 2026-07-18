import Foundation
import CoreFoundation

enum QuotaParserError: Error, Equatable {
    case invalidJSON
}

enum QuotaParser {
    private static let maximumBuckets = 128
    private static let maximumStringScalars = 256

    static func parse(data: Data, updatedAt: Date = Date()) throws -> QuotaSnapshot {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw QuotaParserError.invalidJSON
        }

        guard let root = object as? [String: Any] else {
            throw QuotaParserError.invalidJSON
        }

        let planType = string(in: root, keys: ["planType", "plan_type"]).map(bound)
        let parsedWindows = bucketMaps(in: root)
            .lazy
            .map(parseWindows(in:))
            .first(where: { !$0.isEmpty }) ?? []

        let state: ConnectionState = parsedWindows.isEmpty
            ? .unavailable("未返回 Codex 用量窗口")
            : .ready
        return QuotaSnapshot(planType: planType, windows: parsedWindows, updatedAt: updatedAt, state: state)
    }

    private static func parseWindows(in buckets: [String: [String: Any]]) -> [QuotaWindow] {
        let orderedBucketIDs = buckets.keys.sorted { lhs, rhs in
            if lhs == "codex" { return rhs != "codex" }
            if rhs == "codex" { return false }
            return lhs < rhs
        }

        let parsedWindows = orderedBucketIDs.prefix(maximumBuckets).flatMap { bucketID in
            windows(in: buckets[bucketID] ?? [:], bucketID: bound(bucketID))
        }
        return parsedWindows
    }

    private static func bucketMaps(in root: [String: Any]) -> [[String: [String: Any]]] {
        let keys = ["rateLimitsByLimitId", "rate_limits_by_limit_id", "rateLimits", "rate_limits"]
        return keys.compactMap { key in
            guard let rawBuckets = root[key] as? [String: Any] else { return nil }
            return rawBuckets.compactMapValues { $0 as? [String: Any] }
        }
    }

    private static func windows(in bucket: [String: Any], bucketID: String) -> [QuotaWindow] {
        if isWindow(bucket) {
            return [window(in: bucket, bucketID: bucketID, role: "primary")].compactMap { $0 }
        }

        let knownRoles = ["primary", "secondary"]
        return knownRoles.compactMap { role in
            guard let rawWindow = bucket[role] as? [String: Any] else { return nil }
            return window(in: rawWindow, bucketID: bucketID, role: role)
        }
    }

    private static func window(in object: [String: Any], bucketID: String, role: String) -> QuotaWindow? {
        guard
            let rawUsedPercent = number(in: object, keys: ["usedPercent", "used_percent"])
        else {
            return nil
        }

        let windowDurationMinutes = integer(in: object, keys: ["windowDurationMinutes", "window_duration_mins"])
        guard windowDurationMinutes.map({ $0 > 0 }) ?? true else { return nil }
        let usedPercent = min(max(rawUsedPercent, 0), 100)
        let displayName = string(in: object, keys: ["displayName", "display_name"]).map(bound) ?? bound(role)
        let resetsAt = number(in: object, keys: ["resetsAt", "resets_at"])
            .map(Date.init(timeIntervalSince1970:))
        let boundedRole = bound(role)
        let resetComponent = resetsAt.map { String($0.timeIntervalSince1970) } ?? "none"
        let durationComponent = windowDurationMinutes.map(String.init) ?? "none"
        let id = "\(bucketID)|\(boundedRole)|\(durationComponent)|\(resetComponent)"

        return QuotaWindow(
            id: id,
            bucketID: bucketID,
            displayName: displayName,
            usedPercent: usedPercent,
            remainingPercent: 100 - usedPercent,
            windowDurationMinutes: windowDurationMinutes,
            resetsAt: resetsAt,
            isReached: usedPercent >= 100
        )
    }

    private static func isWindow(_ object: [String: Any]) -> Bool {
        number(in: object, keys: ["usedPercent", "used_percent"]) != nil
            || integer(in: object, keys: ["windowDurationMinutes", "window_duration_mins"]) != nil
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        keys.lazy.compactMap { object[$0] as? String }.first
    }

    private static func number(in object: [String: Any], keys: [String]) -> Double? {
        keys.compactMap { numericValue(object[$0]) }.first.map { $0.doubleValue }
    }

    private static func integer(in object: [String: Any], keys: [String]) -> Int? {
        keys.lazy.compactMap { numericValue(object[$0]) }.first.flatMap { number in
            let value = number.doubleValue
            guard value.isFinite, value.rounded() == value else { return nil }
            return Int(exactly: value)
        }
    }

    private static func numericValue(_ value: Any?) -> NSNumber? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        return number
    }

    private static func bound(_ value: String) -> String {
        String(value.unicodeScalars.prefix(maximumStringScalars))
    }
}
