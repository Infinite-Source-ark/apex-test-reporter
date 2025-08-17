#!/usr/bin/env bash
set -euo pipefail

JSON="${JSON_PATH:?JSON_PATH required}"
CHECK_NAME="${CHECK_NAME:-Apex Tests}"
MIN_COVERAGE="${MIN_COVERAGE:-85}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-75}"
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
TOTAL=$(jq -r '.result.summary.testsRan // .result.summary.numTestsRun // 0' "$JSON")
PASS=$(jq -r '.result.summary.passing // 0' "$JSON")
FAIL=$(jq -r '.result.summary.failing // 0' "$JSON")
SKIP=$(jq -r '.result.summary.skipped // 0' "$JSON")
COVER=$(jq -r '.result.summary.testRunCoverage // .result.summary.orgWideCoverage // "0"' "$JSON" | sed 's/%//')
OUTCOME=$(jq -r '.result.summary.outcome // "Unknown"' "$JSON")

# Determine outcome based on failures
if [[ "$FAIL" -gt 0 ]]; then
    OUTCOME="Failed"
elif [[ "$TOTAL" -gt 0 ]]; then
    OUTCOME="Passed"
fi

echo "::debug::Summary - Total: $TOTAL, Pass: $PASS, Fail: $FAIL, Skip: $SKIP, Coverage: $COVER%"

# ---- Extract individual test data if available ----
TESTS_COUNT=$(jq -r '.result.tests | length' "$JSON" 2>/dev/null || echo "0")
echo "::debug::Found $TESTS_COUNT individual tests in JSON"

# ---- NEW: Enhanced Code Coverage Analysis ----
COVERAGE_COUNT=$(jq -r '.result.coverage.coverage | length' "$JSON" 2>/dev/null || echo "0")
echo "::debug::Found $COVERAGE_COUNT classes with coverage data"

# Initialize coverage variables
LOW_COVERAGE_COUNT=0
WORST_COVERAGE_CLASS=""
WORST_COVERAGE_PCT=100
COVERAGE_ANALYSIS_AVAILABLE="false"

