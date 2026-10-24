# Meta creative test report — English-speaking markets

Prepared 19 October 2026 and updated 20 October 2026. Updated reporting cutoff: **20 October 2026 at 8:57 AM London time**, when the additional Creative 01 run became inactive, unless a platform-specific lag is noted.

## Executive summary

The English-speaking ad set was published on 15 October 2026 at 5:11 PM London time. Creative 01 entered delivery at 5:16 PM and Creative 02 at 5:18 PM. Creative 03 and Creative 04 were subsequently tested. Creative 01 was then switched back on from **19 October at 6:27 PM until 20 October at 8:56 AM**. All four creatives are now off.

The clean, post-launch Meta data that can be isolated without mixing in earlier worldwide delivery now contains at least **37,309 impressions, £195.17 spend and 154 link clicks**. Meta claims eight attributed installs, but that figure is used only as an attribution signal—not as the download source of truth—because it clearly misses downloads visible in Apple's reporting.

For download volume, the primary source is **App Store Connect App Units**, with **RevenueCat New Customers** used as an independent check that downloaded users opened the app and initialized the SDK. These metrics must not be added together. On the now-complete post-launch dates 16–19 October, App Store Connect recorded **107 app units**. RevenueCat recorded **121 newly seen customers from 16–20 October**, of which 4 were on the partial 20 October day. The apparent mismatch reflects different identity, timing and processing rules—not separate groups of downloads.

Across the extended exact PostHog campaign window, **149 unique people started onboarding, 108 completed onboarding, 67 reached the paywall, 35 started a purchase and none recorded `purchase_succeeded`**. RevenueCat still shows **zero live trials, subscriptions, revenue and live transactions**. The added Creative 01 run generated more traffic but did not change the commercial conclusion: there is still no verified paid conversion.

Creative 01 was strongest in its first clean run: 0.633% link CTR, £0.73 CPC and £7.40 per Meta-attributed install in the uncontaminated 16–17 October portion. Its extra run was much weaker: **10,827 impressions, £52.58 spend, 31 link clicks, 0.286% CTR, £1.70 CPC and one Meta-attributed install at £52.58**. Creative 02 remained weaker than the original Creative 01 run. Creatives 03 and 04 both produced roughly 0.43–0.45% link CTR but no Meta-attributed installs.

## Scope and counting rules

- English-speaking campaign cutoff: **15 October 2026, 5:11 PM London time** (4:11 PM UTC).
- Meta delivery began after review at 5:16 PM for Creative 01 and 5:18 PM for Creative 02.
- Meta's 15 October daily rows contain performance from before and after the targeting edit under the same ad identities. Those rows are not valid English-market-only results and are excluded from clean totals.
- PostHog queries use the exact launch timestamp, exclude configured test accounts, and count each person once per event unless otherwise stated.
- App Store Connect reports in UTC. Its historical daily view cannot split 15 October at the launch time. The 24-hour view provides hourly data for the Creative 01 rerun but was still missing its final hour when inspected.
- RevenueCat's chart is daily. “New Customers” means newly seen app users, not purchasers or an additional download count. RevenueCat country is the user's detected country, not deterministic Meta attribution.
- Activity inside an ad's live window is a time correlation, not deterministic creative attribution. This is especially important for Creatives 01 and 02 because they ran concurrently.

## Creative schedule

| Creative | Delivery window (London time) | Approx. duration | Notes |
| --- | --- | ---: | --- |
| Creative 01 | 15 Oct 5:16 PM → 17 Oct 3:12 PM | 45h 56m | Ran concurrently with Creative 02 |
| Creative 02 | 15 Oct 5:18 PM → 18 Oct 12:51 AM | 55h 33m | Ran concurrently with Creative 01 |
| Creative 03 | 18 Oct 12:57 AM → 19 Oct 12:30 PM | 35h 33m | Switched on after Creative 02; delivery began six minutes later |
| Creative 04 | 19 Oct 12:37 PM → 19 Oct 5:46 PM | 5h 09m | A same-minute toggle on 18 Oct did not produce delivery; real delivery began 19 Oct |
| Creative 01 rerun | 19 Oct 6:27 PM → 20 Oct 8:56 AM | 14h 29m | Restarted 41 minutes after Creative 04 stopped; now inactive |

