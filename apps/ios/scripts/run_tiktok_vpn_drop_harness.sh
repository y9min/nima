#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_DEVICE_UDID="00008110-0009144E0212401E"
DEVICE_UDID="${DEVICE_UDID:-$DEFAULT_DEVICE_UDID}"
DURATION="600"
ARTIFACT_DIR=""
APP_GROUP_ID="${APP_GROUP_ID:-group.com.yamin.nimademo}"
BUBBLE_BUNDLE_ID="${BUBBLE_BUNDLE_ID:-com.yamin.nimademo}"
TIKTOK_BUNDLE_ID="${TIKTOK_BUNDLE_ID:-com.zhiliaoapp.musically}"
BUBBLE_WARMUP_SECONDS="${BUBBLE_WARMUP_SECONDS:-8}"
TIKTOK_WARMUP_SECONDS="${TIKTOK_WARMUP_SECONDS:-6}"
SWIPE_INTERVAL_SECONDS="${SWIPE_INTERVAL_SECONDS:-2.5}"
SWIPE_MODE="${SWIPE_MODE:-combo}"
SWIPE_START_X="${SWIPE_START_X:-0.50}"
SWIPE_START_Y="${SWIPE_START_Y:-0.78}"
SWIPE_END_X="${SWIPE_END_X:-0.50}"
SWIPE_END_Y="${SWIPE_END_Y:-0.18}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--duration SECONDS] [--device UDID] [--artifact-dir DIR] [--swipe-interval SECONDS]

Runs a physical-iPhone TikTok scroll harness against the Bubble VPN.
Duration must be at least 600 seconds.

Environment overrides:
  BUBBLE_BUNDLE_ID          default: $BUBBLE_BUNDLE_ID
  TIKTOK_BUNDLE_ID          default: $TIKTOK_BUNDLE_ID
  APP_GROUP_ID              default: $APP_GROUP_ID
  SWIPE_START_X/Y           default: $SWIPE_START_X,$SWIPE_START_Y
  SWIPE_END_X/Y             default: $SWIPE_END_X,$SWIPE_END_Y
  SWIPE_INTERVAL_SECONDS    default: $SWIPE_INTERVAL_SECONDS
  SWIPE_MODE                default: $SWIPE_MODE (combo, app, drag, scroll)
USAGE
}

log() {
  printf '[tiktok-vpn-harness] %s\n' "$*"
}

fail() {
  printf '[tiktok-vpn-harness] ERROR: %s\n' "$*" >&2
  cat >&2 <<'SETUP'

Setup checklist:
- Connect and trust iPhone 00008110-0009144E0212401E over USB.
- Unlock the phone and leave it awake for the whole run.
- Install/prepare Bubble, grant VPN permission, and enable the TikTok policy that starts the VPN.
- Install TikTok and complete any first-run login, age, notification, and network prompts.
- Confirm this Mac can run Xcode UI tests on the phone with the Bubble development team/profile.
SETUP
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command '$1'."
}

devicectl_json() {
  local output="$1"
  shift
  xcrun devicectl --json-output "$output" --quiet "$@" \
    >"${output}.stdout" 2>"${output}.stderr"
}

