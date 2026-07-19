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
    SOURCE_APP="$TEST_ROOT/source/QuotaPet.app"
    [[ -d "$TEST_ROOT/Applications" && ! -L "$TEST_ROOT/Applications" ]] || { echo "Unsafe transaction test Applications directory." >&2; exit 64; }
    APPLICATIONS_DIR="$(cd -- "$TEST_ROOT/Applications" && pwd -P)"
    [[ "$APPLICATIONS_DIR" == "$TEST_ROOT/Applications" ]] || { echo "Transaction test Applications must not escape its root." >&2; exit 64; }
else
    SOURCE_APP="$PROJECT_ROOT/dist/QuotaPet.app"
    [[ -d /Applications && ! -L /Applications ]] || { echo "Unsafe /Applications directory." >&2; exit 1; }
    APPLICATIONS_DIR="$(cd -- /Applications && pwd -P)"
    [[ "$APPLICATIONS_DIR" == "/Applications" ]] || { echo "/Applications escaped its expected path." >&2; exit 1; }
fi

TARGET_APP="$APPLICATIONS_DIR/QuotaPet.app"
EXPECTED_EXECUTABLE="$TARGET_APP/Contents/MacOS/QuotaPet"
EXPECTED_BUNDLE_ID="io.github.asazhangyongchao.quotapet"
TRANSACTION_DIR=""

case "$TARGET_APP" in
    /Applications/QuotaPet.app|*/QuotaPet-transaction-tests-*/Applications/QuotaPet.app) ;;
    *) echo "Refusing unsafe application target: $TARGET_APP" >&2; exit 1 ;;
esac

run_test_hook() {
    local point="$1"
    [[ "$TEST_MODE" == "1" ]] || return 0
    case "$TEST_HOOK" in
        "fail:$point") return 97 ;;
        "int:$point") kill -INT "$$" ;;
        "term:$point") kill -TERM "$$" ;;
    esac
}

safe_remove_transaction() {
    local path="${1:-}"
    case "$path" in
        "$APPLICATIONS_DIR"/.QuotaPet.install.*)
            [[ -n "$path" && "$path" != "/" && "$path" != "$APPLICATIONS_DIR" ]] || return 1
            rm -rf -- "$path"
            ;;
        "") ;;
        *) echo "Refusing unsafe transaction cleanup path: $path" >&2; return 1 ;;
    esac
}

safe_remove_target() {
    [[ "$1" == "$TARGET_APP" ]] || { echo "Refusing unsafe target cleanup path: $1" >&2; return 1; }
    rm -rf -- "$1"
}

rollback_transaction() {
    local transaction="$1"
    local backup="$transaction/QuotaPet.previous.app"
    local new_payload="$transaction/QuotaPet.new.app"
    if [[ -e "$backup" ]]; then
        [[ ! -e "$TARGET_APP" ]] || safe_remove_target "$TARGET_APP"
        mv -- "$backup" "$TARGET_APP"
    elif [[ -e "$transaction/original-app-present" ]]; then
        # The original never left target, or was already restored. Never delete it.
        return 0
    elif [[ -e "$transaction/app-install-intent" && ! -e "$new_payload" && -e "$TARGET_APP" ]]; then
        # There was no original and the staged app demonstrably reached target.
        safe_remove_target "$TARGET_APP"
    fi
}

validate_transaction_dir() {
    local transaction="$1" canonical
    [[ -d "$transaction" && ! -L "$transaction" ]] || return 1
    canonical="$(cd -- "$transaction" && pwd -P)"
    [[ "$canonical" == "$transaction" && "$canonical" == "$APPLICATIONS_DIR"/.QuotaPet.install.* ]]
}

recover_orphaned_transactions() {
    local transaction owner
    for transaction in "$APPLICATIONS_DIR"/.QuotaPet.install.*; do
        [[ -d "$transaction" ]] || continue
        validate_transaction_dir "$transaction" || { echo "Refusing unsafe install transaction: $transaction" >&2; return 1; }
        owner="$(sed -n '1p' "$transaction/owner-pid" 2>/dev/null || true)"
        if [[ "$owner" =~ ^[0-9]+$ && "$owner" != "$$" ]] && kill -0 "$owner" 2>/dev/null; then
            echo "Another QuotaPet install transaction is active." >&2
            return 1
        fi
        TRANSACTION_DIR="$transaction"
        rollback_transaction "$transaction"
        safe_remove_transaction "$transaction"
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
        rollback_transaction "$TRANSACTION_DIR" || rollback_ok=0
    fi
    if [[ "$rollback_ok" -eq 1 ]]; then
        safe_remove_transaction "$TRANSACTION_DIR" || true
    else
        echo "Rollback was incomplete; preserved transaction at $TRANSACTION_DIR" >&2
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -d "$SOURCE_APP" ]] || { echo "Missing $SOURCE_APP; run scripts/build-app.sh first." >&2; exit 1; }
[[ -d "$APPLICATIONS_DIR" && -w "$APPLICATIONS_DIR" ]] || {
    echo "$APPLICATIONS_DIR is not writable by the current user. Use an account with application-install permission." >&2
    exit 1
}

if [[ "$TEST_MODE" != "1" ]]; then
    codesign --verify --deep --strict "$SOURCE_APP"
    [[ "$(plutil -extract CFBundleIdentifier raw "$SOURCE_APP/Contents/Info.plist")" == "$EXPECTED_BUNDLE_ID" ]] || {
        echo "Unexpected bundle identifier in source app." >&2
        exit 1
    }
    [[ -x "$SOURCE_APP/Contents/MacOS/QuotaPet" ]] || { echo "Source executable is missing." >&2; exit 1; }
fi

recover_orphaned_transactions
TRANSACTION_DIR="$(mktemp -d "$APPLICATIONS_DIR/.QuotaPet.install.XXXXXX")"
printf '%s\n' "$$" >"$TRANSACTION_DIR/owner-pid"
NEW_APP="$TRANSACTION_DIR/QuotaPet.new.app"
BACKUP_APP="$TRANSACTION_DIR/QuotaPet.previous.app"

if [[ "$TEST_MODE" == "1" ]]; then
    cp -R -- "$SOURCE_APP" "$NEW_APP"
else
    ditto --rsrc --extattr "$SOURCE_APP" "$NEW_APP"
    codesign --verify --deep --strict "$NEW_APP"
    [[ "$(plutil -extract CFBundleIdentifier raw "$NEW_APP/Contents/Info.plist")" == "$EXPECTED_BUNDLE_ID" ]] || {
        echo "Copied app failed bundle identity verification." >&2
        exit 1
    }
fi

if [[ "$TEST_MODE" != "1" ]]; then
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
fi

if [[ -e "$TARGET_APP" ]]; then
    touch "$TRANSACTION_DIR/original-app-present"
    run_test_hook before_backup_app
    mv -- "$TARGET_APP" "$BACKUP_APP"
    run_test_hook after_backup_app
fi
touch "$TRANSACTION_DIR/app-install-intent"
mv -- "$NEW_APP" "$TARGET_APP"
run_test_hook after_new_app

if [[ "$TEST_MODE" != "1" ]]; then
    codesign --verify --deep --strict "$TARGET_APP"
    [[ "$(plutil -extract CFBundleIdentifier raw "$TARGET_APP/Contents/Info.plist")" == "$EXPECTED_BUNDLE_ID" ]] || {
        echo "Installed app failed bundle identity verification." >&2
        exit 1
    }
fi

safe_remove_transaction "$TRANSACTION_DIR"
TRANSACTION_DIR=""

echo "Installed $TARGET_APP"
