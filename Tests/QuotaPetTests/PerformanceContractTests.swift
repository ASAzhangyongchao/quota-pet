import Foundation
import XCTest

final class PerformanceContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPerformanceScriptUsesFormalDurationsAndTransactionalReportWrite() throws {
        let script = try contents(of: "scripts/measure-performance.sh")

        XCTAssertTrue(script.contains("FORMAL_WARMUP_SECONDS=300"))
        XCTAssertTrue(script.contains("FORMAL_SAMPLE_SECONDS=900"))
        XCTAssertTrue(script.contains("QUOTAPET_PERF_WARMUP_SECONDS"))
        XCTAssertTrue(script.contains("QUOTAPET_PERF_SAMPLE_SECONDS"))
        XCTAssertTrue(script.contains("QUOTAPET_PERF_REPORT"))
        XCTAssertTrue(script.contains("mktemp"))
        XCTAssertTrue(script.contains("mv --"))
        XCTAssertTrue(script.contains("NON-FORMAL TEST RUN"))
        XCTAssertFalse(script.contains("/Users/"))
    }

    func testPerformanceScriptPinsExactProcessScopeAndRequiredGates() throws {
        let script = try contents(of: "scripts/measure-performance.sh")
        let helper = try contents(of: "scripts/ProcessMetrics.swift")
        let implementation = script + helper

        XCTAssertTrue(implementation.contains("Contents/MacOS/QuotaPet"))
        XCTAssertTrue(implementation.contains("ppid"))
        XCTAssertTrue(implementation.contains("proc_pidpath"))
        XCTAssertFalse(script.contains("pkill"))
        XCTAssertFalse(script.contains("killall"))
        for threshold in ["80", "160", "0.2", "0.5", "5", "10"] {
            XCTAssertTrue(implementation.contains(threshold), "Missing performance threshold \(threshold)")
        }
    }

    func testPerformanceShellDelegatesAllStatisticsAndVerdictsToSwiftHelper() throws {
        let script = try contents(of: "scripts/measure-performance.sh")

        XCTAssertTrue(script.contains("\"$METRICS_HELPER\" report"))
        XCTAssertFalse(script.contains("stat_value"))
        XCTAssertFalse(script.contains("verdict()"))
        XCTAssertFalse(script.contains("value[rank]"))
    }

    func testPerformanceLaunchMatchesFinderAllocatorAndForcesRequestedModeWithoutPersistence() throws {
        let script = try contents(of: "scripts/measure-performance.sh")

        XCTAssertTrue(script.contains("RUN_MODE=\"${QUOTAPET_PERF_MODE:-realtime}\""))
        XCTAssertTrue(script.contains("/usr/bin/env -u MallocNanoZone"))
        XCTAssertTrue(script.contains("-QuotaPet.connectionMode"))
        XCTAssertTrue(script.contains("energySaver"))
        XCTAssertFalse(script.contains("defaults write"))
    }

    func testPerformanceUsesDisposableBundleAndConfirmedPreferenceDomain() throws {
        let script = try contents(of: "scripts/measure-performance.sh")

        XCTAssertTrue(script.contains("TEMP_ROOT_RAW=\"$(mktemp"))
        XCTAssertTrue(script.contains("TEMP_ROOT=\"$(cd -- \"$TEMP_ROOT_RAW\" && pwd -P)\""))
        XCTAssertTrue(script.contains("PERFORMANCE_APP=\"$TEMP_ROOT/QuotaPet.app\""))
        XCTAssertTrue(script.contains("cp -R -- \"$APP\" \"$PERFORMANCE_APP\""))
        XCTAssertTrue(script.contains("plutil -replace CFBundleIdentifier"))
        XCTAssertTrue(script.contains("codesign --force --deep --sign - \"$PERFORMANCE_APP\""))
        XCTAssertTrue(script.contains("PreparePerformancePreferences.swift"))
        XCTAssertTrue(script.contains("CodexExecutableResolver.swift"))
        XCTAssertTrue(script.contains("\"$PREFERENCES_HELPER\" prepare \"$PREFERENCES_SUITE\" \"$mode_argument\""))
        XCTAssertTrue(script.contains("\"$PREFERENCES_HELPER\" clear \"$PREFERENCES_SUITE\""))
        XCTAssertFalse(script.contains("CFPREFERENCES_AVOID_DAEMON"))
        XCTAssertFalse(script.contains("CFFIXED_USER_HOME"))
    }

    func testPreferencesHelperPinsOfficialCandidateAndPrintsNoSensitiveData() throws {
        let helper = try contents(of: "scripts/PreparePerformancePreferences.swift")

        for required in [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "com.openai.codex", "2DC432GLL2", "resolver.inspect", "resolver.confirm",
            "resolver.revalidate", "UserDefaults(suiteName:", "JSONEncoder", "QuotaPet.confirmedFingerprints",
            "QuotaPet.connectionMode", "print(\"ready\")",
        ] {
            XCTAssertTrue(helper.contains(required), "Missing preparation contract: \(required)")
        }
        for forbidden in ["account/read", "token", "stderr", "canonicalURL.path", "inputURL.path", "CFPREFERENCES_AVOID_DAEMON"] {
            XCTAssertFalse(helper.localizedCaseInsensitiveContains(forbidden), "Sensitive or unsupported helper output: \(forbidden)")
        }
    }

    func testCodexHashingUsesOneReusablePOSIXBuffer() throws {
        let resolver = try contents(of: "Sources/QuotaPet/Usage/CodexExecutableResolver.swift")

        XCTAssertTrue(resolver.contains("Darwin.read("))
        XCTAssertTrue(resolver.contains("hasher.update(bufferPointer:"))
        XCTAssertTrue(resolver.contains("UnsafeMutableRawPointer.allocate"))
        XCTAssertFalse(resolver.contains("handle.read(upToCount:"))
    }

    func testSettingsAndPopoverHostingAreDeferredUntilUserOpensThem() throws {
        let appDelegate = try contents(of: "Sources/QuotaPet/App/AppDelegate.swift")
        let statusItem = try contents(of: "Sources/QuotaPet/MenuBar/StatusItemController.swift")

        XCTAssertTrue(appDelegate.contains("DeferredConstruction"))
        XCTAssertTrue(appDelegate.contains("settingsController?.value.show()"))
        XCTAssertFalse(appDelegate.contains("settingsController = SettingsWindowController"))
        XCTAssertTrue(statusItem.contains("DeferredConstruction"))
        XCTAssertTrue(statusItem.contains("popoverContent.value"))
        XCTAssertFalse(statusItem.contains("configurePopover()"))
    }

    func testSwiftHelperReportsMedianAverageP95NAAndVerdicts() throws {
        let fixture = try MetricsFixture(repositoryRoot: repositoryRoot)
        defer { fixture.remove() }
        let csv = """
        sample,main_rss_mb,combined_rss_mb,main_footprint_mb,combined_footprint_mb,main_cpu_percent,combined_cpu_percent,main_wakeups_per_min,combined_wakeups_per_min,main_write_kb_per_sec,combined_write_kb_per_sec,child_count
        1,10,20,8,16,0.1,0.2,1,2,3,4,1
        2,20,40,18,36,0.2,0.3,2,4,5,6,1
        3,30,60,28,56,0.3,0.4,3,6,7,8,1
        """
        try csv.write(to: fixture.csvURL, atomically: true, encoding: .utf8)

        let result = try fixture.runReport()

        XCTAssertEqual(result.status, 0, result.error)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "PASS")
        let report = try String(contentsOf: fixture.reportURL, encoding: .utf8)
        XCTAssertTrue(report.contains("| RSS (MB) | QuotaPet main | 20.000 | 20.000 | 30.000 | median <= 80 | PASS |"))
        XCTAssertTrue(report.contains("| RSS (MB) | Direct Codex child | 20.000 | 20.000 | 30.000 | N/A | N/A |"))
        XCTAssertTrue(report.contains("| Physical footprint (MB) | QuotaPet main | 18.000 | 18.000 | 28.000 | N/A | N/A |"))
        XCTAssertTrue(report.contains("| RSS (MB) | Main + direct Codex | 40.000 | 40.000 | 60.000 | median <= 160 | PASS |"))
        XCTAssertTrue(report.contains("| CPU (% single core) | QuotaPet main | 0.200 | 0.200 | 0.300 | average <= 0.2 | PASS |"))
        XCTAssertTrue(report.contains("| Interrupt wakeups/min | Direct Codex child | 2.000 | 2.000 | 3.000 | N/A | N/A |"))
        XCTAssertTrue(report.contains("| Write I/O (KiB/s) | QuotaPet main | 5.000 | 5.000 | 7.000 | N/A | N/A |"))
        XCTAssertTrue(report.contains("Complete samples: 3"))
        XCTAssertTrue(report.contains("Samples with direct Codex child: 3"))
    }

    func testFormalEnergySavingReportRequiresAtLeastOneChildSample() throws {
        let fixture = try MetricsFixture(repositoryRoot: repositoryRoot)
        defer { fixture.remove() }
        let csv = """
        sample,main_rss_mb,combined_rss_mb,main_footprint_mb,combined_footprint_mb,main_cpu_percent,combined_cpu_percent,main_wakeups_per_min,combined_wakeups_per_min,main_write_kb_per_sec,combined_write_kb_per_sec,child_count
        1,10,10,8,8,0.1,0.1,1,1,0,0,0
        """
        try csv.write(to: fixture.csvURL, atomically: true, encoding: .utf8)

        let result = try fixture.runReport(mode: "energy-saving")

        XCTAssertEqual(result.status, 0, result.error)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "FAIL")
        let report = try String(contentsOf: fixture.reportURL, encoding: .utf8)
        XCTAssertTrue(report.contains("Samples with direct Codex child: 0"))
        XCTAssertTrue(report.contains("Direct child coverage gate: FAIL"))
    }

    func testSwiftHelperIncludesOneDirectCodexChild() throws {
        let fixture = try MetricsFixture(repositoryRoot: repositoryRoot)
        let processFixture = try DirectChildProcessFixture()
        defer {
            processFixture.remove()
            fixture.remove()
        }
        try processFixture.start()
        defer { processFixture.stop() }
        Thread.sleep(forTimeInterval: 0.2)

        let result = try fixture.runSample(
            mainPID: processFixture.processIdentifier,
            executablePath: processFixture.executableURL.path
        )

        XCTAssertEqual(result.status, 0, result.error)
        let lines = result.output.split(whereSeparator: \Character.isNewline)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.last?.split(separator: ",").last, "1")
    }

    func testSwiftHelperTreatsProcessListResultAsPIDCount() throws {
        let helper = try contents(of: "scripts/ProcessMetrics.swift")

        XCTAssertTrue(helper.contains("let count = proc_listallpids"))
        XCTAssertTrue(helper.contains("pids.prefix(Int(count))"))
        XCTAssertFalse(helper.contains("Int(bytes) / MemoryLayout<pid_t>.size"))
    }

    func testSwiftHelperRejectsInvalidCSVRowWithoutWritingReport() throws {
        let fixture = try MetricsFixture(repositoryRoot: repositoryRoot)
        defer { fixture.remove() }
        try "sample,main_rss_mb\n1,not-a-number\n".write(to: fixture.csvURL, atomically: true, encoding: .utf8)

        let result = try fixture.runReport()

        XCTAssertNotEqual(result.status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.reportURL.path))
        XCTAssertFalse(result.error.contains(fixture.root.path))
    }

    func testPerformanceBaselineDocumentsMethodsAndLimitations() throws {
        let baseline = try contents(of: "docs/performance-baseline.md")

        for required in [
            "5-minute warm-up", "15-minute sample", "RSS", "CPU", "wakeups", "write I/O",
            "median", "average", "P95", "direct child", "N/A", "realtime", "energy-saving", "67.938", "control",
        ] {
            XCTAssertTrue(baseline.localizedCaseInsensitiveContains(required), "Missing baseline field: \(required)")
        }
        XCTAssertFalse(baseline.contains("/Users/"))
    }

    private func contents(of path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }
}

