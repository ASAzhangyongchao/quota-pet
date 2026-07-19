#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
INFO_PLIST="$PROJECT_ROOT/Resources/Info.plist"
ICON="$PROJECT_ROOT/Resources/AppIcon.icns"
APP="$PROJECT_ROOT/dist/QuotaPet.app"
ZIP="$PROJECT_ROOT/dist/QuotaPet.zip"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/QuotaPet-verify.XXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT INT TERM

fail() {
    echo "Package verification failed: $*" >&2
    exit 1
}

scan_binary_strings() {
    local binary="$1" output="$TEMP_ROOT/binary-strings.txt"
    strings "$binary" >"$output"
    if [[ "$HOME" == /Users/* || "$HOME" == /home/* ]] && grep -Fq "$HOME" "$output"; then
        fail "current user's build path in packaged executable"
    fi
    if grep -Eq "sk-[[:alnum:]_-]{20,}|gh[pousr]_[[:alnum:]]{20,}|AKIA[[:alnum:]]{16}" "$output"; then
        fail "possible sensitive value or build path in packaged executable"
    fi
}

if [[ "${QUOTAPET_TEST_MODE:-0}" == "1" ]]; then
    [[ -d "${QUOTAPET_TEST_ROOT:-}" ]] || fail "invalid scan test root"
    TEST_ROOT="$(cd -- "$QUOTAPET_TEST_ROOT" && pwd -P)"
    TEMP_BASE="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
    case "$TEST_ROOT" in
        "$TEMP_BASE"/QuotaPet-transaction-tests-*|/private/tmp/QuotaPet-transaction-tests-*) ;;
        *) fail "scan test root must be a dedicated temporary directory" ;;
    esac
    SCAN_FILE="${QUOTAPET_VERIFY_SCAN_FILE:-}"
    [[ -f "$SCAN_FILE" && ! -L "$SCAN_FILE" ]] || fail "invalid scan test file"
    SCAN_DIRECTORY="$(cd -- "$(dirname -- "$SCAN_FILE")" && pwd -P)"
    SCAN_FILE="$SCAN_DIRECTORY/$(basename -- "$SCAN_FILE")"
    [[ "$SCAN_FILE" == "$TEST_ROOT"/* ]] || fail "scan test file escaped its root"
    scan_binary_strings "$SCAN_FILE"
    echo "Package binary scan passed."
    exit 0
fi

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

plutil -lint "$INFO_PLIST" >/dev/null
[[ "$(plist_value "$INFO_PLIST" CFBundleIdentifier)" == "io.github.asazhangyongchao.quotapet" ]] || fail "bundle identifier"
[[ "$(plist_value "$INFO_PLIST" CFBundleExecutable)" == "QuotaPet" ]] || fail "bundle executable"
[[ "$(plist_value "$INFO_PLIST" CFBundleIconFile)" == "AppIcon" ]] || fail "bundle icon"
[[ "$(plist_value "$INFO_PLIST" LSUIElement)" == "true" ]] || fail "LSUIElement"
VERSION="$(sed -n '1p' "$PROJECT_ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION format"
[[ "$(plist_value "$INFO_PLIST" CFBundleShortVersionString)" == "$VERSION" ]] || fail "short version"
[[ "$(plist_value "$INFO_PLIST" CFBundleVersion)" == "3" ]] || fail "build version"
[[ "$(plist_value "$INFO_PLIST" LSMinimumSystemVersion)" == "13.0" ]] || fail "minimum macOS"

for key in \
    NSCameraUsageDescription \
    NSMicrophoneUsageDescription \
    NSScreenCaptureUsageDescription \
    NSAccessibilityUsageDescription \
    NSInputMonitoringUsageDescription \
    NSAppleEventsUsageDescription \
    NSNetworkExtensionUsageDescription
do
    if /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" >/dev/null 2>&1; then
        fail "forbidden permission key $key"
    fi
done

[[ -s "$ICON" ]] || fail "missing icon"
file "$ICON" | grep -Eq "Mac OS X icon|Apple Icon Image" || fail "invalid icns file"
iconutil -c iconset "$ICON" -o "$TEMP_ROOT/AppIcon.iconset"
while read -r name pixels; do
    png="$TEMP_ROOT/AppIcon.iconset/$name"
    [[ -f "$png" ]] || fail "missing unpacked icon $name"
    file "$png" | grep -q "PNG image data, $pixels x $pixels" || fail "wrong dimensions for $name"
done <<'EXPECTED_ICONS'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
EXPECTED_ICONS

[[ -d "$APP" && -f "$ZIP" ]] || fail "build artifacts missing"
codesign --verify --deep --strict "$APP"
cmp -s "$INFO_PLIST" "$APP/Contents/Info.plist" || fail "packaged Info.plist differs"
[[ -x "$APP/Contents/MacOS/QuotaPet" ]] || fail "packaged executable missing"
[[ -s "$APP/Contents/Resources/AppIcon.icns" ]] || fail "packaged icon missing"
[[ -d "$APP/Contents/Resources/QuotaPet_QuotaPet.bundle/en.lproj" ]] || fail "English localization missing"
[[ -d "$APP/Contents/Resources/QuotaPet_QuotaPet.bundle/zh-hans.lproj" ]] || fail "Simplified Chinese localization missing"
unzip -tq "$ZIP" >/dev/null
unzip -Z1 "$ZIP" >"$TEMP_ROOT/zip-contents.txt"
grep -qx 'QuotaPet.app/Contents/Info.plist' "$TEMP_ROOT/zip-contents.txt" || fail "ZIP Info.plist missing"
grep -qx 'QuotaPet.app/Contents/MacOS/QuotaPet' "$TEMP_ROOT/zip-contents.txt" || fail "ZIP executable missing"
grep -qx 'QuotaPet.app/Contents/Resources/AppIcon.icns' "$TEMP_ROOT/zip-contents.txt" || fail "ZIP icon missing"
if grep -Eq '(^|/)\.DS_Store$|(^|/)\.build/|(^|/)dist/' "$TEMP_ROOT/zip-contents.txt"; then
    fail "unexpected ZIP content"
fi

cd -- "$PROJECT_ROOT"
git check-ignore -q dist/QuotaPet.app || fail "dist is not ignored"

SOURCE_PATTERNS="sk-[[:alnum:]_-]{20,}|gh[pousr]_[[:alnum:]]{20,}|AKIA[[:alnum:]]{16}|[[:alpha:]][[:alnum:]._%+-]*@[[:alpha:]][[:alnum:].-]*\.[[:alpha:]]{2,}"
while IFS= read -r -d '' path; do
    [[ -f "$path" ]] || continue
    if [[ "$HOME" == /Users/* || "$HOME" == /home/* ]] && LC_ALL=C grep -IFqn "$HOME" "$path"; then
        grep -IFn "$HOME" "$path"
        fail "current user's absolute home path in $path"
    fi
    if LC_ALL=C grep -Iq . "$path" && LC_ALL=C grep -En "$SOURCE_PATTERNS" "$path"; then
        fail "possible sensitive value in $path"
    fi
done < <(git ls-files -co --exclude-standard -z)

scan_binary_strings "$APP/Contents/MacOS/QuotaPet"

echo "Package verification passed."
