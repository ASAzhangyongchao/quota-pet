import Foundation

private enum PreparationError: Error {
    case invalidArguments
    case invalidSuite
    case invalidMode
    case trustedCandidateUnavailable
    case persistenceFailed
}

@main
private enum PreparePerformancePreferences {
    private static let suitePrefix = "io.github.asazhangyongchao.quotapet.performance."
    private static let signingIdentifier = "com.openai.codex"
    private static let teamIdentifier = "2DC432GLL2"

    static func main() {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 3 else { throw PreparationError.invalidArguments }
            let action = arguments[1]
            let suite = arguments[2]
            try validate(suite: suite)
            switch action {
            case "prepare":
                guard arguments.count == 4 else { throw PreparationError.invalidArguments }
                try prepare(suite: suite, mode: arguments[3])
                print("ready")
            case "clear":
                guard arguments.count == 3 else { throw PreparationError.invalidArguments }
                clear(suite: suite)
            default:
                throw PreparationError.invalidArguments
            }
        } catch {
            FileHandle.standardError.write(Data("Performance preference preparation failed.\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func validate(suite: String) throws {
        let suffix = suite.dropFirst(suitePrefix.count)
        guard suite.hasPrefix(suitePrefix), !suffix.isEmpty, suite.utf8.count <= 128,
              suffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else { throw PreparationError.invalidSuite }
    }

    private static func prepare(suite: String, mode: String) throws {
        guard mode == "realtime" || mode == "energySaver" else { throw PreparationError.invalidMode }
        let resolver = CodexExecutableResolver()
        let inspector = CodexStaticExecutableInspector()
        let inputs = [
            ExecutablePathInput(
                url: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
                source: .chatGPTBundle
            ),
            ExecutablePathInput(
                url: URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
                source: .codexBundle
            ),
        ]

        var trustedCandidate: ExecutableCandidate?
        for input in inputs where FileManager.default.fileExists(atPath: input.url.path) {
            guard let staticInspection = try? inspector.inspect(url: input.url, source: input.source),
                  staticInspection.signatureIsValid,
                  staticInspection.bundleIdentifier == signingIdentifier,
                  staticInspection.candidate.signingIdentifier == signingIdentifier,
                  staticInspection.candidate.teamIdentifier == teamIdentifier,
                  case let .accepted(candidate, _)? = resolver.inspect([input]).first,
                  resolver.confirm(candidate),
                  resolver.revalidate(candidate)
            else { continue }
            trustedCandidate = candidate
            break
        }
        guard let trustedCandidate else { throw PreparationError.trustedCandidateUnavailable }

        let defaults = UserDefaults(suiteName: suite)
        guard let defaults else { throw PreparationError.persistenceFailed }
        defaults.removePersistentDomain(forName: suite)
        defaults.set(mode, forKey: "QuotaPet.connectionMode")
        defaults.set(true, forKey: "QuotaPet.petVisible")
        defaults.set(true, forKey: "QuotaPet.alwaysOnTop")
        defaults.set(false, forKey: "QuotaPet.ignoresMouseEvents")
        defaults.set(false, forKey: "QuotaPet.notificationsEnabled")
        defaults.set(false, forKey: "QuotaPet.launchAtLoginEnabled")
        defaults.set(
            try JSONEncoder().encode(Set([TrustFingerprint(candidate: trustedCandidate)])),
            forKey: "QuotaPet.confirmedFingerprints"
        )
        guard defaults.synchronize() else { throw PreparationError.persistenceFailed }
    }

    private static func clear(suite: String) {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        UserDefaults.standard.synchronize()
    }
}
