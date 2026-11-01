# Nima TestFlight physical-device test plan

Date prepared: 1 November 2026  
Target: Nima 1.4 (25) on Nima's physical iPhone, run through iPhone Mirroring  
Release gate: Meta tracking and paid acquisition stay off until this plan passes

This plan has two release stages:

1. **Build 25 baseline:** prove that the new, non-grandfathered customer journey works without requiring the VPN flow.
2. **Combined release build:** merge the live build-24 experience with build 25 and prove that existing paid customers remain on the old experience while new customers receive the pivot. The combined build is expected to be build 26.

Build 25 cannot be the final acquisition release by itself because it does not yet contain the grandfathering decision described in stage 2.

## Plain-English goal

The purpose is to prove four things on the actual phone:

1. A customer can buy, restore, renew, cancel and lose access to Nima Pro exactly as expected, and every transaction is recorded once in RevenueCat, PostHog and Meta.
2. The Instagram, TikTok and X experiences work from a clean install, including access to useful features and protection coming back after Pause Mode.
3. Hard Mode cannot be bypassed accidentally and remains usable with VoiceOver and Reduce Motion.
4. A fresh build-25 customer never hits the old VPN journey, and the later combined build routes grandfathered paid customers back to the old experience.

The tester will drive the phone from the Mac through iPhone Mirroring and collect evidence. The device owner should only need to act for secrets or confirmations that Apple or another provider requires, such as a social login, one-time code, CAPTCHA, passcode, Face ID, payment approval, or stopping auto-renewal.

## Do I need to plug in the phone?

No, not for Apple's iPhone Mirroring. The normal setup uses Wi-Fi and Bluetooth, with the Mac and iPhone signed into the same Apple Account and two-factor authentication enabled. Both devices must be nearby and the iPhone must have been unlocked at least once.

A cable is only a fallback if mirroring is unavailable or unstable. Pairing once with USB and then using it as a wireless device in Xcode is an alternative, but it is not required for the planned test.

## Scope and assumptions

- Use only disposable or carefully controlled test accounts and content.
- The app will be deleted and reinstalled from TestFlight to create a clean app state. The phone itself will not be erased.
- A TestFlight sandbox subscription purchase and its accelerated renewal/expiry cycle are allowed.
- One subscription cycle is enough to test purchase, restore, renewal, cancellation and expiry. The plan uses the monthly product, with no free trial, and the order will be purchase, restore after reinstall, renewal, cancellation, then expiry.
- Cross-device restore is optional. Same-device restore after uninstall/reinstall is the minimum.
- Build 25 is a pre-merge baseline for the new-customer experience. Grandfathered routing is not part of build 25 and must not be reported as passing until a combined build is installed and tested.
- Temporary test posts, stories, comments and direct messages may be created against disposable accounts and removed after capture.
- Reciprocal Instagram and TikTok DM recipients are available. There is currently no controlled X DM recipient, so X DM sending is excluded unless one is added; opening/reading and composer UI can still be checked.
- Personal details, passwords, one-time codes, payment details, private messages and full Apple receipt screens are excluded from evidence.

## Decisions to confirm before execution

| Item | Current assumption |
| --- | --- |
| Device | One physical iPhone 13 running current iOS; the exact iOS version will be recorded during preflight |
| Build | TestFlight currently offers 1.4 (25), uploaded 1 November 2026 and marked Ready to Submit. It is not the final combined build. |
| iPhone Mirroring | Mac and iPhone use the same Apple Account with two-factor authentication |
| Subscription | TestFlight/sandbox monthly plan with no free trial; expect a direct paid subscription rather than a trial-conversion flow |
| Test data | Disposable Instagram, TikTok and X accounts with 2FA access |
| Dashboards | RevenueCat, PostHog and Meta Events Manager are already available; the tester can use existing signed-in sessions |
| Clean install | Nima may be deleted and reinstalled; phone settings and other apps are preserved |
| Network | Stable Wi-Fi; cellular is available as a secondary check if needed |

