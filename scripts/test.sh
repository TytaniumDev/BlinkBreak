#!/usr/bin/env bash
#
# scripts/test.sh
#
# Runs the unit test suite against BlinkBreakCore.
#
# Default path: runs `swift test` against the local package. This works
# everywhere (Command Line Tools or full Xcode), is fast, and is what you
# should use during local iteration.
#
# CI / full path: when the env var BLINKBREAK_FULL_TESTS=1 is set, also runs
# `xcodebuild test -scheme BlinkBreak` on an iOS simulator. This is what
# GitHub Actions runs on macos-15 runners where a simulator runtime is
# guaranteed available.
#

set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR="$(xcode-select -p)"
CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

echo "→ Running BlinkBreakCore tests via swift test..."
(
  cd Packages/BlinkBreakCore
  if [[ "$DEVELOPER_DIR" == *"CommandLineTools"* ]]; then
    # Command Line Tools lacks XCTest but ships the Swift Testing framework in
    # a non-standard location. Point the Swift compiler + linker at it.
    swift test \
      -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" \
      -Xlinker -F -Xlinker "$CLT_FRAMEWORKS" \
      -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS"
  else
    # Full Xcode.app provides Swift Testing in the standard toolchain path.
    swift test
  fi
)
echo "  ok — swift test passed."

if [[ "${BLINKBREAK_FULL_TESTS:-}" != "1" ]]; then
  echo ""
  echo "✓ Tests passed (swift test). Set BLINKBREAK_FULL_TESTS=1 to also run"
  echo "  xcodebuild test via the iOS simulator scheme (for CI)."
  exit 0
fi

echo ""
echo "→ BLINKBREAK_FULL_TESTS=1 — running iOS scheme tests via xcodebuild..."
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
# Pick the first available iPhone simulator whose runtime meets our
# iOS 26.1 deployment target. Hard-coding "iPhone 16" alone breaks because
# runners ship multiple iOS versions and xcodebuild filters out destinations
# whose runtime is older than the project's deployment target — so a
# 26.0 simulator picked here would be rejected by xcodebuild as ineligible.
SIM_ID=$(xcrun simctl list --json devices available | \
  python3 -c "import json,re,sys
d=json.load(sys.stdin)['devices']
def ver(name):
    m=re.search(r'iOS-(\d+)-(\d+)', name)
    return (int(m.group(1)), int(m.group(2))) if m else (0,0)
devs=[(r,x) for r,xs in d.items() if ver(r) >= (26,1) for x in xs if x.get('isAvailable')]
iphones=[x for _,x in devs if 'iPhone' in x['name']]
sys.exit('no iOS 26.1+ iPhone simulator available') if not iphones else print(iphones[0]['udid'])")
echo "  using iOS simulator id $SIM_ID"
xcodebuild test \
  -project BlinkBreak.xcodeproj \
  -scheme BlinkBreak \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -quiet
echo "  ok — xcodebuild test passed."

echo ""
echo "✓ Tests passed (swift test + xcodebuild test)."