if [[ "$COVERAGE_COUNT" -gt 0 ]]; then
    COVERAGE_ANALYSIS_AVAILABLE="true"
    echo "::debug::Processing detailed coverage analysis for $COVERAGE_COUNT classes"
    
    # Parse class coverage data with enhanced details
    mapfile -t COVERAGE_ROWS < <(jq -r --argjson threshold "$COVERAGE_THRESHOLD" '
      .result.coverage.coverage
      | map({
          name: .name,
          totalLines: (.totalLines // .NumLinesCovered + .NumLinesUncovered // 0),
          coveredLines: (.totalCovered // .NumLinesCovered // 0),
          uncoveredLines: (.totalLines - .totalCovered // .NumLinesUncovered // 0),
          coveragePercent: (.coveredPercent // (if (.totalLines // 0) > 0 then ((.totalCovered // 0) * 100 / (.totalLines // 0)) else 0 end) // 0)
        })
      | sort_by(.coveragePercent)
      | .[]
      | [.name, .totalLines, .coveredLines, .uncoveredLines, (.coveragePercent | floor)] | @tsv
    ' "$JSON")

    # Find classes below threshold
    mapfile -t LOW_COVERAGE_CLASSES < <(jq -r --argjson threshold "$COVERAGE_THRESHOLD" '
      .result.coverage.coverage
      | map(select((.coveredPercent // (if (.totalLines // 0) > 0 then ((.totalCovered // 0) * 100 / (.totalLines // 0)) else 0 end) // 0) < $threshold))
      | map({
          name: .name,
          coverage: (.coveredPercent // (if (.totalLines // 0) > 0 then ((.totalCovered // 0) * 100 / (.totalLines // 0)) else 0 end) // 0),
          needed: ($threshold - (.coveredPercent // (if (.totalLines // 0) > 0 then ((.totalCovered // 0) * 100 / (.totalLines // 0)) else 0 end) // 0))
        })
      | sort_by(.coverage)
      | .[]
      | [.name, (.coverage | floor), (.needed | floor)] | @tsv
    ' "$JSON")

    LOW_COVERAGE_COUNT=${#LOW_COVERAGE_CLASSES[@]}
    
    # Find worst coverage class
    if [[ ${#COVERAGE_ROWS[@]} -gt 0 ]]; then
        WORST_ROW="${COVERAGE_ROWS[0]}"
        WORST_COVERAGE_CLASS=$(echo "$WORST_ROW" | cut -f1)
        WORST_COVERAGE_PCT=$(echo "$WORST_ROW" | cut -f5)
    fi

    # Get uncovered lines for low coverage classes
    mapfile -t UNCOVERED_LINES < <(jq -r --argjson threshold "$COVERAGE_THRESHOLD" '
      .result.coverage.coverage
      | map(select((.coveredPercent // (if (.totalLines // 0) > 0 then ((.totalCovered // 0) * 100 / (.totalLines // 0)) else 0 end) // 0) < $threshold))
      | map(select(.lines))
      | .[]
      | "\(.name): Lines " + ([.lines | to_entries[] | select(.value == 0 or .value == "0") | .key] | sort | join(", "))
    ' "$JSON" 2>/dev/null || echo "")

    echo "::debug::Coverage analysis complete - $LOW_COVERAGE_COUNT classes below $COVERAGE_THRESHOLD% threshold"
else
    echo "::warning::No code coverage data found in JSON"
    COVERAGE_ROWS=()
    LOW_COVERAGE_CLASSES=()
    UNCOVERED_LINES=()
fi

# ---- Aggregate by test class ----
if [[ "$TESTS_COUNT" -gt 0 ]]; then
    # Enhanced test class parsing with better field handling
    mapfile -t CLASS_ROWS < <(jq -r --argjson limit "$MAX_FAILURES" '
      (.result.tests // []) as $t
      | group_by(.apexClass.fullName // .ApexClass.Name // "unknown")
      | map({
          class: (.[0].apexClass.fullName // .[0].ApexClass.Name // "unknown"),
          passed: (map(select(.outcome=="Pass" or .Outcome=="Pass")) | length),
          failed: (map(select(.outcome=="Fail" or .Outcome=="Fail")) | length),
          skipped: (map(select((.outcome=="Skip") or (.outcome=="Skipped") or (.Outcome=="Skip") or (.Outcome=="Skipped"))) | length),
          time_ms: (map((.runTime // .runTimeMs // .RunTime // 0)) | add)
        })
      | sort_by(-.failed, -.time_ms, .class)
      | .[]
      | [.class, .passed, .failed, .skipped, .time_ms] | @tsv
    ' "$JSON")

    # Top slow tests
    mapfile -t TOP_SLOW < <(jq -r '
      (.result.tests // [])
      | map({
          name: ((.apexClass.fullName // .ApexClass.Name // "unknown") + "." + (.methodName // .MethodName // "unknown")),
          outcome: (.outcome // .Outcome // "Unknown"),
          time_ms: (.runTime // .runTimeMs // .RunTime // 0)
        })
      | sort_by(-.time_ms)[0:10]
      | .[] | [.name, .outcome, .time_ms] | @tsv
    ' "$JSON")
else
    echo "::warning::No individual test data found in JSON - using summary only"
    CLASS_ROWS=()
    TOP_SLOW=()
fi

# ---- Failures list (limited) ----
mapfile -t FAIL_LIST < <(jq -r --argjson limit "$MAX_FAILURES" '
  (.result.tests // [])
  | map(select(.outcome=="Fail" or .Outcome=="Fail"))[0:$limit]
  | .[]
  | "- **\(.apexClass.fullName // .ApexClass.Name // "unknown").\(.methodName // .MethodName // "unknown")**  
    Message: \(.message // .Message // "n/a")  
    Stack: \((.stackTrace // .StackTrace // "n/a") | gsub("\r";""))"
' "$JSON")

# ---- Top slow tests (best effort) ----
# ---- Remove duplicate sections ----
# The enhanced sections are already defined above

# ---- Build Enhanced Markdown summary with Coverage Analysis ----
SUMMARY_FILE="$GITHUB_WORKSPACE/apex-summary.md"
{
  echo "# ${CHECK_NAME}"
  echo
  echo "- **Outcome:** ${OUTCOME}"
  echo "- **Total:** ${TOTAL}  |  **Pass:** ${PASS}  |  **Fail:** ${FAIL}  |  **Skip:** ${SKIP}"
  echo "- **Org-wide Coverage:** ${COVER}% (threshold: ${MIN_COVERAGE}%)"
  if [[ "$COVERAGE_ANALYSIS_AVAILABLE" == "true" ]]; then
    echo "- **Classes Below ${COVERAGE_THRESHOLD}% Coverage:** ${LOW_COVERAGE_COUNT}"
    if [[ -n "$WORST_COVERAGE_CLASS" ]]; then
      echo "- **Lowest Coverage Class:** ${WORST_COVERAGE_CLASS} (${WORST_COVERAGE_PCT}%)"
    fi
  fi
  echo

  # Test class summary
  echo "## Test Class Summary"
  echo
  echo "| Test Class | Passed | Failed | Skipped | Time |"
  echo "|-----------:|------:|------:|-------:|-----:|"
  if [ "${#CLASS_ROWS[@]}" -eq 0 ]; then
    echo "| _no individual test data available_ | - | - | - | - |"
  else
    for row in "${CLASS_ROWS[@]}"; do
      IFS=$'\t' read -r CLS P F S T <<< "$row"
      echo "| \`$CLS\` | $P | $F | $S | ${T}ms |"
    done
  fi
  echo

  # NEW: Code Coverage by Class Analysis
  if [[ "$COVERAGE_ANALYSIS_AVAILABLE" == "true" && "${#COVERAGE_ROWS[@]}" -gt 0 ]]; then
    echo "## 📊 Code Coverage by Class"
    echo
    echo "| Class Name | Total Lines | Covered | Uncovered | Coverage % | Status |"
    echo "|------------|-------------|---------|-----------|------------|--------|"
    for row in "${COVERAGE_ROWS[@]}"; do
      IFS=$'\t' read -r NAME TOTAL_LINES COVERED UNCOVERED PCT <<< "$row"
      
      # Determine status icon based on coverage
      if [[ "$PCT" -ge 90 ]]; then
        STATUS="🟢 Excellent"
      elif [[ "$PCT" -ge "$COVERAGE_THRESHOLD" ]]; then
        STATUS="🟡 Good"
      elif [[ "$PCT" -ge 50 ]]; then
        STATUS="🟠 Needs Work"
      else
        STATUS="🔴 Critical"
      fi
      
      echo "| \`$NAME\` | $TOTAL_LINES | $COVERED | $UNCOVERED | **${PCT}%** | $STATUS |"
    done
    echo
    
    # Classes needing improvement section
    if [[ "$LOW_COVERAGE_COUNT" -gt 0 ]]; then
      echo "## ⚠️ Classes Needing Coverage Improvement ($LOW_COVERAGE_COUNT classes)"
      echo
      echo "| Class Name | Current Coverage | Improvement Needed | Target |"
      echo "|------------|------------------|-------------------|--------|"
      for row in "${LOW_COVERAGE_CLASSES[@]}"; do
        IFS=$'\t' read -r NAME CURRENT NEEDED <<< "$row"
        echo "| \`$NAME\` | ${CURRENT}% | +${NEEDED}% | ${COVERAGE_THRESHOLD}% |"
      done
      echo
      
      # Uncovered lines details
      if [[ "${#UNCOVERED_LINES[@]}" -gt 0 ]]; then
        echo "### 🔍 Uncovered Lines Details"
        echo
        echo "```"
        for line in "${UNCOVERED_LINES[@]}"; do
          if [[ -n "$line" ]]; then
            echo "$line"
          fi
        done
        echo "```"
        echo
      fi
    else
      echo "## ✅ All Classes Meet Coverage Threshold"
      echo
      echo "🎉 Congratulations! All classes meet the ${COVERAGE_THRESHOLD}% coverage threshold."
      echo
    fi
  else
    echo "## Code Coverage Analysis"
    echo
    echo "_Class-level coverage details not available in this JSON format._"
    echo "Only org-wide coverage (${COVER}%) is available."
    echo
  fi

  # Slow tests
  if [ "${#TOP_SLOW[@]}" -gt 0 ]; then
    echo "## ⏱️ Top Slow Tests"
    echo
    echo "| Test | Outcome | Time |"
    echo "|------|---------|-----:|"
    for row in "${TOP_SLOW[@]}"; do
      IFS=$'\t' read -r NAME OUT TM <<< "$row"
      if [[ "$TM" -gt 1000 ]]; then
        TIME_DISPLAY="🐌 ${TM}ms"
      elif [[ "$TM" -gt 500 ]]; then
        TIME_DISPLAY="⚡ ${TM}ms"
      else
        TIME_DISPLAY="${TM}ms"
      fi
      echo "| \`$NAME\` | $OUT | $TIME_DISPLAY |"
    done
    echo
  fi

  # Failures
  if [ "$FAIL" -gt 0 ]; then
    echo "## ❌ Test Failures (${FAIL})"
    echo
    for f in "${FAIL_LIST[@]}"; do
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

# ---- Expose enhanced outputs ----
{
  echo "tests-ran=$TOTAL"
  echo "passing=$PASS"
  echo "failing=$FAIL"
  echo "skipped=$SKIP"
  echo "coverage=$COVER"
  echo "outcome=$OUTCOME"
  echo "summary-file=$SUMMARY_FILE"
  echo "low-coverage-classes=$LOW_COVERAGE_COUNT"
  echo "coverage-analysis=$COVERAGE_ANALYSIS_AVAILABLE"
  echo "worst-coverage-class=$WORST_COVERAGE_CLASS"
  # Legacy outputs for backward compatibility
  echo "total=$TOTAL"
  echo "summary_file=$SUMMARY_FILE"
} >> "$GITHUB_OUTPUT"

echo "::notice::Successfully generated enhanced test summary with detailed coverage analysis"
echo "::notice::Found $LOW_COVERAGE_COUNT classes below $COVERAGE_THRESHOLD% coverage threshold"
