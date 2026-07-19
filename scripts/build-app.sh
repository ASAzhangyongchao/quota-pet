#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEST_MODE="${QUOTAPET_TEST_MODE:-0}"
TEST_HOOK="${QUOTAPET_TEST_HOOK:-}"

if [[ "$TEST_MODE" == "1" ]]; then
    [[ -d "${QUOTAPET_TEST_ROOT:-}" ]] || { echo "Invalid transaction test root." >&2; exit 64; }
    TEST_ROOT="$(cd -- "$QUOTAPET_TEST_ROOT" && pwd -P)"
    TEMP_BASE="$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
    case "$TEST_ROOT" in
        "$TEMP_BASE"/QuotaPet-transaction-tests-*|/private/tmp/QuotaPet-transaction-tests-*) ;;
        *) echo "Transaction test root must be a dedicated temporary directory." >&2; exit 64 ;;
    esac
    [[ -d "$TEST_ROOT/dist" && ! -L "$TEST_ROOT/dist" ]] || { echo "Unsafe transaction test dist directory." >&2; exit 64; }
    DIST_DIR="$(cd -- "$TEST_ROOT/dist" && pwd -P)"
    [[ "$DIST_DIR" == "$TEST_ROOT/dist" ]] || { echo "Transaction test dist must not escape its root." >&2; exit 64; }
else
    mkdir -p -- "$PROJECT_ROOT/dist"
    [[ ! -L "$PROJECT_ROOT/dist" ]] || { echo "Project dist must not be a symbolic link." >&2; exit 1; }
    DIST_DIR="$(cd -- "$PROJECT_ROOT/dist" && pwd -P)"
    [[ "$DIST_DIR" == "$PROJECT_ROOT/dist" ]] || { echo "Project dist escaped its root." >&2; exit 1; }
fi

LOCK_PARENT="$(cd -- "$DIST_DIR/.." && pwd -P)"
LOCK_NAME=".QuotaPet.build.lock"
LOCK_COMMAND="QuotaPet/build-app"
source "$SCRIPT_DIR/transaction-lock.sh"

FINAL_APP="$DIST_DIR/QuotaPet.app"
FINAL_ZIP="$DIST_DIR/QuotaPet.zip"
STAGING_DIR=""
TRANSACTION_DIR=""

case "$DIST_DIR" in
    "$PROJECT_ROOT/dist"|*/QuotaPet-transaction-tests-*/dist) ;;
    *) echo "Refusing unsafe dist path: $DIST_DIR" >&2; exit 1 ;;
esac

run_test_hook() {
    local point="$1"
    [[ "$TEST_MODE" == "1" ]] || return 0
    case "$TEST_HOOK" in
        "fail:$point") return 97 ;;
        "int:$point") kill -INT "$$" ;;
        "term:$point") kill -TERM "$$" ;;
        "kill:$point") kill -KILL "$$" ;;
        "block:$point")
            mkdir -p -- "$TEST_ROOT/hooks"
            : >"$TEST_ROOT/hooks/$point.ready"
            for _ in {1..500}; do
                [[ ! -e "$TEST_ROOT/hooks/$point.release" ]] || return 0
                sleep 0.02
            done
            return 98
            ;;
    esac
}

safe_remove_temporary() {
    local path="${1:-}"
    case "$path" in
        "$DIST_DIR"/.staging-*|"$DIST_DIR"/.transaction-*)
            [[ -n "$path" && "$path" != "/" && "$path" != "$DIST_DIR" ]] || return 1
            rm -rf -- "$path"
            ;;
        "") ;;
        *) echo "Refusing unsafe temporary cleanup path: $path" >&2; return 1 ;;
    esac
}

safe_remove_final() {
    local path="$1"
    case "$path" in
        "$FINAL_APP") rm -rf -- "$path" ;;
        "$FINAL_ZIP") rm -f -- "$path" ;;
        *) echo "Refusing unsafe final cleanup path: $path" >&2; return 1 ;;
    esac
}

