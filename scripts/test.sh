#!/usr/bin/env bash
#
# scripts/test.sh
#
# Runs the unit test suite against BlinkBreakCore.
#
# On full Xcode.app machines: runs `xcodebuild test -scheme BlinkBreak`, which
# is what CI uses.
#
# On Command Line Tools only: runs `swift test` against the local package,
# passing the framework search path + rpath flags needed to find the Swift
# Testing framework bundled with the CLT.
#

set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR="$(xcode-select -p)"
CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

if [[ "$DEVELOPER_DIR" == *"CommandLineTools"* ]]; then
  echo "→ Running BlinkBreakCore tests via swift test (Command Line Tools mode)..."
  cd Packages/BlinkBreakCore
  swift test \
    -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" \
    -Xlinker -F -Xlinker "$CLT_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS"
  echo ""
  echo "✓ Tests passed (swift test)."
  exit 0
fi

echo "→ Running BlinkBreakCore tests via swift test..."
(
  cd Packages/BlinkBreakCore
  swift test
)
echo "  ok — swift test passed."

echo ""
echo "→ Running iOS test scheme via xcodebuild test..."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "  xcodegen not installed. Install via 'brew install xcodegen'."
  exit 1
fi
xcodegen generate

# Use the oldest-new iOS simulator we support as the destination. CI pins a
# specific runner so this should resolve deterministically.
xcodebuild test \
  -project BlinkBreak.xcodeproj \
  -scheme BlinkBreak \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -quiet
echo "  ok — xcodebuild test passed."

echo ""
echo "✓ Tests passed."
