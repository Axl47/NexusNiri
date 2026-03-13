#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Building NexusApp with SwiftPM..."
rtk proxy swift build -c debug --product NexusApp

echo "Bundling build/Nexus.app..."
rtk proxy bash "$ROOT_DIR/scripts/make-app-bundle.sh"

echo "Nexus.app ready at $ROOT_DIR/build/Nexus.app"