private final class MetricsFixture {
    let root: URL
    let csvURL: URL
    let reportURL: URL
    private let helperURL: URL

    init(repositoryRoot: URL) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("QuotaPet-metrics-tests-\(UUID().uuidString)")
        csvURL = root.appendingPathComponent("samples.csv")
        reportURL = root.appendingPathComponent("report.md")
        helperURL = root.appendingPathComponent("ProcessMetrics")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = [
            "swiftc", "-O",
            repositoryRoot.appendingPathComponent("scripts/ProcessMetrics.swift").path,
            "-o", helperURL.path,
        ]
        let error = Pipe()
        compile.standardOutput = Pipe()
        compile.standardError = error
        try compile.run()
        compile.waitUntilExit()
        guard compile.terminationStatus == 0 else {
            throw NSError(
                domain: "MetricsFixture",
                code: Int(compile.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)]
            )
        }
    }

    func runReport(mode: String = "realtime") throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = helperURL
        process.arguments = [
            "report", csvURL.path, reportURL.path, "Formal baseline", mode,
            "TestMac", "13.0", "1.0.0", "300", "900", "1",
        ]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    func runSample(mainPID: Int32, executablePath: String) throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["sample", String(mainPID), executablePath, "1", "1"]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class DirectChildProcessFixture {
    let root: URL
    let executableURL: URL
    private let childURL: URL
    private let process = Process()

    var processIdentifier: Int32 { process.processIdentifier }

    init() throws {
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("QuotaPet-child-metrics-tests-\(UUID().uuidString)")
        executableURL = root.appendingPathComponent("FixtureParent")
        childURL = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let childSourceURL = root.appendingPathComponent("FixtureChild.swift")
        try "import Foundation\nThread.sleep(forTimeInterval: 10)\n"
            .write(to: childSourceURL, atomically: true, encoding: .utf8)
        try Self.compile(sourceURL: childSourceURL, outputURL: childURL)
        let sourceURL = root.appendingPathComponent("FixtureParent.swift")
        let source = """
        import Foundation
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        child.arguments = ["10"]
        try child.run()
        Thread.sleep(forTimeInterval: 10)
        if child.isRunning { child.terminate() }
        child.waitUntilExit()
        """
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        try Self.compile(sourceURL: sourceURL, outputURL: executableURL)
    }

    private static func compile(sourceURL: URL, outputURL: URL) throws {
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["swiftc", "-O", sourceURL.path, "-o", outputURL.path]
        let error = Pipe()
        compile.standardOutput = Pipe()
        compile.standardError = error
        try compile.run()
        compile.waitUntilExit()
        guard compile.terminationStatus == 0 else {
            throw NSError(
                domain: "DirectChildProcessFixture",
                code: Int(compile.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)]
            )
        }
    }

    func start() throws {
        process.executableURL = executableURL
        process.arguments = [childURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
