#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/Nexus.app"

rtk proxy bash "$ROOT_DIR/scripts/dev-build.sh"

echo "Launching Nexus.app..."
rtk proxy open -na "$APP_PATH"
