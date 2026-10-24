# Meta ads measurement implementation plan

Prepared 12 October 2026. Status: app implementation complete with measurement disabled pending dashboard credentials and device validation. See [implementation record](meta-ads-implementation-record.md) for verified work and release blockers.

## Outcome

Connect Nima's iPhone app to Meta so the first ad experiment can measure app activity and subscriptions. In plain English: help identify which ads produce paying customers and give Meta useful feedback. Reporting will remain incomplete for some iOS users; RevenueCat remains the source for total subscription revenue.

## Current code and implementation locations

- `apps/ios/project.yml` owns the XcodeGen package and target configuration. Add Meta CoreKit to the main app only, then regenerate `Nima.xcodeproj`; preserve existing URL schemes and dependencies.
- `apps/ios/Nima/NimaApp.swift` owns startup and scene activation. Integrate a small new `Services/MetaAdsService.swift` here without slowing launch or blocking onboarding.
- `apps/ios/Nima/Models/SubscriptionStore.swift` owns RevenueCat configuration and identity changes. Coordinate attribution setup here before purchases and after identity changes, preserving anonymous purchases and account linking.
- `apps/ios/Secrets.xcconfig.example` provides configuration placeholders. Add Meta App ID and client-token placeholders; keep actual configuration local. Server access tokens belong in the RevenueCat dashboard, never the app bundle or Git.
- `apps/ios/Nima/Info.plist` is generated from project configuration. Add required Meta settings and tracking-purpose text through `project.yml`.
- The privacy manifest and `docs/app-store-privacy-submission.md` currently declare no tracking. Update them and the public privacy policy to match the final integration.

## Work order

### 1. Prepare account configuration

Create/select Nima's Meta developer app under its business portfolio. Configure the iOS bundle ID `so.nima.app` and App Store ID `6790122342`; verify the live listing. Connect the intended ad account. Obtain the app configuration and create/link the event dataset. Prepare separate sandbox event delivery for testing.

Deliverable: a configuration checklist with identifiers and dashboard locations, without exposing tokens.

### 2. Add the SDK and lifecycle service

Use Meta's official iOS SDK, select a supported release and resolve/pin the dependency. Implement configuration validation and an enable/disable switch. Missing configuration must safely disable Meta integration. Use the SDK's required launch hooks and one activation path; verify against the selected SDK version. Disable automatic purchase logging so RevenueCat owns subscription reporting.

Keep this service independent of PostHog and the tunnel. Send no domains, traffic details, blocking rules, diagnostics or onboarding answers to Meta.

### 3. Implement tracking permission

Add Apple's App Tracking Transparency (ATT) request at an active, stable onboarding point before subscription purchase, without colliding with VPN/notification prompts. Suggested purpose text: "Your permission helps us measure which Nima ads lead to downloads and subscriptions."

Handle not determined, authorised, denied and restricted states. Users can continue and subscribe after refusal. Gate advertising identifiers, customer matching and trackable Meta events on authorisation. Recheck status on app activation. Keep RevenueCat's option to send App Store events without ATT authorisation disabled; propagate current consent and verify refusal/revocation prevents subsequent matching event delivery. Do not treat an anonymous identifier as a consent bypass.

Use only an explicitly documented privacy-preserving measurement path for non-consenting users; verify the selected SDK behaviour before enabling it. Do not promise complete per-ad purchase attribution.

### 4. Connect RevenueCat

After RevenueCat is configured and consent permits matching, attach the required Meta attribution identifiers before purchasing. Reapply attribution safely after account linking and consent changes. Initially omit optional email/phone matching to minimise data sharing.

Configure RevenueCat's Meta Conversions API integration and subscription event mapping. Separate trial starts from payments in reporting. Choose and record the revenue basis so comparisons use consistent figures. Verify iOS campaign measurement configuration and event eligibility separately from successful event delivery; assign only one conversion-value updater if SKAdNetwork is used.

### 5. Update disclosures and verify

Update the public policy, privacy manifest, App Store privacy answers and review notes based on actual SDK behaviour. Preserve Nima's local VPN-data processing promises. Inspect the archive's combined SDK privacy report.

Add focused tests for missing configuration, consent transitions, attribution ordering and duplicate activation prevention. Build the app and run affected subscription tests. On a physical iPhone test new installs, acceptance/refusal, purchase, trial where offered, restore, account linking and consent changes. Verify Google/email sign-in and feed blocking still work.

With a new sandbox customer, inspect RevenueCat's delivery details and Meta's received events. Confirm one subscription event per transaction and correct revenue/currency. A sandbox test proves delivery, not attribution to a real ad.

### 6. Release and validate with a small live campaign

Create a new build with updated metadata, test through TestFlight, then submit to Apple. After approval and release, use a small paid smoke test to check install measurement, campaign attribution and selectable optimisation events. Launch the planned creative test after this check; reconcile Meta results with RevenueCat and App Store Connect rather than expecting identical totals.

## Timing and dependencies

Allow roughly 4–6 hours for code, configuration and initial testing if accounts and credentials are ready. Reporting delays, dashboard eligibility issues, physical-device access and Apple review add elapsed time. The estimate is not a release guarantee.

Required inputs: Meta app/account access, app configuration, RevenueCat integration access and a physical iPhone with a sandbox purchase account. Implementation can begin with placeholders while these are gathered.

## Completion criteria

- App builds and onboarding, subscriptions, sign-in and blocking remain functional.
- Consent refusal/revocation prevents matching-based tracking without preventing payment.
- Sandbox subscription delivery is verified without duplicate purchase events.
- Disclosures match the shipped integration.
- Production campaign eligibility and measurement are checked after release.

## Reference documentation

- [RevenueCat Meta integration](https://www.revenuecat.com/docs/integrations/attribution/meta-ads)
- [Apple user privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [Official Meta iOS SDK](https://github.com/facebook/facebook-ios-sdk)
