#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nexus.app"
APP_DIR="$ROOT_DIR/build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

BIN_DIR="$(cd "$ROOT_DIR" && rtk proxy swift build -c debug --show-bin-path | tail -n 1)"
EXECUTABLE_PATH="$BIN_DIR/NexusApp"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/AppResources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/NexusApp"

if compgen -G "$BIN_DIR/*.bundle" > /dev/null; then
  cp -R "$BIN_DIR"/*.bundle "$RESOURCES_DIR/"
fi

echo "Ad-hoc signing $APP_DIR..."
rtk proxy codesign \
  --force \
  --deep \
  --sign - \
  --entitlements "$ROOT_DIR/AppResources/Nexus.entitlements" \
  "$APP_DIR"