## Required accounts and access

Have these ready before the screen-sharing session:

- The iPhone unlocked and TestFlight signed in.
- The Apple Account password/passcode and Face ID available for TestFlight/sandbox purchases and subscription management.
- Instagram, TikTok and X account handles, passwords and 2FA methods available.
- One disposable Instagram post or Reel, TikTok video and X post suitable for comments, replies and shared-link tests.
- Permission for one test DM to a controlled recipient on Instagram and TikTok.
- RevenueCat, PostHog and Meta Events Manager access.
- The RevenueCat project's app user ID, sandbox transaction details and Meta integration enabled.

Do not send passwords or one-time codes in chat. Enter them directly on the phone or in the secure mirrored prompt, then hand control back.

## Human-intervention points

The tester will pause only when one of these appears:

1. Apple Account, TestFlight, StoreKit or local-authentication prompt.
2. Subscription purchase confirmation.
3. Subscription management or auto-renewal confirmation.
4. Instagram, TikTok, X or Google sign-in, passkey, CAPTCHA or one-time code.
5. A provider requires credentials in a field that iPhone Mirroring blocks.

The tester will resume all ordinary navigation, permission taps, preferences, app relaunch, screenshots, logs and dashboard checks.

## Evidence and safety

Create this evidence folder after recording the actual build:

```text
docs/qa/test-runs/2026-11-01-nima-testflight-<version>-<build>/
  results.md
  screenshots/
  recordings/
  logs/
```

For every case record:

- Test ID, local time, account or anonymous subscriber ID where relevant.
- Device model, iOS version, Nima version and build.
- Network type and permission state.
- Action taken and expected result.
- Actual result, pass/fail and a screenshot or recording reference.
- PostHog `purchase_attempt_id`, RevenueCat transaction/customer record and Meta event timestamp where applicable.

Before starting, hide private notification previews, close unrelated apps, and ensure screen recordings stop before any credential, payment detail or personal message appears. Sanitise logs before moving them into the repository.

## Preflight

### P1. Pin the environment

1. Confirm iPhone Mirroring is connected without a cable.
2. In TestFlight, disable automatic updates and record the exact Nima version and build.
3. In Nima Settings, record the displayed version/build.
4. Record iPhone model, iOS version, locale, time zone and starting battery level.
5. Use a stable Wi-Fi connection and disable Low Power Mode.
6. Confirm ATT, Screen Time, notification and VPN permission states.
7. Confirm no important data depends on Nima's current local sessions.

Pass: the exact build can be identified, the phone is stable, and no ambiguous build or stale local state can invalidate the result.

### P2. Create a genuinely clean app install

1. Start a screen recording that contains no sensitive content.
2. Delete Nima from the iPhone.
3. Reinstall build 25 from TestFlight and confirm both TestFlight and Nima report 1.4 (25).
4. Launch it and confirm onboarding begins from a fresh state.
5. Confirm no cached subscription, social login, blockers, windows, Hard Mode setting or pause state survives.

Pass: a new anonymous RevenueCat/PostHog user is created and the app presents first-run onboarding.

If deleting Nima does not produce a clean state, stop and record the surviving app-group data as a failure before continuing.

### P3. Confirm the build-25 baseline boundary

Before buying anything, record:

1. Whether a VPN education screen appears anywhere in fresh onboarding.
2. Whether iOS shows a VPN configuration permission prompt.
3. Whether Nima creates a VPN profile when launched as a completely new user.
4. Whether VPN controls, tunnel status or VPN troubleshooting are exposed in the new-customer path.

Expected for build 25:

- Onboarding presents the Screen Time and controlled-client experience.
- No VPN permission prompt appears.
- No VPN profile is created merely by launching or completing onboarding.
- No VPN control is presented as required for the new-customer experience.

