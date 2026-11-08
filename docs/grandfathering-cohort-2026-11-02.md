# Grandfathered subscriber snapshot — 2 November 2026

## Plain-English rule

The three customers with active paid production Nima Pro subscriptions at the snapshot are grandfathered into the build-24 VPN experience. A customer who subscribes after this snapshot is not automatically added. A customer remains in this cohort if they later cancel or lapse, but paid features still require an active subscription.

## Snapshot and dashboard marker

- RevenueCat project: `e46e9882`.
- Snapshot requested at `2026-11-02T10:17:06Z` with Customers filtered to `Subscription status is Active` and sandbox data off.
- RevenueCat showed three paid subscribers and zero trialing subscribers. Each of the three initial purchase events was checked as `PRODUCTION` and `APP_STORE`.
- An audience export was requested; RevenueCat confirmed that it will email a ZIP download link. The email attachment has not yet been received or inspected.
- All three customer profiles were assigned custom attribute `nima_legacy_vpn_cohort = 2026-11-02` and the attribute was verified on each profile.
- Private identifiers, including the original App Store transaction IDs and RevenueCat aliases, are saved in `.secrets/grandfathered-subscribers-2026-11-02.json`. That file is gitignored and mode `0600`. Do not commit or publish it.

## Combined-build implementation requirement

The dashboard attribute is an operational record. RevenueCat customer attributes cannot be read from the iOS SDK. The combined app must independently recognize these three purchase lineages, or query a trusted server that reads the RevenueCat attribute. Do not place a RevenueCat secret API key in the app.

Choose the old experience only after the grandfathered cohort and the current Pro entitlement have been resolved. Preserve build-24 VPN settings for these customers. New customers must receive the build-28 experience without a VPN prompt. An unresolved lookup must not permanently route a customer into the wrong experience. Verify update, reinstall, restore, cancellation, lapse, and ATT denial on the combined TestFlight build.

Sources: [RevenueCat customer attributes](https://www.revenuecat.com/docs/customers/customer-attributes), [RevenueCat restore behavior](https://www.revenuecat.com/docs/projects/restore-behavior), and [Apple StoreKit original transaction ID](https://developer.apple.com/documentation/storekit/transaction/originalid).
