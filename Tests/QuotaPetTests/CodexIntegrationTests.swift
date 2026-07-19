import Darwin
import Foundation
import XCTest
@testable import QuotaPet

final class CodexIntegrationTests: XCTestCase {
    func testDirectChildEnumerationIncludesOneProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        let expectedPath = try XCTUnwrap(executablePath(for: process.processIdentifier))

        XCTAssertTrue(directChildExecutablePaths().contains(expectedPath))
    }

    func testTrustedOfficialCodexHandshakeAndRateLimitsRead() async throws {
        guard ProcessInfo.processInfo.environment["QUOTAPET_CODEX_INTEGRATION"] == "1" else {
            throw XCTSkip("Set QUOTAPET_CODEX_INTEGRATION=1 to run the read-only Codex integration test")
        }

        let resolver = CodexExecutableResolver()
        let candidate = trustedCandidate(using: resolver)
        guard let candidate else {
            throw XCTSkip("No safe Codex app-bundle candidate is installed")
        }
        guard resolver.revalidate(candidate) else {
            XCTFail("The trusted Codex executable changed before launch")
            return
        }

        let provider = CodexAppServerStdioProvider(
            candidate: candidate,
            resolver: resolver,
            sessionFactory: FoundationCodexAppServerSessionFactory(),
            requestTimeout: 20
        )

        do {
            async let snapshot = firstReadySnapshot(from: provider.snapshots, timeout: 30)
            await provider.start(mode: .energySaver)
            let ready = try await snapshot
            XCTAssertFalse(ready.windows.isEmpty)
            for window in ready.windows {
                XCTAssertTrue((0 ... 100).contains(window.usedPercent))
                XCTAssertTrue((0 ... 100).contains(window.remainingPercent))
                XCTAssertEqual(window.usedPercent + window.remainingPercent, 100, accuracy: 0.000_001)
                print(sanitizedLine(for: window))
            }
        } catch {
            await provider.stop()
            throw error
        }

        await provider.stop()
        XCTAssertTrue(
            waitUntilNoDirectChild(executablePath: candidate.canonicalURL.path, timeout: 3),
            "Codex app-server child remained after provider shutdown"
        )
    }

    private func trustedCandidate(using resolver: CodexExecutableResolver) -> ExecutableCandidate? {
        for resolution in resolver.resolve() {
            guard case let .accepted(candidate, trust) = resolution,
                  candidate.source == .chatGPTBundle || candidate.source == .codexBundle
            else { continue }
            switch trust {
            case .bundleAllowList, .confirmed:
                if resolver.revalidate(candidate) { return candidate }
            case .requiresConfirmation:
                if resolver.confirm(candidate), resolver.revalidate(candidate) { return candidate }
            }
        }
        return nil
    }

    private func firstReadySnapshot(
        from stream: AsyncStream<QuotaSnapshot>,
        timeout: TimeInterval
    ) async throws -> QuotaSnapshot {
        try await withThrowingTaskGroup(of: QuotaSnapshot.self) { group in
            group.addTask {
                for await snapshot in stream {
                    if snapshot.state == .ready { return snapshot }
                    switch snapshot.state {
                    case let .incompatible(message), let .unavailable(message), let .stale(message):
                        throw IntegrationFailure(message: message)
                    case .loading, .ready:
                        break
                    }
                }
                throw IntegrationFailure(message: "Usage stream ended before a ready snapshot")
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw IntegrationFailure(message: "Timed out waiting for a rate-limit snapshot")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func sanitizedLine(for window: QuotaWindow) -> String {
        let reset = window.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "N/A"
        return String(
            format: "used=%.3f remaining=%.3f resetsAt=%@",
            window.usedPercent,
            window.remainingPercent,
            reset
        )
    }

    private func waitUntilNoDirectChild(executablePath: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !directChildExecutablePaths().contains(executablePath) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return !directChildExecutablePaths().contains(executablePath)
    }

    private func directChildExecutablePaths() -> [String] {
        var children = [pid_t](repeating: 0, count: 64)
        let count = proc_listchildpids(getpid(), &children, Int32(children.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return children.prefix(Int(count)).compactMap(executablePath(for:))
    }

    private func executablePath(for pid: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return String(cString: path)
    }
}

private struct IntegrationFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