The VPN extension may still be present inside the binary. That is not itself a failure for build 25; exposing or activating it for a fresh user is.

## Part A. Subscription lifecycle and transaction parity

### A1. ATT and paywall preflight

1. Advance through onboarding to the paywall.
2. Accept ATT for the primary transaction test.
3. Confirm the native permission copy and status.
4. Confirm the paywall displays the offering, product, localized price, billing period, auto-renewal wording, Restore Purchases, Privacy Policy and Terms.
5. Record the RevenueCat offering ID, package ID and store product ID.

Expected in PostHog:

- One or more legitimate `paywall_screen_viewed` events depending on how many times the paywall is genuinely opened.
- One `paywall_load_started` for the initial network load.
- One `paywall_loaded` for that load.

Pass: ATT is recorded, the correct product loads, and no analytics event is duplicated by rerendering.

### A2. Cancel the purchase sheet before paying

1. Tap the purchase action.
2. When Apple's purchase sheet opens, cancel it.
3. Confirm the app does not unlock.

Expected:

- One `purchase_started`.
- One `purchase_cancelled` with the same `purchase_attempt_id`.
- No new RevenueCat transaction or entitlement.
- No Meta purchase event.

This verifies that abandoning checkout does not count as revenue.

### A3. Start the real sandbox subscription

1. Select the monthly product.
2. Record the displayed price, currency and period. There is no free trial in this test.
3. Ask the device owner to approve the purchase.
4. Immediately record the local time and let the app finish activating.
5. Locate the matching `purchase_started` event in PostHog and record its `purchase_attempt_id`.
6. Locate the matching customer and transaction in RevenueCat.
7. Locate the matching event in Meta Events Manager.

Expected app behaviour:

- Purchase succeeds once.
- The `nima Pro` entitlement becomes active.
- The app unlocks without requiring a restart.
- The same entitlement remains active after backgrounding and relaunching.

Expected PostHog sequence for the purchase attempt:

- One `purchase_started`.
- One `purchase_succeeded`.
- One `entitlement_activated`.
- One `app_unlocked`.
- All purchase events share the same `purchase_attempt_id`.
- `purchase_succeeded` and `entitlement_activated` are deliberate companion events, not duplicates of the same event.

Expected RevenueCat:

- One transaction for the successful purchase.
- Product ID matches the selected App Store Connect product.
- `nima Pro` is active.
- The anonymous app user ID is stable.
- With ATT allowed, RevenueCat attribution contains the expected IDFA/IDFA status, Facebook anonymous ID and consent fields.
- RevenueCat's Meta integration records the purchase or trial exactly once.

Expected Meta:

- One direct purchase/subscribe event for the paid subscription; no `StartTrial` or trial-conversion event.
- Product, price, currency, attribution and consent fields are correct.
- The event is not sent again merely because the app is relaunched.

Do not infer success from a green screen alone. The app, RevenueCat, PostHog and Meta must agree on product, time and subscriber identity.

### A4. Restore after clean reinstall

1. While the subscription is active, delete Nima again.
2. Reinstall from TestFlight.
3. Advance to the paywall and choose Restore Purchases.
4. Ask the device owner only if Apple requires authentication.

Expected:

- One `restore_started` and one `restore_succeeded` in PostHog.
- `nima Pro` is active and the app unlocks.
- RevenueCat shows a successful restore to the new anonymous app user.
- Meta does not create a second initial purchase or trial event, because restoring access is not a new transaction.
- A second foregrounding or restore does not silently duplicate the successful restore.

### A5. Sandbox renewal

1. Keep auto-renewal enabled.
2. Record the current RevenueCat entitlement expiry and Apple/TestFlight sandbox renewal schedule.
3. Leave the app and wait for one controlled sandbox renewal.
4. Reopen Nima and refresh RevenueCat.

Expected:

