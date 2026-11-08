import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy Policy | Nima",
  description: "How Nima collects, uses, shares, and protects data.",
};

const lastUpdated = "November 8, 2026";
const contactEmail = "help@nima.so";

const sections = [
  {
    title: "Who We Are",
    body: [
      "Nima is operated by 9INE LTD (company number 17294957), registered at 71-75 Shelton Street, Covent Garden, London, United Kingdom, WC2H 9JQ. Nima helps people reduce distracting app use with subscriptions, device-based filtering, and related support services.",
      "This policy covers the Nima iOS app, Android waitlist, filtering systems, subscription systems, and support flows.",
      `Questions or privacy requests can be sent to ${contactEmail}.`,
    ],
  },
  {
    title: "Data We Collect",
    body: [
      "Account data from earlier iOS versions: optional account linking could collect an email address, Supabase user ID, authentication and session data, and Apple or Google sign-in identifiers. Version 1.4 does not offer account creation or linking; existing records are retained temporarily for support, security, deletion requests, or legal obligations.",
      "Purchase data: subscription status, purchase history, entitlement state, RevenueCat app user ID, purchase, restore, and offering information.",
      "Product analytics: randomly generated device/user identifier, onboarding screen reached, paywall, purchase, and restore outcomes, foreground sessions, retention, practice completion, app version, device type, operating-system version, and event timestamps. Nima does not send your onboarding answers, display name, email address, or VPN/network activity to PostHog.",
      "Android waitlist data: email address and signup timestamp.",
      "Support and diagnostics you choose to share: app/tunnel logs, VPN lifecycle state, connection errors, performance counters, crash-like or stop diagnostics, local traffic diagnostic files, and related troubleshooting details.",
      "Local-only app data: onboarding answers, age, phone-hours answer, selected habits/apps, display name, streaks, reminder settings, time windows, notification preferences, and CoreMotion data used for visual motion effects.",
      "Local filtering signals: the Network Extension processes signals such as domains, SNI, ports, connection metadata, and block decisions to apply blocking rules. These signals are not retained for server analytics or sent to OpenAI.",
    ],
  },
  {
    title: "How We Use Data",
    body: [
      "Provide subscriptions, restore purchases, and customer support without requiring an iOS account in version 1.4; maintain and delete account records created by earlier versions where needed.",
      "Operate the VPN and content blocking features, including processing network signals to decide whether a connection should be allowed or blocked.",
      "Show local blocking status and local diagnostics on your device.",
      "Send Android waitlist updates and service communications.",
      "Handle billing issues, privacy requests, abuse prevention, and reliability troubleshooting.",
      "Measure where people leave onboarding, whether they reach the paywall, and whether purchase and restore flows work, so Nima can improve those flows.",
    ],
  },
  {
    title: "Third-Party Processors",
    body: [
      "Supabase provides remote feature configuration and Android waitlist storage. Existing legacy account records may be retained while Nima completes the account-system retirement described below.",
      "RevenueCat processes subscription status, purchase history, entitlements, offerings, purchases, and restores.",
      "PostHog provides product analytics for the limited app events described above. Nima uses PostHog's EU service endpoint, disables session replay and automatic screen/tap capture, and disables IP-based location enrichment.",
      "Tenjin measures advertising attribution when you allow tracking, using device identifiers, installation and session signals, selected onboarding and checkout milestones, and subscription data from RevenueCat. When available and permitted by the ad network, campaign and creative information is linked to product analytics and subscription records. Tenjin does not receive VPN traffic, browsing content, blocking rules, or onboarding answers.",
      "Apple processes App Store purchase information. Apple’s SKAdNetwork provides aggregate advertising measurement independently of tracking permission. Nima updates coarse and fine conversion values for installation, onboarding, paywall, checkout, trial, and paid subscription milestones; Apple can send privacy-preserving attribution postbacks to the ad network and a copy to Tenjin.",
      "Meta receives consented app activation, device identifiers, selected onboarding/paywall/checkout milestones through Tenjin, and RevenueCat subscription events for advertising measurement. No VPN traffic, blocking rules, onboarding answers, or diagnostic reports are sent to Meta for advertising. The SDK also declares crash data for app functionality and other data for analytics.",
      "Hosting and infrastructure providers process the limited server, web app, database, and filtering traffic needed to operate Nima. Nima does not use those providers to retain ordinary browsing metadata for analytics.",
    ],
  },
  {
    title: "Retention",
    body: [
      "Legacy account and authentication data is retained temporarily while Nima safely retires the former account system, or longer where required for security, support, business records, or legal obligations. You can request deletion now by contacting us.",
      "Android waitlist emails are kept until Android launch communications are complete or you ask us to remove your email.",
      "Local diagnostic files and logs are kept on your device until rotated, cleared, or the app is removed.",
      "Diagnostics you choose to share with support are kept only as long as needed to resolve the request or meet legal obligations.",
      "Purchase records are kept as required by Apple, RevenueCat, tax, fraud prevention, and subscription operations.",
      "Product analytics is kept only as long as reasonably needed to understand onboarding and purchase performance, operate the service, and investigate reliability issues, then deleted or aggregated.",
    ],
  },
  {
    title: "Sharing, Sale, and Tracking",
    body: [
      "Nima does not sell personal data.",
      "When ad measurement is enabled and you allow Apple’s App Tracking Transparency request, Nima shares advertising and device identifiers, Meta’s app identifier for your device, app activation signals, and subscription events (including trial starts, payments, renewals, revenue, and currency) with Meta and Tenjin to measure Nima ads and improve their delivery. Selected onboarding, paywall, and checkout milestones are also shared after tracking permission. RevenueCat supplies subscription events. We do not provide optional email or phone matching for advertising.",
      "Nima does not sell, use, or disclose data derived from VPN use to third parties for any purpose.",
      "Network signals processed to provide blocking are not retained for server analytics, advertising, profiling, or AI processing.",
      "You can refuse tracking and still use Nima, subscribe, and restore purchases. You can change permission in iOS Settings > Privacy & Security > Tracking. Nima checks permission when it becomes active and stops new matching-based event collection on refusal or revocation. Data already delivered cannot be recalled; RevenueCat learns permission changes when the app next connects, so server-side events already sent or queued may not be recalled immediately.",
      "Meta processes consented advertising measurement data under its own privacy policy. Other service providers process data to provide Nima functionality, security, support, billing, or legal compliance.",
    ],
  },
  {
    title: "Children",
    body: [
      "Nima is not directed to children under 13.",
      "Users under 13 should not use the service.",
    ],
  },
  {
    title: "Your Rights and Choices",
    body: [
      `You can request access, correction, deletion, or Android waitlist removal by emailing ${contactEmail}.`,
      "Version 1.4 no longer requires or offers customer accounts. If you created one in an earlier version, email us to request deletion of the account and linked backend data.",
      "You can also disable local notifications in iOS settings or in Nima settings where supported.",
      `You can ask us to delete analytics associated with your device identifier by emailing ${contactEmail}.`,
    ],
  },
  {
    title: "Changes",
    body: [
      "We may update this policy when Nima changes or when legal, security, or operational requirements change.",
      "The latest policy will be posted on this page with an updated date.",
    ],
  },
];