The first two creatives were not isolated sequential tests. Their overlapping windows mean App Store, RevenueCat and PostHog activity cannot be assigned between them from timing alone. Creatives 03 and 04 were much cleaner sequential periods.

## Meta performance

### Clean post-launch comparison

The table below excludes every 15 October Meta metric because the daily export mixes earlier worldwide delivery with the English-market period. Creative 01 therefore uses 16–17 October, Creative 02 uses 16–18 October, and Creatives 03/04 use their complete delivery totals.

| Creative | Impressions | Spend | CPM | Link clicks | Link CTR | CPC | Meta installs | Cost/install |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Creative 01, first clean run | 8,059 | £36.99 | £4.59 | 51 | 0.633% | £0.73 | 5 | £7.40 |
| Creative 01, extra run | 10,827 | £52.58 | £4.86 | 31 | 0.286% | £1.70 | 1 | £52.58 |
| **Creative 01, combined clean** | **18,886** | **£89.57** | **£4.74** | **82** | **0.434%** | **£1.09** | **6** | **£14.93** |
| Creative 02 | 7,520 | £37.90 | £5.04 | 24 | 0.319% | £1.58 | 2 | £18.95 |
| Creative 03 | 3,986 | £27.29 | £6.85 | 17 | 0.426% | £1.61 | 0 | — |
| Creative 04 | 6,917 | £40.41 | £5.84 | 31 | 0.448% | £1.30 | 0 | — |
| **Clean minimum, all runs** | **37,309** | **£195.17** | **£5.23** | **154** | **0.413%** | **£1.27** | **8** | **£24.40** |

### What the contaminated export contains

For auditability, the raw exports through 20 October contain approximately 166,985 impressions, £235.02 spend, 682 link clicks and 45 Meta-attributed installs across the four creatives. However, 129,683 impressions and 37 installs sit on 15 October, before and after the targeting edit under the same ad identities. The unusually low 15 October CPMs (£0.32 for Creative 01 and £0.27 for Creative 02) are further evidence that the row is dominated by the earlier worldwide delivery. These figures must not be presented as English-market-only performance.

### Creative interpretation

**Creative 01** was the strongest acquisition creative in its initial clean run, but the follow-up did not reproduce that strength. The rerun's CTR fell from 0.633% to 0.286%, CPC rose from £0.73 to £1.70, and Meta CPI rose from £7.40 to £52.58. Combined clean performance remains better than Creative 02 on CPC and attributed CPI, but the rerun substantially weakens the case that Creative 01 is a scalable winner.

**Creative 02** was clearly weaker. Its link CTR was roughly half of Creative 01's, CPC was more than twice as high, and cost per attributed install was about 2.6 times higher.

**Creative 03** and **Creative 04** had similar click-through performance, with Creative 04 slightly ahead on CPM and CPC. Neither produced a Meta-attributed install. Their zero-install result is more meaningful than a small early sample because both exceeded the minimum exposure threshold.

No creative produced a Meta-reported trial or subscription.

## Download source of truth: App Store Connect plus RevenueCat

For this report, **App Store Connect App Units is the authoritative download count**. RevenueCat New Customers is the activation cross-check: it indicates that an app user was first seen by the RevenueCat SDK. Meta's install column is retained only to compare ad attribution efficiency between creatives.

Do not add App Store units and RevenueCat customers. In plain English: they are two cameras looking at much of the same traffic, not two separate groups of downloads.

### App Store Connect app units

App Store Connect recorded the following app units in UTC:

| UTC date | App units |
| --- | ---: |
| 15 Oct | 385 |
| 16 Oct | 25 |
| 17 Oct | 37 |
| 18 Oct | 1 |
| 19 Oct | 44 |
| 20 Oct daily report | 0 (reporting incomplete) |

