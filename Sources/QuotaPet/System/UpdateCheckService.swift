import Foundation

enum UpdateCheckOutcome: Equatable, Sendable {
    case upToDate(remote: AppVersion)
    case updateAvailable(version: AppVersion, releaseURL: URL)
    case noPublicRelease
    case failed
}

enum GitHubReleasesAtomParser {
    /// Parses the first Atom `<entry>` from GitHub's `releases.atom`.
    /// Empty feeds (no entries) mean no published releases.
    static func latestRelease(from data: Data) -> (version: AppVersion, htmlURL: URL)? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        guard let entryStart = xml.range(of: "<entry>") else { return nil }
        let fromEntry = xml[entryStart.lowerBound...]
        guard let entryEnd = fromEntry.range(of: "</entry>") else { return nil }
        let entry = String(fromEntry[..<entryEnd.upperBound])

        guard let href = firstCapture(
            in: entry,
            pattern: #"href="(https://github\.com/[^"]+/releases/tag/[^"]+)""#
        ), let url = URL(string: href), url.scheme == "https" else {
            return nil
        }

        let tag: String
        if let pathTag = url.path.split(separator: "/").last.map(String.init), !pathTag.isEmpty {
            tag = pathTag
        } else if let title = firstCapture(in: entry, pattern: #"<title[^>]*>([^<]+)</title>"#) {
            tag = title.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil
        }

        guard let version = AppVersion.parse(tag) else { return nil }
        return (version, url)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2,
              let capture = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[capture])
    }
}

enum UpdateCheckEvaluator {
    static func outcome(
        currentMarketingVersion: String,
        statusCode: Int,
        data: Data?
    ) -> UpdateCheckOutcome {
        guard let current = AppVersion.parse(currentMarketingVersion) else { return .failed }
        if statusCode == 404 { return .noPublicRelease }
        guard (200..<300).contains(statusCode), let data else { return .failed }

        // Prefer Atom (no unauthenticated API rate limit). Empty feed => no releases yet.
        if let remote = GitHubReleasesAtomParser.latestRelease(from: data) {
            if remote.version > current {
                return .updateAvailable(version: remote.version, releaseURL: remote.htmlURL)
            }
            return .upToDate(remote: remote.version)
        }

        if let xml = String(data: data, encoding: .utf8),
           xml.contains("<feed"),
           !xml.contains("<entry>")
        {
            return .noPublicRelease
        }

        // Legacy JSON decode kept for tests / optional API responses.
        if let release = try? JSONDecoder().decode(GitHubLatestReleaseDTO.self, from: data) {
            guard let remote = AppVersion.parse(release.tagName),
                  let url = URL(string: release.htmlURL),
                  url.scheme == "https"
            else {
                return .failed
            }
            if remote > current {
                return .updateAvailable(version: remote, releaseURL: url)
            }
            return .upToDate(remote: remote)
        }

        if let body = String(data: data, encoding: .utf8),
           body.localizedCaseInsensitiveContains("rate limit exceeded")
        {
            return .failed
        }

        return .failed
    }
}

struct GitHubLatestReleaseDTO: Decodable, Equatable, Sendable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

struct UpdateCheckService: Sendable {
    /// Prefer the public Atom feed over `api.github.com` so unauthenticated clients
    /// are not blocked by the 60 req/hour REST rate limit (which surfaces as HTTP 403).
    static let releasesAtomURL = URL(string: "https://github.com/ASAzhangyongchao/quota-pet/releases.atom")!
    static let releasesPageURL = URL(string: "https://github.com/ASAzhangyongchao/quota-pet/releases")!

    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let currentMarketingVersion: String
    private let load: DataLoader

    init(
        currentMarketingVersion: String,
        load: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.currentMarketingVersion = currentMarketingVersion
        self.load = load
    }

    func check() async -> UpdateCheckOutcome {
        var request = URLRequest(url: Self.releasesAtomURL)
        request.setValue(
            "QuotaPet-macOS/\(currentMarketingVersion) (+https://github.com/ASAzhangyongchao/quota-pet)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/atom+xml, application/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await load(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return UpdateCheckEvaluator.outcome(
                currentMarketingVersion: currentMarketingVersion,
                statusCode: status,
                data: data
            )
        } catch {
            return .failed
        }
    }
}
