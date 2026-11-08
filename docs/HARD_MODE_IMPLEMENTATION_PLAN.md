# Hard Mode implementation plan

## Plain-English contract

When Hard Mode is on, trying to turn off a selected social app blocker opens a four-step challenge. After the timer, a separate page lets the user choose what happens to each currently blocked social app: keep blocking, pause for 5, 10 or 15 minutes, or turn off until manually re-enabled. The same page can turn Hard Mode off. Nothing changes until the user confirms the summary. Turning Hard Mode itself off also requires the challenge. The existing Home Pause Mode remains available without the challenge. Closing or leaving the challenge discards progress.

There is no extra waiting in steps 1–3. Step 4 is the existing 60-second paint-drying animation. Because the challenge can finish in less than five minutes, replace the introduction's “5–10 minute process” claim with accurate copy before release.

## Decisions and scope

| Area | Required behavior |
| --- | --- |
| Activation | Hold the Home rail's Hard Mode control to activate; show the warning card first. “Not yet” leaves it off. Persist only the enabled flag. |
| Disable request | Capture the selected app and the pending off action; keep protection active throughout the challenge. Show a full-screen card rising from the current card position. |
| Existing Home Pause Mode | Keep its current direct 5/10/15-minute flow and behavior. Hard Mode's post-challenge pause is scoped to the selected app. |
| Scheduled blocker | Include it. A successful indefinite-off choice must suppress the selected app across current and future scheduled occurrences until the user explicitly turns that app back on. Do not delete or silently rewrite the user's window. |
| Turning Hard Mode off | Run the same four steps; the final page defaults to turning off Hard Mode while keeping app blockers as they are. App changes require separate explicit selections. |
| Exit/restart | X, dismiss, backgrounding, navigation away, or app termination cancels the attempt; all step progress and timer progress reset. The enabled flag and any committed pause/off choice remain stored. |
| Sorting | Use 15 items in both shade and size variants. Size is the only alternate challenge shown. |

## What exists in the repository

- `apps/ios/Nima/Screens/HomeScreen.swift`: Hard Mode is a visual-only item in `StreakActionRail`; blocker off requests are handled directly by `toggleBlockState(for:)`. It also presents the current `EditBlockersSheet`, Home Pause Mode, and the confirmation for ending an active window.
- `apps/ios/Nima/Components/BlockingStatusCard.swift`: dragging a blocked tile to unlock or invoking its accessibility action calls the Home callbacks. A scheduled tile calls `onEndScheduledWindow`.
- `apps/ios/Nima/Models/TimeWindowStore.swift`: `endActiveWindow(for:)` ends only the current occurrence. Window switches, editing, deletion, and “pause all windows” are separate paths in `TimeWindowsScreen.swift`.
- `apps/ios/Nima/Screens/BlockingOptionsScreen.swift` can turn an option off directly. The Instagram, TikTok, and X protection stores each persist a manual enabled flag. `AppControlRulesStore` controls separate app-wide shields; removing one can also unblock an app and needs the same gate.
- `deliverables/paint-drying/nima_paint_drying.json` and its sibling `assets/` are the finished 60-second, non-looping Lottie asset. The app target does not yet include Lottie or these files.
- The working tree already contains unrelated iOS changes. Implementation should build on them without resetting or overwriting them.

## Architecture and state

1. Add a `HardModeCoordinator` owned above Home and Windows (at the app/root level), so every relevant screen sees one state. Persist `isEnabled` in the app group defaults. Keep `activeAttempt`, current stage, touch paths, tile order, and timer in memory only. Use a typed `PendingAction` containing the affected app ID set and the requested mutation, or `.turnOffHardMode`. A window edit can affect several apps, so the final choice must name every affected app.
2. Provide a single `requestOff(action:)` entry point. UI callbacks do not call protection-store setters or window mutation methods until the coordinator returns an authorized, one-use completion. Keep a distinct `commitAuthorizedAction` path that rechecks current protection and consumes the authorization once. Never persist a reusable “passed Hard Mode” flag.
3. Distinguish manual protection, scheduled protection, and a Hard Mode indefinite-off override per app. The override takes precedence over scheduled evaluation until a deliberate on action clears it. When turning off, clear the manual protection for that app and apply the override to schedule evaluation. When turning back on, clear the override and let any active schedule apply again. Store override state in the app group so the schedule monitor/extensions and foreground app agree. Avoid changing unrelated apps or windows.
4. For the post-challenge pause, use a per-app expiry and the existing pause/reapply machinery where possible. At expiry, recompute protection from the manual flag plus active windows and override; do not blindly force it on. Reconcile after app launch and foreground return, with a scheduled recovery path so an expired pause does not depend solely on the app being open.
5. Audit all *user-driven* paths that remove protection: Home drag and accessibility action; `BlockingOptionsScreen`; active-window end; window disable, edit, delete and pause-all; and app-wide blocked-rule removal. Gate a schedule or rule edit only when it would lift currently effective protection; adding or strengthening protection proceeds directly. For an edit/delete attempt, the temporary-pause choice leaves the underlying schedule/rule in place, while indefinite off applies the requested edit. Keep lifecycle reconciliation, account deletion, and guided-onboarding cleanup as explicit internal actions rather than sending them through a user challenge. Home Pause Mode remains the intentional exception.

## Presentation and motion

