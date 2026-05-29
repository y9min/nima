#!/usr/bin/env bash
set -euo pipefail

PROJECT="Bubble.xcodeproj"
SCHEME="BubbleTunnel"
DERIVED_DATA="${DERIVED_DATA:-/tmp/nima-deriveddata}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.4}"

cd "$(dirname "$0")/.."

echo "[gate] running BubbleTunnel unit + harness tests"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -only-testing:BubbleTunnelTests/ReelsBlockFilterPolicyTests \
  -only-testing:BubbleTunnelTests/TransportProtectionDecisionTests \
  -only-testing:BubbleTunnelTests/UDPControlStreamDecoderTests \
  -only-testing:BubbleTunnelTests/TrafficStatsSnapshotTests \
  -only-testing:BubbleTunnelTests/HarnessScenarioTests \
  -only-testing:BubbleTunnelTests/DiagnosticContractTests

echo "[gate] running harness summary script tests"
python3 scripts/tiktok_vpn_drop_summary_test.py

echo "[gate] PASS"
