# Apex Test Reporter (GitHub Action)

Parses `sf apex test run -r json` output from Salesforce CLI, writes a clean Markdown summary to the GitHub Actions job summary, and exposes outputs (coverage, failing, total, outcome) that you can use to gate PRs or post comments.

> Lightweight composite action (Bash + jq). No external services.

## ✨ Features
- Parses **Apex JSON** from `sf apex test run -r json`
- Publishes a readable **summary** (pass/fail/skip/coverage)
- **📊 Detailed class-level code coverage analysis** with visual indicators
- **⚠️ Identifies classes needing coverage improvement** with specific targets
- **🔍 Shows uncovered line numbers** for precise development guidance
- Exposes handy **outputs** for PR gating or comments
- Transparent & simple (Bash + `jq`)

## ✅ Prerequisites
- Salesforce CLI available in your job
- `jq` installed by the calling workflow:
```yaml
- name: Install jq
  run: sudo apt-get update && sudo apt-get install -y jq
```

## 🚀 Usage

### Basic Usage
```yaml
- name: Run Apex tests (JSON)
  run: sf apex test run -c -r json -w 30 --target-org qa_scratchorg > testout.json

- name: Parse Test Results
  id: apex
  uses: Infinite-Source-ark/apex-test-reporter@v1
  with:
    json_path: testout.json
    check_name: "Apex Tests"
    min_coverage: "85"
```

### Advanced Usage with Coverage Analysis
```yaml
- name: Run Apex tests (JSON)
  run: sf apex test run -c -r json -w 30 --target-org qa_scratchorg > testout.json

- name: Parse Test Results with Coverage Analysis
  id: apex
  uses: Infinite-Source-ark/apex-test-reporter@v1
  with:
    json_path: testout.json
    check_name: "Apex Tests"
    min_coverage: "75"
    coverage_threshold: "80"  # Individual class threshold
    max_failures: "25"

- name: Check Overall Coverage
  if: steps.apex.outputs.coverage < 75
  run: |
    echo "::error::Org-wide coverage (${{ steps.apex.outputs.coverage }}%) is below required threshold (75%)"
    exit 1

- name: Check Individual Class Coverage
  if: steps.apex.outputs.low-coverage-classes > 0
  run: |
    echo "::warning::Found ${{ steps.apex.outputs.low-coverage-classes }} classes below 80% coverage"
    echo "Worst coverage: ${{ steps.apex.outputs.worst-coverage-class }}"
    # You can choose to fail or just warn
    # exit 1

- name: Check for Test Failures
  if: steps.apex.outputs.failing > 0
  run: |
    echo "::error::There are ${{ steps.apex.outputs.failing }} failing tests"
    exit 1

- name: Display Test Summary
  run: |
    echo "✅ Tests Passed: ${{ steps.apex.outputs.passing }}"
    echo "❌ Tests Failed: ${{ steps.apex.outputs.failing }}"
    echo "⏭️ Tests Skipped: ${{ steps.apex.outputs.skipped }}"
    echo "📊 Coverage: ${{ steps.apex.outputs.coverage }}%"
    echo "🎯 Outcome: ${{ steps.apex.outputs.outcome }}"
```

## 🔁 Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `tests-ran` | Total number of tests executed | `42` |
| `passing` | Number of passing tests | `40` |
| `failing` | Number of failing tests | `2` |
| `skipped` | Number of skipped tests | `0` |
| `coverage` | Org-wide test coverage percentage | `87` |
| `outcome` | Overall test run outcome | `Failed` |
| `summary-file` | Path to generated markdown summary | `/path/to/apex-summary.md` |
| `low-coverage-classes` | Number of classes below coverage threshold | `3` |
| `coverage-analysis` | Whether detailed coverage analysis is available | `true` |
| `worst-coverage-class` | Class with the lowest coverage percentage | `AccountService` |

### Legacy Outputs (for backward compatibility)
- `total` — same as `tests-ran`
- `summary_file` — same as `summary-file`

## 📊 Coverage Analysis Features

When class-level coverage data is available, the action provides:

### Visual Coverage Indicators
- 🟢 **Excellent** (90%+): Classes with great coverage
- 🟡 **Good** (75-89%): Classes meeting threshold  
- 🟠 **Needs Work** (50-74%): Classes below threshold
- 🔴 **Critical** (<50%): Classes requiring immediate attention

### Detailed Analysis
- **Per-class coverage table** with line counts and percentages
- **Classes needing improvement** with specific targets
- **Uncovered line numbers** for precise development guidance
- **Configurable thresholds** for different coverage requirements

## 🚦 Example: Complete CI Workflow

```yaml
name: Salesforce CI

on:
  pull_request:
    branches: [main]

jobs:
  apex-tests:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Salesforce CLI
        run: npm install -g @salesforce/cli

      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq

      - name: Authenticate to Salesforce
        run: sf org login sfdx-url --sfdx-url-file ${{ secrets.SF_AUTH_URL }}

      - name: Deploy to Scratch Org
        run: sf project deploy start --target-org qa_scratchorg

      - name: Run Apex Tests
        run: sf apex test run -c -r json -w 30 --target-org qa_scratchorg > testout.json

      - name: Parse Test Results
        id: apex
        uses: Infinite-Source-ark/apex-test-reporter@v1
        with:
          json_path: testout.json
          check_name: "Apex Tests"
          min_coverage: "85"

      - name: Gate PR on Test Results
        run: |
          if [ "${{ steps.apex.outputs.failing }}" -gt 0 ]; then
            echo "::error::There are ${{ steps.apex.outputs.failing }} failing tests"
            exit 1
          fi
          if [ "${{ steps.apex.outputs.coverage }}" -lt 85 ]; then
            echo "::error::Coverage ${{ steps.apex.outputs.coverage }}% is below 85%"
            exit 1
          fi
          echo "::notice::All tests passed with ${{ steps.apex.outputs.coverage }}% coverage! 🎉"
```

🔐 Recommended permissions

permissions:
  contents: read
  pull-requests: write   # only if you also post PR comments
  checks: write          # optional; not required by this action

⚠️ Limitations

• Salesforce JSON does not include per-file line numbers; failures are summarized, not inlined as annotations.