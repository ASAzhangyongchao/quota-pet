import Foundation

struct AppVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    var displayString: String { "\(major).\(minor).\(patch)" }

    static func parse(_ raw: String) -> AppVersion? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first.map({ $0 == "v" || $0 == "V" }) == true {
            value.removeFirst()
        }
        let core = value.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? value
        let parts = core.split(separator: ".").map(String.init)
        guard (1...3).contains(parts.count), let major = Int(parts[0]), major >= 0 else { return nil }
        let minor: Int
        let patch: Int
        if parts.count > 1 {
            guard let parsedMinor = Int(parts[1]), parsedMinor >= 0 else { return nil }
            minor = parsedMinor
        } else {
            minor = 0
        }
        if parts.count > 2 {
            guard let parsedPatch = Int(parts[2]), parsedPatch >= 0 else { return nil }
            patch = parsedPatch
        } else {
            patch = 0
        }
        return AppVersion(major: major, minor: minor, patch: patch)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AppVersionInfo: Equatable, Sendable {
    let marketing: String
    let build: String

    var displayLabel: String { "\(marketing) (\(build))" }

    static func fromBundle(_ bundle: Bundle = .main) -> AppVersionInfo {
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return AppVersionInfo(marketing: marketing, build: build)
    }
}
