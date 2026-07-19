# QuotaPet performance baseline

Status: **PASS** (Formal baseline, energy-saving mode)

## Environment

- Machine model: Mac17_9
- macOS: 26.5.2
- Codex: 0.145.0-alpha.18
- Warm-up: 300.000 seconds
- Sample: 900.000 seconds at 1.000-second intervals
- Complete samples: 900
- Samples with direct Codex child: 6
- Direct child coverage gate: PASS

## Results

| Metric | Scope | Median | Average | P95 | Gate | Result |
|---|---|---:|---:|---:|---:|---|
| RSS (MB) | QuotaPet main | 69.094 | 68.411 | 69.203 | median <= 80 | PASS |
| RSS (MB) | Direct Codex child | 0.000 | 0.378 | 0.000 | N/A | N/A |
| RSS (MB) | Main + direct Codex | 69.094 | 68.789 | 69.203 | median <= 160 | PASS |
| Physical footprint (MB) | QuotaPet main | 19.813 | 21.834 | 25.595 | N/A | N/A |
| Physical footprint (MB) | Direct Codex child | 0.000 | 0.123 | 0.000 | N/A | N/A |
| Physical footprint (MB) | Main + direct Codex | 19.813 | 21.956 | 25.595 | N/A | N/A |
| CPU (% single core) | QuotaPet main | 0.000 | 0.003 | 0.000 | average <= 0.2 | PASS |
| CPU (% single core) | Direct Codex child | 0.000 | 0.000 | 0.000 | N/A | N/A |
| CPU (% single core) | Main + direct Codex | 0.000 | 0.003 | 0.000 | average <= 0.5 | PASS |
| Interrupt wakeups/min | QuotaPet main | 0.000 | 1.653 | 0.000 | average <= 5 | PASS |
| Interrupt wakeups/min | Direct Codex child | 0.000 | 0.530 | 0.000 | N/A | N/A |
| Interrupt wakeups/min | Main + direct Codex | 0.000 | 2.183 | 0.000 | average <= 10 | PASS |
| Write I/O (KiB/s) | QuotaPet main | 0.000 | 0.000 | 0.000 | N/A | N/A |
| Write I/O (KiB/s) | Direct Codex child | 0.000 | 0.581 | 0.000 | N/A | N/A |
| Write I/O (KiB/s) | Main + direct Codex | 0.000 | 0.581 | 0.000 | N/A | N/A |

## Realtime screening

A post-fix 60-second realtime screening run captured the direct Codex child in all 60 samples. Main interrupt wakeups averaged 16.905/min, the direct child averaged 88.343/min, and the combined scope averaged 105.248/min, so realtime failed the 5/min main and 10/min combined wakeup gates and triggered the complete formal energy-saving run above. Main and combined RSS medians were 69.031 MB and 135.734 MB; CPU averages were 0.000% and 0.002% of one core. The screening run used only a 0.1-second warm-up, so it documents the fallback decision but does not replace the formal baseline.

## Method and limitations

The formal workflow uses a 5-minute warm-up followed by a 15-minute sample in realtime mode first. If a hard gate fails, energy-saving mode is measured with another complete 5-minute warm-up and 15-minute sample. A formal energy-saving run must include at least one sample with a direct Codex child or the run fails as incomplete. `ProcessMetrics.swift` uses macOS `proc_pidpath`, `proc_listchildpids`, and `proc_pid_rusage(RUSAGE_INFO_V4)`: RSS is resident bytes, CPU is the user-plus-system time delta normalized to one core, wakeups are interrupt wakeup deltas per minute, and write I/O is the disk-byte-write delta. Combined scope is the exact QuotaPet bundle binary plus only direct child processes whose executable basename is exactly `codex`; it never records command lines or executable paths.

The RSS release gates are calibrated against a same-machine empty AppKit control whose median RSS was 67.938 MB. Main <= 80 MB and main-plus-child <= 160 MB preserve measurable headroom above that platform floor while still detecting product regressions. RSS remains the release gate; physical footprint is reported as a secondary diagnostic and does not replace RSS.

These are sampled counters, not Instruments Energy Log estimates. A direct child that starts and exits entirely between sample boundaries can be missed. Interrupt wakeups are the reliable native counter available to an unprivileged process; timer wakeup classifications unavailable from this API are N/A. APFS caching can delay or coalesce write accounting. CPU percentages from this report should not be compared directly with `ps`'s decaying average or `top`'s initial sample. Results vary with hardware, macOS, Codex version, authentication/network latency, and foreground interaction.
