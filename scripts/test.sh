#!/usr/bin/env bash
#
# scripts/test.sh
#
# Runs the BlinkBreakCore unit test suite via `swift test`. Sub-second runtime.
# What you should use during local iteration. CI runs this same script.
#
# For end-to-end verification (XCUITest through the simulator), use
# scripts/test-integration.sh.
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "→ Running BlinkBreakCore tests via swift test..."
(
  cd Packages/BlinkBreakCore
  swift test
)

echo ""
echo "✓ Tests passed."
