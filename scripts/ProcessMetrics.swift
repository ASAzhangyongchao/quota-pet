import Darwin
import Foundation

private struct Counters {
    let residentBytes: UInt64
    let physicalFootprintBytes: UInt64
    let cpuNanoseconds: UInt64
    let interruptWakeups: UInt64
    let bytesWritten: UInt64
}

private enum MetricsError: Error {
    case invalidArguments
    case processUnavailable
    case processIdentityChanged
    case invalidCSV
}

private struct Statistics {
    let median: Double
    let average: Double
    let p95: Double
}

private struct ReportMetric {
    enum ValueSource {
        case column(Int)
        case difference(combined: Int, main: Int)
    }

    enum Gate {
        case median(Double)
        case average(Double)
        case none
    }

    let name: String
    let scope: String
    let source: ValueSource
    let gate: Gate
}

private func executablePath(for pid: pid_t) -> String? {
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
    return String(cString: path)
}

private func childPIDs(of parentPID: pid_t) -> [pid_t] {
    var children = [pid_t](repeating: 0, count: 256)
    let count = proc_listchildpids(parentPID, &children, Int32(children.count * MemoryLayout<pid_t>.size))
    guard count > 0 else { return [] }
    return Array(children.prefix(Int(count)))
}

private func counters(for pid: pid_t) throws -> Counters {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        proc_pid_rusage(
            pid,
            RUSAGE_INFO_V4,
            UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self)
        )
    }
    guard result == 0 else { throw MetricsError.processUnavailable }
    return Counters(
        residentBytes: info.ri_resident_size,
        physicalFootprintBytes: info.ri_phys_footprint,
        cpuNanoseconds: info.ri_user_time + info.ri_system_time,
        interruptWakeups: info.ri_interrupt_wkups,
        bytesWritten: info.ri_diskio_byteswritten
    )
}

private func scopedCounters(mainPID: pid_t, expectedMainPath: String) throws -> [pid_t: Counters] {
    guard executablePath(for: mainPID) == expectedMainPath else {
        throw MetricsError.processIdentityChanged
    }
    var result = [mainPID: try counters(for: mainPID)]
    for pid in childPIDs(of: mainPID) {
        guard let path = executablePath(for: pid), URL(fileURLWithPath: path).lastPathComponent == "codex" else {
            continue
        }
        if let value = try? counters(for: pid) {
            result[pid] = value
        }
    }
    return result
}

private func delta(_ current: UInt64, _ previous: UInt64?) -> UInt64 {
    guard let previous else { return current }
    return current >= previous ? current - previous : 0
}

private func metricDelta(
    current: [pid_t: Counters],
    previous: [pid_t: Counters],
    value: (Counters) -> UInt64,
    mainPID: pid_t,
    includeChildren: Bool
) -> UInt64 {
    current.reduce(into: 0) { total, entry in
        guard includeChildren || entry.key == mainPID else { return }
        total += delta(value(entry.value), previous[entry.key].map(value))
    }
}

private func residentBytes(
    in counters: [pid_t: Counters],
    mainPID: pid_t,
    includeChildren: Bool
) -> UInt64 {
    counters.reduce(into: 0) { total, entry in
        guard includeChildren || entry.key == mainPID else { return }
        total += entry.value.residentBytes
    }
}

