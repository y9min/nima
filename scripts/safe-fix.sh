#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"single specific bug\""
  exit 1
fi

TOPIC_RAW="$*"
TOPIC_SLUG="$(echo "$TOPIC_RAW" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-48)"
DATE_STAMP="$(date +%Y-%m-%d)"
TIME_STAMP="$(date +%Y%m%d-%H%M%S)"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "Switching to main from $CURRENT_BRANCH"
  git switch main
fi

echo "Comparing local baseline vs origin/main..."
if git rev-parse --verify origin/main >/dev/null 2>&1; then
  git rev-list --left-right --count main...origin/main | awk '{printf "Ahead: %s, Behind: %s\n", $1, $2}'
else
  echo "origin/main not available locally; skipping ahead/behind check"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  WIP_BRANCH="codex/wip-${TIME_STAMP}"
  echo "Dirty tree detected. Creating snapshot branch: $WIP_BRANCH"
  git switch -c "$WIP_BRANCH"
  git add -A
  git commit -m "WIP snapshot before clean fix: ${TOPIC_RAW}"
  git switch main
else
  echo "Working tree clean; no snapshot needed"
fi

FIX_BRANCH="codex/fix-${DATE_STAMP}-${TOPIC_SLUG}"
echo "Creating fix branch: $FIX_BRANCH"
git switch -c "$FIX_BRANCH"

echo "Ready. Branch: $FIX_BRANCH"
echo "Next: implement only this concern -> $TOPIC_RAW"
