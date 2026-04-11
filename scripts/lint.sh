#!/usr/bin/env bash
#
# scripts/lint.sh
#
# Lints the BlinkBreak sources. Two checks:
#
#  1. BlinkBreakCore must not import any UI framework. This is enforced via grep
#     against Packages/BlinkBreakCore/Sources/. The check is a structural guarantee
#     of the UI/logic separation rule — if this fails, your PR broke the boundary.
#
#  2. SwiftLint, if installed. Skipped with a note if not installed, because
#     the official SwiftLint bottle requires full Xcode.app to build — developers
#     on Command Line Tools only will skip it, but CI (which runs on a macOS
#     runner with full Xcode) will not.
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "→ Checking BlinkBreakCore for forbidden UI imports..."
# Look for any import SwiftUI / UIKit / WatchKit in the core package sources.
if grep -rEn "^\s*import\s+(SwiftUI|UIKit|WatchKit)" Packages/BlinkBreakCore/Sources/; then
  echo "✗ Forbidden UI framework import found in BlinkBreakCore. Move it to an app target."
  exit 1
fi
echo "  ok — no UI framework imports in BlinkBreakCore."

echo ""
echo "→ Running SwiftLint (if installed)..."
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint --quiet
  echo "  ok — swiftlint passed."
else
  echo "  swiftlint not installed — skipping. (Install via 'brew install swiftlint'"
  echo "  on a machine with full Xcode.app.)"
fi

echo ""
echo "✓ Lint passed."