private func runSampler(mainPID: pid_t, expectedMainPath: String, duration: TimeInterval, interval: TimeInterval) throws {
    guard mainPID > 0, duration > 0, interval > 0 else { throw MetricsError.invalidArguments }
    var previous = try scopedCounters(mainPID: mainPID, expectedMainPath: expectedMainPath)
    var previousTime = DispatchTime.now().uptimeNanoseconds
    let sampleCount = max(1, Int(duration / interval))
    print("sample,main_rss_mb,combined_rss_mb,main_footprint_mb,combined_footprint_mb,main_cpu_percent,combined_cpu_percent,main_wakeups_per_min,combined_wakeups_per_min,main_write_kb_per_sec,combined_write_kb_per_sec,child_count")

    for sample in 1 ... sampleCount {
        Thread.sleep(forTimeInterval: interval)
        let now = DispatchTime.now().uptimeNanoseconds
        let current = try scopedCounters(mainPID: mainPID, expectedMainPath: expectedMainPath)
        let elapsedNanoseconds = max(1, now - previousTime)
        let elapsedSeconds = Double(elapsedNanoseconds) / 1_000_000_000

        let mainCPU = metricDelta(current: current, previous: previous, value: { $0.cpuNanoseconds }, mainPID: mainPID, includeChildren: false)
        let combinedCPU = metricDelta(current: current, previous: previous, value: { $0.cpuNanoseconds }, mainPID: mainPID, includeChildren: true)
        let mainWakeups = metricDelta(current: current, previous: previous, value: { $0.interruptWakeups }, mainPID: mainPID, includeChildren: false)
        let combinedWakeups = metricDelta(current: current, previous: previous, value: { $0.interruptWakeups }, mainPID: mainPID, includeChildren: true)
        let mainWrites = metricDelta(current: current, previous: previous, value: { $0.bytesWritten }, mainPID: mainPID, includeChildren: false)
        let combinedWrites = metricDelta(current: current, previous: previous, value: { $0.bytesWritten }, mainPID: mainPID, includeChildren: true)

        let fields: [String] = [
            String(sample),
            String(format: "%.6f", Double(residentBytes(in: current, mainPID: mainPID, includeChildren: false)) / 1_048_576),
            String(format: "%.6f", Double(residentBytes(in: current, mainPID: mainPID, includeChildren: true)) / 1_048_576),
            String(format: "%.6f", Double(current[mainPID]?.physicalFootprintBytes ?? 0) / 1_048_576),
            String(format: "%.6f", Double(current.values.reduce(0) { $0 + $1.physicalFootprintBytes }) / 1_048_576),
            String(format: "%.6f", Double(mainCPU) / Double(elapsedNanoseconds) * 100),
            String(format: "%.6f", Double(combinedCPU) / Double(elapsedNanoseconds) * 100),
            String(format: "%.6f", Double(mainWakeups) / elapsedSeconds * 60),
            String(format: "%.6f", Double(combinedWakeups) / elapsedSeconds * 60),
            String(format: "%.6f", Double(mainWrites) / 1024 / elapsedSeconds),
            String(format: "%.6f", Double(combinedWrites) / 1024 / elapsedSeconds),
            String(max(0, current.count - 1)),
        ]
        print(fields.joined(separator: ","))
        fflush(stdout)
        previous = current
        previousTime = now
    }
}

private func findProcesses(executablePath expectedPath: String) -> [pid_t] {
    let capacity = 16_384
    var pids = [pid_t](repeating: 0, count: capacity)
    let count = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
    guard count > 0 else { return [] }
    return pids.prefix(Int(count)).filter { pid in
        pid > 0 && executablePath(for: pid) == expectedPath
    }
}

private let expectedCSVHeader = [
    "sample", "main_rss_mb", "combined_rss_mb", "main_footprint_mb", "combined_footprint_mb",
    "main_cpu_percent", "combined_cpu_percent",
    "main_wakeups_per_min", "combined_wakeups_per_min", "main_write_kb_per_sec",
    "combined_write_kb_per_sec", "child_count",
]

private let reportMetrics = [
    ReportMetric(name: "RSS (MB)", scope: "QuotaPet main", source: .column(1), gate: .median(80)),
    ReportMetric(name: "RSS (MB)", scope: "Direct Codex child", source: .difference(combined: 2, main: 1), gate: .none),
    ReportMetric(name: "RSS (MB)", scope: "Main + direct Codex", source: .column(2), gate: .median(160)),
    ReportMetric(name: "Physical footprint (MB)", scope: "QuotaPet main", source: .column(3), gate: .none),
    ReportMetric(name: "Physical footprint (MB)", scope: "Direct Codex child", source: .difference(combined: 4, main: 3), gate: .none),
    ReportMetric(name: "Physical footprint (MB)", scope: "Main + direct Codex", source: .column(4), gate: .none),
    ReportMetric(name: "CPU (% single core)", scope: "QuotaPet main", source: .column(5), gate: .average(0.2)),
    ReportMetric(name: "CPU (% single core)", scope: "Direct Codex child", source: .difference(combined: 6, main: 5), gate: .none),
    ReportMetric(name: "CPU (% single core)", scope: "Main + direct Codex", source: .column(6), gate: .average(0.5)),
    ReportMetric(name: "Interrupt wakeups/min", scope: "QuotaPet main", source: .column(7), gate: .average(5)),
    ReportMetric(name: "Interrupt wakeups/min", scope: "Direct Codex child", source: .difference(combined: 8, main: 7), gate: .none),
    ReportMetric(name: "Interrupt wakeups/min", scope: "Main + direct Codex", source: .column(8), gate: .average(10)),
    ReportMetric(name: "Write I/O (KiB/s)", scope: "QuotaPet main", source: .column(9), gate: .none),
    ReportMetric(name: "Write I/O (KiB/s)", scope: "Direct Codex child", source: .difference(combined: 10, main: 9), gate: .none),
    ReportMetric(name: "Write I/O (KiB/s)", scope: "Main + direct Codex", source: .column(10), gate: .none),
]

