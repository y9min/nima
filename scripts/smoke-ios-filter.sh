#!/usr/bin/env bash
set -euo pipefail

echo "Smoke checklist (manual/CI gate)"
echo "- both toggles off => no block + vpn auto-off"
echo "- reels on/messages off"
echo "- reels off/messages on"
echo "- both on"

echo "No deterministic CLI simulator harness is configured in this repo yet."
echo "Treat this as a checklist gate until xcodebuild test targets are stabilized."
exit 0