rollback_artifact() {
    local final="$1" backup="$2" new_payload="$3" original_marker="$4" install_intent="$5"
    if [[ -e "$backup" ]]; then
        [[ ! -e "$final" ]] || safe_remove_final "$final"
        mv -- "$backup" "$final"
    elif [[ -e "$original_marker" ]]; then
        # The original never left final, or was already restored. Never delete it.
        return 0
    elif [[ -e "$install_intent" && ! -e "$new_payload" && -e "$final" ]]; then
        # There was no original and the staged payload demonstrably reached final.
        safe_remove_final "$final"
    fi
}

rollback_transaction() {
    local transaction="$1"
    local failed=0
    rollback_artifact \
        "$FINAL_APP" "$transaction/QuotaPet.previous.app" "$transaction/QuotaPet.new.app" \
        "$transaction/original-app-present" "$transaction/app-install-intent" || failed=1
    rollback_artifact \
        "$FINAL_ZIP" "$transaction/QuotaPet.previous.zip" "$transaction/QuotaPet.new.zip" \
        "$transaction/original-zip-present" "$transaction/zip-install-intent" || failed=1
    return "$failed"
}

validate_transaction_dir() {
    local transaction="$1" canonical
    [[ -d "$transaction" && ! -L "$transaction" ]] || return 1
    canonical="$(cd -- "$transaction" && pwd -P)"
    [[ "$canonical" == "$transaction" && "$canonical" == "$DIST_DIR"/.transaction-* ]]
}

discard_committed_transaction() {
    local transaction="$1"
    validate_transaction_dir "$transaction" || return 1
    rm -rf -- \
        "$transaction/QuotaPet.previous.app" "$transaction/QuotaPet.new.app" \
        "$transaction/QuotaPet.previous.zip" "$transaction/QuotaPet.new.zip"
    rm -f -- \
        "$transaction/original-app-present" "$transaction/original-zip-present" \
        "$transaction/app-install-intent" "$transaction/zip-install-intent" \
        "$transaction/owner-pid"
    # Remove this last: while it exists, interrupted cleanup remains metadata-only.
    rm -f -- "$transaction/committed"
    safe_remove_temporary "$transaction"
}

recover_orphaned_transactions() {
    local transaction owner
    for transaction in "$DIST_DIR"/.transaction-*; do
        [[ -d "$transaction" ]] || continue
        validate_transaction_dir "$transaction" || { echo "Refusing unsafe packaging transaction: $transaction" >&2; return 1; }
        if [[ -e "$transaction/committed" ]]; then
            TRANSACTION_DIR="$transaction"
            discard_committed_transaction "$transaction"
            TRANSACTION_DIR=""
            continue
        fi
        owner="$(sed -n '1p' "$transaction/owner-pid" 2>/dev/null || true)"
        if [[ "$owner" =~ ^[0-9]+$ && "$owner" != "$$" ]] && kill -0 "$owner" 2>/dev/null; then
            echo "Another QuotaPet packaging transaction is active." >&2
            return 1
        fi
        TRANSACTION_DIR="$transaction"
        rollback_transaction "$transaction"
        safe_remove_temporary "$transaction"
        TRANSACTION_DIR=""
    done
}