The 15 October value cannot be split at the English-market launch time and is therefore excluded from any strict English-only total. The confirmed post-launch total for complete dates is now **107 App Store units from 16–19 October**, plus an unknown number from the post-4:11 PM UTC portion of 15 October. Apple's 20 October daily report was still incomplete when inspected.

The App Store hourly view for the Creative 01 rerun showed **21 clear app units from 6:00 PM UTC on 19 October through 6:00 AM UTC on 20 October**, plus one unit in the 5:00–5:59 PM UTC transition hour that cannot be split around the 5:27 PM UTC restart. The hourly feed did not yet include the final 7:00–7:56 AM UTC portion before the ad stopped. These are time-correlated App Store units, not creative-attributed downloads.

For the clean sequential windows:

- Creative 03's delivery window contains approximately **11–12 App Store units**: one on 18 October plus 10 clearly before its 19 October stop and one in the 11 AM UTC transition hour that cannot be split at 11:30.
- Creative 04's observed portion contains **at least 13 App Store units**, with one additional unit in the 11 AM UTC transition hour that cannot be allocated before or after its 11:37 AM UTC delivery start. Later hours were still subject to App Store reporting lag.
- Creatives 01 and 02 overlap. App Store Connect recorded 62 units across the clean full days of 16–17 October, but those downloads cannot be assigned between the two ads by timing.

App Store units are not equivalent to Meta-attributed installs. App Store units include organic downloads and other sources; Meta uses its own one-day click attribution and reported eight installs in the clean, isolatable period.

### RevenueCat activation check and daily country breakdown

RevenueCat showed **zero active trials, zero active subscriptions, zero MRR, zero revenue and no live transactions**.

Daily newly seen customers were:

| Date | New customers |
| --- | ---: |
| 15 Oct | 305 |
| 16 Oct | 41 |
| 17 Oct | 29 |
| 18 Oct | 10 |
| 19 Oct | 37 |
| 20 Oct, partial | 4 |

This is **121 new customers on 16–20 October**, including four on the partial 20 October day, plus an unknown subset of the 305 customers on 15 October after the launch cutoff. RevenueCat customers are app users seen by the SDK, not paid customers. The difference from App Store units is expected because the platforms use different timestamps, processing rules and identity models.

The following is the full non-zero country breakdown shown by RevenueCat for each launch-period calendar day. **15 October is a mixed worldwide/English-targeting day and must not be attributed wholesale to the English campaign.** Later dates are also not ad-attributed: they can contain organic users, delayed opens and users from other acquisition sources.

- **15 Oct — 305:** India 128; Nepal 20; Bangladesh 18; Other 12; Algeria 11; Iraq 11; Pakistan 11; Egypt 9; Morocco 8; Jordan 7; Tunisia 7; Vietnam 6; Ethiopia 5; Uzbekistan 4; Mongolia 3; Thailand 3; Türkiye 3; United States 3; Belgium 2; Georgia 2; Indonesia 2; Kenya 2; Kyrgyzstan 2; Malaysia 2; Mexico 2; Nigeria 2; Palestine, State of 2; Philippines 2; Somalia 2; Trinidad and Tobago 2; Afghanistan 1; Albania 1; Canada 1; Lebanon 1; Malawi 1; Maldives 1; Netherlands 1; New Zealand 1; Panama 1; Peru 1; Poland 1; Venezuela 1.
- **16 Oct — 41:** Canada 8; India 8; New Zealand 5; Pakistan 4; Bangladesh 3; United States 3; Algeria 2; Türkiye 2; United Kingdom 2; Ethiopia 1; Nepal 1; Other 1; Serbia 1.
- **17 Oct — 29:** Canada 7; United States 6; New Zealand 5; United Kingdom 4; Iraq 2; Andorra 1; Australia 1; Bangladesh 1; Ethiopia 1; India 1.
- **18 Oct — 10:** United Kingdom 2; Australia 1; Canada 1; India 1; Indonesia 1; Lebanon 1; Mexico 1; Moldova 1; Netherlands 1.
- **19 Oct — 37:** Canada 13; Australia 6; United States 5; India 4; United Kingdom 4; Kuwait 1; Moldova 1; Morocco 1; New Zealand 1; Rwanda 1.
- **20 Oct, partial — 4:** Australia 2; Canada 1; New Zealand 1.

