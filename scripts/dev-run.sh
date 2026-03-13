#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${NEXUS_DEV_INSTALL_PATH:-$HOME/Applications/Nexus.app}"

if [[ "${NEXUS_RESET_ACCESSIBILITY_ON_START:-0}" == "1" ]]; then
  rtk proxy bash "$ROOT_DIR/scripts/dev-reset-accessibility.sh"
fi

rtk proxy bash "$ROOT_DIR/scripts/dev-build.sh"

echo "Launching Nexus.app..."
rtk proxy open -n "$APP_PATH"
