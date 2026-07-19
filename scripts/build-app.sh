#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
DIST_DIR="$PROJECT_ROOT/dist"
FINAL_APP="$DIST_DIR/QuotaPet.app"
FINAL_ZIP="$DIST_DIR/QuotaPet.zip"

case "$DIST_DIR" in
    "$PROJECT_ROOT/dist") ;;
    *) echo "Refusing unsafe dist path: $DIST_DIR" >&2; exit 1 ;;
esac

mkdir -p -- "$DIST_DIR"
STAGING_DIR="$(mktemp -d "$DIST_DIR/.staging-XXXXXX")"
NEXT_APP="$DIST_DIR/.QuotaPet.app.next.$$"
NEXT_ZIP="$DIST_DIR/.QuotaPet.zip.next.$$"
OLD_APP="$DIST_DIR/.QuotaPet.app.previous.$$"
OLD_ZIP="$DIST_DIR/.QuotaPet.zip.previous.$$"
COMMITTING=0
HAD_OLD_APP=0
HAD_OLD_ZIP=0

safe_remove() {
    local path="${1:-}"
    case "$path" in
        "$DIST_DIR"/.staging-*|"$DIST_DIR"/.QuotaPet.app.next.*|"$DIST_DIR"/.QuotaPet.zip.next.*|"$DIST_DIR"/.QuotaPet.app.previous.*|"$DIST_DIR"/.QuotaPet.zip.previous.*)
            [[ -n "$path" && "$path" != "/" && "$path" != "$DIST_DIR" ]] || return 1
            rm -rf -- "$path"
            ;;
        "") ;;
        *) echo "Refusing unsafe cleanup path: $path" >&2; return 1 ;;
    esac
}

rollback_artifacts() {
    [[ "$COMMITTING" -eq 1 ]] || return 0
    if [[ "$HAD_OLD_APP" -eq 1 && -e "$OLD_APP" ]]; then
        [[ ! -e "$FINAL_APP" ]] || rm -rf -- "$FINAL_APP"
        mv -- "$OLD_APP" "$FINAL_APP"
    elif [[ "$HAD_OLD_APP" -eq 0 && -e "$FINAL_APP" ]]; then
        rm -rf -- "$FINAL_APP"
    fi
    if [[ "$HAD_OLD_ZIP" -eq 1 && -e "$OLD_ZIP" ]]; then
        [[ ! -e "$FINAL_ZIP" ]] || rm -f -- "$FINAL_ZIP"
        mv -- "$OLD_ZIP" "$FINAL_ZIP"
    elif [[ "$HAD_OLD_ZIP" -eq 0 && -e "$FINAL_ZIP" ]]; then
        rm -f -- "$FINAL_ZIP"
    fi
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ "$status" -ne 0 ]]; then
        rollback_artifacts || true
    fi
    safe_remove "$STAGING_DIR" || true
    safe_remove "$NEXT_APP" || true
    safe_remove "$NEXT_ZIP" || true
    if [[ "$COMMITTING" -eq 0 ]]; then
        safe_remove "$OLD_APP" || true
        safe_remove "$OLD_ZIP" || true
    fi
    exit "$status"
}
trap cleanup EXIT INT TERM

cd -- "$PROJECT_ROOT"
plutil -lint Resources/Info.plist >/dev/null
[[ -s Resources/AppIcon.icns ]] || { echo "Resources/AppIcon.icns is missing; run scripts/generate-icon.swift" >&2; exit 1; }

swift build -c release -Xswiftc -gnone
BIN_DIR="$(swift build -c release -Xswiftc -gnone --show-bin-path)"
[[ -x "$BIN_DIR/QuotaPet" ]] || { echo "Release executable was not produced" >&2; exit 1; }

STAGED_APP="$STAGING_DIR/QuotaPet.app"
STAGED_ZIP="$STAGING_DIR/QuotaPet.zip"
mkdir -p -- "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
install -m 0755 "$BIN_DIR/QuotaPet" "$STAGED_APP/Contents/MacOS/QuotaPet"
strip -S -x "$STAGED_APP/Contents/MacOS/QuotaPet"
install -m 0644 Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
install -m 0644 Resources/AppIcon.icns "$STAGED_APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$STAGED_ZIP"
unzip -tq "$STAGED_ZIP" >/dev/null

mv -- "$STAGED_APP" "$NEXT_APP"
mv -- "$STAGED_ZIP" "$NEXT_ZIP"

COMMITTING=1
if [[ -e "$FINAL_APP" ]]; then
    mv -- "$FINAL_APP" "$OLD_APP"
    HAD_OLD_APP=1
fi
if [[ -e "$FINAL_ZIP" ]]; then
    mv -- "$FINAL_ZIP" "$OLD_ZIP"
    HAD_OLD_ZIP=1
fi
mv -- "$NEXT_APP" "$FINAL_APP"
mv -- "$NEXT_ZIP" "$FINAL_ZIP"
COMMITTING=0
safe_remove "$OLD_APP"
safe_remove "$OLD_ZIP"

echo "Built $FINAL_APP"
echo "Built $FINAL_ZIP"
