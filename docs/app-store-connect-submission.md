# Nima App Store Connect Submission Copy

Prepared for the first iPhone release and checked against the live Apple Developer, App Store Connect, and RevenueCat setup on 14 July 2026. Fields marked **ACTION REQUIRED** are not yet complete.

## Product Page

- App name: `Nima: Block Reels & FYP` (the name already reserved in App Store Connect)
- Subtitle: `Block scrolling, keep social`
- Promotional text: `Stop distracting feeds without deleting social apps. Block Reels and For You feeds, schedule focus windows, and build healthier habits.`
- Primary category: `Productivity`
- Secondary category: `Health & Fitness`
- Privacy policy URL: `https://nima.so/privacy-policy`
- Support URL: `https://nima.so/help`
- Marketing URL: `https://nima.so/`
- Copyright: `2026 9INE LTD`

### Keywords

`focus,screen time,doomscroll,reels,tiktok,instagram,habits,productivity,digital wellbeing,blocker`

### Description

Nima helps you spend less time scrolling while keeping the useful parts of social apps.

BLOCK DISTRACTING FEEDS

- Block short-form feeds such as Instagram Reels and TikTok's For You feed.
- Keep messaging and other useful social features available.
- Choose which supported apps and feeds to block.

BUILD BETTER ROUTINES

- Schedule time windows for focused mornings, work sessions, or bedtime.
- Pause and resume blocking from a simple dashboard.
- Build a daily streak and see your progress over time.

HOW IT WORKS

Nima uses an on-device local VPN configuration to identify and block selected distracting connections. It is a content-blocking tool, not a service for changing your location or routing traffic through a remote VPN server.

PRIVACY

Network signals used for blocking are processed on the device. Nima does not sell, use, or disclose data derived from VPN use to third parties for any purpose. Diagnostic information stays local unless you choose to share it with support.

Some features require an auto-renewing subscription. Available plans, prices, renewal periods, and trial eligibility are shown before purchase. Subscriptions can be managed or cancelled through your Apple account.

Privacy Policy: https://nima.so/privacy-policy

Terms & Conditions: https://nima.so/terms-and-conditions

## Screenshots

- Six iPhone screenshots are ready in `~/Downloads/app store screenshots`.
- Size: `1260 x 2736` portrait, PNG, sRGB.
- Upload them to the 6.9-inch iPhone screenshot slot in numerical order.
- No iPad screenshots are required because the release targets iPhone only.

## Version Information

- Version: `1.0`
- Build: `1` (increase before each replacement upload)
- What's New: `Welcome to Nima. Block distracting feeds, schedule focus windows, and build healthier scrolling habits.`

## App Review Contact And Access

- Contact name: **ACTION REQUIRED — enter the person Apple should contact during review**
- Phone: **ACTION REQUIRED — enter a monitored phone number**
- Email: `help@nima.so` or the monitored review-contact address
- Sign-in required: `No`
- Demo account: `Not applicable — Nima does not have customer accounts`

### Review Notes

Nima is a content-blocking app that uses Apple's Network Extension framework and a local packet-tunnel provider. It is not a location-changing or remote-server VPN. The tunnel processes network signals on the device to identify and block selected short-form feed connections while leaving other app features, such as messaging, available.

Before requesting VPN permission, Nima displays a disclosure explaining that it processes domains, SNI, ports, connection metadata, byte counts, and block decisions to apply the user's rules. Nima does not sell, use, or disclose data derived from VPN use to third parties for any purpose. Ordinary browsing metadata is not sent to Supabase or OpenAI. Local diagnostics are shared only when the user explicitly chooses to send them to support.

To review the app:

1. Launch Nima and complete the onboarding questions using any sample answers.
2. On "Let Nima block the scroll," tap Continue, read the privacy disclosure, then continue to Apple's VPN configuration prompt.
3. Allow the VPN configuration. Notification permission may be allowed or declined.
4. Complete the guided setup. Nima then shows its subscription paywall; no sign-in or account linking is required.
5. Use Apple's review purchase environment to start a subscription, or use Restore Purchases for an Apple ID that already owns one.
6. From Home, enable a supported app/feed or create a time window. The system VPN indicator confirms that the local filter is active.

The app includes Restore Purchases on the RevenueCat-hosted paywall and Apple subscription management under Settings > Manage Subscription.

## App Privacy Answers

Use `docs/app-store-privacy-submission.md` as the source of truth.

- Tracking: `No`
- Data used for third-party advertising: `No`
- Data used to track users: `No`
- User ID: linked pseudonymous RevenueCat/analytics/advertising identifiers, App Functionality / Analytics / advertising purposes as detailed in `docs/app-store-privacy-submission.md`
- Purchase History: linked, App Functionality and the analytics/advertising purposes detailed in `docs/app-store-privacy-submission.md`
- Performance Data: linked, App Functionality / Diagnostics when shared for support
- Other Diagnostic Data: linked, App Functionality / Diagnostics when shared for support
- Customer Support: linked, Customer Support / App Functionality
- Do not declare Email Address or Other Data for this iOS build; customer sign-in and cancellation feedback have been removed.
- Do not declare Browsing History for local-only filtering signals.

## Age Rating Questionnaire Draft

Answer based on the shipped app rather than selecting a rating manually:

- Parental controls: No
- Age assurance: No
- Unrestricted web access: No
- User-generated content displayed inside Nima: No
- Messaging or chat inside Nima: No
- Advertising: No
- Gambling, contests, loot boxes, alcohol, tobacco, drugs, violence, horror, sexual content, profanity, medical content: None

