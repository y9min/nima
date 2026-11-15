# Nima 1.4 (34) — TestFlight, 13 November 2026

## Status

Build 34 uploaded to App Store Connect and finished processing. It is assigned to the existing **IPhone X** internal testing group (one tester). TestFlight's **What to Test** notes cover scheduled shields, Hard Mode's session-scoped Off choice, overlapping and overnight windows, and relaunching Nima. The TestFlight build page is open in the in-app browser.

## Artifacts

- Archive: `apps/ios/artifacts/Nima-1.4-34.xcarchive`
- Signed IPA: `apps/ios/artifacts/export-1.4-34-distribution/Nima.ipa`
- IPA SHA-256: `8c40647cafeffd0644205c59b14026c71325d7dadb5f09100870a6a66c15605c`
- Source patch against `1c83e674f843328ad048ad7d4051dfbfe96b62df`: `apps/ios/artifacts/Nima-1.4-34-source.patch` (SHA-256 `76ef95a18049834b005a0dcdf0b4aebb32c36fa543bda800ebba49dd06ec9a21`)
- App and all four extensions: version 1.4, build 34
- Apple delivery UUID: `e39ffa3a-6ae6-4b99-8fe1-3e18c30b44c3`

## Verification

- Focused iOS Simulator tests passed for the client shield policy, Hard Mode coordinator, and time-window store.
- Release archive and App Store Connect IPA export succeeded with Xcode 26.4.
- Exported app passed `codesign --verify --deep --strict`.
- Apple upload succeeded with no errors; build status reached `VALID` and appeared in TestFlight as 1.4 (34).
- The physical-device Screen Time shield behavior still needs testing on the internal tester's iPhone.
