#!/usr/bin/env bash
#
# scripts/test-integration.sh
#
# Runs the XCUITest integration suite — 21 end-to-end tests that drive the
# real iOS app through a simulator.
#
# SLOW (~4 minutes). ONLY run as a final verification step before committing
# or creating a PR. Do NOT run during iteration — use ./scripts/test.sh
# instead for the fast unit-test loop (~4ms, runs in swift test).
#
# The suite covers:
#   - App launch and idle state
#   - Start/Stop transitions
#   - Full break cycle (running → breakActive → lookAway → running)
#   - State reconciliation across app terminate + relaunch
#   - Rapid start/stop stress testing
#
# What the suite CANNOT cover (requires on-device manual verification):
#   - Focus Mode break-through semantics
#   - Actual custom alarm sound playback through the speaker
#
# The UITests scheme sets BB_BREAK_INTERVAL=3 and BB_LOOKAWAY_DURATION=3 so
# tests can exercise a full cycle in ~6 seconds of wall-clock time instead of
# 20 minutes + 20 seconds.
#

set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR="$(xcode-select -p)"
if [[ "$DEVELOPER_DIR" == *"CommandLineTools"* ]]; then
  echo "✗ test-integration.sh requires the full Xcode.app, not just Command Line Tools."
  echo "  Install Xcode from the App Store and run:"
  echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ xcodegen not installed. Install via 'brew install xcodegen'."
  exit 1
fi

echo "→ Regenerating Xcode project via xcodegen..."
xcodegen generate >/dev/null
echo "  ok — project regenerated."

# Fresh simulator state avoids the intermittent "Application failed preflight
# checks" flake where a stale runner bundle fails to launch. Costs a few
# seconds, much cheaper than debugging transient false positives.
echo ""
echo "→ Resetting simulator state (shutdown + erase)..."
xcrun simctl shutdown all 2>/dev/null || true
xcrun simctl erase all >/dev/null 2>&1 || true
sleep 2
echo "  ok — simulators reset."

echo ""
echo "→ Running XCUITest integration suite (expect ~4 minutes)..."
echo "  BB_BREAK_INTERVAL=3, BB_LOOKAWAY_DURATION=3 set by the UITests scheme."
echo ""

xcodebuild test \
  -project BlinkBreak.xcodeproj \
  -scheme BlinkBreakUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet

echo ""
echo "✓ Integration tests passed."
echo ""
echo "Reminder: this suite does NOT verify hardware-dependent behavior"
echo "(Focus Mode break-through, real alarm-volume playback). Those still"
echo "require the manual on-device checklist before shipping."
