# Apex Test Reporter - AI Coding Agent Instructions

## Project Overview

This is a **composite GitHub Action** that parses Salesforce CLI Apex test results (JSON format) and generates readable GitHub Actions job summaries with **enhanced code coverage analysis**. It's authored by **uttam** and designed to be lightweight with no external service dependencies.

## Architecture

- **Composite Action**: Uses `runs.using: "composite"` in `action.yml`
- **Single Script**: Core logic in `scripts/parse-and-publish.sh` (Bash + jq)
- **No Docker**: Pure shell execution for faster startup
- **Input/Output Pattern**: Takes JSON file path, outputs parsed metrics and coverage analysis

## Key Files & Their Purpose

- `action.yml`: Action metadata, inputs/outputs (including coverage thresholds), and step definition
- `scripts/parse-and-publish.sh`: Main parser logic with enhanced coverage analysis using jq
- `samples/testout.sample.json`: Example Salesforce CLI output for testing
- `.github/workflows/ci.yml`: Self-test workflow with coverage feature validation

## Critical Patterns

### Input Processing

The action expects specific Salesforce CLI JSON structure from `sf apex test run -r json`. Key fields:

- `.result.summary.{testsRan, passing, failing, skipped, testRunCoverage, outcome}`
- `.result.tests[]` array with individual test results
- **NEW**: `.result.coverage.coverage[]` array with per-class coverage details

### Enhanced Coverage Analysis

**Major Feature**: Detailed class-level code coverage analysis with:

- Per-class coverage percentages and line counts
- Visual status indicators (🟢🟡🟠🔴) based on coverage levels
- Identification of classes below configurable thresholds
- Uncovered line number reporting for precise development guidance
- Configurable coverage thresholds via `coverage_threshold` input

### Output Generation

- Writes to `$GITHUB_STEP_SUMMARY` for job summary display with enhanced coverage tables
- Exposes structured outputs via `$GITHUB_OUTPUT` including coverage analysis metrics
- Creates markdown file at `$GITHUB_WORKSPACE/apex-summary.md` with rich coverage details
- **NEW**: Outputs include `low-coverage-classes`, `coverage-analysis`, `worst-coverage-class`

### Error Handling

- Uses `set -euo pipefail` for strict error handling
- Enhanced JSON validation with Salesforce CLI structure checks
- Defensive parsing with fallback defaults (`// 0`, `// "Unknown"`)
- Graceful degradation when coverage data is unavailable

## Development Workflow

1. **Local Testing**: Use `samples/testout.sample.json` with the CI workflow
2. **Shell Requirements**: Bash + jq (no Node.js/Python dependencies)
3. **Composite Action Testing**: Test via `.github/workflows/ci.yml` with coverage validation
4. **Coverage Testing**: Validates both basic functionality and enhanced coverage features

## Repository Conventions

- **Owner**: `Infinite-Source-ark`
- **Action Name**: `apex-test-reporter`
- **Author**: `uttam` (set in action.yml)
- **License**: MIT (see LICENSE file)
- **Versioning**: Uses GitHub releases with automatic major version tag updates

## Common Integration Points

- Used after `sf apex test run -c -r json -w 30` command
- Requires `jq` installation in calling workflow
- Often combined with PR gating logic based on coverage/failures outputs
- **NEW**: Can gate PRs on individual class coverage thresholds
- **NEW**: Provides detailed coverage improvement guidance for developers

## Coverage Analysis Features

- **Configurable Thresholds**: Separate org-wide and per-class coverage requirements
- **Visual Indicators**: Color-coded status indicators for immediate identification
- **Improvement Targets**: Specific guidance on coverage improvements needed
- **Line-Level Details**: Exact uncovered line numbers for focused development
- **Backward Compatibility**: Gracefully handles JSON without detailed coverage data
