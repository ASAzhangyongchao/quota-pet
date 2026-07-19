#!/usr/bin/env bash
set -euo pipefail

FORMAL_WARMUP_SECONDS=300
FORMAL_SAMPLE_SECONDS=900
FORMAL_SAMPLE_INTERVAL_SECONDS=1
WARMUP_SECONDS="${QUOTAPET_PERF_WARMUP_SECONDS:-$FORMAL_WARMUP_SECONDS}"
SAMPLE_SECONDS="${QUOTAPET_PERF_SAMPLE_SECONDS:-$FORMAL_SAMPLE_SECONDS}"
SAMPLE_INTERVAL_SECONDS="${QUOTAPET_PERF_SAMPLE_INTERVAL_SECONDS:-$FORMAL_SAMPLE_INTERVAL_SECONDS}"
RUN_MODE="${QUOTAPET_PERF_MODE:-realtime}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
APP="${QUOTAPET_PERF_APP:-$PROJECT_ROOT/dist/QuotaPet.app}"
SOURCE_APP_BINARY="$APP/Contents/MacOS/QuotaPet"
FORMAL_REPORT="$PROJECT_ROOT/docs/performance-baseline.md"
REPORT="${QUOTAPET_PERF_REPORT:-$FORMAL_REPORT}"
TEMP_ROOT_RAW="$(mktemp -d "${TMPDIR:-/tmp}/QuotaPet-performance.XXXXXX")"
TEMP_ROOT="$(cd -- "$TEMP_ROOT_RAW" && pwd -P)"
PERFORMANCE_APP="$TEMP_ROOT/QuotaPet.app"
APP_BINARY="$PERFORMANCE_APP/Contents/MacOS/QuotaPet"
METRICS_HELPER="$TEMP_ROOT/QuotaPetProcessMetrics"
PREFERENCES_HELPER="$TEMP_ROOT/PreparePerformancePreferences"
PREFERENCES_SUITE="io.github.asazhangyongchao.quotapet.performance.$(/usr/bin/uuidgen)"
CSV="$TEMP_ROOT/samples.csv"
REPORT_TEMP="$TEMP_ROOT/performance-report.md"
STARTED_PID=""

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ -n "$STARTED_PID" ]] && kill -0 "$STARTED_PID" 2>/dev/null; then
        kill -TERM "$STARTED_PID" 2>/dev/null || true
        for _ in {1..20}; do
            kill -0 "$STARTED_PID" 2>/dev/null || break
            sleep 0.1
        done
    fi
    if [[ -x "$PREFERENCES_HELPER" ]] && ! "$PREFERENCES_HELPER" clear "$PREFERENCES_SUITE" >/dev/null 2>&1; then
        echo "Performance preference cleanup failed." >&2
        [[ "$status" -ne 0 ]] || status=1
    fi
    rm -rf -- "$TEMP_ROOT"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    echo "Performance measurement failed: $*" >&2
    exit 1
}

is_positive_number() {
    [[ "$1" =~ ^([1-9][0-9]*([.][0-9]+)?|0[.][0-9]*[1-9][0-9]*)$ ]]
}

is_positive_number "$WARMUP_SECONDS" || fail "warm-up duration must be positive"
is_positive_number "$SAMPLE_SECONDS" || fail "sample duration must be positive"
is_positive_number "$SAMPLE_INTERVAL_SECONDS" || fail "sample interval must be positive"
[[ "$RUN_MODE" == "realtime" || "$RUN_MODE" == "energy-saving" ]] || fail "mode must be realtime or energy-saving"
[[ -x "$SOURCE_APP_BINARY" ]] || fail "build dist/QuotaPet.app before measuring"
[[ -f "$SCRIPT_DIR/ProcessMetrics.swift" ]] || fail "native metrics helper source is missing"
[[ -f "$SCRIPT_DIR/PreparePerformancePreferences.swift" ]] || fail "preference preparation helper source is missing"
[[ -f "$PROJECT_ROOT/Sources/QuotaPet/Usage/CodexExecutableResolver.swift" ]] || fail "Codex resolver source is missing"

IS_FORMAL=0
if [[ "$WARMUP_SECONDS" == "$FORMAL_WARMUP_SECONDS" && \
      "$SAMPLE_SECONDS" == "$FORMAL_SAMPLE_SECONDS" && \
      "$SAMPLE_INTERVAL_SECONDS" == "$FORMAL_SAMPLE_INTERVAL_SECONDS" ]]; then
    IS_FORMAL=1
fi
if [[ "$IS_FORMAL" -ne 1 && "$REPORT" == "$FORMAL_REPORT" ]]; then
    fail "NON-FORMAL TEST RUN must set QUOTAPET_PERF_REPORT and cannot replace the formal baseline"
