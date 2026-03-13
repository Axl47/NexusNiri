#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/AppResources/Info.plist"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"

echo "Resetting Accessibility permission for $BUNDLE_IDENTIFIER..."
rtk proxy tccutil reset Accessibility "$BUNDLE_IDENTIFIER"
echo "Accessibility permission reset complete."
echo "The next Nexus launch should prompt again or require re-enabling it in System Settings."
