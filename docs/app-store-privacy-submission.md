# Nima App Store Privacy Submission

Last updated: June 21, 2026

Use this file as the source of truth for App Store Connect privacy answers and App Review notes. The public privacy policy must be live at `https://nima.so/privacy-policy` before submission.

## Privacy Policy URL

- URL: `https://nima.so/privacy-policy`
- Privacy contact: `help@nima.so`
- Disclosure posture: conservative
- Tracking answer: No

## App Store Connect Data Types

Mark the following data types as collected. Mark them as linked to the user when tied to an account, session, Supabase user ID, RevenueCat user ID, VPN client mapping, or traffic dashboard identity.

| Data type | Linked to user | Purposes |
| --- | --- | --- |
| Contact Info - Email Address | Yes | App Functionality, Account Management |
| Identifiers - User ID | Yes | App Functionality, Account Management, Analytics, Diagnostics |
| Purchases - Purchase History | Yes | App Functionality, Account Management |
| Browsing History | Yes | App Functionality, Analytics, Diagnostics |
| Usage Data - Product Interaction | Yes | App Functionality, Analytics |
| Usage Data - Other Usage Data | Yes | App Functionality, Analytics, Diagnostics |
| Diagnostics - Performance Data | Yes | App Functionality, Diagnostics |
| Diagnostics - Other Diagnostic Data | Yes | App Functionality, Diagnostics |
| User Content - Customer Support | Yes | Customer Support, App Functionality |
| Other Data | Yes | App Functionality, Analytics, Diagnostics |

Use `Other Data` only for data App Store Connect cannot cleanly represent elsewhere, including VPN client IP, URL metadata, block policy decisions, generated insights, and cancellation reasons.

Do not declare location, contacts, camera, microphone, photos, health, IDFA, advertising data, or payment-card financial data unless new code adds those features.

## Third-Party Processing

- Supabase: authentication, sessions, database storage, waitlist, account deletion, traffic events/summaries, cancellation feedback, generated insights.
- RevenueCat: purchase history, subscription status, entitlements, offerings, purchases, restores.
- Google Sign-In: authentication data, user identifier, and IP address as described by Google.
- Apple: Sign in with Apple and App Store purchase processing.
- OpenAI: hostname classification and aggregated usage insight generation.
- Hosting and infrastructure providers: web app, database, server, and VPN/filtering operations.

## App Review Notes

Nima uses a Network Extension VPN to classify and block distracting traffic for apps such as Instagram and TikTok. The VPN/filtering system may process and log traffic metadata such as hostnames, SNI/domain names, ports, URL paths where server proxy logging is enabled, request method, status code, content type, byte counts, duration, block/allow decision, block reason, app category, VPN client IP, and user ID.

Nima uses this data to operate blocking, show traffic dashboards, produce insights, debug reliability, and support account deletion. Nima does not sell personal data, does not use personal data for third-party advertising, and does not track users across apps or websites owned by other companies.

Nima uses OpenAI only as a service provider to classify hostnames and generate aggregate usage insights. Nima does not intend to send full URL paths to OpenAI insight prompts.

## Verification Checklist

- Public policy opens without authentication at `https://nima.so/privacy-policy`.
- iOS Settings privacy link opens the same URL.
- App Store Connect privacy labels match the table above.
- `PrivacyInfo.xcprivacy` is present in the app target.
- Xcode archive/privacy report has no missing privacy manifest warnings.
- Account deletion removes linked backend rows and local app-group data.
- OpenAI routes send hostnames or aggregated stats only, not full URL paths.
- No ATT prompt is required because no cross-app tracking, IDFA, ad SDK, or third-party advertising use is present.
