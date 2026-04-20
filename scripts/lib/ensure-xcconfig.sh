#!/usr/bin/env bash
#
# scripts/lib/ensure-xcconfig.sh
#
# Sourced by build.sh and test-integration.sh. Creates a stub
# BlinkBreak/BugReport/BugReport.xcconfig from the .example template if missing,
# so xcodegen doesn't fail validation on the configFiles reference.
#
# The real xcconfig (containing a GitHub PAT) is gitignored. Production CI
# generates its own from secrets at build time.
#

ensure_bug_report_xcconfig() {
  local xcconfig="BlinkBreak/BugReport/BugReport.xcconfig"
  if [ ! -f "$xcconfig" ]; then
    echo "  creating stub $xcconfig (gitignored)..."
    cp BlinkBreak/BugReport/BugReport.xcconfig.example "$xcconfig"
  fi
}
