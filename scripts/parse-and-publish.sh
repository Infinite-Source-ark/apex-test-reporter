#!/usr/bin/env bash
set -euo pipefail

# --- Inputs ---
JSON="${JSON_PATH:?JSON_PATH required}"
CHECK_NAME="${CHECK_NAME:-Apex Tests}"
MIN_COVERAGE="${MIN_COVERAGE:-85}"

# --- Pre-flight checks ---
if ! command -v jq >/dev/null; then
  echo "::error::jq not found. The calling workflow must install jq before using this action."
  exit 1
fi

if [ ! -f "$JSON" ]; then
  echo "::error file=$JSON::JSON results file not found"
  exit 1
fi

# --- Parse SF JSON safely (defaults avoid nulls) ---
TOTAL=$(jq -r '.result.summary.testsRan // 0' "$JSON")
PASS=$(jq -r '.result.summary.passing // 0' "$JSON")
FAIL=$(jq -r '.result.summary.failing // 0' "$JSON")
SKIP=$(jq -r '.result.summary.skipped // 0' "$JSON")
COVER=$(jq -r '.result.summary.testRunCoverage // 0' "$JSON")
OUTCOME=$(jq -r '.result.summary.outcome // "Unknown"' "$JSON")

FAIL_ROWS=$(jq -r '
  .result.tests[]? | select(.outcome == "Fail") |
  "- **\(.methodName // "unknown")** in `\(.apexClass.fullName // "unknown")`
    Message: \(.message // "n/a")
    Stack: \(.stackTrace // "n/a")"
' "$JSON")

# --- Build summary markdown ---
SUMMARY_FILE="${GITHUB_WORKSPACE:-.}/apex-summary.md"
{
  echo "## ${CHECK_NAME}"
  echo ""
  echo "- **Outcome:** ${OUTCOME}"
  echo "- **Total:** ${TOTAL}  |  **Pass:** ${PASS}  |  **Fail:** ${FAIL}  |  **Skip:** ${SKIP}"
  echo "- **Org-wide Coverage:** ${COVER}% (threshold: ${MIN_COVERAGE}%)"
  if [ -n "$FAIL_ROWS" ]; then
    echo ""
    echo "### Failures"
    echo "$FAIL_ROWS"
  fi
} > "$SUMMARY_FILE"

# --- Publish to job summary ---
cat "$SUMMARY_FILE" >> "$GITHUB_STEP_SUMMARY"

# --- Expose outputs ---
{
  echo "coverage=$COVER"
  echo "failing=$FAIL"
  echo "total=$TOTAL"
  echo "outcome=$OUTCOME"
  echo "summary_file=$SUMMARY_FILE"
} >> "$GITHUB_OUTPUT"
