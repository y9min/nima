# Nima 1.4 (29): review and release notes

Build 29 contains the current controlled-client and Screen Time experience and a VPN-backed experience for a fixed group of existing subscribers. New purchases use the current experience. The legacy route uses verified Apple purchase history and saved RevenueCat identity hashes; the RevenueCat Pro entitlement controls paid access independently. The app contains no RevenueCat secret key or raw cohort identifiers.

## App Review

The standard review account and a new installation use the current experience. Follow the onboarding, subscribe or restore, and use the Instagram, TikTok and X controls and windows. The current experience does not require a VPN profile.

The legacy route presents the earlier Instagram and TikTok blocking dashboard and time windows. It uses the existing Nima VPN profile to enforce enabled controls and windows. The VPN permission prompt appears when VPN protection is requested. Subscription access is still required.

These notes describe the intended behavior. Do not submit them as verified review instructions until the release checks below pass.

## Release gate

- Test an in-place upgrade from the old app on a physical iPhone, using a controlled sandbox purchase lineage compiled into a non-production test allowlist. Verify manual blockers, windows, pause settings, existing profile and protection state.
- Test a clean new-customer installation on a physical iPhone and verify that the new route never asks for or requires VPN permission.
- Test purchase, restore, cancellation with remaining access, expiry, relaunch, ATT denial and a temporary offline check. Verify the complete legacy flow with the controlled sandbox lineage and compare the matching procedure against the three saved production purchase records.
- Reconcile the emailed RevenueCat export against the private 2 November snapshot before public release. Keep the raw export and raw identifiers out of Git, analytics and test output.
- Upload to TestFlight only after the checks required by the build plan pass. Keep paid acquisition off until the combined TestFlight build passes.

The production allowlist is fixed to the three saved subscribers. A sandbox lineage is not yet provided and is not included in the production allowlist; use a separate test build for controlled sandbox testing and remove its test-only entry from the production archive.
