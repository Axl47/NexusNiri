#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nexus.app"
APP_DIR="$ROOT_DIR/build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$ROOT_DIR/AppResources/Info.plist"
ENTITLEMENTS_PATH="$ROOT_DIR/AppResources/Nexus.entitlements"
METADATA_PATH="$RESOURCES_DIR/dev-build-metadata.json"
INSTALL_PATH="${NEXUS_DEV_INSTALL_PATH:-$HOME/Applications/Nexus.app}"

if [[ "${NEXUS_ALLOW_ADHOC:-0}" == "1" ]]; then
  SIGNING_MODE="adHoc"
  SIGNING_IDENTITY="-"
  SIGNING_LABEL="ad-hoc"
  echo "Warning: building an ad-hoc Nexus.app. Accessibility trust will not be reliable for window choreography testing."
else
  if [[ -z "${NEXUS_CODESIGN_IDENTITY:-}" ]]; then
    echo "Error: NEXUS_CODESIGN_IDENTITY is required for dev builds that exercise Accessibility."
    echo "Set NEXUS_CODESIGN_IDENTITY to your stable self-signed certificate name, or set NEXUS_ALLOW_ADHOC=1 only for non-TCC debugging."
    exit 1
  fi

  if ! rtk proxy security find-identity -v -p codesigning | grep -F "\"$NEXUS_CODESIGN_IDENTITY\"" > /dev/null; then
    echo "Error: '$NEXUS_CODESIGN_IDENTITY' is not a valid macOS code-signing identity."
    echo "Create or select a certificate that appears in 'security find-identity -v -p codesigning', then rebuild."
    exit 1
  fi

  SIGNING_MODE="selfSigned"
  SIGNING_IDENTITY="$NEXUS_CODESIGN_IDENTITY"
  SIGNING_LABEL="$NEXUS_CODESIGN_IDENTITY"
fi

BIN_DIR="$(cd "$ROOT_DIR" && rtk proxy swift build -c debug --show-bin-path | tail -n 1)"
EXECUTABLE_PATH="$BIN_DIR/NexusApp"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
BUILD_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/NexusApp"

if compgen -G "$BIN_DIR/*.bundle" > /dev/null; then
  cp -R "$BIN_DIR"/*.bundle "$RESOURCES_DIR/"
fi

cat > "$METADATA_PATH" <<EOF
{
  "bundleIdentifier": "$(json_escape "$BUNDLE_IDENTIFIER")",
  "signingMode": "$SIGNING_MODE",
  "signingIdentityLabel": "$(json_escape "$SIGNING_LABEL")",
  "expectedInstallPath": "$(json_escape "$INSTALL_PATH")",
  "buildTimestamp": "$BUILD_TIMESTAMP"
}
EOF

echo "Signing $APP_DIR with $SIGNING_LABEL..."
rtk proxy codesign \
  --force \
  --deep \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "$ENTITLEMENTS_PATH" \
  "$APP_DIR"
