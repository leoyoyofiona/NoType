#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$BUILD_DIR/installer"
APP_NAME="NoType.app"
APP_IDENTIFIER="com.leo.notype"
PKG_IDENTIFIER="com.leo.notype.installer"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Sources/notype/Resources/Info.plist")}"
KEYCHAIN="$HOME/Library/Keychains/notype-dev.keychain-db"
SIGNING_SCRIPT="$ROOT_DIR/scripts/setup_dev_signing.sh"
ICON_PATH="$ROOT_DIR/Sources/notype/Resources/AppIcon.icns"
SIGNING_MODE="${NOTYPE_SIGNING_MODE:-adhoc}"

APP_SOURCE_EXECUTABLE="$BUILD_DIR/release/NoType"
APP_BUNDLE_DIR="$STAGING_DIR/$APP_NAME"
PKG_PATH="$DIST_DIR/NoType-Installer.pkg"
COMPONENT_PKG_PATH="$STAGING_DIR/NoType-component.pkg"
PAYLOAD_ROOT="$STAGING_DIR/root"

rm -rf "$APP_BUNDLE_DIR" "$DIST_DIR/$APP_NAME" "$PKG_PATH" "$COMPONENT_PKG_PATH" "$PAYLOAD_ROOT"
mkdir -p "$DIST_DIR" "$APP_BUNDLE_DIR/Contents/MacOS" "$APP_BUNDLE_DIR/Contents/Resources" "$PAYLOAD_ROOT/Applications"

swift build -c release --package-path "$ROOT_DIR"

cp "$APP_SOURCE_EXECUTABLE" "$APP_BUNDLE_DIR/Contents/MacOS/NoType"
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
cp -R "$APP_BUNDLE_DIR" "$PAYLOAD_ROOT/Applications/"

pkgbuild \
    --root "$PAYLOAD_ROOT" \
    --identifier "$PKG_IDENTIFIER" \
    --version "$VERSION" \
    --install-location "/" \
    "$COMPONENT_PKG_PATH" >/dev/null

productbuild \
    --package "$COMPONENT_PKG_PATH" \
    "$PKG_PATH" >/dev/null

echo "Built installer: $PKG_PATH"
if [[ "$SIGNING_MODE" == "dev" ]]; then
    echo "Note: the app bundle is signed with the local NoType Dev identity, but the .pkg itself is unsigned unless you provide a Developer ID Installer certificate."
else
    echo "Note: the app bundle is signed ad-hoc by default to avoid local keychain prompts. The .pkg itself is still unsigned unless you provide a Developer ID Installer certificate."
fi
