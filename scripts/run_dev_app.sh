#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_ROOT="$HOME/Applications"
APP_DIR="$INSTALL_ROOT/NoType.app"
EXECUTABLE="$ROOT_DIR/.build/debug/NoType"
SIGNING_SCRIPT="$ROOT_DIR/scripts/setup_dev_signing.sh"
ICON_PATH="$ROOT_DIR/Sources/notype/Resources/AppIcon.icns"
IDENTITY_NAME="NoType Dev"
KEYCHAIN="$HOME/Library/Keychains/notype-dev.keychain-db"

swift build --package-path "$ROOT_DIR"
"$SIGNING_SCRIPT"

mkdir -p "$INSTALL_ROOT"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/NoType"
cp "$ROOT_DIR/Sources/notype/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$ICON_PATH" ]; then
  cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --keychain "$KEYCHAIN" --sign "$IDENTITY_NAME" "$APP_DIR" >/dev/null

open "$APP_DIR"