- One renewal transaction in RevenueCat, with the new period reflected once.
- One corresponding renewal event in Meta if the RevenueCat-to-Meta integration is configured for renewals.
- Entitlement remains active without a user action.
- No second initial purchase/start-trial event is created.

PostHog is a likely gap here: the current app-side analytics code explicitly emits purchase events from the interactive paywall, but no equivalent renewal, cancellation or expiry event was found. If the release condition requires every renewal to be visible in PostHog, this test should fail unless a RevenueCat-to-PostHog integration or another backend event supplies it.

### A6. Cancel auto-renewal

1. Open Settings > Manage Subscription in Nima.
2. Let Apple's subscription-management screen open.
3. Ask the device owner to turn off auto-renewal and confirm.
4. Return to Nima and relaunch it.

Expected:

- The subscription remains active until the paid period expires.
- RevenueCat records the cancellation/auto-renew status change.
- The app does not immediately revoke access.
- No duplicate entitlement or purchase event occurs.
- Meta does not count the cancellation as another purchase.

Record whether PostHog has any explicit cancellation event. The current app code has none, so the release gate should treat a required cancellation event as missing unless the dashboard supplies it from RevenueCat.

### A7. Entitlement expiry

1. Note the exact sandbox period expiry.
2. Do not change the device clock.
3. Wait for the period to expire and for Apple/RevenueCat to report it.
4. Relaunch or foreground Nima.
5. Attempt to open a premium-gated feature.

Expected:

- RevenueCat no longer reports an active `nima Pro` entitlement.
- The app returns to the subscription gate or blocks the premium action.
- No stale local premium access remains.
- No extra purchase, renewal or entitlement events appear.
- Record whether Meta sends an expiration/refund/cancellation event; it must not be confused with a purchase.

If the app still grants access, capture the elapsed offline time and current entitlement state. The code contains a 72-hour offline-access window, so distinguish intentional grace behaviour from a stale entitlement.

### A8. Transaction reconciliation table

Complete this table before assessing the subscription gate.

| Checkpoint | RevenueCat record | PostHog event/ID | Meta event/ID | Exactly once? |
| --- | --- | --- | --- | --- |
| Purchase sheet cancelled | No transaction | `purchase_cancelled` | None | Yes/No |
| Initial paid purchase | TBD | TBD | TBD | Yes/No |
| Restore | Restore, not new purchase | TBD | No duplicate purchase | Yes/No |
| Renewal | TBD | TBD | TBD | Yes/No |
| Cancellation | TBD | TBD or documented gap | Not a purchase | Yes/No |
| Expiry | Inactive entitlement | TBD or documented gap | Not a purchase | Yes/No |

The subscription gate fails if:

- A successful transaction is absent from any system that is required to receive it.
- A single transaction appears twice.
- The same transaction is counted as both a new purchase and a renewal.
- Product, price, currency, user identity or time disagree materially.
- App access disagrees with RevenueCat's entitlement.

## Part B. Clean-install core-function test

Run this while subscription access is active. Use only the disposable accounts and temporary content prepared in advance.

### B1. Permissions and setup

1. Complete onboarding using controlled test answers.
2. Test the Screen Time permission explanation and system prompt.
3. Confirm the build-25 new-customer path does not require VPN setup or approval. Record a failure if it appears.
4. Test notification permission.
5. Confirm the app returns to the correct screen after each prompt.
6. Select Instagram, TikTok and X as managed apps.

Pass: each required permission has a clear explanation, denial/cancellation does not crash the app, an allowed state enables the intended protection, and the fresh path never diverts into the legacy VPN journey.

### B2. Official-app shields and local filter

For each of Instagram, TikTok and X:

1. Enable its blocker or clean mode from Nima.
2. Confirm the Home state and protection indicator agree without requiring a VPN tunnel.
3. Open the official social app and verify the expected shield/restriction appears.
4. Exercise the allowed shield action and confirm it returns to a usable Nima flow or applies the chosen pause.
5. Disable the blocker through the normal non-Hard-Mode flow and confirm the official app becomes accessible.
6. Re-enable protection for the remaining tests.

