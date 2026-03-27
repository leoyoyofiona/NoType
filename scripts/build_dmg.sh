#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$BUILD_DIR/dmg"
APP_NAME="NoType.app"
APP_BUNDLE_DIR="$STAGING_DIR/$APP_NAME"
DMG_ROOT="$STAGING_DIR/root"
DMG_PATH="$DIST_DIR/NoType.dmg"
ICON_PATH="$ROOT_DIR/Sources/notype/Resources/AppIcon.icns"
KEYCHAIN="$HOME/Library/Keychains/notype-dev.keychain-db"
SIGNING_SCRIPT="$ROOT_DIR/scripts/setup_dev_signing.sh"
SIGNING_MODE="${NOTYPE_SIGNING_MODE:-adhoc}"

rm -rf "$APP_BUNDLE_DIR" "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DIST_DIR" "$APP_BUNDLE_DIR/Contents/MacOS" "$APP_BUNDLE_DIR/Contents/Resources" "$DMG_ROOT"

swift build -c release --package-path "$ROOT_DIR"

cp "$BUILD_DIR/release/NoType" "$APP_BUNDLE_DIR/Contents/MacOS/NoType"
cp "$ROOT_DIR/Sources/notype/Resources/Info.plist" "$APP_BUNDLE_DIR/Contents/Info.plist"
if [[ -f "$ICON_PATH" ]]; then
    cp "$ICON_PATH" "$APP_BUNDLE_DIR/Contents/Resources/AppIcon.icns"
fi

if [[ "$SIGNING_MODE" == "dev" ]]; then
    "$SIGNING_SCRIPT" >/dev/null
    IDENTITY_HASH="$(
        security find-identity -v -p codesigning "$KEYCHAIN" |
        awk '/NoType Dev/ {print $2; exit}'
    )"

    if [[ -z "$IDENTITY_HASH" ]]; then
        echo "NoType Dev signing identity not found in $KEYCHAIN" >&2
        exit 1
    fi

    codesign --force --deep --keychain "$KEYCHAIN" --sign "$IDENTITY_HASH" "$APP_BUNDLE_DIR" >/dev/null
else
    codesign --force --deep --sign - "$APP_BUNDLE_DIR" >/dev/null
fi

cp -R "$APP_BUNDLE_DIR" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
    -volname "NoType" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "Built dmg: $DMG_PATH"
if [[ "$SIGNING_MODE" == "dev" ]]; then
    echo "Signing: local NoType Dev identity"
else
    echo "Signing: ad-hoc (default, avoids local keychain prompts)"
fi
