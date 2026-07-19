#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
SOURCE_APP="$PROJECT_ROOT/dist/QuotaPet.app"
APPLICATIONS_DIR="/Applications"
TARGET_APP="/Applications/QuotaPet.app"
EXPECTED_EXECUTABLE="$TARGET_APP/Contents/MacOS/QuotaPet"
EXPECTED_BUNDLE_ID="io.github.asazhangyongchao.quotapet"
TEMP_ROOT=""
TEMP_APP=""
BACKUP_APP="$APPLICATIONS_DIR/.QuotaPet.backup.$$"
OLD_MOVED=0
NEW_MOVED=0
INSTALLED=0

safe_remove() {
    local path="${1:-}"
    case "$path" in
        "$APPLICATIONS_DIR"/.QuotaPet.install.*|"$APPLICATIONS_DIR"/.QuotaPet.backup.*)
            [[ -n "$path" && "$path" != "/" && "$path" != "$APPLICATIONS_DIR" ]] || return 1
            rm -rf -- "$path"
            ;;
        "") ;;
        *) echo "Refusing unsafe cleanup path: $path" >&2; return 1 ;;
    esac
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ "$status" -ne 0 && "$NEW_MOVED" -eq 1 && -e "$TARGET_APP" ]]; then
        rm -rf -- "$TARGET_APP"
    fi
    if [[ "$status" -ne 0 && "$OLD_MOVED" -eq 1 && -e "$BACKUP_APP" ]]; then
        mv -- "$BACKUP_APP" "$TARGET_APP" || true
    fi
    safe_remove "$TEMP_ROOT" || true
    if [[ "$INSTALLED" -eq 1 ]]; then
        safe_remove "$BACKUP_APP" || true
    fi
    exit "$status"
}
trap cleanup EXIT INT TERM

[[ -d "$SOURCE_APP" ]] || { echo "Missing $SOURCE_APP; run scripts/build-app.sh first." >&2; exit 1; }
codesign --verify --deep --strict "$SOURCE_APP"
[[ "$(plutil -extract CFBundleIdentifier raw "$SOURCE_APP/Contents/Info.plist")" == "$EXPECTED_BUNDLE_ID" ]] || {
    echo "Unexpected bundle identifier in source app." >&2
    exit 1
}
[[ -x "$SOURCE_APP/Contents/MacOS/QuotaPet" ]] || { echo "Source executable is missing." >&2; exit 1; }
[[ -d "$APPLICATIONS_DIR" && -w "$APPLICATIONS_DIR" ]] || {
    echo "$APPLICATIONS_DIR is not writable by the current user. Use an account with application-install permission." >&2
    exit 1
}

TEMP_ROOT="$(mktemp -d "$APPLICATIONS_DIR/.QuotaPet.install.XXXXXX")"
TEMP_APP="$TEMP_ROOT/QuotaPet.app"
ditto --rsrc --extattr "$SOURCE_APP" "$TEMP_APP"
codesign --verify --deep --strict "$TEMP_APP"
[[ "$(plutil -extract CFBundleIdentifier raw "$TEMP_APP/Contents/Info.plist")" == "$EXPECTED_BUNDLE_ID" ]] || {
    echo "Copied app failed bundle identity verification." >&2
    exit 1
}

running_pids=()
while read -r pid command; do
    if [[ "$command" == "$EXPECTED_EXECUTABLE" || "$command" == "$EXPECTED_EXECUTABLE "* ]]; then
        running_pids+=("$pid")
    fi
done < <(/bin/ps -axo pid=,command=)

for pid in "${running_pids[@]:-}"; do
    [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
done
for _ in {1..25}; do
    still_running=0
    for pid in "${running_pids[@]:-}"; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then still_running=1; fi
    done
    [[ "$still_running" -eq 0 ]] && break
    sleep 0.2
done
for pid in "${running_pids[@]:-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; fi
done

if [[ -e "$TARGET_APP" ]]; then
    mv -- "$TARGET_APP" "$BACKUP_APP"
    OLD_MOVED=1
fi
mv -- "$TEMP_APP" "$TARGET_APP"
NEW_MOVED=1
codesign --verify --deep --strict "$TARGET_APP"
[[ "$(plutil -extract CFBundleIdentifier raw "$TARGET_APP/Contents/Info.plist")" == "$EXPECTED_BUNDLE_ID" ]] || {
    echo "Installed app failed bundle identity verification." >&2
    exit 1
}
INSTALLED=1

echo "Installed $TARGET_APP"