Record that blocking is on-device and that no unrelated app or general web traffic is affected. Any VPN dependency in the build-25 new-customer path is a release failure.

### B3. Platform feature matrix

Use this matrix as the minimum on-device coverage.

| Area | Instagram | TikTok | X |
| --- | --- | --- | --- |
| Login-intro disclosure | Open and verify | Open and verify | Open and verify |
| Provider login | Owner signs in | Owner signs in | Owner signs in |
| Endless feed/Reels/For You restriction | Reels and endless feed removed | For You feed removed | Home/endless timeline restricted per current product design |
| Profile or individual post | Open a managed profile/post | Open a managed profile/post | Open a managed profile/post |
| DM/inbox | Send test DM to controlled recipient | Send test DM to controlled recipient | Open/read and verify composer; sending excluded without a controlled recipient |
| Comments/replies | Add a disposable comment | Add a disposable comment/reply if supported | Reply to a disposable post |
| Posting | Publish a temporary post through Pause Mode | Publish a temporary post through Pause Mode | Publish a temporary post through Pause Mode |
| Story | Publish a temporary story through Pause Mode | Test the available Story flow, or mark N/A if absent | N/A; X no longer has Stories |
| Shared link | Open a copied post/Reel link | Open a copied post/profile link | Open a copied post/profile link |
| Single-link containment | Confirm next-item/endless swiping is blocked | Confirm next-item/endless swiping is blocked | Confirm following another account cannot reopen the endless feed |
| Return from Pause Mode | Verify at expiry | Verify at expiry | Verify at expiry |

For every platform record:

- Whether login persists after backgrounding and force-quitting Nima.
- Which content is blocked and which actions are still possible.
- Whether media, comments, composing, sending and error states render correctly.
- Whether opening a single shared link remains contained rather than becoming an endless feed.
- Whether a provider change banner or degraded-mode warning is accurate when a feed is unavailable.
- The final Home state and protection-client state.

### B4. Content actions

Perform these only with test content:

1. Like or react without error.
2. On Instagram and TikTok, open a thread and send a test DM to the controlled recipient. On X, verify inbox, thread and composer access without sending to a real contact.
3. Create, submit and then delete a test comment or reply.
4. Use Pause Mode to compose and publish a test post.
5. Use Pause Mode to publish a test story where the platform supports it.
6. Delete the temporary post/story/comment/message after capture where possible.

Pass: normal actions work, sensitive credentials stay out of evidence, and the test cleanup leaves no public content or unread test message behind.

### B5. Pause Mode and automatic restoration

For each platform:

1. Confirm protection is currently active.
2. Start a 5-minute Pause Mode.
3. Verify the official app and Nima client become usable for the intended action.
4. Background Nima and use another app.
5. Reopen Nima and confirm the remaining pause state is accurate.
6. Leave Nima closed until expiry.
7. Confirm a notification appears if notifications are enabled.
8. Reopen Nima and the social app.

Pass: paused features work during the window and protection returns automatically at expiry without depending on the user opening Nima.

### B6. Relaunch and persistence

After completing each platform:

1. Background Nima, switch away, and return.
2. Force-quit and relaunch Nima.
3. Open each social client again.
4. Reopen the official app where a shield is enabled.

Pass:

- Provider logins persist.
- Chosen modes persist.
- Blockers and windows persist.
- Protection is active after relaunch.
- No stale pause remains after expiry.
- No duplicate subscription entitlement is created.

## Part C. Hard Mode independent validation

Hard Mode is a release gate on its own. If any protection bypass, lifecycle reset, timer, VoiceOver or Reduce Motion check fails, keep Hard Mode out of the acquisition release.

### C1. Baseline protection topology

Set up:

