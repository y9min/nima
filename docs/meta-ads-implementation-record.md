# Meta ads implementation record

Updated 12 October 2026. App-side implementation is present; dashboard configuration is saved and local measurement is enabled for TestFlight build 1.3 (24). Production release remains pending device validation.

In plain English: the app asks permission before helping Meta connect app activity and subscriptions to ads. Refusing does not prevent subscribing. RevenueCat owns subscription reporting so the app does not send duplicate purchase events.

## Code and configuration

- Official Meta iOS SDK **18.1.1**, exact XcodeGen pin and resolved Swift package revision. CoreKit is linked only into the main app; the tunnel does not link Meta.
- `NimaApplicationDelegate` captures the launch options. `MetaAdsService` defers SDK initialization until ATT is authorised, disables automatic app/purchase logging, uses explicit flushing, and manually activates once per foreground session. Temporary inactive states do not reset that session.
- `META_ADS_ENABLED=YES`, numeric `META_APP_ID`, and `META_CLIENT_TOKEN` are required in the ignored local `apps/ios/Secrets.xcconfig`. Placeholders, absent settings, and the default disabled switch prevent initialization and ATT prompts. Never store a server access token there or in Git.
- ATT is requested at the paywall after earlier onboarding prompts. The native purchase screen waits for this preparation; denied/restricted users continue normally.
- RevenueCat device identifiers and Meta anonymous ID are attached after RevenueCat configuration, after account linking, and before manual purchase/restore. The RevenueCat UI path is prepared before the paywall is shown. Matching identifiers are cleared on refusal/revocation and consent is synced on foreground. Failed syncs retry on later foreground/purchase calls. No optional advertising email/phone matching is added.
- SDK SKAdNetwork reporting/conversion updating is **disabled**. No non-consenting measurement path or conversion updater is enabled. Campaign eligibility/SKAN setup remains a separate release gate.
- Public policy source, app privacy manifest, and next-build App Store privacy/review instructions have been updated. The live policy and live App Store labels still require publication aligned with the next release.

## Dashboard checklist

| Item | Value / status |
| --- | --- |
| Legal entity | 9INE LTD, company 17294957 |
| iOS bundle | `so.nima.app` |
| App Store ID | `6790122342` |
| Current ASC version observed | 1.2, build 23, Ready for Distribution |
| RevenueCat project | `e46e9882` (nima) |
| RevenueCat integration | Saved: CAPI, gross revenue, consent override OFF, both production/sandbox credentials |
| Meta app | Nima, ID `930216026566807`, created under Nima portfolio; iOS `so.nima.app` / store `6790122342` saved, auto purchase logging OFF |
| Meta business | Nima portfolio created, ID `970011838864094`; business verification not yet completed |
| Meta app ID / client token | App ID `930216026566807`; client token saved to ignored local Secrets.xcconfig; enabled in build 1.3 (24) |
| Production dataset / CAPI token | Nima iOS Production `1673956754297628` paired with app `930216026566807`; CAPI token saved in RevenueCat |
| Sandbox dataset / token | Nima iOS Sandbox `1292940769582420` created; separate CAPI credential saved in RevenueCat |

Verified RevenueCat configuration:

- Conversions API; production and separate sandbox dataset credentials.
- **Send events when ATT consent is not authorized: OFF** (the new-integration form initially defaults ON; verify before saving).
- Revenue basis: **gross revenue**, before Apple commission/taxes. Reconcile against matching gross RevenueCat metrics.
- Trial Started → `StartTrial`; Trial Converted, Initial Purchase, Renewal → `Subscribe`; Non-Subscription Purchase → `fb_mobile_purchase`.
- Meta iOS automatic purchase logging is OFF. Production dataset SDK automatic event logging and Event Suggestions are explicitly OFF. Meta InstrumentManager skips crash/error instrumentation when automatic logging is off. Link the app, intended ad account and datasets, and verify eligibility for app promotion/optimization separately from delivery.

## Verification and remaining release work

Simulator build and unsigned Release archive succeeded. Archive inspection found 19 privacy manifests, including Meta CoreKit/Basics/AEM and RevenueCat. Meta CoreKit declares tracking with `ep1.facebook.com`, device identifiers for advertising, and unlinked crash/other data for functionality/analytics; the app declares `graph.facebook.com` and `ep1.facebook.com`. This is inspection of bundled declarations, not confirmation of enabled network behavior or the Xcode-generated aggregate privacy report.

All **344 simulator tests passed** (157 Nima tests including Meta/subscription coverage, and 187 tunnel tests). The harness summary script and web TypeScript check passed. Web TypeScript checking passed. Focused simulator tests cover invalid/disabled configuration, consent refusal/revocation, duplicate activation prevention, attribution ordering and anonymous-to-linked identity transitions. Run the existing SubscriptionStore tests alongside them. The web policy source must pass the web TypeScript check.

Physical-device work remains: new install; ATT accept/refuse/restrict/revoke; sandbox trial/purchase/renewal; restore; anonymous account linking; Google/email sign-in; VPN/feed blocking. The paired iPhone was unavailable during initial implementation. Validate new sandbox customer attributes, a successful RevenueCat delivery and Meta reception, exactly one subscription event per transaction, correct currency/revenue and absence of matching delivery for refused/revoked users.

Revocation cannot recall data already transmitted. A permission change while the app is closed cannot reach RevenueCat until the app reconnects; in-flight events and server renewals need physical-device/dashboard verification. Do not claim immediate server-side revocation while offline.

Public policy published at https://nima.so/privacy-policy through Cloudflare Pages project `nima-site`; source commit `b2df47f` in `y9min/nima-site`, deployment `a83c9c3a.nima-site-apa.pages.dev`. App Store version 1.3 draft created with updated release and review notes. Privacy labels were completed and published on October 12, 2026; all ten data types configured, with consented Meta identifiers, activation and purchase data marked as tracking. Signed build 1.3 (24) archive and App Store Connect upload succeeded; TestFlight processing/group assignment is pending. Existing internal group: `IPhone X` (`4f526300-8b3b-4b91-a1f5-5b96583360c9`), one current tester.

Before production submission: complete physical-device/sandbox delivery checks, inspect aggregate privacy behavior and choose campaign measurement mode. After Apple approval/release, perform a budget-authorised live smoke test. No campaign or ad spending has been started.

## References

- https://www.revenuecat.com/docs/integrations/attribution/meta-ads
- https://github.com/facebook/facebook-ios-sdk/releases/tag/v18.1.1
- https://developer.apple.com/app-store/user-privacy-and-data-use/

## App Review submission

October 12, 2026 at 3:46 PM: Submitted iOS version 1.3, build 24. App Store Connect confirms Waiting for Review. Submission ID: `0e8d87ce-7273-4980-a53e-bb9eda910984`. Manual release remains selected, so approval alone will not publish this version. User reported the remaining checks completed and explicitly instructed submission; end-to-end Meta delivery was not independently verified by this agent.
