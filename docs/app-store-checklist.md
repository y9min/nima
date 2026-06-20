# App Store Checklist

Use this as the launch-readiness checklist for Nima before App Store submission.

## App Store Metadata

- Confirm app name, subtitle, description, keywords, category, support URL, marketing URL, and age rating.
- Prepare final App Store screenshots for each required device size.
- Verify the screenshots match the current release build and do not include simulator/debug UI.

## Privacy And Account

- Complete App Privacy labels for account data, purchase data, diagnostics, and any analytics.
- Verify sign in works for the configured providers.
- Verify account deletion or cancellation flow is available and documented.
- Confirm privacy policy and terms links are live in the app and App Store Connect.

## Subscription

- Confirm RevenueCat API key is configured through release secrets, not hardcoded.
- Confirm the RevenueCat entitlement ID is `nima Pro`.
- Verify monthly and yearly products are active in App Store Connect and mapped in RevenueCat.
- Test purchase, restore, entitlement refresh, and logged-out behavior in sandbox/TestFlight.

## VPN And Entitlements

- Confirm bundle IDs match the release app and Network Extension targets.
- Confirm the app group is enabled for the app and tunnel extension.
- Confirm Network Extension entitlement approval is in place.
- Prepare App Review notes explaining the VPN purpose and how to test blocking behavior.

## Final QA

- Run web typecheck on Node 22 with the pinned pnpm version.
- Run the iOS regression gate before TestFlight upload.
- Verify onboarding, blocking setup, subscription gating, restore purchases, settings, and logs on a physical device.
- Confirm no debug screenshots, raw artifacts, build outputs, or local secrets are tracked by Git.
