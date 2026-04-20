#!/usr/bin/env bash
#
# scripts/build.sh
#
# Builds BlinkBreak. Two phases:
#
#  1. swift build on Packages/BlinkBreakCore — verifies the shared business logic
#     compiles on the current machine. Works with Command Line Tools alone.
#
#  2. xcodegen generate + xcodebuild build — verifies the iOS project builds.
#     Requires full Xcode.app (not just Command Line Tools).
#     If only Command Line Tools are installed, this phase is skipped with a warning.
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "→ Building BlinkBreakCore package..."
(
  cd Packages/BlinkBreakCore
  swift build
)
echo "  ok — BlinkBreakCore built."

echo ""
echo "→ Generating Xcode project with xcodegen..."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "  xcodegen not installed. Install via 'brew install xcodegen'."
  exit 1
fi
# BugReport.xcconfig is gitignored (contains a GitHub PAT). Create a stub if
# missing so xcodegen doesn't fail validation on the configFiles reference.
XCCONFIG="BlinkBreak/BugReport/BugReport.xcconfig"
if [ ! -f "$XCCONFIG" ]; then
  echo "  creating stub $XCCONFIG (gitignored)..."
  cp BlinkBreak/BugReport/BugReport.xcconfig.example "$XCCONFIG"
fi
xcodegen generate
echo "  ok — BlinkBreak.xcodeproj generated."

echo ""
echo "→ Checking for full Xcode.app..."
DEVELOPER_DIR="$(xcode-select -p)"
if [[ "$DEVELOPER_DIR" == *"CommandLineTools"* ]]; then
  echo "  ⚠ Only Command Line Tools are installed at $DEVELOPER_DIR."
  echo "  xcodebuild cannot compile iOS/watchOS targets without full Xcode.app."
  echo "  Install Xcode from the Mac App Store, then run:"
  echo "    sudo xcode-select -s /Applications/Xcode.app"
  echo "  Skipping xcodebuild phase."
  echo ""
  echo "✓ BlinkBreakCore build succeeded (app targets skipped)."
  exit 0
fi

echo "  full Xcode found at $DEVELOPER_DIR."

echo ""
echo "→ Building iOS app target..."
xcodebuild build \
  -project BlinkBreak.xcodeproj \
  -scheme BlinkBreak \
  -destination 'generic/platform=iOS Simulator' \
  -quiet
echo "  ok — BlinkBreak (iOS) built."

echo ""
echo "✓ Build passed."
