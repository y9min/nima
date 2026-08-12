# Growth and polish backlog

## Restrict the guided experience before the paywall

Priority: revisit when Nima is being polished for a growing user base.

The guided experience currently renders the live Home, Windows, and Settings tabs before the mandatory subscription paywall. This is acceptable for the initial App Store launch, and deliberate avoidance is expected to be uncommon, but a determined user could leave the guided path unfinished and explore parts of the app.

Future hardening:

- Keep only the controls required by the current guided step interactive.
- Disable Settings and unrelated dock navigation until the guide finishes.
- Persist and resume the exact guided step after relaunching; do not use a short timeout that restarts onboarding.
- After the final guided step, immediately route unsubscribed users to the non-closable paywall.
- Keep Settings → Subscription → View plans as a closable, secondary purchase route.
- Enforce subscription access at core feature actions as well as at the UI routing layer.

Before shipping this hardening, regression-test the complete guided flow on both iPhone and iPad so the App Review path remains reliable.
