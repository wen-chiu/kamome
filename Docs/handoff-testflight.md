# Handoff — TestFlight: what is still owed

PO audit 2026-09-18 against `main` at PR #74. **The code is done**: Tasks 1–5 in
PR #76, Task 6 in PR #77. What remains is two verifications and Chiu's steps
outside the repository. Charter for any session picking this up: `Arch.md`.

**TestFlight is not the App Store submission.** `Docs/release-readiness.md`
gates the submission. The audience here is people Chiu knows — accepted
2026-08-20 (`Docs/_archive/pre-launch.md`, "The TestFlight position"). D1–D5 and
S7 do not block it; the TestFlight build is how D1–D5 get run.

## Done — kept as a ledger, not a to-do (VERIFIED against the tree 2026-09-19)

- **T1 version from build settings** — PR #76. `project.yml` maps
  `CFBundleShortVersionString` / `CFBundleVersion` to the build settings;
  `MARKETING_VERSION` is `0.1` (Chiu 2026-09-18), `CURRENT_PROJECT_VERSION` is `1`.
  ⚠️ **Each upload bumps `CURRENT_PROJECT_VERSION`** — App Store Connect refuses a
  build number it has already seen.
- **T2 privacy manifest** — PR #76. `App/PrivacyInfo.xcprivacy`, `plutil -lint` OK,
  `NSPrivacyCollectedDataTypes` deliberately empty: what Kamome declares as
  collected is Chiu's, owed at the App Store privacy label.
- **T3 export compliance** — PR #76. `ITSAppUsesNonExemptEncryption: false`.
- **T4 device appearance** — PR #76. `.preferredColorScheme(.dark)` is gone; the
  app follows the device (ADR 2026-09-18 (d)). Captures: see below.
- **T5 first-run notice backgrounds the app** — PR #76 did **not** reproduce it
  (simulator, two fresh installs). Not fixed, because a guess is not a fix.
- **T6 terrain credit follows the licence** — PR #77. `RecapMapAttribution`
  credits a source only when its licence requires it and the film's extent
  intersects its coverage box; six tests added, Iceland and Miyakojima desk-rendered.
  ⚠️ One question came out of it: the film shortens EU-DEM's Copernicus wording
  where ADR (f) says it may not — `HANDOFF.md`.

## Still owed — two verifications

1. **T4's captures.** PR #76 checked S1 light + dark, the first-run notice light and
   About light. Still owed: **S3 (Trip Detail), the recap screen, the Discovery beta
   (`-demo-discover` on the simulator), light and dark, and one film exported in
   each mode.** All need a trip with photos. Light-mode in-app screens have never
   been looked at — **report what reads badly; do not restyle** (`DESIGNER.md`'s
   call). The light film style is approved (addendum to ADR (d)).
2. **T5 on a device.** Fresh install, dismiss the notice, watch whether the app
   backgrounds. The fix, if it exists, must keep: shown once, remembered, one
   button, no swipe-dismiss (ADR 2026-09-05 (b), the 2026-09-06 three-line ceiling).
   Add a test that fails on the regression if the cause can be held by one.

## For Chiu, outside the repository

- Paid Program, the App Store Connect record for `com.chiu.kamome.dev`, team
  `B9U326WRA4` — **UNKNOWN** from here.
- **Internal testers first** — no Beta App Review. A public link ends the
  "people Chiu knows" condition of the open-endpoint acceptance (pre-launch.md
  2026-08-29 a); the 2000/day ceiling and burst limit hold either way.
- Archive → `./check.sh --release <.xcarchive>` (the real key, his shell) →
  **S7 can happen now**: builds since ADR 2026-09-12 carry no key, so a rotation
  after this archive passes is final and kills the key in every IPA already out.
  **INFERRED** — confirm nothing else uses the key first.

## Not blockers — tell testers

- D1 unverified: keep the screen on during an export.
- Imported trips show no kilometres; a ferry gets a boarding pass and a plane
  (`HANDOFF.md` Open).
- Japanese place names render in Chinese glyph forms (`MLNIdeographicFontFamilyName`
  in `project.yml`) — a DESIGNER question.