Across 16–20 October, the five visible English target markets contributed **78 of 121 RevenueCat new customers (64.5%)**:

| RevenueCat country | 16 Oct | 17 Oct | 18 Oct | 19 Oct | 20 Oct partial | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Canada | 8 | 7 | 1 | 13 | 1 | 30 |
| United States | 3 | 6 | 0 | 5 | 0 | 14 |
| United Kingdom | 2 | 4 | 2 | 4 | 0 | 12 |
| New Zealand | 5 | 5 | 0 | 1 | 1 | 12 |
| Australia | 0 | 1 | 1 | 6 | 2 | 10 |
| **English-market total** | **18** | **23** | **4** | **29** | **4** | **78** |
| **All countries** | **41** | **29** | **10** | **37** | **4** | **121** |

The remaining 43 users from 16–20 October do not prove Meta served outside the target countries. RevenueCat is not a Meta attribution report, so those users may be organic, delayed opens from earlier worldwide acquisition, referrals or other sources.

## PostHog product funnel

### Unique people by tracked event

Exact extended window: 15 October 2026 at 4:11:10 PM UTC through 20 October 2026 at 7:57 AM UTC. Test accounts excluded.

| Tracked event | Unique people | Share of onboarding starts |
| --- | ---: | ---: |
| `onboarding_started` | 149 | 100.0% |
| `onboarding_completed` | 108 | 72.5% |
| `paywall_screen_viewed` | 67 | 45.0% |
| `purchase_started` | 35 | 23.5% |
| `purchase_failed` | 2 | 1.3% |
| `purchase_succeeded` | 0 | 0.0% |
| `restore_started` | 8 | 5.4% |
| `restore_succeeded` | 7 | 4.7% |
| `account_screen_viewed` | 33 | 22.1% |
| `auth_started` | 16 | 10.7% |
| `auth_succeeded` | 11 | 7.4% |
| `auth_failed` | 6 | 4.0% |
| `permission_requested` | 1 | 0.7% |
| `permission_resolved` | 1 | 0.7% |
| `guided_practice_started` | 1 | 0.7% |
| `paywall_unlocked` | 1 | 0.7% |
| `app_unlocked` | 2 | 1.3% |
| `account_link_deferred` | 2 | 1.3% |

Important instrumentation caveat: `guided_practice_started`, permission events and unlock events only appear from 18 October onward, so they are not complete funnel stages for the whole campaign. They must not be used to claim that only one person reached guided practice. The reliable whole-period funnel is onboarding start → onboarding completion → paywall view → purchase start → purchase success.

Daily unique-person counts for the reliable funnel were:

| UTC date | Started onboarding | Completed | Paywall viewed | Purchase started | Purchase failed | Purchase succeeded |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 15 Oct, post-launch partial | 11 | 7 | 8 | 4 | 0 | 0 |
| 16 Oct | 49 | 35 | 24 | 11 | 1 | 0 |
| 17 Oct | 37 | 27 | 18 | 8 | 0 | 0 |
| 18 Oct | 14 | 11 | 7 | 4 | 0 | 0 |
| 19 Oct | 38 | 25 | 11 | 8 | 0 | 0 |
| 20 Oct, through 7:57 AM UTC | 6 | 3 | 3 | 1 | 1 | 0 |

Daily rows count a person once per day, while the headline totals count a person once across the entire window. Consequently, daily rows should not be summed to reproduce the whole-window unique-person total.

### Reliable conversion ratios

- Onboarding completion: **108 / 149 = 72.5%**.
- Paywall reach from onboarding start: **67 / 149 = 45.0%**.
- Paywall reach from onboarding completion: **67 / 108 = 62.0%**.
- Purchase start from paywall view: **35 / 67 = 52.2%**.
- Recorded purchase success from purchase start: **0 / 35 = 0%**.

