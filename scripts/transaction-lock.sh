#!/usr/bin/env bash

# Callers provide canonical LOCK_PARENT, LOCK_NAME, and LOCK_COMMAND values.
LOCK_DIR="$LOCK_PARENT/$LOCK_NAME"
LOCK_TOKEN="$$.$RANDOM.$RANDOM.$(date +%s)"
LOCK_HELD=0

validate_lock_path() {
    [[ -d "$LOCK_PARENT" && ! -L "$LOCK_PARENT" && "$LOCK_DIR" == "$LOCK_PARENT/$LOCK_NAME" ]]
}

safe_remove_lock_claim() {
    local claim="$1"
    case "$claim" in
        "$LOCK_DIR".claim.*)
            [[ -d "$claim" && ! -L "$claim" ]] || return 1
            rm -rf -- "$claim"
            ;;
        *) echo "Refusing unsafe lock claim cleanup: $claim" >&2; return 1 ;;
    esac
}

lock_metadata_complete() {
    [[ -s "$LOCK_DIR/owner-pid" && -s "$LOCK_DIR/owner-command" && -s "$LOCK_DIR/owner-token" ]]
}

lock_owner_is_active() {
    local owner_pid owner_command owner_token
    owner_pid="$(sed -n '1p' "$LOCK_DIR/owner-pid" 2>/dev/null || true)"
    owner_command="$(sed -n '1p' "$LOCK_DIR/owner-command" 2>/dev/null || true)"
    owner_token="$(sed -n '1p' "$LOCK_DIR/owner-token" 2>/dev/null || true)"
    [[ "$owner_pid" =~ ^[0-9]+$ && "$owner_command" == "$LOCK_COMMAND" && -n "$owner_token" ]] || return 1
    kill -0 "$owner_pid" 2>/dev/null || return 1
    # PID reuse with matching lock metadata is conservatively busy, never reclaimed.
    return 0
}

incomplete_lock_is_recent() {
    local modified now
    modified="$(stat -f %m "$LOCK_DIR" 2>/dev/null || true)"
    now="$(date +%s)"
    [[ "$modified" =~ ^[0-9]+$ ]] && (( now - modified < 5 ))
}

acquire_global_lock() {
    local claim
    validate_lock_path || { echo "Unsafe transaction lock path: $LOCK_DIR" >&2; return 1; }
    for _ in 1 2 3 4; do
        if mkdir -- "$LOCK_DIR" 2>/dev/null; then
            (
                umask 077
                printf '%s\n' "$$" >"$LOCK_DIR/owner-pid"
                printf '%s\n' "$LOCK_COMMAND" >"$LOCK_DIR/owner-command"
                printf '%s\n' "$LOCK_TOKEN" >"$LOCK_DIR/owner-token"
            )
            LOCK_HELD=1
            return 0
        fi
        [[ -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]] || { echo "Unsafe transaction lock: $LOCK_DIR" >&2; return 1; }
        if lock_metadata_complete && lock_owner_is_active; then
            echo "Another QuotaPet transaction is active: $LOCK_COMMAND" >&2
            return 1
        fi
        if ! lock_metadata_complete && incomplete_lock_is_recent; then
            echo "Another QuotaPet transaction lock is being initialized." >&2
            return 1
        fi
        claim="$LOCK_DIR.claim.$LOCK_TOKEN"
        [[ ! -e "$claim" && ! -L "$claim" ]] || { echo "Lock claim already exists: $claim" >&2; return 1; }
        if mv -- "$LOCK_DIR" "$claim" 2>/dev/null; then
            safe_remove_lock_claim "$claim"
        fi
    done
    echo "Could not acquire QuotaPet transaction lock: $LOCK_DIR" >&2
    return 1
}

release_global_lock() {
    local stored_token claim
    [[ "$LOCK_HELD" -eq 1 ]] || return 0
    stored_token="$(sed -n '1p' "$LOCK_DIR/owner-token" 2>/dev/null || true)"
    [[ "$stored_token" == "$LOCK_TOKEN" ]] || {
        echo "Refusing to release a transaction lock owned by another token." >&2
        return 1
    }
    claim="$LOCK_DIR.claim.$LOCK_TOKEN"
    [[ ! -e "$claim" && ! -L "$claim" ]] || { echo "Lock release claim already exists: $claim" >&2; return 1; }
    mv -- "$LOCK_DIR" "$claim"
    LOCK_HELD=0
    safe_remove_lock_claim "$claim"
}
