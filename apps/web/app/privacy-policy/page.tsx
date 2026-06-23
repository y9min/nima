import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy Policy | Nima",
  description: "How Nima collects, uses, shares, and protects data.",
};

const lastUpdated = "June 21, 2026";
const contactEmail = "help@nima.so";

const sections = [
  {
    title: "Who We Are",
    body: [
      "Nima helps people reduce distracting app use with account features, subscriptions, a VPN-based filtering app, a web dashboard, and related backend services.",
      "This policy covers the Nima iOS app, web dashboard, Android waitlist, VPN/filtering backend, account and subscription systems, and support flows.",
      `Questions or privacy requests can be sent to ${contactEmail}.`,
    ],
  },
  {
    title: "Data We Collect",
    body: [
      "Account data: email address, Supabase user ID, authentication/session data, Apple Sign In data, and Google Sign-In data.",
      "Purchase data: subscription status, purchase history, entitlement state, RevenueCat app user ID, purchase, restore, and offering information.",
      "VPN and filtering data: hostnames, SNI/domain names, ports, URL paths where server proxy logging is enabled, request method, status code, content type, bytes in/out, duration, block/allow decision, block reason, app category, VPN client IP, and user ID.",
      "Usage analytics: app/category request counts, blocked/allowed counts, top domains, bandwidth, methods, content types, dashboard summaries, and generated insights.",
      "Cancellation feedback: selected reason and optional free-text details.",
      "Android waitlist data: email address and signup timestamp.",
      "Diagnostics: app/tunnel logs, VPN lifecycle state, connection errors, performance counters, crash-like or stop diagnostics, local traffic dashboard files, and related troubleshooting data.",
      "Local-only app data: onboarding answers, age, phone-hours answer, selected habits/apps, display name, streaks, reminder settings, time windows, notification preferences, and CoreMotion data used for visual motion effects.",
    ],
  },
  {
    title: "How We Use Data",
    body: [
      "Provide account login, session management, subscriptions, restore purchases, and customer support.",
      "Operate the VPN and content blocking features, including detecting traffic categories and deciding whether a request should be allowed or blocked.",
      "Show the traffic dashboard, app usage summaries, blocking history, bandwidth information, and insight cards.",
      "Send Android waitlist updates and service communications.",
      "Handle cancellation feedback, account deletion, billing issues, abuse prevention, reliability debugging, and product improvement.",
    ],
  },
  {
    title: "Third-Party Processors",
    body: [
      "Supabase provides authentication, sessions, database storage, waitlist storage, account deletion support, traffic events/summaries, feedback storage, and generated insight storage.",
      "RevenueCat processes subscription status, purchase history, entitlements, offerings, purchases, and restores.",
      "Google Sign-In processes Google authentication data. Google states its iOS sign-in SDK may process identifiers and IP addresses for authentication, security, and fraud prevention.",
      "Apple processes Sign in with Apple and App Store purchase information.",
      "OpenAI is used to classify hostnames and generate aggregate usage insights.",
      "Hosting and infrastructure providers may process server, web app, database, and VPN/filtering traffic needed to operate Nima.",
    ],
  },
  {
    title: "AI Processing",
    body: [
      "Nima may send hostnames to OpenAI so they can be categorized into app or content categories.",
      "Nima may send aggregated request and block counts to OpenAI to generate short usage insights.",
      "Nima does not intend to send full URL paths to OpenAI insight prompts. If this changes, this policy will be updated before the change is used.",
      "OpenAI is used as a service provider for Nima functionality, not for advertising or cross-app tracking.",
    ],
  },
  {
    title: "Retention",
    body: [
      "Account and authentication data is kept while your account exists.",
      "Traffic events are kept by default for 30 days.",
      "Aggregated summaries and generated insights are kept by default for 12 months.",
      "Cancellation feedback is kept while your account exists or as needed for support, business records, or legal obligations.",
      "Android waitlist emails are kept until Android launch communications are complete or you ask us to remove your email.",
      "Local diagnostic files and logs are kept on your device until rotated, cleared, or removed during account deletion/local reset.",
      "Purchase records are kept as required by Apple, RevenueCat, tax, fraud prevention, and subscription operations.",
    ],
  },
  {
    title: "Sharing, Sale, and Tracking",
    body: [
      "Nima does not sell personal data.",
      "Nima does not use personal data for third-party advertising or cross-app tracking.",
      "Nima does not use the App Tracking Transparency prompt because Nima does not track users across apps or websites owned by other companies.",
      "Service providers process data only to provide Nima functionality, security, support, billing, analytics, AI features, or legal compliance.",
    ],
  },
  {
    title: "Children",
    body: [
      "Nima is not directed to children under 13.",
      "Users under 13 should not create an account or use the service.",
    ],
  },
  {
    title: "Your Rights and Choices",
    body: [
      `You can request access, correction, deletion, or Android waitlist removal by emailing ${contactEmail}.`,
      "Where available, you can delete your account in the app.",
      "Account deletion removes linked backend account data, traffic events, traffic summaries, generated insights, cancellation feedback, profile/blocker state, and local app-group data where available.",
      "You can also disable local notifications in iOS settings or in Nima settings where supported.",
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
        <strong>Plain English summary:</strong> Nima uses account, purchase,
        VPN traffic metadata, usage analytics, diagnostics, and support data to
        run the app. Nima does not sell personal data and does not use it for
        third-party advertising or cross-app tracking.
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
