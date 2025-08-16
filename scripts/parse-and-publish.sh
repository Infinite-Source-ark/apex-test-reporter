#!/usr/bin/env bash
set -euo pipefail

JSON="${JSON_PATH:?JSON_PATH required}"
CHECK_NAME="${CHECK_NAME:-Apex Tests}"
MIN_COVERAGE="${MIN_COVERAGE:-85}"
MAX_FAILURES="${MAX_FAILURES:-50}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "::error::$1 not found"; exit 1; }; }
require_cmd jq

# Enhanced input validation
if [[ ! -f "$JSON" ]]; then
    echo "::error file=$JSON::JSON file not found: $JSON"
    echo "Make sure the file exists and the path is correct."
    exit 1
fi

# Validate JSON format
if ! jq empty "$JSON" 2>/dev/null; then
    echo "::error file=$JSON::Invalid JSON format in file: $JSON"
    echo "Please ensure the file contains valid JSON output from 'sf apex test run -r json'"
    exit 1
fi

# Validate expected Salesforce CLI JSON structure
if ! jq -e '.result' "$JSON" >/dev/null 2>&1; then
    echo "::error file=$JSON::JSON does not contain expected Salesforce CLI structure (.result)"
    echo "Expected JSON from 'sf apex test run -r json' command"
    exit 1
fi

# ---- Pull summary fields (defensive defaults) ----
TOTAL=$(jq -r '.result.summary.testsRan // 0' "$JSON")
PASS=$(jq -r '.result.summary.passing // 0' "$JSON")
FAIL=$(jq -r '.result.summary.failing // 0' "$JSON")
SKIP=$(jq -r '.result.summary.skipped // 0' "$JSON")
COVER=$(jq -r '.result.summary.testRunCoverage // 0' "$JSON")
OUTCOME=$(jq -r '.result.summary.outcome // "Unknown"' "$JSON")

# ---- Aggregate by test class ----
# We sort by failed desc, then time desc, then class asc
mapfile -t CLASS_ROWS < <(jq -r '
  (.result.tests // []) as $t
  | group_by(.apexClass.fullName // "unknown")
  | map({
      class: (.[0].apexClass.fullName // "unknown"),
      passed: (map(select(.outcome=="Pass")) | length),
      failed: (map(select(.outcome=="Fail")) | length),
      skipped: (map(select((.outcome=="Skip") or (.outcome=="Skipped"))) | length),
      time_ms: (map((.runTime // .runTimeMs // 0)) | add)
    })
  | sort_by(-.failed, -.time_ms, .class)
  | .[]
  | [.class, .passed, .failed, .skipped, .time_ms] | @tsv
' "$JSON")

# ---- Top slow tests (best effort) ----
mapfile -t TOP_SLOW < <(jq -r '
  (.result.tests // [])
  | map({
      name: ((.apexClass.fullName // "unknown") + "." + (.methodName // "unknown")),
      outcome: (.outcome // "Unknown"),
      time_ms: (.runTime // .runTimeMs // 0)
    })
  | sort_by(-.time_ms)[0:10]
  | .[] | [.name, .outcome, .time_ms] | @tsv
' "$JSON")

# ---- Failures list (limited) ----
mapfile -t FAIL_LIST < <(jq -r --argjson limit "$MAX_FAILURES" '
  (.result.tests // [])
  | map(select(.outcome=="Fail"))[0:$limit]
  | .[]
  | "- **\(.apexClass.fullName // "unknown").\(.methodName // "unknown")**  
    Message: \(.message // "n/a")  
    Stack: \((.stackTrace // "n/a") | gsub("\r";""))"
' "$JSON")

# ---- Build Markdown summary ----
SUMMARY_FILE="$GITHUB_WORKSPACE/apex-summary.md"
{
  echo "## ${CHECK_NAME}"
  echo
  echo "- **Outcome:** ${OUTCOME}"
  echo "- **Total:** ${TOTAL}  |  **Pass:** ${PASS}  |  **Fail:** ${FAIL}  |  **Skip:** ${SKIP}"
  echo "- **Org-wide Coverage:** ${COVER}% (threshold: ${MIN_COVERAGE}%)"
  echo

  # Class table
  echo "### Test class summary"
  echo
  echo "| Test class | Passed | Failed | Skipped | Time |"
  echo "|-----------:|------:|------:|-------:|-----:|"
  if [ "${#CLASS_ROWS[@]}" -eq 0 ]; then
    echo "| _no tests_ | 0 | 0 | 0 | 0ms |"
  else
    for row in "${CLASS_ROWS[@]}"; do
      IFS=$'\t' read -r CLS P F S T <<< "$row"
      echo "| \`$CLS\` | $P | $F | $S | ${T}ms |"
    done
  fi
  echo

  # Slow tests
  if [ "${#TOP_SLOW[@]}" -gt 0 ]; then
    echo "<details><summary><b>Top slow tests</b></summary>"
    echo
    echo "| Test | Outcome | Time |"
    echo "|------|---------|-----:|"
    for row in "${TOP_SLOW[@]}"; do
      IFS=$'\t' read -r NAME OUT TM <<< "$row"
      echo "| \`$NAME\` | $OUT | ${TM}ms |"
    done
    echo
    echo "</details>"
    echo
  fi

  # Failures
  if [ "$FAIL" -gt 0 ]; then
    echo "### Failures (${FAIL})"
    echo
    for f in "${FAIL_LIST[@]}"; do
      # Each item already contains newlines/markdown
      echo "$f"
      echo
    done

    # If we truncated
    FAIL_TOTAL_SHOWN=${#FAIL_LIST[@]}
    if [ "$FAIL" -gt "$FAIL_TOTAL_SHOWN" ]; then
      echo "_Showing first ${FAIL_TOTAL_SHOWN} of ${FAIL} failures. Increase \`max_failures\` to see more._"
      echo
    fi
  fi
} > "$SUMMARY_FILE"

# ---- Write to job summary ----
cat "$SUMMARY_FILE" >> "$GITHUB_STEP_SUMMARY"

# ---- Expose outputs ----
{
  echo "tests-ran=$TOTAL"
  echo "passing=$PASS"
  echo "failing=$FAIL"
  echo "skipped=$SKIP"
  echo "coverage=$COVER"
  echo "outcome=$OUTCOME"
  echo "summary-file=$SUMMARY_FILE"
  # Legacy outputs for backward compatibility
  echo "total=$TOTAL"
  echo "summary_file=$SUMMARY_FILE"
} >> "$GITHUB_OUTPUT"
