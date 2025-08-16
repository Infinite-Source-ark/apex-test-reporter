# Apex Test Reporter (GitHub Action)

Parses `sf apex test run -r json` output from Salesforce CLI, writes a clean Markdown summary to the GitHub Actions job summary, and exposes outputs (coverage, failing, total, outcome) that you can use to gate PRs or post comments.

> Lightweight composite action (Bash + jq). No external services.

## ✨ Features
- Parses **Apex JSON** from `sf apex test run -r json`
- Publishes a readable **summary** (pass/fail/skip/coverage)
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

### Advanced Usage with PR Gating
```yaml
- name: Run Apex tests (JSON)
  run: sf apex test run -c -r json -w 30 --target-org qa_scratchorg > testout.json

- name: Parse Test Results
  id: apex
  uses: Infinite-Source-ark/apex-test-reporter@v1
  with:
    json_path: testout.json
    check_name: "Apex Tests"
    min_coverage: "75"
    max_failures: "25"

- name: Check Coverage Threshold
  if: steps.apex.outputs.coverage < 75
  run: |
    echo "::error::Code coverage (${{ steps.apex.outputs.coverage }}%) is below required threshold (75%)"
    exit 1

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
| `coverage` | Test coverage percentage | `87` |
| `outcome` | Overall test run outcome | `Failed` |
| `summary-file` | Path to generated markdown summary | `/path/to/apex-summary.md` |

### Legacy Outputs (for backward compatibility)
- `total` — same as `tests-ran`
- `summary_file` — same as `summary-file`

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