**ACTION REQUIRED:** App Store Connect currently shows `Set Up Age Ratings`. Complete the current questionnaire and check the rating it generates.

## Export Compliance Draft

Nima uses HTTPS and Apple platform cryptography for service communication. Its local packet tunnel does not add proprietary encryption or operate a remote encrypted VPN service.

- Complete Apple's export-compliance questionnaire for the first uploaded build.
- Expected result: exempt/no documentation required, subject to Apple's questionnaire and the exact linked SDK behavior.
- Add `ITSAppUsesNonExemptEncryption = NO` only after App Store Connect confirms the exempt result.

## Subscription

- RevenueCat entitlement: `nima Pro`
- RevenueCat current offering: `default` (published)
- App Store Connect monthly product ID: `so.nima.app.pro.monthly`
- App Store Connect annual product ID: `so.nima.app.pro.yearly`
- **ACTION REQUIRED:** RevenueCat currently returns store product identifiers `monthly` and `yearly`, which do not match the App Store Connect identifiers above. Map the offering packages to the two `so.nima.app.pro.*` products before purchase testing.
- Products must be in the same subscription group.
- Both products are in the `Nima Pro` subscription group and have English (U.S.) display names/descriptions.
- **ACTION REQUIRED:** Both products currently show `Missing Metadata`. Add subscription pricing and an App Review screenshot for each product. The monthly product is available in 174 of 175 regions; review the excluded region intentionally.
- The published paywall must visibly show product price, renewal period, auto-renewal wording, Restore Purchases, Privacy Policy, and Terms.
- Submit the subscriptions with the first app version.

## Agreements And Availability

- Free Apps Agreement: active through 25 April 2027.
- Paid Apps Agreement: active through 25 April 2027.
- Banking: active.
- U.S. tax forms: active.
- Digital Services Act trader status: active.
- Select only territories where Nima's Network Extension/content-blocking use is lawful and no VPN licence is required, or provide licence details in Review Notes where required.

## Verified Live Setup

- Apple Developer organization: `9INE LTD` (`SSTZYP6ZWB`).
- App ID `so.nima.app`: App Groups and Network Extensions enabled. The build no longer requests the Sign in with Apple entitlement; disable the unused capability in the Apple Developer portal when provisioning allows.
- Extension ID `so.nima.app.NimaTunnel`: App Groups and Network Extensions enabled.
- App Group `group.so.nima.app`: present in the signed entitlements for both targets.
- App Store Connect record uses `so.nima.app`, version `1.0`, Apple ID `6790122342`.
- App Store distribution archive and IPA export succeed for both targets using Apple Distribution profiles valid through 14 July 2027.
- The exported app contains the expected privacy manifests and release entitlements.
- RevenueCat's published paywall includes price/period variables, auto-renewal wording, Restore Purchases, Privacy Policy, and Terms links.
- The iPhone 17 simulator test run passes all 290 tests.

## Remaining Live Actions

- Fill the blank App Store version metadata, upload the six screenshots, and select a build.
- Set Content Rights, primary/secondary categories, age rating, App Privacy answers, review contact details, and review notes.
- Finish the two subscription records and correct their RevenueCat product mappings.
- Upload the signed build and answer its export-compliance questions. Server-side App Store validation happens after upload.
- Test anonymous purchase, restore after reinstall/on another device with the same Apple ID, VPN permission, and blocking on a physical iPhone/TestFlight build.
- Attach both subscriptions to version 1.0 before adding the version for review.

## App Store Connect API Automation

The repository includes `apps/ios/scripts/app_store_connect.py` for credential checks,
IPA uploads, and guarded subscription-price changes. Real credentials must stay local.

1. Create a Team Key in App Store Connect under Users and Access > Integrations.
   Use Admin or App Manager access and download its `.p8` file once.
2. Store the key outside the repository, or under the ignored
   `.secrets/app-store-connect/` directory, and restrict it with `chmod 600`.
3. Export these variables in your terminal (or load them from an ignored `.env` file):

   ```sh
   export APP_STORE_CONNECT_KEY_ID="YOUR_KEY_ID"
   export APP_STORE_CONNECT_ISSUER_ID="YOUR_ISSUER_UUID"
   export APP_STORE_CONNECT_PRIVATE_KEY_PATH="/absolute/path/AuthKey_YOUR_KEY_ID.p8"
   ```

4. Verify access:

   ```sh
   pnpm --filter @nima/ios asc doctor
   ```

5. Validate an exported build, then upload it:

   ```sh
   pnpm --filter @nima/ios asc upload-build --ipa /absolute/path/Nima.ipa --validate-only
   pnpm --filter @nima/ios asc upload-build --ipa /absolute/path/Nima.ipa --wait
   ```

6. Inspect and preview subscription pricing. `GBR` is the default base territory;
   use another three-letter App Store territory code if needed.

   ```sh
   pnpm --filter @nima/ios asc list-prices \
     --product-id so.nima.app.pro.monthly --territory GBR

   pnpm --filter @nima/ios asc set-price \
     --product-id so.nima.app.pro.monthly \
     --territory GBR --customer-price 4.99 --start-date 2026-09-07 \
     --equalize-all
   ```

   The last command is a read-only preview. Add `--confirm SET_PRICE` only after
   checking the product, price, start date, territory count, and whether existing
   subscribers should keep their current price (`--preserve-current-price`). Apple
   warns that an effective price change cannot simply be reverted.

Build upload places the binary in App Store Connect for processing. Selecting the
processed build on a version and submitting that version for App Review remain
separate release steps.
