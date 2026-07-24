#!/usr/bin/env bash
# Build ad-hoc (non-notarized) ZIP + DMG for interim GitHub Releases.
# Does NOT use Developer ID / notarytool. Downloaders will see Gatekeeper warnings.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
VERSION="$(sed -n '1p' "$PROJECT_ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }

OUTPUT_DIR="${1:-$PROJECT_ROOT/dist/adhoc-release}"
mkdir -p -- "$OUTPUT_DIR"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd -P)"
FINAL_ZIP="$OUTPUT_DIR/QuotaPet-$VERSION.zip"
FINAL_DMG="$OUTPUT_DIR/QuotaPet-$VERSION.dmg"
[[ ! -e "$FINAL_ZIP" && ! -e "$FINAL_DMG" ]] || {
  echo "Artifacts already exist in $OUTPUT_DIR — remove them first." >&2
  exit 1
}

cd -- "$PROJECT_ROOT"
./scripts/build-app.sh
./scripts/verify-package.sh

APP="$PROJECT_ROOT/dist/QuotaPet.app"
[[ -d "$APP" ]] || { echo "Missing $APP" >&2; exit 1; }

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/QuotaPet-adhoc.XXXXXX")"
cleanup() { rm -rf -- "$TEMP_ROOT"; }
trap cleanup EXIT

ditto -c -k --sequesterRsrc --keepParent "$APP" "$TEMP_ROOT/QuotaPet-$VERSION.zip"

DMG_ROOT="$TEMP_ROOT/dmg-root"
mkdir -p -- "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/QuotaPet.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "QuotaPet $VERSION" -srcfolder "$DMG_ROOT" -ov -format UDZO "$TEMP_ROOT/QuotaPet-$VERSION.dmg" >/dev/null

mv -- "$TEMP_ROOT/QuotaPet-$VERSION.zip" "$FINAL_ZIP"
mv -- "$TEMP_ROOT/QuotaPet-$VERSION.dmg" "$FINAL_DMG"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "QuotaPet-$VERSION.zip" "QuotaPet-$VERSION.dmg" > SHA256SUMS
)

echo "Prepared ad-hoc (non-notarized) artifacts:"
echo "  $FINAL_ZIP"
echo "  $FINAL_DMG"
echo "  $OUTPUT_DIR/SHA256SUMS"