private func parseCSV(at url: URL) throws -> [[Double]] {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let lines = contents.split(whereSeparator: \Character.isNewline).map(String.init)
    guard lines.count >= 2, lines[0].split(separator: ",").map(String.init) == expectedCSVHeader else {
        throw MetricsError.invalidCSV
    }
    return try lines.dropFirst().enumerated().map { offset, line in
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == expectedCSVHeader.count else { throw MetricsError.invalidCSV }
        let values = try fields.map { field -> Double in
            guard let value = Double(field), value.isFinite, value >= 0 else { throw MetricsError.invalidCSV }
            return value
        }
        guard values[0] == Double(offset + 1), values[0].rounded() == values[0] else {
            throw MetricsError.invalidCSV
        }
        return values
    }
}

private func statistics(for values: [Double]) throws -> Statistics {
    guard !values.isEmpty else { throw MetricsError.invalidCSV }
    let sorted = values.sorted()
    let midpoint = sorted.count / 2
    let median = sorted.count.isMultiple(of: 2)
        ? (sorted[midpoint - 1] + sorted[midpoint]) / 2
        : sorted[midpoint]
    let average = values.reduce(0, +) / Double(values.count)
    let p95Index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
    return Statistics(median: median, average: average, p95: sorted[p95Index])
}

private func values(for source: ReportMetric.ValueSource, rows: [[Double]]) -> [Double] {
    switch source {
    case let .column(column):
        return rows.map { $0[column] }
    case let .difference(combined, main):
        return rows.map { max(0, $0[combined] - $0[main]) }
    }
}

private func safeField(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._+-"))
    return String(value.unicodeScalars.prefix(64).map { allowed.contains($0) ? Character(String($0)) : "_" })
}

