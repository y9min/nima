# Launch review — 15 October 2026

Read-only investigation of Meta, RevenueCat, App Store Connect and PostHog. No campaign budgets, delivery switches, tracking configuration or app code changed.

## Acquisition and revenue

- Meta reporting set to Today and yesterday (14–15 October, London): Creative 01 had 24 attributed installs, £33.71 spend and £1.40 per attributed install; Creative 02 had 5 installs, £18.99 spend and £3.80 per attributed install. Total spend £52.70; 29 attributed installs. Both enabled; creatives 03/04 off.
- RevenueCat production overview: zero active trials, subscriptions, MRR and revenue; no live transactions. New Customers daily chart: 30 on 14 October and 250 on 15 October at inspection. Chart defines customers as app users irrespective of purchase and excludes aliased customer records.
- App Store Connect Sales and Trends, Last 24 Hours (14–15 October, UTC): 410 app units. Sales with content filters removed: $0. Standard daily report had only reached 13 October; the recent data came from the hourly view.
- These windows and definitions differ. App units, newly seen customer profiles, people starting onboarding and ad-attributed installs must not be treated as interchangeable or assigned to ads without attribution evidence.

## PostHog funnel

One-off ordered person funnel, project 297541 (UTC), 13 October 23:00 UTC through 15 October 09:15 UTC, filterTestAccounts=true. No saved governed metric existed. These are project users, not an ad-attributed cohort.

| Step | People |
| --- | ---: |
| onboarding_started | 281 |
| onboarding_completed | 238 |
| paywall_screen_viewed | 100 |
| purchase_started | 61 |
| purchase_succeeded | 0 |

43 people (15.3%) did not complete initial onboarding. A further 138 of the 238 completers (58.0%) did not reach the paywall by the observation cutoff. Source routing places the required guided practice/window flow between initial onboarding completion and paywall; existing events cannot isolate which guided substep accounts for this loss. 39 of 100 paywall viewers did not trigger purchase_started. None of the 61 purchase starters recorded purchase_succeeded.

purchase_failed had two events from one person on 14 October, reason purchase_error; zero on 15 October. The code records a generic error reason and no purchase-cancelled callback. Therefore the remaining attempts cannot be classified as payment failures, cancellations or stalled sheets from these events. Account screen views are not proof of purchase: 49 were tagged existing_subscriber and one post_purchase across the daily unique counts. The app provides an Already subscribed? Sign in route.

## Measurement limitation

Services/MetaAdsService.swift initializes and activates Meta only with ATT authorization; isSKAdNetworkReportEnabled=false. Screens/PaywallScreen.swift requests ATT before capturing paywallViewed. This explains a structural blind spot for people who leave before the prompt or do not authorize tracking. The precise portion of the discrepancy caused by consent, timing, attribution window and other acquisition sources was not quantified.

## Billing reconciliation

Meta payment activity (9–15 October) listed five paid transactions: £17 + £8 + £8 + £8 + £8 = £49. Current outstanding balance £3.70. £49 + £3.70 = £52.70, matching the campaign spend observed across 14–15 October. Payment settings showed an £8 automatic billing threshold, explaining the repeated charges. Bank settlement/authorization status was not inspected.

Payment settings also displayed a Meta-imposed £39.89 daily spending limit and the message that ads were paused because today's limit was reached. Enabled/Active table status is therefore insufficient to conclude continuous delivery.

## Priorities

1. Verify production App Store purchase and cancellation behavior before increasing spend; instrument purchase cancellation and safe error codes.
2. Add guided practice/window funnel checkpoints to pinpoint the largest pre-paywall loss.
3. Review privacy-preserving aggregate attribution so campaign learning does not depend solely on ATT opt-in.

Evidence screenshots: screenshots/meta-ads/apple-sales-2026-10-15.jpg and screenshots/meta-ads/billing-reconciled-2026-10-15.jpg.
