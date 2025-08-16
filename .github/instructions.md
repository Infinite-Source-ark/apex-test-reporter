# Apex Test Reporter - AI Coding Agent Instructions

## Project Overview

This is a **composite GitHub Action** that parses Salesforce CLI Apex test results (JSON format) and generates readable GitHub Actions job summaries. It's authored by **uttam** and designed to be lightweight with no external service dependencies.

## Architecture

- **Composite Action**: Uses `runs.using: "composite"` in `action.yml`
- **Single Script**: Core logic in `scripts/parse-and-publish.sh` (Bash + jq)
- **No Docker**: Pure shell execution for faster startup
- **Input/Output Pattern**: Takes JSON file path, outputs parsed metrics

## Key Files & Their Purpose

- `action.yml`: Action metadata, inputs/outputs, and step definition
- `scripts/parse-and-publish.sh`: Main parser logic using jq for JSON processing
- `samples/testout.sample.json`: Example Salesforce CLI output for testing
- `.github/workflows/ci.yml`: Self-test workflow using the sample data

## Critical Patterns

### Input Processing

The action expects specific Salesforce CLI JSON structure from `sf apex test run -r json`. Key fields:

- `.result.summary.{testsRan, passing, failing, skipped, testRunCoverage, outcome}`
- `.result.tests[]` array with individual test results

### Output Generation

- Writes to `$GITHUB_STEP_SUMMARY` for job summary display
- Exposes structured outputs via `$GITHUB_OUTPUT`
- Creates markdown file at `$GITHUB_WORKSPACE/apex-summary.md`

### Error Handling

- Uses `set -euo pipefail` for strict error handling
- Defensive JSON parsing with fallback defaults (`// 0`, `// "Unknown"`)
- File existence checks before processing

## Development Workflow

1. **Local Testing**: Use `samples/testout.sample.json` with the CI workflow
2. **Shell Requirements**: Bash + jq (no Node.js/Python dependencies)
3. **Composite Action Testing**: Test via `.github/workflows/ci.yml`

## Repository Conventions

- **Owner**: `Infinite-Source-ark`
- **Action Name**: `apex-test-reporter` (not `apex-json-test-reporter`)
- **Author**: `uttam` (set in action.yml)
- **License**: MIT (see LICENSE file)

## Common Integration Points

- Used after `sf apex test run -c -r json -w 30` command
- Requires `jq` installation in calling workflow
- Often combined with PR gating logic based on coverage/failures outputs
