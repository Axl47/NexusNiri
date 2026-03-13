#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_PATH="${NEXUS_DEV_INSTALL_PATH:-$HOME/Applications/Nexus.app}"
INSTALL_DIR="$(dirname "$INSTALL_PATH")"

echo "Building NexusApp with SwiftPM..."
rtk proxy swift build -c debug --product NexusApp

echo "Bundling build/Nexus.app..."
export NEXUS_DEV_INSTALL_PATH="$INSTALL_PATH"
rtk proxy bash "$ROOT_DIR/scripts/make-app-bundle.sh"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_PATH"
rtk proxy ditto "$ROOT_DIR/build/Nexus.app" "$INSTALL_PATH"

if [[ "${NEXUS_ALLOW_ADHOC:-0}" == "1" ]]; then
  SIGNING_LABEL="ad-hoc"
else
  SIGNING_LABEL="${NEXUS_CODESIGN_IDENTITY:-unknown}"
fi

echo "Installed Nexus.app at $INSTALL_PATH"
echo "Signing identity: $SIGNING_LABEL"
