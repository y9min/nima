# Nima 1.4 (33) — TestFlight preparation, 12 November 2026

## Status

Build 33 is prepared locally. It has **not** been uploaded to App Store Connect, assigned to a TestFlight group, or submitted for App Review. The archive contains the current working-tree changes, including the focus-window Screen Time connection fix and the other uncommitted changes already present in the checkout. The source patch below preserves that snapshot relative to commit `1c83e674f843328ad048ad7d4051dfbfe96b62df`.

## Artifacts

- Archive: `apps/ios/artifacts/Nima-1.4-33.xcarchive`
- App Store Connect distribution IPA: `apps/ios/artifacts/export-1.4-33-distribution/Nima.ipa`
- IPA SHA-256: `7ec63ea6d96377728bc7f841cd7c11b729ae760552ad8bedf26fa547ad3a9a29`
- IPA size: 44,136,344 bytes
- Source patch: `apps/ios/artifacts/Nima-1.4-33-source.patch` (SHA-256 `49332ca6a4a32eadec43fa372bd0a99934502e7dec79d902f99443dc0403bbcd`)
- App and four extensions: version 1.4, build 33
- Signing: Apple Distribution: 9INE LTD (SSTZYP6ZWB); `codesign --verify --deep --strict` passed on the exported app.

## Verification

- Release archive and App Store Connect export succeeded with Xcode 26.4.
- Focused iOS Simulator suite passed: 48 tests, 0 failures. It covered time-window scheduling, editor defaults, client shield policy, pause behavior, and Home card status.
- The Screen Time shield still needs a physical-device check. Simulator tests and signature verification cannot confirm that iOS blocks the selected official app on a real iPhone.

## TestFlight notes to use after upload

What to test: Create a focus window for Instagram, TikTok, or X. The editor should require Screen Time permission and an app connection before saving. For an older active window missing setup, open App Controls and use its setup warning. Check that the official app receives the iOS shield during the window and becomes available after it ends. Repeat after force-quitting and relaunching Nima. Check Home shows an unconnected app as off and lets the user finish setup.

Before upload, confirm the App Store Connect status of iOS 1.4 and whether the existing build-31 review must be withdrawn or replaced. Do not submit build 33 for review until the physical-device checks and release decision are complete.
