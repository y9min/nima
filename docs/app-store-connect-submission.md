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
- Sign-in required: `Yes`
- Demo email: `review@nima.so`
- Demo password: `Not required`

### Review Notes

Nima is a content-blocking app that uses Apple's Network Extension framework and a local packet-tunnel provider. It is not a location-changing or remote-server VPN. The tunnel processes network signals on the device to identify and block selected short-form feed connections while leaving other app features, such as messaging, available.

Before requesting VPN permission, Nima displays a disclosure explaining that it processes domains, SNI, ports, connection metadata, byte counts, and block decisions to apply the user's rules. Nima does not sell, use, or disclose data derived from VPN use to third parties for any purpose. Ordinary browsing metadata is not sent to Supabase or OpenAI. Local diagnostics are shared only when the user explicitly chooses to send them to support.

To review the full app without purchasing:

1. Launch Nima and complete the onboarding questions using any sample answers.
2. On "Let Nima block the scroll," tap Continue, read the privacy disclosure, then continue to Apple's VPN configuration prompt.
3. Allow the VPN configuration. Notification permission may be allowed or declined.
4. On the account screen choose "Continue with email."
5. Enter `review@nima.so`. No password or email-link access is required for this review account.
6. The review account receives demo annual access and opens the main Nima experience.
7. From Home, enable a supported app/feed or create a time window. The system VPN indicator confirms that the local filter is active.

The app includes Restore Purchases on the RevenueCat-hosted paywall and Apple subscription management under Settings > Manage Subscription.

## App Privacy Answers

Use `docs/app-store-privacy-submission.md` as the source of truth.

- Tracking: `No`
- Data used for third-party advertising: `No`
- Data used to track users: `No`
- Email Address: linked, App Functionality / Account Management
- User ID: linked, App Functionality / Account Management
- Purchase History: linked, App Functionality / Account Management
- Performance Data: linked, App Functionality / Diagnostics when shared for support
- Other Diagnostic Data: linked, App Functionality / Diagnostics when shared for support
- Customer Support: linked, Customer Support / App Functionality
- Other Data: linked, App Functionality (cancellation reason and optional details)
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

Nima uses HTTPS and Apple platform cryptography for authentication and service communication. Its local packet tunnel does not add proprietary encryption or operate a remote encrypted VPN service.

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
- App ID `so.nima.app`: App Groups, Network Extensions, and Sign in with Apple enabled.
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
- Test purchase, restore, login, account deletion, VPN permission, and blocking on a physical iPhone/TestFlight build.
- Attach both subscriptions to version 1.0 before adding the version for review.
