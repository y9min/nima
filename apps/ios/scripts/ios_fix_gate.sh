#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURATION="300"
DEVICE_ARGS=()
HARNESS_ARGS=()

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--duration SECONDS] [--device UDID] [--artifact-dir DIR]

Runs the normal NimaTunnel regression gate, then the physical-iPhone TikTok
VPN drop smoke test. Default device duration is 300 seconds.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration)
      [[ $# -ge 2 ]] || { echo "--duration requires a value" >&2; exit 1; }
      DURATION="$2"
      shift 2
      ;;
    --device)
      [[ $# -ge 2 ]] || { echo "--device requires a UDID" >&2; exit 1; }
      DEVICE_ARGS=(--device "$2")
      shift 2
      ;;
    --artifact-dir)
      [[ $# -ge 2 ]] || { echo "--artifact-dir requires a path" >&2; exit 1; }
      HARNESS_ARGS+=(--artifact-dir "$2")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 300 ]]; then
  echo "--duration must be an integer of at least 300 seconds" >&2
  exit 1
fi

echo "[fix-gate] running fast NimaTunnel regression gate"
"$SCRIPT_DIR/ios_regression_gate.sh"

echo "[fix-gate] running physical-device TikTok VPN drop smoke (${DURATION}s)"
"$SCRIPT_DIR/run_tiktok_vpn_drop_harness.sh" --duration "$DURATION" "${DEVICE_ARGS[@]}" "${HARNESS_ARGS[@]}"

echo "[fix-gate] PASS"
