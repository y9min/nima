#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

FAIL=0

echo "[1/4] Branch safety"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" == "main" ]]; then
  echo "FAIL: You are on main. Use a codex/fix-* branch."
  FAIL=1
else
  echo "PASS: branch=$BRANCH"
fi

echo "[2/4] Single-concern file scope hint"
CHANGED_FILES="$(git diff --name-only -- '*.swift' '*.json' '*.md' '*.sh' || true)"
echo "$CHANGED_FILES"

# Soft guard: if both UI app and tunnel transport changed together, flag for review.
TOUCH_UI=0
TOUCH_TUNNEL=0
if echo "$CHANGED_FILES" | rg -q '^apps/ios/Bubble/'; then TOUCH_UI=1; fi
if echo "$CHANGED_FILES" | rg -q '^apps/ios/BubbleTunnel/'; then TOUCH_TUNNEL=1; fi
if [[ $TOUCH_UI -eq 1 && $TOUCH_TUNNEL -eq 1 ]]; then
  echo "WARN: UI and Tunnel changed together. Confirm this is intentional single-task scope."
fi

echo "[3/4] Regression docs presence"
if [[ -f docs/regression-matrix.md ]]; then
  echo "PASS: docs/regression-matrix.md present"
else
  echo "FAIL: docs/regression-matrix.md missing"
  FAIL=1
fi

echo "[4/4] Test/Smoke hook"
if [[ -x ./scripts/smoke-ios-filter.sh ]]; then
  ./scripts/smoke-ios-filter.sh || FAIL=1
else
  echo "WARN: scripts/smoke-ios-filter.sh missing or not executable"
fi

if [[ $FAIL -ne 0 ]]; then
  echo "QUALITY GATE: FAIL"
  exit 1
fi

echo "QUALITY GATE: PASS"
