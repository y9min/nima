# Nima 1.4 build 31 release preparation — 8 November 2026

## Plain-English status

Build 30 was uploaded on 6 November. The final Hard Mode choices were changed on 7 November, so build 30 does not contain the current Hard Mode implementation. Build 31 was built from the current committed feature code and has been prepared locally. At the user's request, build 31 has **not** been uploaded to App Store Connect or submitted for review.

## Prepared binary and verification

- Source feature commit: `43a39c5` plus the build-31 version bump. All five app and extension bundles report version `1.4`, build `31`.
- Signed archive: `apps/ios/artifacts/Nima-1.4-31.xcarchive`.
- Apple Distribution IPA: `apps/ios/artifacts/export-1.4-31-distribution/Nima.ipa`.
- IPA SHA-256: `a9240ecb362cc26eb4c998c91a735a5825194676cd0cd62e6c634e8ad0b6ac8b`.
- Release archive and App Store export succeeded. The exported app passes `codesign --verify --deep --strict` with the 9INE LTD Apple Distribution identity. It contains the Tenjin SDK, 12 privacy manifests, and the four expected extensions. The app binary contains the Hard Mode “Choose what changes” screen text.
- Focused simulator tests passed: 63 tests across Hard Mode, cohort routing, acquisition tracking, and subscriptions, with zero failures. The app was installed and launched on the paired iPhone 13; the device reports Nima 1.4 (31) running. Interactive physical-device checks remain open.

## App Store Connect and public policy

- App Store Connect now has an iOS 1.4 **Prepare for Submission** draft with updated description, What's New text, and App Review notes for the current and grandfathered experiences. Manual release remains selected. No build has been attached.
- The public policy at `https://nima.so/privacy-policy` now displays version 1.4, dated 8 November 2026. It covers Tenjin and the earlier optional account flow as well as version 1.4. The source is in `apps/web/app/privacy-policy/page.tsx`; the static site is `y9min/nima-site` commit `91032dc`, deployed to the existing Cloudflare Pages project.
- App Store privacy answers still describe the **currently live 1.3 app**. Apple says privacy answers for a live app should reflect the version currently available. Before releasing 1.4, review the build-31 privacy report and revise the answers: remove Email Address and Other Data if the current app no longer collects them, and assess Advertising Data declared by Tenjin's bundled manifest. Publish the revised answers at the appropriate release point.

## Remaining release checks before upload or review

1. Complete interactive physical-device checks for new-customer routing, purchase/restore, no VPN prompt, protection, time windows, Hard Mode challenge and pause expiry, ATT denial/revocation, and the grandfathered cohort. The prior test plan does not establish a build-31 pass.
2. Replace or validate App Store screenshots against the current new-customer experience. The existing upload-ready images date from July and show an earlier dashboard.
3. Reconcile the private grandfathered subscriber export and verify the three production purchase lineages; do not place raw identifiers in Git or review notes. The sandbox lineage test still needs a controlled test build or equivalent safe fixture.
4. Verify Tenjin live events, Meta callbacks, RevenueCat attribution and subscription event mapping, and Apple aggregate attribution as recorded in `docs/tracking/acquisition-tracking-2026-11-04.md`. Keep paid acquisition off until those checks pass.
5. When the user authorizes submission, upload build 31, wait for Apple processing, attach it to the 1.4 draft, complete any build-specific compliance questions, and add the version for App Review. Do not select build 30 as the final binary.