1. Extract shared styling from `EditBlockersSheet` into a card shell: dark green background, rounded top corners, matching border, safe-area handling, close circle, centered lower-case title, muted subtitle, lime four-segment progress, and bottom Continue capsule. Do not duplicate screen layouts or hardcode the screenshots' pixel dimensions.
2. Present the activation warning as a centered charcoal card over Home, matching screenshot 1: warning symbol, headline/body, lime Continue, “Not yet”. The hold gesture should show a visible hold-progress ring and cancel if the finger lifts early; VoiceOver gets a named Activate action.
3. On a disable request, animate the shared card shell upward from the blocker/Edit Blockers card region to a nearly full-screen panel. Host it in the same root overlay instead of crossing a SwiftUI sheet boundary, so its geometry can animate continuously. Lock interactions behind it. Close reverses the transition and resets the attempt. Honor Reduce Motion with a short fade.
4. Use a responsive vertical layout: stable header/progress and bottom action, scrollable challenge content, safe-area-aware bottom inset, and no clipping on smaller iPhones or larger Dynamic Type. Recreate the screenshots' artwork and spacing as closely as possible, then compare device captures side by side at the screenshots' size.

## Four challenge steps

### 1. Trace the phrases

- Present three phrases in this fixed order: “Scrolling is the enemy.”, “Discipline beats motivation.”, and “My time is worth more.” Show the `1 of 3` badge and Reset control. Continue advances only after the current phrase passes; after phrase 3 it advances to step 2.
- Generate and bundle reproducible vector stroke paths for the phrases, using one consistent cursive style. Reconstruct the pictured dotted white lettering rather than using a text field or accepting a tap. Render the target and touch trace in normalized coordinates so hit testing scales with the card.
- Define the forgiving 35% threshold precisely: at least 35% of target path samples must be covered within a finger-sized tolerance, and at least 35% of the user's drawn length must lie near the target. Require several distinct covered regions across the phrase, so a short scribble or holding a finger in one place cannot pass. Reset clears only the current phrase; failed Continue explains what remains without losing the trace.

### 2. Arrange by shade

- Generate 15 distinct, ordered green swatches from a fixed palette with a measured lightness ordering; shuffle their initial positions per attempt. The answer row contains 15 slots. Allow drag/drop and tap-to-place/reorder; prevent duplicate placement. The alternative “Sort by size instead” switches to 15 same-color objects with unambiguous ascending sizes and resets this step.
- Continue activates after all 15 slots are filled and the order is correct. On a wrong order, retain placements and mark the first neighboring pair to reconsider. Keep the underlying order as explicit ranks, not a runtime comparison of display colors. Avoid near ties and check the palette on real displays and with color-filter settings.

### 3. Draw this

- Recreate the palm-tree outline as a bundled vector path, with the pictured reference panel above a dotted drawing grid. Collect finger or Pencil strokes in normalized canvas coordinates; provide Clear/Retry and an obvious drawing stroke.
- Compare sampled drawing to the palm target with a forgiving distance tolerance. Require at least 35% overall target coverage *and* some coverage of the trunk and fronds, plus a minimum fraction of the user's ink near the target. Do not use exact pixel equality; reject empty, one-dot, or fill-the-canvas attempts. Show a short retry hint on failure.

### 4. Wait for the timer

- Bundle `nima_paint_drying.json` with its relative `assets/` folder in the Nima target and pin a verified Lottie package version. Use the 60-second asset as delivered; do not loop or generate a second fence animation.
- Make foreground elapsed time the sole source of truth for both `0:60` → `0:00` and Lottie `currentProgress` (clamped to 0...1). Continue is unavailable until the full 60 seconds elapsed. Leaving or backgrounding cancels the attempt and resets progress. On return to a new attempt, the fence starts wet at frame 0.

## Completion and protection changes

- After step 4, replace the timer page with a separate “Choose what changes” page. Show each currently blocked social app with its own Keep blocked, Pause 5/10/15 min, or Off until I turn it back on choice. Show Hard Mode as a separate Keep on/Turn off choice. Summarize every selected change and commit only when Confirm changes is tapped. A failed commit leaves protection on and shows a retryable error.
- When the request originated from turning off Hard Mode, default that row to Turn off and leave every app at Keep blocked. Once confirmed, clear the enabled flag and update the Home rail.
- If the target app becomes unblocked, a window expires, or the underlying state changes during the attempt, revalidate before commit. Never apply a stale off action to another app or to a new window. For a scheduled app with both manual and scheduled sources, remove both sources for that app only when the user picks indefinite off.

## Verification gates

1. Unit tests for the coordinator's state machine, one-use completion, cancellation/reset, activation/deactivation, per-app override, expiry and schedule precedence. Use an injected clock for the timer and expiry tests.
2. Geometry/interaction tests for phrase coverage, shade ordering, size alternative, palm scoring, wrong-answer retry, and all Continue disabled states. Test touch coordinates after resizing.
3. Route tests for every off entry point, especially scheduled-window edits and the tile's accessibility action. Confirm Home Pause Mode still opens directly and that its 5/10/15-minute restoration works.
4. Asset smoke test: Lottie JSON and both images resolve in the built app, frame 0 is wet, frame 1800 is dry, scrub progress matches the countdown, and the animation plays without looping.
5. Simulator and device walkthrough at small/large iPhone sizes, Dynamic Type, VoiceOver, Reduce Motion, app background/kill, active schedule changes, and protection expiry. Capture all four steps plus activation and completion; compare to the supplied screenshots and fix layout differences before calling the feature done.

## Release order

Implement the coordinator and protection semantics first, then wire every off entry point, then build the card motion and four challenges, then connect Lottie, then run the verification gates. Do not ship a visual-only challenge: blocking must stay active until a valid completion and explicit final choice are committed.
