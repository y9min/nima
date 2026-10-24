# Nima App Store Privacy Submission

Last updated: October 23, 2026

Use this file as the source of truth for App Store Connect privacy answers and App Review notes. The public privacy policy must be live at `https://nima.so/privacy-policy` before submission.

## Privacy Policy URL

- URL: `https://nima.so/privacy-policy`
- Privacy contact: `help@nima.so`
- Disclosure posture: conservative
- Tracking answer for the upcoming Meta-enabled build: Yes. Do not apply these answers to build 23 as if it already includes Meta.

## App Store Connect Data Types

Mark the following data types as collected when they are transmitted for the listed service purpose. Local-only filtering signals and local diagnostic files are not App Store "collected" data unless the user chooses to share them with support.

| Data type | Linked to user | Purposes |
| --- | --- | --- |
| Identifiers - User ID | Yes | App Functionality, Analytics, Developer’s Advertising or Marketing, Third-Party Advertising (consented Meta subscription matching) |
| Identifiers - Device ID | Yes | Analytics, Developer’s Advertising or Marketing, Third-Party Advertising (ATT authorised only) |
| Usage Data - Product Interaction | Yes | Analytics, Developer’s Advertising or Marketing, Third-Party Advertising (consented activation events) |
| Usage Data - Other Usage Data | Yes | Analytics (PostHog only, no tracking) |
| Purchases - Purchase History | Yes | App Functionality, Analytics, Developer’s Advertising or Marketing, Third-Party Advertising (ATT authorised only) |
| Diagnostics - Performance Data | Yes | App Functionality, Diagnostics, when shared for support |
| Diagnostics - Other Diagnostic Data | Yes | App Functionality, Diagnostics, when shared for support |
| User Content - Customer Support | Yes | Customer Support, App Functionality |
| Other Data | Yes | App Functionality |

Do not declare Email Address or Other Data for the iOS app: sign-in and in-app cancellation feedback have been removed. Do not declare Browsing History, location, contacts, camera, microphone, photos, health or payment-card financial data unless new code transmits those data types. Declare Product Interaction and Other Usage Data for analytics because the app sends limited onboarding, paywall, purchase, and restore events to PostHog. User ID refers to pseudonymous RevenueCat, analytics, and advertising identifiers rather than a Supabase login.

## Third-Party Processing

- Supabase: remote feature configuration and Android waitlist storage. Legacy iOS account records remain temporarily during retirement but are no longer used by the app.
- RevenueCat: purchase history, subscription status, entitlements, offerings, purchases, restores.
- Apple: App Store purchase processing.
- Meta: ATT-authorised app activation/device identifiers and RevenueCat subscription lifecycle events for ad measurement.
- PostHog: limited product analytics at the EU endpoint, without VPN data.
- Hosting and infrastructure providers: web app, database, and collection-free filtering operations.

## App Review Notes

Nima uses an iOS Network Extension to classify and block distracting traffic for apps such as Instagram and TikTok. Network signals such as domains, SNI, ports, connection metadata, and block decisions are processed inside the app's tunnel to enforce the user's blocking rules.

Traffic details may appear in local diagnostic files on the device. Nima does not transmit ordinary browsing metadata to Supabase or OpenAI, does not provide a web traffic dashboard, and does not generate AI traffic insights. A user may choose to share a diagnostic report with support.

Nima does not sell, use, or disclose data derived from VPN use to third parties for any purpose. With ATT authorisation, Meta receives app activation and identifiers, and RevenueCat sends subscription lifecycle events for Nima ad measurement. Email and phone matching are omitted. VPN-derived data is never used for advertising.

## Verification Checklist

- Public policy opens without authentication at `https://nima.so/privacy-policy`.
- iOS Settings privacy link opens the same URL.
- App Store Connect privacy labels match the table above.
- `PrivacyInfo.xcprivacy` is present in the app target.
- Xcode archive/privacy report has no missing privacy manifest warnings.
- Legacy account deletion requests are handled through `help@nima.so` until the old records are retired.
- Browsing History remains removed. Product Interaction, Other Usage Data, and User ID analytics labels match the pseudonymous PostHog, RevenueCat, and consented Meta identifiers.
- Ordinary VPN use produces no Supabase or OpenAI traffic-analytics requests.
- ATT appears at the subscription screen after earlier onboarding permission prompts. Refusal/restriction permits purchases and restores.
- Verify refusal and revocation on a physical device; RevenueCat must keep “Send events when ATT consent is not authorized” OFF.
- Inspect the combined archive privacy report, including Meta CoreKit/Basics/AEM manifests, before submitting.
- Publish the updated policy before enabling measurement.

Meta 18.1.1 declares crash data in its bundled manifest. Its InstrumentManager skips crash/error-report activation when automatic app-event logging is disabled, as it is in this integration and the production dataset. Do not infer active crash collection solely from that manifest declaration; confirm the final physical-device network behavior.

## Publication record

October 12, 2026: Published all ten data types in App Store Connect. User ID, Device ID, Product Interaction, and Purchase History declare analytics, developer advertising/marketing, third-party advertising, linked identity, and tracking. User ID and Purchase History retain App Functionality. Other Usage Data declares linked analytics without tracking. Existing functionality/support disclosures remain. The page confirms publication and no unfinished data-type warning remains. Apple’s preview also displays extra unlinked User ID/Purchases entries despite the individual disclosures showing linked identity; recorded as a preview inconsistency.

October 23, 2026: Removed iOS sign-in, account linking, and cancellation feedback. Before submitting this build, remove Email Address and Other Data from App Store Connect and confirm the remaining pseudonymous identifier disclosures against the archive privacy report.
