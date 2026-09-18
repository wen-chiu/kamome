# Handoff — TestFlight: the fixes an engineering session owes

PO audit 2026-09-18 against `main` at PR #74 (`./check.sh` green, 531 tests).
**This file is the engineering prompt.** Charter: `Arch.md`. One PR for all of
it; `./check.sh` green before "done"; the visual items owe captures.

**TestFlight is not the App Store submission.** `Docs/release-readiness.md`
gates the submission. The audience here is people Chiu knows — accepted
2026-08-20 (`Docs/_archive/pre-launch.md`, "The TestFlight position"). D1–D5 and
S7 do not block it; the TestFlight build is how D1–D5 get run.

## Task 1 — the version comes from build settings (T1)

`App/Info.plist` (XcodeGen output, tracked) carries `CFBundleShortVersionString`
`1.0` and `CFBundleVersion` `1` as literals; `project.yml`'s `MARKETING_VERSION`
`0.1.0` and `CURRENT_PROJECT_VERSION` `1` are read by nothing. **VERIFIED.**
App Store Connect refuses a build number it has already seen.

- In `project.yml` `targets.Kamome.info.properties`:
  `CFBundleShortVersionString: $(MARKETING_VERSION)` and
  `CFBundleVersion: $(CURRENT_PROJECT_VERSION)`. `xcodegen generate`.
- Values: Chiu decides the marketing version. Whether `1.0 (1)` was ever
  uploaded is **UNKNOWN** — ask him to read App Store Connect → TestFlight and
  set `CURRENT_PROJECT_VERSION` above anything there.
- Pass: the built `.app`'s `Info.plist` shows the two build-setting values.

## Task 2 — a privacy manifest (T2)

No `PrivacyInfo.xcprivacy` exists in the app target, and app code reads
`UserDefaults` — `FirstRunNotice`, `JourneyNaming`, `LastVehicleChoice`,
`JourneyDiscoveryModel`, `DemoJourneyLibrary`. **VERIFIED.** GRDB 6.29.3 and
MapLibre 6.27.0 ship their own manifests. That a missing one fails the upload
(ITMS-91053) is **INFERRED** from Apple's 2024-05-01 policy.

- Add `App/PrivacyInfo.xcprivacy` as a resource of the `Kamome` target (via
  `project.yml`): `NSPrivacyTracking` false, `NSPrivacyTrackingDomains` empty,
  `NSPrivacyAccessedAPITypes` = `NSPrivacyAccessedAPICategoryUserDefaults` with
  reason `CA92.1`.
- `FilmStore.fileSize` reads `.size` only — no file-timestamp entry. Before
  adding the file, grep once more for timestamp, boot-time and disk-space APIs
  (Apple's required-reason list) in `App`, `UI`, `Core`.
- `NSPrivacyCollectedDataTypes`: leave **empty** and say so in the PR. What
  Kamome declares as collected (coordinates reach the Worker, OpenFreeMap, AWS,
  Apple) is a product statement — Chiu's, owed at the App Store privacy label.
- Pass: the file is in the built `.app`; `plutil -lint` clean.

## Task 3 — export compliance (T3)

Add `ITSAppUsesNonExemptEncryption: false` to the `info.properties`.
**Chiu 2026-09-18: set it to false if Kamome only uses HTTPS.** Checked 2026-09-18:
no `CryptoKit`, `CommonCrypto`, `Security`/`SecKey`, SQLCipher or `Network`
imports in `App`, `UI`, `Core`, `Package.swift`; plain GRDB (no SQLCipher); all
traffic is `URLSession`/MapLibre/`CLGeocoder` over the OS's TLS. **Re-run that
grep in the PR** — if anything turns up, stop and report instead of setting the key.

## Task 4 — the app follows the device's appearance (ADR 2026-09-18 (d))

- Delete `.preferredColorScheme(.dark)` at `UI/Home/HomeView.swift:77`.
- Rewrite the ⚠️ comment at `UI/Discovery/JourneyTimelineView.swift` (≈67) that
  says the beta inherits the dark override — it will not be true.
- Captures: S1, S3, the recap screen, the first-run notice, About and the
  discovery beta, **light and dark**, one film exported in each. Light-mode
  in-app screens have never been looked at — **report what reads badly; do not
  restyle** (`DESIGNER.md`'s call).
- Do **not** write another ADR; (d) is the record.

## Task 5 — dismissing the first-run notice backgrounds the app

Found while verifying PR #44 (commit `625316b`), simulator-reproducible, no
repro steps recorded, **UNKNOWN on device**. `HomeView` presents
`FirstRunNoticeView` as a sheet with `interactiveDismissDisabled()`; its only
button calls `FirstRunNotice.acknowledge()` and sets the flag false.

- Reproduce first on a fresh install (the notice shows only when
  `matching.base_url` is non-empty — it is, in the shipped config). If it does
  not reproduce, say so with the steps tried; do not "fix" by guessing.
- The fix must keep: shown once, remembered, one button, no swipe-dismiss
  (ADR 2026-09-05 (b), the 2026-09-06 three-line ceiling).
- A test that fails on the regression, if the cause can be held by one.

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
- Terrain credit ships unapproved (`HANDOFF.md` Awaiting Chiu).
- Japanese place names render in Chinese glyph forms (`MLNIdeographicFontFamilyName`
  in `project.yml`) — a DESIGNER question.
