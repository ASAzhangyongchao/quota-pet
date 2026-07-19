#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
VERSION="${1:-}"
OUTPUT_ARGUMENT="${2:-dist/release}"

fail() {
    echo "Release prerequisite failed: $*" >&2
    exit 1
}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be MAJOR.MINOR.PATCH"
for command in swift plutil codesign lipo ditto hdiutil spctl xcrun security; do
    command -v "$command" >/dev/null 2>&1 || fail "required command is unavailable: $command"
done

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
APPLE_API_PRIVATE_KEY="${APPLE_API_PRIVATE_KEY:-}"
APPLE_API_KEY_ID="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER_ID="${APPLE_API_ISSUER_ID:-}"
[[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || fail "SIGNING_IDENTITY must name a Developer ID Application identity"
[[ -n "$APPLE_API_KEY_ID" ]] || fail "APPLE_API_KEY_ID is missing"
[[ -n "$APPLE_API_ISSUER_ID" ]] || fail "APPLE_API_ISSUER_ID is missing"
[[ -f "$APPLE_API_PRIVATE_KEY" && ! -L "$APPLE_API_PRIVATE_KEY" ]] || fail "APPLE_API_PRIVATE_KEY must be a regular private-key file"
security find-identity -v -p codesigning | grep -F -- "\"$SIGNING_IDENTITY\"" >/dev/null || fail "Developer ID Application identity is unavailable"
xcrun notarytool --version >/dev/null 2>&1 || fail "notarytool is unavailable"
xcrun --find stapler >/dev/null 2>&1 || fail "stapler is unavailable"

case "$OUTPUT_ARGUMENT" in
    /*) OUTPUT_DIR="$OUTPUT_ARGUMENT" ;;
    *) OUTPUT_DIR="$PROJECT_ROOT/$OUTPUT_ARGUMENT" ;;
esac
[[ ! -L "$OUTPUT_DIR" ]] || fail "output directory must not be a symbolic link"
mkdir -p -- "$OUTPUT_DIR"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd -P)"
FINAL_ZIP="$OUTPUT_DIR/QuotaPet-$VERSION.zip"
FINAL_DMG="$OUTPUT_DIR/QuotaPet-$VERSION.dmg"
[[ ! -e "$FINAL_ZIP" && ! -e "$FINAL_DMG" ]] || fail "release artifacts already exist"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/QuotaPet-release.XXXXXX")"
cleanup() {
    rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

APP="$TEMP_ROOT/QuotaPet.app"
mkdir -p -- "$APP/Contents/MacOS" "$APP/Contents/Resources"
cd -- "$PROJECT_ROOT"
plutil -lint Resources/Info.plist >/dev/null
[[ -s Resources/AppIcon.icns ]] || fail "Resources/AppIcon.icns is missing"

swift build -c release --arch arm64 --arch x86_64 -Xswiftc -gnone
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 -Xswiftc -gnone --show-bin-path)"
[[ -x "$BIN_DIR/QuotaPet" ]] || fail "Universal release executable was not produced"
[[ -d "$BIN_DIR/QuotaPet_QuotaPet.bundle" ]] || fail "Localization resource bundle was not produced"
lipo "$BIN_DIR/QuotaPet" -verify_arch arm64 x86_64

install -m 0755 "$BIN_DIR/QuotaPet" "$APP/Contents/MacOS/QuotaPet"
install -m 0644 Resources/Info.plist "$APP/Contents/Info.plist"
install -m 0644 Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto "$BIN_DIR/QuotaPet_QuotaPet.bundle" "$APP/Contents/Resources/QuotaPet_QuotaPet.bundle"
[[ -d "$APP/Contents/Resources/QuotaPet_QuotaPet.bundle/en.lproj" ]] || fail "English localization is missing"
[[ -d "$APP/Contents/Resources/QuotaPet_QuotaPet.bundle/zh-hans.lproj" ]] || fail "Simplified Chinese localization is missing"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"

codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/QuotaPet" -verify_arch arm64 x86_64

NOTARY_ZIP="$TEMP_ROOT/QuotaPet-notary.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
    --key "$APPLE_API_PRIVATE_KEY" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" \
    --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"

STAGED_ZIP="$TEMP_ROOT/QuotaPet-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGED_ZIP"
unzip -tq "$STAGED_ZIP" >/dev/null

DMG_ROOT="$TEMP_ROOT/dmg-root"
mkdir -p -- "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/QuotaPet.app"
ln -s /Applications "$DMG_ROOT/Applications"
STAGED_DMG="$TEMP_ROOT/QuotaPet-$VERSION.dmg"
hdiutil create -volname "QuotaPet $VERSION" -srcfolder "$DMG_ROOT" -format UDZO "$STAGED_DMG" >/dev/null
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$STAGED_DMG"
codesign --verify --strict --verbose=2 "$STAGED_DMG"
xcrun notarytool submit "$STAGED_DMG" \
    --key "$APPLE_API_PRIVATE_KEY" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" \
    --wait
xcrun stapler staple "$STAGED_DMG"
xcrun stapler validate "$STAGED_DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$STAGED_DMG"

mv -- "$STAGED_ZIP" "$FINAL_ZIP"
mv -- "$STAGED_DMG" "$FINAL_DMG"
echo "Prepared notarized release artifacts for QuotaPet $VERSION."
