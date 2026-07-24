import Foundation

/// GUI apps often inherit a short PATH; merge login-shell and common install dirs for Codex discovery.
enum CodexDiscoveryPATH {
    private static let lock = NSLock()
    private static var cachedLoginPATH: String?

    static func merged(
        processPATH: String?,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        loginPATHProvider: () -> String? = { readLoginShellPATH() }
    ) -> String {
        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let raw, !raw.isEmpty else { return }
            for part in raw.split(separator: ":", omittingEmptySubsequences: true) {
                let directory = String(part)
                guard seen.insert(directory).inserted else { continue }
                ordered.append(directory)
            }
        }

        append(processPATH)
        append(loginPATHProvider())
        append([
            "/opt/homebrew/bin",
            "/usr/local/bin",
            homeDirectory.appendingPathComponent(".local/bin").path,
        ].joined(separator: ":"))
        append(nvmBinDirectories(homeDirectory: homeDirectory).joined(separator: ":"))
        return ordered.joined(separator: ":")
    }

    static func resetLoginPATHCacheForTests() {
        lock.lock()
        defer { lock.unlock() }
        cachedLoginPATH = nil
    }

    private static func nvmBinDirectories(homeDirectory: URL) -> [String] {
        let versions = homeDirectory.appendingPathComponent(".nvm/versions/node")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: versions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .map { $0.appendingPathComponent("bin").path }
            .sorted()
            .suffix(6)
            .map { $0 }
    }

    private static func readLoginShellPATH() -> String? {
        lock.lock()
        if let cachedLoginPATH {
            lock.unlock()
            return cachedLoginPATH
        }
        lock.unlock()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            // Avoid hanging the settings UI if the login shell is slow.
            let deadline = Date().addingTimeInterval(1.5)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, !value.isEmpty else { return nil }
            lock.lock()
            cachedLoginPATH = value
            lock.unlock()
            return value
        } catch {
            return nil
        }
    }
}
