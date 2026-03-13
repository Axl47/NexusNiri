#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  cat >&2 <<'EOF'
xcodegen is required to regenerate Nexus.xcodeproj.

Install it with:
  rtk proxy brew install xcodegen
EOF
  exit 1
fi

cd "$ROOT_DIR"
xcodegen

echo "Generated $ROOT_DIR/Nexus.xcodeproj"
