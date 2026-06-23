#!/usr/bin/env bash
set -euo pipefail

PROJECT="Nima.xcodeproj"
SCHEME="NimaTunnel"
DERIVED_DATA="${DERIVED_DATA:-/tmp/nima-deriveddata}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.4}"

cd "$(dirname "$0")/.."

echo "[gate] running NimaTunnel unit + harness tests"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -only-testing:NimaTunnelTests/ReelsBlockFilterPolicyTests \
  -only-testing:NimaTunnelTests/TransportProtectionDecisionTests \
  -only-testing:NimaTunnelTests/UDPControlStreamDecoderTests \
  -only-testing:NimaTunnelTests/TrafficStatsSnapshotTests \
  -only-testing:NimaTunnelTests/HarnessScenarioTests \
  -only-testing:NimaTunnelTests/DiagnosticContractTests

echo "[gate] running harness summary script tests"
python3 scripts/tiktok_vpn_drop_summary_test.py

echo "[gate] PASS"
