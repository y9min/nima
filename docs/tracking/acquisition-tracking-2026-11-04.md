# Acquisition tracking implementation — 4 November 2026

Plain English: PostHog records the product funnel and returning sessions. Tenjin measures acquisition. RevenueCat owns subscription revenue. Nima updates Apple's aggregate conversion values without identifying people who decline tracking. No new app build has been released as part of this work.

## Saved service configuration

- Tenjin iOS app: Nima: Block Reels & FYP, bundle `so.nima.app`, App Store ID `6790122342`, Tenjin app ID `9a785c34-2ee5-4710-a78b-ee17a09ab70b`.
- Tenjin client SDK key is stored in ignored `apps/ios/Secrets.xcconfig`; `TENJIN_ENABLED=YES`. The checked-in example stays disabled. No server credentials were added to source.
- RevenueCat → Tenjin integration saved with the user's approval and gross-revenue reporting. RevenueCat requires an advertising ID attribute to deliver events to Tenjin. This implementation supplies it only with ATT authorization; denied users use aggregate Apple measurement. It intentionally does not populate a zero IDFA to expand individual server reporting.
- Meta OAuth approved by the user. Selected the current Nima business `970011838864094`, excluding unrelated and future businesses.
- Meta ad account `185174636858322` linked in Tenjin. The service displays the account as Yamin Ahmed.
- Nima's Meta app ID `930216026566807` saved in Tenjin. Meta Install callback ON. AEM appeared ON automatically after saving the app ID; the app itself does not connect Tenjin or send individual events without ATT authorization.
- Tenjin's Meta IAP, Meta Start Trial, Meta Subscription Revenue and ad-revenue callbacks remain OFF. RevenueCat's existing direct Meta integration remains the subscription sender.
- Existing RevenueCat → PostHog integration verified active, EU region, gross revenue, with recent successful delivery records. Subscriber attributes as person properties is OFF; this was preserved.
- Created [Nima Acquisition & Revenue](https://eu.posthog.com/project/297541/dashboard/1084871), with an ordered onboarding-to-first-payment funnel, initial-versus-renewal revenue, checkout problems, and ATT decisions. The earlier dashboard was preserved. No approved Data Catalog metrics existed; these are saved dashboard analyses, not approved canonical definitions.

## App behavior

Tenjin SDK 1.20.1 is pinned in XcodeGen and Package.resolved and linked only to the main application. AdServices is optional and `-ObjC` is set. No advertising code was added to the VPN or Screen Time extensions.

ATT stays at the existing pre-paywall location. Meta and Tenjin individual tracking only starts after authorization. Tenjin reconnects once per foreground, opts out after refusal/revocation, disables SDK purchase/subscription auto-tracking, and keeps offline advertising-event caching disabled. New transactions and renewals are reported by RevenueCat, including when the app is closed. Consent changes reach RevenueCat when the app reconnects; already transmitted/in-flight data cannot be recalled.

The advertising event boundary accepts only names for onboarding completion, rendered paywall, and checkout start. It does not copy arbitrary PostHog event properties. VPN traffic, browsing content, onboarding answers, device selections, diagnostic payloads and social login details are excluded.

The rendered-paywall event now fires when RevenueCatUI actually displays the offering. The earlier loading-screen entry is separately recorded as `paywall_screen_entered`. Product/package IDs, offering and context accompany the rendered impression in PostHog. Purchase attempts retain their existing correlation IDs, pricing, currency, timings and error diagnostics.

Product telemetry includes `app_first_observed`, `app_session_started`, `app_foregrounded`, `app_backgrounded` and once-per-install `activation_completed` (completion of guided practice, a candidate activation milestone rather than a validated retention predictor). Temporary inactive states do not create sessions; background gaps under 30 minutes reuse the session. Events include session ID, app/build, schema version, ATT state, runtime environment and elapsed days since first observation. This enables D1/D7/D30 reporting after cohorts mature. Existing installs are labelled `existing` when onboarding was already complete; incomplete installs are labelled `new_or_incomplete`, not asserted to be fresh installs.

RevenueCat's existing `$posthogUserId` linkage is preserved. Tenjin installation IDs attach to RevenueCat before purchase when available; failed attribute syncs retry. Optional attribution context is fetched with bounded retries. Only a small allowlist of campaign fields is eligible for first-party analytics, with identifiers and URLs discarded. **Meta/Facebook/Instagram attribution payloads are excluded entirely from PostHog/RevenueCat profile enrichment**, because Meta's optional AMM terms impose separate restrictions. AMM terms were viewed, not accepted. Payloads missing an ad-network name are also excluded.

## Apple conversion mapping

Nima's acquisition coordinator is the single owner of conversion progress. For authorized users with Tenjin connected, it calls Tenjin's conversion API, which updates Apple and reports the value to Tenjin. Without individual tracking permission, it calls Apple's aggregate API directly and does not connect Tenjin. These routes are serialized, use the same schema, and never both submit the same in-flight update. Meta's independent SDK updater remains disabled. The advertiser postback endpoint is `https://tenjin-skan.com`.

| Fine value | Meaning | Coarse value |
| --- | --- | --- |
| 0 | Installation registration | low |
| 1 | Onboarding complete | low |
| 2 | Actual paywall rendered | low |
| 3 | Checkout initiated | low |
| 4 | Verified trial | medium |
| 5 | Verified paid subscription | high |

Conversion progress cannot decrease. Direct Apple acknowledgement is persisted separately; errors remain retryable. Tenjin's conversion API has no success callback, so the app records `submitted` rather than claiming delivery, keeps progress, and resubmits on the next foreground. Progress is reasserted on later daily foregrounds for 35 days after this measurement version first observes the installation. Apple determines the actual attribution windows; local elapsed time is not claimed to recover an existing user's installation date. No window is locked early. Sandbox/family-shared entitlements are excluded. Restore or cached access alone does not create a paid conversion. A newly verified transaction after first observation can advance progress when the app reopens after trial conversion.

`tenjin-meta-conversion-schema.csv` follows Tenjin's published Meta template. It is prepared, **not uploaded or active**. Conversion value 0 is omitted from the CSV as required by Tenjin; Apple receives it for registration. Coarse mapping distinguishes trial from paid conversion. Meta event names for custom onboarding, ViewContent and InitiatedCheckout still require UI validation when source events become available. This is a milestone schema; it does not invent revenue amounts or provide revenue-bucket value optimization.

## Remaining activation work

1. Run the new tracking build on a registered physical test device, accept/refuse/revoke ATT, and verify Tenjin's live event tool. Unit tests deliberately suppress external telemetry and do not establish end-to-end delivery.
2. Tenjin's source-event selector currently returns **No options** for `paywall_viewed` because no build with this SDK has sent it yet. After the first real test events arrive, save and activate these callbacks: `onboarding_completed` → same-named Meta custom event; `paywall_viewed` → `fb_mobile_content_view`; `checkout_started` → `fb_mobile_initiated_checkout`. Keep the subscription callbacks OFF to prevent duplicate RevenueCat revenue/trials.
3. Tenjin's SKAdNetwork page remains **Unverified**, with an empty MMP connection URL and no schema-upload/ownership action exposed in the inspected UI. Complete Tenjin ownership verification, then upload/validate the prepared schema and import its connection URL into Meta Events Manager. Do not claim SKAN campaign setup complete from an SDK build alone.
4. Verify the exact trial/initial payment/renewal mapping in live Meta Events Manager, dataset/app association, receipt of one event per transaction, and campaign optimization eligibility. Successful HTTP delivery alone is insufficient. No campaign or budget was changed.
5. Reconcile PostHog revenue with production RevenueCat transactions and confirm sandbox separation before making ROAS decisions. The existing feed has frequent renewal events, but sandbox/production separation was not established by this audit. Historical data was preserved and the dashboard explicitly notes the limitation.
6. Publish the updated privacy policy source and align App Store disclosures before releasing the new SDK. The local source was updated; no live policy or App Store submission was published.
7. Meta's optional AMM enrollment is not required for the basic callback setup. It was not accepted, and no restricted per-user Meta campaign data is exported to PostHog. Any future AMM enrollment requires explicit agreement review and compliance with its use, sharing and retention restrictions.

## Validation

- Simulator build-for-testing succeeded with the new dependency.
- All 53 focused Nima tests passed: acquisition, product analytics, Meta consent and subscriptions. Exact final result-bundle path is in `/tmp/nima-tracking-tests-final.log`.
- Web policy TypeScript check passed using `apps/web/node_modules/.bin/tsc --noEmit -p apps/web/tsconfig.json`. The pnpm wrapper attempted dependency installation and stopped at its existing ignored-build-script policy; no build-script permission was broadened.
- `git diff --check` passed. Pre-existing changes in the checkout were preserved.

## References

- https://tenjin.com/docs/meta-setup/
- https://tenjin.com/docs/upload-conversion-value-schema/
- https://tenjin.com/docs/mmp-sdk-ios/
- https://www.revenuecat.com/docs/integrations/attribution/tenjin
- https://www.revenuecat.com/docs/integrations/attribution/meta-ads
- https://developer.apple.com/documentation/storekit/skadnetwork
- https://developers.facebook.com/advanced_mobile_measurement/terms