cleanup() {
    local status=$? rollback_ok=1
    trap - EXIT
    trap '' INT TERM
    if [[ "$status" -ne 0 && -d "$TRANSACTION_DIR" ]]; then
        validate_transaction_dir "$TRANSACTION_DIR" || rollback_ok=0
    fi
    if [[ "$status" -ne 0 && "$rollback_ok" -eq 1 && -d "$TRANSACTION_DIR" ]]; then
        if [[ -e "$TRANSACTION_DIR/committed" ]]; then
            if discard_committed_transaction "$TRANSACTION_DIR"; then
                TRANSACTION_DIR=""
            else
                rollback_ok=0
            fi
        else
            rollback_transaction "$TRANSACTION_DIR" || rollback_ok=0
        fi
    fi
    safe_remove_temporary "$STAGING_DIR" || true
    if [[ "$rollback_ok" -eq 1 ]]; then
        safe_remove_temporary "$TRANSACTION_DIR" || true
    else
        echo "Rollback was incomplete; preserved transaction at $TRANSACTION_DIR" >&2
    fi
    if ! release_global_lock; then
        [[ "$status" -ne 0 ]] || status=1
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_global_lock
run_test_hook after_lock
recover_orphaned_transactions
STAGING_DIR="$(mktemp -d "$DIST_DIR/.staging-XXXXXX")"
STAGED_APP="$STAGING_DIR/QuotaPet.app"
STAGED_ZIP="$STAGING_DIR/QuotaPet.zip"

if [[ "$TEST_MODE" == "1" ]]; then
    cp -R -- "$TEST_ROOT/fixture/QuotaPet.app" "$STAGED_APP"
    cp -- "$TEST_ROOT/fixture/QuotaPet.zip" "$STAGED_ZIP"
else
    cd -- "$PROJECT_ROOT"
    plutil -lint Resources/Info.plist >/dev/null
    [[ -s Resources/AppIcon.icns ]] || { echo "Resources/AppIcon.icns is missing; run scripts/generate-icon.swift" >&2; exit 1; }
    swift build -c release -Xswiftc -gnone
    BIN_DIR="$(swift build -c release -Xswiftc -gnone --show-bin-path)"
    [[ -x "$BIN_DIR/QuotaPet" ]] || { echo "Release executable was not produced" >&2; exit 1; }
    [[ -d "$BIN_DIR/QuotaPet_QuotaPet.bundle" ]] || { echo "Localization resource bundle was not produced" >&2; exit 1; }
    mkdir -p -- "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
    install -m 0755 "$BIN_DIR/QuotaPet" "$STAGED_APP/Contents/MacOS/QuotaPet"
    strip -S -x "$STAGED_APP/Contents/MacOS/QuotaPet"
    install -m 0644 Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
    install -m 0644 Resources/AppIcon.icns "$STAGED_APP/Contents/Resources/AppIcon.icns"
    ditto "$BIN_DIR/QuotaPet_QuotaPet.bundle" "$STAGED_APP/Contents/Resources/QuotaPet_QuotaPet.bundle"
    codesign --force --deep --sign - "$STAGED_APP"
    codesign --verify --deep --strict "$STAGED_APP"
    ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$STAGED_ZIP"
    unzip -tq "$STAGED_ZIP" >/dev/null
fi

TRANSACTION_DIR="$(mktemp -d "$DIST_DIR/.transaction-XXXXXX")"
printf '%s\n' "$$" >"$TRANSACTION_DIR/owner-pid"
NEW_APP="$TRANSACTION_DIR/QuotaPet.new.app"
NEW_ZIP="$TRANSACTION_DIR/QuotaPet.new.zip"
BACKUP_APP="$TRANSACTION_DIR/QuotaPet.previous.app"
BACKUP_ZIP="$TRANSACTION_DIR/QuotaPet.previous.zip"
mv -- "$STAGED_APP" "$NEW_APP"
mv -- "$STAGED_ZIP" "$NEW_ZIP"

if [[ -e "$FINAL_APP" ]]; then
    touch "$TRANSACTION_DIR/original-app-present"
    run_test_hook before_backup_app
    mv -- "$FINAL_APP" "$BACKUP_APP"
    run_test_hook after_backup_app
fi
if [[ -e "$FINAL_ZIP" ]]; then
    touch "$TRANSACTION_DIR/original-zip-present"
    run_test_hook before_backup_zip
    mv -- "$FINAL_ZIP" "$BACKUP_ZIP"
    run_test_hook after_backup_zip
fi

touch "$TRANSACTION_DIR/app-install-intent"
mv -- "$NEW_APP" "$FINAL_APP"
run_test_hook after_new_app
touch "$TRANSACTION_DIR/zip-install-intent"
mv -- "$NEW_ZIP" "$FINAL_ZIP"
run_test_hook after_new_zip

if [[ "$TEST_MODE" != "1" ]]; then
    codesign --verify --deep --strict "$FINAL_APP"
    unzip -tq "$FINAL_ZIP" >/dev/null
fi
COMMIT_MARKER_TMP="$TRANSACTION_DIR/.committed.$$"
: >"$COMMIT_MARKER_TMP"
mv -- "$COMMIT_MARKER_TMP" "$TRANSACTION_DIR/committed"
run_test_hook after_commit_marker_before_cleanup
discard_committed_transaction "$TRANSACTION_DIR"
TRANSACTION_DIR=""

echo "Built $FINAL_APP"
echo "Built $FINAL_ZIP"