- One app blocked manually.
- One app scheduled by a future/current window.
- One app left unblocked.
- At least one active window that can be edited or ended.

Record the starting app states, window state, protection indicator and current pause values.

### C2. Activation warning and hold gesture

1. Press Hard Mode without completing the hold and verify it cancels.
2. Open the warning and choose Not yet.
3. Confirm Hard Mode stays off.
4. Hold until activation completes.
5. Force-quit and relaunch Nima.

Pass: accidental taps cancel, the warning is modal and understandable, activation persists after relaunch, and no blocker is changed by activation alone.

### C3. Challenge cancellation and lifecycle reset

Start an off attempt and cancel it at the trace stage. Then repeat and test each lifecycle exit:

1. Tap the close button.
2. Swipe/dismiss if a dismissal gesture is available.
3. Background Nima.
4. Force-quit and relaunch.
5. Navigate away if the overlay allows it.

Expected:

- The off action is not applied.
- Trace, sort, draw and timer progress are discarded.
- A new attempt starts at step 1.
- Hard Mode remains enabled.
- Existing blocking and windows remain unchanged.

### C4. Complete all four challenge stages

1. Trace all three phrases.
2. Confirm Reset clears the current trace.
3. Confirm a tiny scribble or empty canvas cannot pass.
4. Sort all 15 objects from smallest to largest.
5. Submit one deliberately incorrect order, verify useful feedback, then correct it.
6. Complete the drawing step and test Clear.
7. Confirm empty or irrelevant drawing cannot pass.
8. Enter the paint-drying timer.
9. Attempt Continue before 60 seconds and confirm it stays unavailable.
10. Keep Nima foregrounded and wait for the full timer.
11. Confirm exactly one set of final choices appears.

Record the random drawing target and capture each stage. Across repeated attempts, cover multiple drawing targets where practical; unit coverage remains responsible for every possible target.

### C5. Background during the final timer

1. Start the 60-second timer.
2. After 15-20 seconds, background Nima.
3. Return after at least 10 seconds.

Expected:

- The attempt is not completed from elapsed background time.
- The challenge has reset or explicitly requires a new attempt.
- Continue is unavailable.
- Protection remains on.

### C6. Successful final choices and protection changes

Run repeated full challenges to cover:

1. Pause one blocked app for 5 minutes.
2. Confirm only that app is unpaused.
3. Use the app while paused, then close Nima and wait for expiry.
4. Confirm protection returns automatically.
5. Verify the 10- and 15-minute choices are present and selectable; complete a full timer for each if time permits.
6. Choose Turn off until I turn it back on for the scheduled app.
7. Confirm the current schedule no longer unblocks that app and a future occurrence remains suppressed.
8. Turn the app back on deliberately and verify scheduled protection resumes.
9. Repeat for a manual blocker.

For every choice confirm:

- The confirmation says exactly which app(s) and schedule(s) are affected.
- Unrelated apps and windows do not change.
- Shield, client protection, Home state and persisted defaults agree.
- A failed/stale commit leaves protection on and offers a retry.

### C7. Turning Hard Mode itself off

1. Start the Hard Mode-off request.
2. Verify all four stages and the standalone Turn off Hard Mode choice.
3. Complete the challenge.
4. Confirm only Hard Mode is disabled; existing blockers and windows remain unchanged.
5. Relaunch and confirm Hard Mode stays off.

### C8. VoiceOver

With VoiceOver enabled, verify:

- Hard Mode activation and warning focus order.
- Modal containment and an accessible close action.
- Progress is announced as steps 1 to 4.
- Trace and draw canvases have understandable labels, hints and feedback.
- Sort items, selected state and incorrect-order feedback are announced.
- The timer exposes useful progress and does not cause constant disruptive announcements.
- Final choices identify the affected apps and outcome.
- Focus returns to a sensible Home element after cancellation or completion.
- No action is possible using only an unlabeled control.

