#!/usr/bin/env bash
# Capture App Store marketing screenshots.
#
# Runs the ScreenshotTests class against a 6.9" iPhone simulator, then exports
# the PNG attachments into build/screenshots/ for upload to App Store Connect.
#
# Usage:
#   ./scripts/capture-screenshots.sh                  # iPhone 16 Pro Max (6.9")
#   ./scripts/capture-screenshots.sh "iPhone 16 Pro"  # override simulator
#
# App Store Connect currently requires 6.9" iPhone screenshots. The 6.7"
# "Pro Max" slot from prior generations is optional now but still accepted.

set -euo pipefail

DEVICE="${1:-iPhone 16 Pro Max}"
OS="${2:-latest}"
RESULT_BUNDLE="build/screenshots.xcresult"
OUT_DIR="build/screenshots"

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Erasing previous result bundle + output"
rm -rf "$RESULT_BUNDLE" "$OUT_DIR"
mkdir -p "$(dirname "$RESULT_BUNDLE")"

echo "==> Running ScreenshotTests on $DEVICE ($OS)"
xcodebuild test \
    -project BlinkBreak.xcodeproj \
    -scheme BlinkBreakUITests \
    -destination "platform=iOS Simulator,name=$DEVICE,OS=$OS" \
    -only-testing:BlinkBreakUITests/ScreenshotTests \
    -resultBundlePath "$RESULT_BUNDLE" \
    BB_CAPTURE_SCREENSHOTS=1 \
    | xcpretty || true

echo "==> Exporting PNG attachments to $OUT_DIR"
xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$OUT_DIR"

echo
echo "Screenshots written to $OUT_DIR"
ls -la "$OUT_DIR"
