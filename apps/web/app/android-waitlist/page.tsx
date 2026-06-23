import Script from "next/script";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";

export default function AndroidWaitlistPage() {
  const initScript = `
    (function setupAndroidWaitlist() {
      var status = document.querySelector("#android-waitlist-status");
      if (!${JSON.stringify(supabaseUrl)} || !${JSON.stringify(supabaseAnonKey)}) {
        if (status) {
          status.textContent = "Waitlist is not configured yet.";
          status.dataset.status = "error";
        }
        return;
      }
      if (!window.NimaAndroidWaitlist) {
        window.setTimeout(setupAndroidWaitlist, 25);
        return;
      }
      window.NimaAndroidWaitlist.init({
        form: "#android-waitlist-form",
        email: "#android-waitlist-email",
        status: "#android-waitlist-status",
        supabaseUrl: ${JSON.stringify(supabaseUrl)},
        supabaseAnonKey: ${JSON.stringify(supabaseAnonKey)}
      });
    })();
  `;

  return (
    <main className="waitlist-page">
      <section className="waitlist-panel" aria-labelledby="android-waitlist-title">
        <p className="waitlist-kicker">Nima for Android</p>
        <h1 id="android-waitlist-title">Join the Android waitlist</h1>
        <p className="waitlist-copy">
          Get an email when Android access opens. We only store this email address.
        </p>
        <form id="android-waitlist-form" className="waitlist-form" noValidate>
          <label htmlFor="android-waitlist-email">Email</label>
          <div className="waitlist-row">
            <input
              id="android-waitlist-email"
              name="email"
              type="email"
              inputMode="email"
              autoComplete="email"
              placeholder="you@example.com"
              required
            />
            <button type="submit">Join</button>
          </div>
          <p id="android-waitlist-status" className="waitlist-status" aria-live="polite" />
        </form>
      </section>

      <Script src="/android-waitlist.js" strategy="afterInteractive" />
      <Script id="android-waitlist-init" strategy="afterInteractive">
        {initScript}
      </Script>
      <style
        dangerouslySetInnerHTML={{
          __html: `
            .waitlist-page {
              min-height: 100vh;
              display: grid;
              place-items: center;
              padding: 24px;
              background: #f8fbff;
              color: #101828;
              font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }
            .waitlist-panel {
              width: min(100%, 460px);
              display: grid;
              gap: 18px;
            }
            .waitlist-kicker {
              color: #2f5fce;
              font-size: 13px;
              font-weight: 700;
              letter-spacing: 0.08em;
              text-transform: uppercase;
            }
            .waitlist-panel h1 {
              font-family: Coolvetica, Inter, ui-sans-serif, system-ui, sans-serif;
              font-size: clamp(42px, 8vw, 68px);
              font-weight: 400;
              line-height: 0.92;
              letter-spacing: 0;
            }
            .waitlist-copy {
              color: #475467;
              font-size: 17px;
              line-height: 1.5;
            }
            .waitlist-form {
              display: grid;
              gap: 10px;
              margin-top: 8px;
            }
            .waitlist-form label {
              color: #344054;
              font-size: 14px;
              font-weight: 650;
            }
            .waitlist-row {
              display: flex;
              gap: 10px;
            }
            .waitlist-row input {
              min-width: 0;
              flex: 1;
              height: 48px;
              border: 1px solid #d0d5dd;
              border-radius: 8px;
              padding: 0 14px;
              color: #101828;
              font: inherit;
              background: #ffffff;
            }
            .waitlist-row input:focus {
              border-color: #2f5fce;
              outline: 3px solid rgba(47, 95, 206, 0.16);
            }
            .waitlist-row button {
              height: 48px;
              border: 0;
              border-radius: 8px;
              padding: 0 20px;
              color: #ffffff;
              font: inherit;
              font-weight: 750;
              background: #101828;
              cursor: pointer;
            }
            .waitlist-row button:hover {
              background: #1d2939;
            }
            .waitlist-status {
              min-height: 20px;
              color: #475467;
              font-size: 14px;
            }
            .waitlist-status[data-status="success"] {
              color: #067647;
            }
            .waitlist-status[data-status="error"] {
              color: #b42318;
            }
            @media (max-width: 520px) {
              .waitlist-row {
                flex-direction: column;
              }
              .waitlist-row button {
                width: 100%;
              }
            }
          `,
        }}
      />
    </main>
  );
}
