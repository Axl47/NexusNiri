#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Removing SwiftPM and app bundle artifacts..."
rtk proxy rm -rf "$ROOT_DIR/.build" "$ROOT_DIR/build"