The largest reliable loss is between onboarding completion and reaching the paywall: 41 of 108 onboarding completers did not record a paywall view in the window. The commercial failure is after purchase intent: 35 people started a purchase, two recorded a generic purchase failure, but none recorded success. Because cancellations were not separately instrumented during this period, the remaining attempts cannot be classified as cancellation, stalled StoreKit sheet or another untracked outcome.

### Activity during each creative window

These are unique people active during each exact Meta delivery window. They are not creative-attributed conversions. Creative 01 and 02 overlap, and organic users are included.

| Window | Onboarding started | Completed | Paywall viewed | Purchase started | Purchase failed | Purchase succeeded |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Creative 01 live | 78 | 61 | 40 | 19 | 1 | 0 |
| Creative 02 live | 92 | 69 | 48 | 22 | 1 | 0 |
| Creative 03 live | 22 | 17 | 10 | 7 | 0 | 0 |
| Creative 04 live | 16 | 12 | 6 | 4 | 0 | 0 |
| Creative 01 extra run | 20 | 10 | 5 | 2 | 1 | 0 |

## Cross-platform reconciliation

The platforms answer different questions and are used in this order:

- **App Store Connect:** authoritative count of app units/downloads, including organic and other sources.
- **RevenueCat:** validation of newly activated app users, daily country mix and transaction truth.
- **Meta:** ad delivery, click efficiency and attributed-install comparison—not total downloads.
- PostHog reports tracked in-app behavior from people who generated analytics events.

The strongest common conclusion is not the exact download count but the absence of monetisation: Meta reported no trials or subscriptions, RevenueCat reported no live transactions, and PostHog recorded zero purchase successes.

The download source-of-truth statement is therefore: **107 App Store units occurred on the complete clean dates 16–19 October, while RevenueCat saw 121 new users on 16–20 October, including four on the partial final day.** The exact English-campaign-attributable download count is smaller than or equal to the Apple total and cannot be isolated without campaign-level attribution. RevenueCat's 78 customers in the five target markets are a useful directional subset, not a replacement download count.

The launch-day boundary remains especially problematic: 15 October includes 385 App Store units, 305 RevenueCat new customers and very large pre-edit Meta delivery. Counting the whole day would falsely attribute worldwide and possibly organic traffic to the English-market test.

## Decision and recommended next actions

1. **Do not scale any creative on purchase performance.** There were no verified trials, subscriptions or purchase successes.
2. **Do not treat Creative 01 as a proven winner.** Its original clean result justified the rerun, but the rerun CTR, CPC and attributed CPI deteriorated sharply. Test a genuinely new iteration only after the purchase path and instrumentation are fixed, using a fresh ad identity so reporting cannot inherit earlier worldwide data.
3. **Reject Creative 02 in its current form.** Its post-launch CTR and cost per install were materially worse than Creative 01.
4. **Do not promote Creative 03 or 04 as winners.** Their CTRs were middling and neither produced an attributed install after exceeding the exposure threshold.
5. **Fix post-click conversion before spending more.** Add explicit purchase-cancelled instrumentation, retain safe StoreKit error categories, and verify a real production purchase appears in PostHog and RevenueCat end to end.
6. **Run future creative tests one at a time.** Aim for roughly 2,000–3,000 impressions per creative, never judge below 1,000, and stop near the planned ceiling. The observed exposures—especially Creative 01's 10,827-impression rerun and the 7,520 and 6,917-impression batches—were substantially above the intended low-budget test batch.
7. **Keep winners separate from testing.** If Creative 01 later proves it can generate trials or purchases, move it to a scaling campaign and raise budget gradually by about 15–20% at a time.

## Source record

- Meta Ads Manager: exported ad-level and day-level CSV data through 20 October, plus each ad's activity history.
- App Store Connect Sales and Trends: Units, daily range through 20 October UTC and Last 24 Hours hourly view for 19–20 October.
- RevenueCat: New Customers chart segmented by country and production overview, refreshed 20 October.
- PostHog project 297541: exact-timestamp unique-person trends through the Creative 01 rerun, with test accounts excluded.

All analysis is read-only. No campaign, budget, targeting, analytics configuration or app code was changed.
