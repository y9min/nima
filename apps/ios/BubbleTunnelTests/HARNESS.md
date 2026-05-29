# Unified Regression Harness (TikTok + Instagram)

## Plain English
Every future change must pass a fixed scenario matrix before merge. If one area regresses (dropoff, blocking, messaging, spillover), tests fail.

## What runs
- Fast unit suites:
  - `ReelsBlockFilterPolicyTests`
  - `TransportProtectionDecisionTests`
  - `UDPControlStreamDecoderTests`
  - `TrafficStatsSnapshotTests`
- Harness suites:
  - `HarnessScenarioTests` (canonical + cross-app scenarios)
  - `DiagnosticContractTests` (diagnostic key/shape contract)

## Required local gate
```bash
apps/ios/scripts/ios_regression_gate.sh
```

## After A Physical-Device Repro
Plain English: `.ips` files are helpful when iOS creates them, but they are not guaranteed for every Network Extension disappearance. Always keep the harness artifact folder, because it includes app logs plus the fallback evidence from unified logs and sysdiagnose.

```bash
DEVICE_UDID=<UDID> apps/ios/scripts/run_tiktok_vpn_drop_harness.sh --duration 600 --device <UDID>
/usr/bin/log collect --device-udid <UDID> --last 10m --output <artifact-dir>/device_<UDID>_last10m.logarchive
xcrun devicectl device sysdiagnose --device <UDID> --gather-full-logs --destination <artifact-dir>/sysdiagnose
```

Expected artifacts:
- `app_diagnostic_log.txt`, `tunnel_log.txt`, `traffic_stats.json`, and `app_group_prefs.plist`
- `device_<UDID>_last10m.logarchive`
- `sysdiagnose/`
- optional matching `Bubble*.ips`, `BubbleTunnel*.ips`, `JetsamEvent*.ips`, `networkextensiond`, `neagent`, or `nesessionmanager` files when iOS creates them

Known limitation: Network Extension process deaths may only appear in unified logs or sysdiagnose. Xcode Devices and Simulators > View Device Logs and automatic crash/energy logs are useful, but no `.ips` file is guaranteed for every tunnel disappearance.

Apple references:
- Xcode View Device Logs: https://help.apple.com/xcode/mac/current/en.lproj/dev85c64ec79.html
- Xcode crash and energy logs: https://help.apple.com/xcode/mac/current/en.lproj/dev0f3181c2c.html
- sysdiagnose profiles/logs: https://developer.apple.com/feedback-assistant/profiles-and-logs/?name=sysdiagnose

## Scenario fixture contract
- Versioned field: `harness_schema_version`
- Inputs include toggles, synthetic stream/classification/lifecycle/transport stress flags.
- Expected includes policy decision, class admission, lifecycle inference, and transport trip expectation.

## Canonical baseline
- TikTok: dropoff, block, messaging, spillover
- Instagram: dropoff, block, messaging, spillover
- Cross-app isolation stress scenarios also required.