copy_if_present() {
  local source="$1"
  local destination="$2"
  if [[ -f "$source" ]]; then
    cp "$source" "$destination"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration)
      [[ $# -ge 2 ]] || fail "--duration requires a value."
      DURATION="$2"
      shift 2
      ;;
    --device)
      [[ $# -ge 2 ]] || fail "--device requires a UDID."
      DEVICE_UDID="$2"
      shift 2
      ;;
    --artifact-dir)
      [[ $# -ge 2 ]] || fail "--artifact-dir requires a path."
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --swipe-interval)
      [[ $# -ge 2 ]] || fail "--swipe-interval requires a value."
      SWIPE_INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --swipe-mode)
      [[ $# -ge 2 ]] || fail "--swipe-mode requires a value."
      SWIPE_MODE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 600 ]]; then
  fail "--duration must be an integer of at least 600 seconds."
fi

if ! [[ "$SWIPE_INTERVAL_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  fail "--swipe-interval must be a number of seconds."
fi

case "$SWIPE_MODE" in
  combo|app|drag|scroll) ;;
  *) fail "--swipe-mode must be one of: combo, app, drag, scroll." ;;
esac

need_cmd xcrun
need_cmd python3
need_cmd plutil

if [[ -z "$ARTIFACT_DIR" ]]; then
  ARTIFACT_DIR="$IOS_ROOT/artifacts/tiktok-vpn-drop/$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$ARTIFACT_DIR"
RUN_LOG="$ARTIFACT_DIR/run.log"
exec > >(tee -a "$RUN_LOG") 2>&1

log "artifact_dir=$ARTIFACT_DIR"
log "device_udid=$DEVICE_UDID duration=${DURATION}s swipe_interval=${SWIPE_INTERVAL_SECONDS}s swipe_mode=$SWIPE_MODE"

DEVICE_JSON="$ARTIFACT_DIR/device.json"
LOCK_JSON="$ARTIFACT_DIR/lock_state.json"
BUBBLE_APP_JSON="$ARTIFACT_DIR/bubble_app.json"
TIKTOK_APP_JSON="$ARTIFACT_DIR/tiktok_app.json"
XCODEBUILD_LOG="$ARTIFACT_DIR/xcodebuild_tiktok_ui_test.log"

log "checking connected physical iPhone"
devicectl_json "$DEVICE_JSON" list devices
python3 - "$DEVICE_JSON" "$DEVICE_UDID" <<'PY'
import json
import sys

path, udid = sys.argv[1], sys.argv[2]
data = json.load(open(path))
devices = data.get("result", {}).get("devices", [])
matches = [
    device for device in devices
    if device.get("hardwareProperties", {}).get("udid") == udid
    or device.get("identifier") == udid
]
if not matches:
    raise SystemExit(f"Device {udid} was not found by devicectl.")
device = matches[0]
hardware = device.get("hardwareProperties", {})
connection = device.get("connectionProperties", {})
properties = device.get("deviceProperties", {})
problems = []
if hardware.get("deviceType") != "iPhone":
    problems.append(f"expected iPhone, found {hardware.get('deviceType')!r}")
if hardware.get("reality") != "physical":
    problems.append(f"expected physical device, found {hardware.get('reality')!r}")
if hardware.get("platform") != "iOS":
    problems.append(f"expected iOS platform, found {hardware.get('platform')!r}")
if connection.get("pairingState") != "paired":
    problems.append(f"device is not paired/trusted: {connection.get('pairingState')!r}")
if connection.get("tunnelState") not in ("connected", None):
    problems.append(f"CoreDevice tunnel is not connected: {connection.get('tunnelState')!r}")
if properties.get("developerModeStatus") not in ("enabled", None):
    problems.append(f"Developer Mode is not enabled: {properties.get('developerModeStatus')!r}")
if problems:
    raise SystemExit("; ".join(problems))
print(f"Using {properties.get('name', 'iPhone')} ({hardware.get('marketingName', 'unknown model')}, iOS {properties.get('osVersionNumber', 'unknown')})")
PY

log "checking lock state"
devicectl_json "$LOCK_JSON" device info lockState --device "$DEVICE_UDID"
python3 - "$LOCK_JSON" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
result = data.get("result", {})
if result.get("unlockedSinceBoot") is False:
    raise SystemExit("Device has not been unlocked since boot. Unlock it before running the harness.")
PY

log "checking Bubble and TikTok installs"
devicectl_json "$BUBBLE_APP_JSON" device info apps --device "$DEVICE_UDID" --include-all-apps --bundle-id "$BUBBLE_BUNDLE_ID"
devicectl_json "$TIKTOK_APP_JSON" device info apps --device "$DEVICE_UDID" --include-all-apps --bundle-id "$TIKTOK_BUNDLE_ID"
python3 - "$BUBBLE_APP_JSON" "$BUBBLE_BUNDLE_ID" "$TIKTOK_APP_JSON" "$TIKTOK_BUNDLE_ID" <<'PY'
import json
import sys

for path, bundle_id in ((sys.argv[1], sys.argv[2]), (sys.argv[3], sys.argv[4])):
    data = json.load(open(path))
    apps = data.get("result", {}).get("apps", [])
    if not apps:
        raise SystemExit(f"Required app is not installed or not visible to devicectl: {bundle_id}")
PY

START_EPOCH="$(date +%s)"
START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "started_at=$START_ISO"

log "running XCUITest TikTok swipe harness for ${DURATION}s"
if ! (
  cd "$IOS_ROOT"
  TIKTOK_HARNESS_DURATION="$DURATION" \
  TIKTOK_HARNESS_SWIPE_INTERVAL="$SWIPE_INTERVAL_SECONDS" \
  TIKTOK_HARNESS_SWIPE_START_X="$SWIPE_START_X" \
  TIKTOK_HARNESS_SWIPE_START_Y="$SWIPE_START_Y" \
  TIKTOK_HARNESS_SWIPE_END_X="$SWIPE_END_X" \
  TIKTOK_HARNESS_SWIPE_END_Y="$SWIPE_END_Y" \
  TIKTOK_HARNESS_SWIPE_MODE="$SWIPE_MODE" \
  TIKTOK_HARNESS_BUBBLE_WARMUP="$BUBBLE_WARMUP_SECONDS" \
  TIKTOK_HARNESS_TIKTOK_WARMUP="$TIKTOK_WARMUP_SECONDS" \
  BUBBLE_BUNDLE_ID="$BUBBLE_BUNDLE_ID" \
  TIKTOK_BUNDLE_ID="$TIKTOK_BUNDLE_ID" \
  xcodebuild test \
    -project Bubble.xcodeproj \
    -scheme TikTokVPNDropUITests \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -allowProvisioningUpdates \
    -derivedDataPath "${DERIVED_DATA:-/tmp/nima-tiktok-ui-deriveddata}" \
    -only-testing:TikTokVPNDropUITests/TikTokVPNDropUITests/testTikTokVPNDropScroll
) >"$XCODEBUILD_LOG" 2>&1; then
  tail -80 "$XCODEBUILD_LOG" >&2 || true
  fail "XCUITest TikTok swipe harness failed. Keep the phone unlocked, clear TikTok/Bubble prompts, and confirm the development profile can run UI tests on this device."
fi

END_EPOCH="$(date +%s)"
END_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "ended_at=$END_ISO"

APP_GROUP_DIR="$ARTIFACT_DIR/app_group"
mkdir -p "$APP_GROUP_DIR"
log "pulling app-group diagnostics"
if ! devicectl_json "$ARTIFACT_DIR/copy_app_group.json" device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appGroupDataContainer \
  --domain-identifier "$APP_GROUP_ID" \
  --source / \
  --destination "$APP_GROUP_DIR"; then
  fail "Could not copy the Bubble app-group container. Confirm the app is installed with the $APP_GROUP_ID entitlement."
fi

copy_if_present "$APP_GROUP_DIR/app_diagnostic_log.txt" "$ARTIFACT_DIR/app_diagnostic_log.txt"
copy_if_present "$APP_GROUP_DIR/tunnel_log.txt" "$ARTIFACT_DIR/tunnel_log.txt"
copy_if_present "$APP_GROUP_DIR/traffic_stats.json" "$ARTIFACT_DIR/traffic_stats.json"
PREFS_SOURCE="$APP_GROUP_DIR/Library/Preferences/${APP_GROUP_ID}.plist"
copy_if_present "$PREFS_SOURCE" "$ARTIFACT_DIR/app_group_prefs.plist"
if [[ -f "$ARTIFACT_DIR/app_group_prefs.plist" ]]; then
  plutil -convert xml1 -o "$ARTIFACT_DIR/app_group_prefs.xml" "$ARTIFACT_DIR/app_group_prefs.plist" || true
  plutil -convert json -o "$ARTIFACT_DIR/app_group_prefs.json" "$ARTIFACT_DIR/app_group_prefs.plist" || true
fi

log "collecting unified device logarchive"
LOGARCHIVE_PATH="$ARTIFACT_DIR/device_${DEVICE_UDID}_last10m.logarchive"
if ! /usr/bin/log collect --device-udid "$DEVICE_UDID" --last 10m --output "$LOGARCHIVE_PATH" \
  >"$ARTIFACT_DIR/log_collect.stdout" 2>"$ARTIFACT_DIR/log_collect.stderr"; then
  log "warning: log collect failed; see $ARTIFACT_DIR/log_collect.stderr"
fi

log "collecting device sysdiagnose"
SYSDIAG_DIR="$ARTIFACT_DIR/sysdiagnose"
mkdir -p "$SYSDIAG_DIR"
if ! xcrun devicectl device sysdiagnose \
  --device "$DEVICE_UDID" \
  --gather-full-logs \
  --destination "$SYSDIAG_DIR" \
  >"$ARTIFACT_DIR/sysdiagnose.stdout" 2>"$ARTIFACT_DIR/sysdiagnose.stderr"; then
  log "warning: sysdiagnose failed; see $ARTIFACT_DIR/sysdiagnose.stderr"
fi

log "copying matching host-side crash and energy logs when present"
CRASH_DIR="$ARTIFACT_DIR/device_crash_logs"
mkdir -p "$CRASH_DIR"
HOST_CRASH_ROOT="$HOME/Library/Logs/CrashReporter/MobileDevice"
if [[ -d "$HOST_CRASH_ROOT" ]]; then
  find "$HOST_CRASH_ROOT" -type f \( \
      -name 'Bubble*.ips' -o \
      -name 'BubbleTunnel*.ips' -o \
      -name 'JetsamEvent*.ips' -o \
      -name '*networkextensiond*.ips' -o \
      -name '*neagent*.ips' -o \
      -name '*nesessionmanager*.ips' \
    \) -mmin -30 -print0 \
    | while IFS= read -r -d '' crash_file; do
        cp "$crash_file" "$CRASH_DIR/$(basename "$crash_file")" || true
      done
fi

log "generating summary"
python3 "$SCRIPT_DIR/tiktok_vpn_drop_summary.py" \
  --artifact-dir "$ARTIFACT_DIR" \
  --duration "$DURATION" \
  --started-at "$START_EPOCH" \
  --ended-at "$END_EPOCH" \
  --device-udid "$DEVICE_UDID" \
  --tiktok-bundle-id "$TIKTOK_BUNDLE_ID" \
  --app-group-id "$APP_GROUP_ID"

python3 - "$ARTIFACT_DIR/summary.json" <<'PY'
import json
import sys

summary = json.load(open(sys.argv[1]))
failures = []
required = {"app_diagnostic_log", "tunnel_log", "traffic_stats", "app_group_prefs", "device_logarchive", "sysdiagnose"}
missing_required = required.intersection(summary.get("missing_artifacts", []))
if missing_required:
    failures.append("missing required artifacts: " + ", ".join(sorted(missing_required)))
if summary.get("vpn_disconnected"):
    failures.append("VPN disconnect evidence found: " + str(summary.get("disconnect_evidence")))
if not summary.get("tiktok_traffic_observed"):
    failures.append("no TikTok traffic was observed in traffic_stats.json or logs")
if not summary.get("ten_minute_pass"):
    failures.append("ten-minute stability contract failed")
if failures:
    for failure in failures:
        print(failure, file=sys.stderr)
    raise SystemExit(1)
PY

log "PASS summary=$ARTIFACT_DIR/summary.md"