private func report(
    csvURL: URL,
    outputURL: URL,
    runLabel: String,
    mode: String,
    machine: String,
    macOS: String,
    codex: String,
    warmup: String,
    sample: String,
    interval: String
) throws -> String {
    guard mode == "realtime" || mode == "energy-saving",
          let warmupSeconds = Double(warmup), warmupSeconds > 0,
          let sampleSeconds = Double(sample), sampleSeconds > 0,
          let intervalSeconds = Double(interval), intervalSeconds > 0
    else { throw MetricsError.invalidArguments }
    let rows = try parseCSV(at: csvURL)
    let childSampleCount = rows.filter { $0[11] >= 1 }.count
    let requiresChildCoverage = runLabel == "Formal baseline" && mode == "energy-saving"
    let childCoveragePass = !requiresChildCoverage || childSampleCount > 0
    var tableRows: [String] = []
    var overallPass = childCoveragePass
    for metric in reportMetrics {
        let stats = try statistics(for: values(for: metric.source, rows: rows))
        let gateText: String
        let result: String
        switch metric.gate {
        case let .median(threshold):
            gateText = "median <= \(threshold.formatted(.number.precision(.fractionLength(threshold.rounded() == threshold ? 0 : 1))))"
            result = stats.median <= threshold + 0.000_000_001 ? "PASS" : "FAIL"
        case let .average(threshold):
            gateText = "average <= \(threshold.formatted(.number.precision(.fractionLength(threshold.rounded() == threshold ? 0 : 1))))"
            result = stats.average <= threshold + 0.000_000_001 ? "PASS" : "FAIL"
        case .none:
            gateText = "N/A"
            result = "N/A"
        }
        if result == "FAIL" { overallPass = false }
        tableRows.append(
            "| \(metric.name) | \(metric.scope) | \(String(format: "%.3f", stats.median)) | \(String(format: "%.3f", stats.average)) | \(String(format: "%.3f", stats.p95)) | \(gateText) | \(result) |"
        )
    }
    let overall = overallPass ? "PASS" : "FAIL"
    let markdown = """
    # QuotaPet performance baseline

    Status: **\(overall)** (\(safeField(runLabel)), \(mode) mode)

    ## Environment

    - Machine model: \(safeField(machine))
    - macOS: \(safeField(macOS))
    - Codex: \(safeField(codex))
    - Warm-up: \(String(format: "%.3f", warmupSeconds)) seconds
    - Sample: \(String(format: "%.3f", sampleSeconds)) seconds at \(String(format: "%.3f", intervalSeconds))-second intervals
    - Complete samples: \(rows.count)
    - Samples with direct Codex child: \(childSampleCount)
    - Direct child coverage gate: \(requiresChildCoverage ? (childCoveragePass ? "PASS" : "FAIL") : "N/A")

    ## Results

    | Metric | Scope | Median | Average | P95 | Gate | Result |
    |---|---|---:|---:|---:|---:|---|
    \(tableRows.joined(separator: "\n"))

    ## Method and limitations

    The formal workflow uses a 5-minute warm-up followed by a 15-minute sample in realtime mode first. If a hard gate fails, energy-saving mode is measured with another complete 5-minute warm-up and 15-minute sample. A formal energy-saving run must include at least one sample with a direct Codex child or the run fails as incomplete. `ProcessMetrics.swift` uses macOS `proc_pidpath`, `proc_listchildpids`, and `proc_pid_rusage(RUSAGE_INFO_V4)`: RSS is resident bytes, CPU is the user-plus-system time delta normalized to one core, wakeups are interrupt wakeup deltas per minute, and write I/O is the disk-byte-write delta. Combined scope is the exact QuotaPet bundle binary plus only direct child processes whose executable basename is exactly `codex`; it never records command lines or executable paths.

    The RSS release gates are calibrated against a same-machine empty AppKit control whose median RSS was 67.938 MB. Main <= 80 MB and main-plus-child <= 160 MB preserve measurable headroom above that platform floor while still detecting product regressions. RSS remains the release gate; physical footprint is reported as a secondary diagnostic and does not replace RSS.

    These are sampled counters, not Instruments Energy Log estimates. A direct child that starts and exits entirely between sample boundaries can be missed. Interrupt wakeups are the reliable native counter available to an unprivileged process; timer wakeup classifications unavailable from this API are N/A. APFS caching can delay or coalesce write accounting. CPU percentages from this report should not be compared directly with `ps`'s decaying average or `top`'s initial sample. Results vary with hardware, macOS, Codex version, authentication/network latency, and foreground interaction.
    """
    try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
    return overall
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count >= 3 else { throw MetricsError.invalidArguments }
    switch arguments[1] {
    case "find":
        for pid in findProcesses(executablePath: arguments[2]) { print(pid) }
    case "sample":
        guard arguments.count == 6,
              let pid = pid_t(arguments[2]),
              let duration = TimeInterval(arguments[4]),
              let interval = TimeInterval(arguments[5])
        else { throw MetricsError.invalidArguments }
        try runSampler(mainPID: pid, expectedMainPath: arguments[3], duration: duration, interval: interval)
    case "report":
        guard arguments.count == 12 else { throw MetricsError.invalidArguments }
        print(try report(
            csvURL: URL(fileURLWithPath: arguments[2]),
            outputURL: URL(fileURLWithPath: arguments[3]),
            runLabel: arguments[4],
            mode: arguments[5],
            machine: arguments[6],
            macOS: arguments[7],
            codex: arguments[8],
            warmup: arguments[9],
            sample: arguments[10],
            interval: arguments[11]
        ))
    default:
        throw MetricsError.invalidArguments
    }
} catch {
    FileHandle.standardError.write(Data("Process metrics collection failed.\n".utf8))
    exit(1)
}
