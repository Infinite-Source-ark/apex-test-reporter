# Apex JSON Test Reporter (GitHub Action)

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

🚀 Usage

- name: Run Apex tests (JSON)
  run: sf apex test run -c -r json -w 30 --target-org qa_scratchorg > testout.json

- name: Publish Apex results
  id: apex
  uses: <your-org>/apex-json-test-reporter@v1
  with:
    json_path: testout.json
    check_name: "Apex Tests"
    min_coverage: "85"

🔁 Outputs

• coverage — org-wide coverage (%)

• failing — number of failing tests

• total — tests executed

• outcome — overall outcome

• summary_file — path to generated Markdown summary

🚦 Gate the PR (coverage + failures)

- name: Gate on coverage/failures
  run: |
    echo "Coverage: ${{ steps.apex.outputs.coverage }}%"
    echo "Failing:  ${{ steps.apex.outputs.failing }}"
    req=85
    cov=${{ steps.apex.outputs.coverage }}
    fail=${{ steps.apex.outputs.failing }}
    if [ "$fail" -gt 0 ]; then
      echo "::error::There are $fail failing tests."
      exit 1
    fi
    awk -v r="$cov" -v req="$req" 'BEGIN { exit (r+0 >= req ? 0 : 1) }' \
      || { echo "::error::Coverage ${cov}% is below ${req}%"; exit 1; }

🔐 Recommended permissions

permissions:
  contents: read
  pull-requests: write   # only if you also post PR comments
  checks: write          # optional; not required by this action

⚠️ Limitations

• Salesforce JSON does not include per-file line numbers; failures are summarized, not inlined as annotations.