export default function PrivacyPolicyPage() {
  return (
    <main className="privacy-page">
      <section className="privacy-hero">
        <p className="eyebrow">Nima privacy</p>
        <h1>Privacy Policy</h1>
        <p className="intro">
          This policy explains what Nima collects, why it is used, who processes
          it, how long it is kept, and how to request deletion.
        </p>
        <p className="updated">Last updated: {lastUpdated}</p>
      </section>

      <section className="notice">
        <strong>Plain English summary:</strong> Nima uses purchase, waitlist,
        and support data to run the
        service. Nima uses limited PostHog events to see where onboarding,
        purchase, and restore flows succeed or fail. It does not send
        onboarding answers, email, or VPN/network activity to PostHog. Network
        signals are processed for blocking and local diagnostics; ordinary
        browsing metadata is not stored for server analytics or sent to OpenAI.
        Nima does not sell personal data. If ad measurement is enabled, Apple asks
        your permission before sharing app and subscription activity with Meta and Tenjin
        to measure Nima ads. Refusing does not prevent subscribing or using Nima.
      </section>

      <section className="content" aria-label="Privacy policy sections">
        {sections.map((section) => (
          <article key={section.title} className="policy-section">
            <h2>{section.title}</h2>
            <ul>
              {section.body.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </article>
        ))}
      </section>

      <section className="contact">
        <h2>Contact</h2>
        <p>
          Privacy requests and questions:{" "}
          <a href={`mailto:${contactEmail}`}>{contactEmail}</a>
        </p>
      </section>

      <style
        dangerouslySetInnerHTML={{
          __html: `
            .privacy-page {
              min-height: 100vh;
              background: #f7fbff;
              color: #132033;
              font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              padding: 48px 22px 72px;
            }
            .privacy-hero,
            .notice,
            .content,
            .contact {
              width: min(100%, 860px);
              margin: 0 auto;
            }
            .privacy-hero {
              padding: 24px 0 22px;
            }
            .eyebrow {
              color: #2f5fce;
              font-size: 13px;
              font-weight: 800;
              letter-spacing: 0.08em;
              text-transform: uppercase;
              margin-bottom: 12px;
            }
            h1 {
              color: #101828;
              font-family: Coolvetica, Inter, ui-sans-serif, system-ui, sans-serif;
              font-size: clamp(48px, 8vw, 76px);
              font-weight: 400;
              line-height: 0.92;
              letter-spacing: 0;
              margin-bottom: 18px;
            }
            .intro {
              max-width: 700px;
              color: #344054;
              font-size: 19px;
              line-height: 1.55;
            }
            .updated {
              margin-top: 16px;
              color: #667085;
              font-size: 14px;
            }
            .notice {
              margin-top: 12px;
              border: 1px solid #b9cdfb;
              background: #edf4ff;
              border-radius: 8px;
              padding: 16px 18px;
              color: #1d2939;
              font-size: 15px;
              line-height: 1.55;
            }
            .content {
              display: grid;
              gap: 28px;
              margin-top: 34px;
            }
            .policy-section,
            .contact {
              border-top: 1px solid #d9e2f1;
              padding-top: 24px;
            }
            h2 {
              color: #101828;
              font-size: 24px;
              line-height: 1.2;
              margin-bottom: 12px;
            }
            ul {
              display: grid;
              gap: 10px;
              padding-left: 20px;
            }
            li,
            .contact p {
              color: #344054;
              font-size: 16px;
              line-height: 1.58;
            }
            a {
              color: #2f5fce;
              font-weight: 700;
            }
            .contact {
              margin-top: 34px;
            }
            @media (max-width: 620px) {
              .privacy-page {
                padding: 34px 18px 56px;
              }
              .intro {
                font-size: 17px;
              }
              h2 {
                font-size: 22px;
              }
            }
          `,
        }}
      />
    </main>
  );
}