Physical phone gestures may be needed for some VoiceOver interactions. Capture the exact point if that is required.

### C9. Reduce Motion and layout

1. Enable Reduce Motion.
2. Repeat activation, challenge presentation, cancellation and completion.
3. Confirm the challenge uses the intended reduced transition.
4. Confirm timer progress and final choices remain understandable.
5. Repeat at the largest practical text size and check for clipping or inaccessible controls.
6. Restore the original accessibility settings after the test.

### C10. Hard Mode release gate

Hard Mode passes only if:

- Protection cannot be removed before a complete challenge and explicit final choice.
- Cancellation, backgrounding and relaunch cannot preserve a partial pass.
- Every pause/off choice restores or suppresses exactly the named protection.
- The 60-second timer uses foreground elapsed time.
- VoiceOver can complete and cancel the full flow.
- Reduce Motion preserves meaning and control access.
- The on-screen claim matches actual duration; the current warning's "5–10 minute process" copy must be corrected if the real flow can take less than five minutes.

If any of these fail, remove Hard Mode from the acquisition release rather than documenting it as a known issue.

## Part D. Combined build acceptance — grandfathering

Part D is not executable against build 25. Run it against the next uploaded build after the build-24 legacy experience and the build-25 pivot have been combined. The expected build is 26.

### D1. Prepare the two test cohorts

Use controlled TestFlight accounts and subscriptions only:

1. Select one test customer who represents an existing paid build-24 customer and assign the approved grandfathered test flag.
2. Use a second clean install with no purchase history, entitlement or grandfathered flag.
3. Record each test customer's RevenueCat app user ID and both PostHog distinct IDs without placing secrets in evidence.
4. Confirm the combined build identifies the two customers as different cohorts before onboarding begins.

Pass: the cohort assignment is explicit and testable. Do not infer grandfathering from installation time, marketing attribution or whether an old VPN profile happens to exist.

### D2. Upgrade the grandfathered paid customer

1. Preserve the build-24 app data, RevenueCat identity and VPN configuration when moving the device to the combined build, where TestFlight permits this without deleting the app.
2. If a direct upgrade is not possible, reproduce the saved build-24 state using the approved test setup and record that limitation.
3. Launch the combined build.
4. Confirm the customer enters the old VPN experience, not fresh onboarding for the pivot.
5. Verify the existing paid entitlement, manual blockers, schedules, pause state, notification settings and VPN configuration are preserved.
6. Background and relaunch the app.
7. Confirm the same legacy experience and protection state remain selected.

Pass: an existing paid customer can update without losing paid access, protection settings, VPN configuration or the experience they were promised.

### D3. Complete the fresh-customer journey

1. Delete the app and reinstall the combined build on a device or Apple Account with no prior Nima purchase.
2. Complete onboarding.
3. Confirm no VPN education or VPN configuration permission prompt appears.
4. Confirm no VPN profile is created during launch, onboarding or ordinary use.
5. Confirm no VPN control is required to activate the Instagram, TikTok or X experience.
6. Purchase and restore Nima Pro.
7. Continue through the subscription, social-client, Pause Mode, relaunch and Hard Mode checks in Parts A-C where affected by the combined routing.

Pass: a new customer receives the pivot and completes the normal purchase and protection journey without touching the VPN path.

### D4. Reinstall, restore and cohort persistence

For each cohort:

1. Delete Nima while retaining the provider and platform test state needed by the plan.
2. Reinstall the combined build.
3. Refresh or restore the subscription.
4. Confirm the app returns to the correct experience.
5. Force-quit, relaunch and repeat the entitlement check.
6. Repeat with ATT denied.

Expected:

- The grandfathered paid customer returns to the legacy experience through entitlement or the approved persistent legacy marker.
- The fresh customer remains on the pivot.
- A failed RevenueCat request cannot silently switch, erase or duplicate either cohort.
- No VPN prompt appears for a fresh customer whose check is still loading.

