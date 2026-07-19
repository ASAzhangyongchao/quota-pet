#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
VERSION="${1:-}"
SHA256="${2:-}"
OUTPUT_ARGUMENT="${3:-Casks/quotapet.rb}"

fail() {
    echo "Cask update failed: $*" >&2
    exit 1
}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be MAJOR.MINOR.PATCH"
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "SHA256 must be 64 lowercase hexadecimal characters"

case "$OUTPUT_ARGUMENT" in
    /*) OUTPUT="$OUTPUT_ARGUMENT" ;;
    *) OUTPUT="$PROJECT_ROOT/$OUTPUT_ARGUMENT" ;;
esac
[[ ! -L "$OUTPUT" ]] || fail "output must not be a symbolic link"
OUTPUT_PARENT="$(dirname -- "$OUTPUT")"
mkdir -p -- "$OUTPUT_PARENT"
OUTPUT_PARENT="$(cd -- "$OUTPUT_PARENT" && pwd -P)"
OUTPUT="$OUTPUT_PARENT/$(basename -- "$OUTPUT")"
TEMP_OUTPUT="$(mktemp "$OUTPUT_PARENT/.quotapet-cask.XXXXXX")"
cleanup() {
    rm -f -- "$TEMP_OUTPUT"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cat > "$TEMP_OUTPUT" <<CASK
cask "quotapet" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/ASAzhangyongchao/quota-pet/releases/download/v#{version}/QuotaPet-#{version}.dmg"
  name "QuotaPet"
  desc "Local-first macOS companion for Codex usage limits"
  homepage "https://github.com/ASAzhangyongchao/quota-pet"

  depends_on macos: ">= :ventura"

  app "QuotaPet.app"

  zap trash: "~/Library/Preferences/io.github.asazhangyongchao.quotapet.plist"
end
CASK

mv -- "$TEMP_OUTPUT" "$OUTPUT"
echo "Updated pinned cask at $OUTPUT"
