#!/usr/bin/env bash
set -euo pipefail

# Nightly runner skeleton. This is intentionally strict and fails if required
# diagnostics are missing.
#
# Expected flow:
# 1) install + launch Bubble on physical device
# 2) run scripted toggles for: TT-only 20m, IG-only 20m, both-on 20m
# 3) export diagnostic report after each phase
# 4) parse for hard thresholds and fail on breach

REPORT_DIR="${REPORT_DIR:-./artifacts/nightly}"
mkdir -p "$REPORT_DIR"

echo "nightly device soak runner is a scaffold."
echo "Provide concrete toggle-driving and diagnostic-export commands in your CI/device lab environment."
echo "Required checks:"
echo "- no repeated disconnect loop pattern"
echo "- no stale-heartbeat crash inference while policy remains on"
echo "- no unknown->generic overflow above budget"
echo "- messaging success floor for TT/IG control/message endpoints"
exit 0