### D5. Combined-build release gate

The combined build passes only if:

- Existing paid customers keep the old experience and the primary functionality they paid for.
- Fresh customers receive the pivot and never encounter the VPN journey.
- Both cohorts are chosen by explicit persisted state rather than a timing race or local guess.
- Restore, reinstall, ATT denial and offline launch do not move a user into the wrong experience.
- One App Store subscription maps correctly to the correct experience.
- The old VPN state remains untouched for legacy customers until an intentional migration is available.
- PostHog records the selected experience as an analytics property without sending VPN traffic data.
- App Review notes clearly explain the two experiences and how to test each one.

## Final decision

### Build 25 baseline passes only if

- The exact TestFlight build is recorded.
- A clean install reaches the new-customer experience without a VPN prompt or required VPN setup.
- No VPN profile is created merely by launching build 25 as a fresh user.
- Initial purchase/trial, restore, renewal, cancellation and expiry agree with RevenueCat.
- Every transaction that is required in PostHog and Meta appears exactly once.
- No duplicate purchase/start-trial event appears after relaunch or restore.
- Instagram, TikTok and X pass the clean-install core-function matrix.
- Protection and access persist after relaunch.
- Pause Mode restores protection automatically.
- Hard Mode passes its independent release gate.

### GO for Meta tracking and paid ads only if

- Build 25 has passed its baseline checks.
- The combined build has passed every Part D grandfathering check.
- The final App Store build number is newer than every uploaded build and is the exact build referenced in this evidence folder.

### NO-GO if any of these occurs

- A purchase or renewal is missing, duplicated, misattributed or mapped to the wrong product.
- The app grants access without a matching active entitlement, beyond an explicitly accepted grace period.
- A core social flow becomes unusable or a shared link turns into an endless feed.
- Pause Mode does not restore protection.
- Hard Mode can be bypassed, cancelled without resetting, or cannot be completed with VoiceOver.
- A fresh customer sees or is forced to approve VPN setup.
- A grandfathered paid customer is moved into the pivot or loses access to their existing paid functionality and settings.
- The test would require modifying production customer data or exposing credentials.

## Suggested execution order and rough time

### Build 25 baseline session

| Stage | Estimated active time |
| --- | --- |
| Preflight and clean install | 10-15 minutes |
| Build 25 no-VPN baseline | 10 minutes |
| Purchase, restore and immediate reconciliation | 20-30 minutes |
| Sandbox renewal, cancellation and expiry | Depends on Apple's sandbox schedule; active work is short |
| Instagram, TikTok and X core test plus pauses | 60-90 minutes |
| Hard Mode, lifecycle and accessibility | 45-75 minutes |
| Dashboard reconciliation and cleanup | 20-30 minutes |

Plan for a three-to-five-hour build-25 session, with waits between checks. Work that does not depend on wall-clock time should be done while waiting for renewal or expiry.

### Combined-build acceptance session

After the next build is uploaded, repeat the affected subscription, core-function, Hard Mode and relaunch checks and reserve 30-45 minutes for the Part D cohort tests. Do not copy a build-25 pass into the combined-build result.

## Remaining clarifications

1. Which iPhone model and iOS version will be used?
2. Confirm the physical device installs 1.4 (25) from TestFlight. The later combined release is expected to use a new build number, currently expected to be 26.
3. Is monthly acceptable for the sandbox subscription, and does the test account have a current trial offer?
4. Are disposable Instagram, TikTok and X accounts with 2FA ready, including a safe post for comments/replies, plus Instagram and TikTok DM recipients? Should X DM sending be treated as required coverage, which needs a second controlled X account?
5. Are RevenueCat, PostHog and Meta Events Manager already signed in on this Mac?
6. May the tester delete and reinstall Nima from TestFlight twice, and may they publish and then remove temporary test content?
7. Is same-device restore after reinstall sufficient, or must restore also be proven on a second physical device?
