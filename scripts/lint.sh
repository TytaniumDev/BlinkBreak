#!/usr/bin/env bash
#
# scripts/lint.sh
#
# Lints the BlinkBreak sources. Two checks:
#
#  1. BlinkBreakCore must not import any UI or Apple-platform-only framework
#     (SwiftUI, UIKit, WatchKit, AlarmKit, ActivityKit, AppIntents) or a
#     third-party SDK (Sentry). Enforced via grep against
#     Packages/BlinkBreakCore/Sources/. The check is a structural guarantee of the
#     UI/logic separation rule — if this fails, your PR broke the boundary.
#
#  2. SwiftLint, if installed. Skipped with a note if not installed, because
#     the official SwiftLint bottle requires full Xcode.app to build — developers
#     on Command Line Tools only will skip it, but CI (which runs on a macOS
#     runner with full Xcode) will not.
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "→ Checking BlinkBreakCore for forbidden imports..."
if grep -rEn "^\s*import\s+(SwiftUI|UIKit|WatchKit|AlarmKit|ActivityKit|AppIntents|Sentry)\b" Packages/BlinkBreakCore/Sources/; then
  echo "✗ Forbidden import found in BlinkBreakCore. Move that code to the app target."
  exit 1
fi
echo "  ok — no forbidden imports in BlinkBreakCore."

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
