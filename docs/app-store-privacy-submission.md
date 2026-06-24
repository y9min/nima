# Nima App Store Privacy Submission

Last updated: June 24, 2026

Use this file as the source of truth for App Store Connect privacy answers and App Review notes. The public privacy policy must be live at `https://nima.so/privacy-policy` before submission.

## Privacy Policy URL

- URL: `https://nima.so/privacy-policy`
- Privacy contact: `help@nima.so`
- Disclosure posture: conservative
- Tracking answer: No

## App Store Connect Data Types

Mark the following data types as collected when they are transmitted for the listed service purpose. Local-only filtering signals and local diagnostic files are not App Store "collected" data unless the user chooses to share them with support.

| Data type | Linked to user | Purposes |
| --- | --- | --- |
| Contact Info - Email Address | Yes | App Functionality, Account Management |
| Identifiers - User ID | Yes | App Functionality, Account Management |
| Purchases - Purchase History | Yes | App Functionality, Account Management |
| Diagnostics - Performance Data | Yes | App Functionality, Diagnostics, when shared for support |
| Diagnostics - Other Diagnostic Data | Yes | App Functionality, Diagnostics, when shared for support |
| User Content - Customer Support | Yes | Customer Support, App Functionality |
| Other Data | Yes | App Functionality |

Use `Other Data` for cancellation reasons and optional cancellation details that App Store Connect cannot cleanly represent elsewhere.

Do not declare Browsing History, Product Interaction analytics, Other Usage Data analytics, location, contacts, camera, microphone, photos, health, IDFA, advertising data, or payment-card financial data unless new code transmits those data types.

## Third-Party Processing

- Supabase: authentication, sessions, profile/blocker state, waitlist, account deletion, and cancellation feedback.
- RevenueCat: purchase history, subscription status, entitlements, offerings, purchases, restores.
- Google Sign-In: authentication data, user identifier, and IP address as described by Google.
- Apple: Sign in with Apple and App Store purchase processing.
- Hosting and infrastructure providers: web app, database, and collection-free filtering operations.

## App Review Notes

Nima uses an iOS Network Extension to classify and block distracting traffic for apps such as Instagram and TikTok. Network signals such as domains, SNI, ports, connection metadata, and block decisions are processed inside the app's tunnel to enforce the user's blocking rules.

Traffic details may appear in local diagnostic files on the device. Nima does not transmit ordinary browsing metadata to Supabase or OpenAI, does not provide a web traffic dashboard, and does not generate AI traffic insights. A user may choose to share a diagnostic report with support.

Nima does not sell, use, or disclose data derived from VPN use to third parties for any purpose. Nima does not use personal data for third-party advertising or track users across apps or websites owned by other companies.

## Verification Checklist

- Public policy opens without authentication at `https://nima.so/privacy-policy`.
- iOS Settings privacy link opens the same URL.
- App Store Connect privacy labels match the table above.
- `PrivacyInfo.xcprivacy` is present in the app target.
- Xcode archive/privacy report has no missing privacy manifest warnings.
- Account deletion removes linked backend rows and local app-group data.
- Browsing History and analytics-purpose labels are removed from App Store Connect.
- Ordinary VPN use produces no Supabase or OpenAI traffic-analytics requests.
- No ATT prompt is required because no cross-app tracking, IDFA, ad SDK, or third-party advertising use is present.