fi

xcrun swiftc -O "$SCRIPT_DIR/ProcessMetrics.swift" -o "$METRICS_HELPER"
xcrun swiftc -O \
    "$SCRIPT_DIR/PreparePerformancePreferences.swift" \
    "$PROJECT_ROOT/Sources/QuotaPet/Usage/CodexExecutableResolver.swift" \
    -o "$PREFERENCES_HELPER"
mapfile_supported=0
if builtin help mapfile >/dev/null 2>&1; then mapfile_supported=1; fi
if [[ "$mapfile_supported" -eq 1 ]]; then
    mapfile -t pids < <("$METRICS_HELPER" find "$SOURCE_APP_BINARY")
else
    pids=()
    while IFS= read -r pid; do [[ -n "$pid" ]] && pids+=("$pid"); done < <("$METRICS_HELPER" find "$SOURCE_APP_BINARY")
fi
[[ "${#pids[@]}" -eq 0 ]] || fail "quit the existing exact QuotaPet bundle process before measurement"
mode_argument="realtime"
[[ "$RUN_MODE" == "realtime" ]] || mode_argument="energySaver"

cp -R -- "$APP" "$PERFORMANCE_APP"
plutil -replace CFBundleIdentifier -string "$PREFERENCES_SUITE" "$PERFORMANCE_APP/Contents/Info.plist"
codesign --force --deep --sign - "$PERFORMANCE_APP"
codesign --verify --deep --strict "$PERFORMANCE_APP"
preparation="$("$PREFERENCES_HELPER" prepare "$PREFERENCES_SUITE" "$mode_argument")" || fail "trusted Codex preference preparation failed"
[[ "$preparation" == "ready" ]] || fail "trusted Codex preference preparation was not ready"

# Finder/launchd does not inherit terminal-only allocator diagnostics. Clear this
# known diagnostic variable so the direct bundle launch matches normal app startup.
/usr/bin/env -u MallocNanoZone "$APP_BINARY" -QuotaPet.connectionMode "$mode_argument" >/dev/null 2>&1 &
MAIN_PID=$!
STARTED_PID="$MAIN_PID"
sleep 2
kill -0 "$MAIN_PID" 2>/dev/null || fail "QuotaPet exited during launch"

# Scope is exact: the helper revalidates APP_BINARY using proc_pidpath and includes
# only direct ppid children whose executable basename is exactly codex.
echo "Warming up QuotaPet for ${WARMUP_SECONDS}s (${RUN_MODE})."
sleep "$WARMUP_SECONDS"
kill -0 "$MAIN_PID" 2>/dev/null || fail "QuotaPet exited during warm-up"
echo "Sampling QuotaPet and direct Codex children for ${SAMPLE_SECONDS}s."
"$METRICS_HELPER" sample "$MAIN_PID" "$APP_BINARY" "$SAMPLE_SECONDS" "$SAMPLE_INTERVAL_SECONDS" >"$CSV"

machine_model="$(system_profiler SPHardwareDataType 2>/dev/null | sed -n 's/^[[:space:]]*Model Identifier: //p' | sed -n '1p')"
[[ -n "$machine_model" ]] || machine_model="N/A"
macos_version="$(sw_vers -productVersion 2>/dev/null || true)"
[[ -n "$macos_version" ]] || macos_version="N/A"
codex_version="N/A"
for candidate in "/Applications/ChatGPT.app/Contents/Resources/codex" "/Applications/Codex.app/Contents/Resources/codex"; do
    if [[ -x "$candidate" ]]; then
        version_output="$($candidate --version 2>/dev/null || true)"
        if [[ "$version_output" =~ ([0-9]+[.][0-9]+[.][0-9]+([-+][[:alnum:]._-]+)?) ]]; then
            codex_version="${BASH_REMATCH[1]}"
            break
        fi
    fi
done

run_label="Formal baseline"
[[ "$IS_FORMAL" -eq 1 ]] || run_label="NON-FORMAL TEST RUN"
overall="$("$METRICS_HELPER" report "$CSV" "$REPORT_TEMP" "$run_label" "$RUN_MODE" "$machine_model" "$macos_version" "$codex_version" "$WARMUP_SECONDS" "$SAMPLE_SECONDS" "$SAMPLE_INTERVAL_SECONDS")"

mkdir -p -- "$(dirname -- "$REPORT")"
mv -- "$REPORT_TEMP" "$REPORT"
echo "Performance gate: $overall"
echo "Report written without process paths or command lines."
[[ "$overall" == "PASS" ]] || exit 2
