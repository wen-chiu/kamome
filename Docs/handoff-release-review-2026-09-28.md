# Release review — 2026-09-28

Chiu asked for a last check before the App Store: what is still untested, what
could still break, and whether Kamome can be released. Against `main` at PR #110
(`b02b261`). `Docs/release-readiness.md` stays the gate; this file adds only what
that gate and `HANDOFF.md` did not already carry.

Evidence labels (`CLAUDE.md` rule 4): **VERIFIED** = read in the code or run,
**INFERRED** = follows but not provoked, **UNKNOWN**.

## Fixed on this branch

1. **`main` was red.** All 783 tests passed, but two gates failed:
   - `check-staleness.sh`: `current-state.md` named PR #107, and four PRs had
     merged since.
   - `check-test-count.sh`: the baseline said 771 against 783. A bump was lost
     in the stacked merges of #106 and #108–#110, and no test disappeared.
     VERIFIED on a clean worktree, so no untracked file inflates the count.
2. **The privacy manifest lacked a required-reason API.**
   - `ProcessInfo.systemUptime` arrived 2026-09-26 in `ThermalWatch.swift:34` and
     `MapSubstrateMeter.swift:102` (VERIFIED).
   - `App/PrivacyInfo.xcprivacy` declared UserDefaults only.
   - App Store Connect refuses such an upload (ITMS-91053): **INFERRED** from
     Apple's published policy, and never provoked here.
   - The fix declares `NSPrivacyAccessedAPICategorySystemBootTime` with `35F9.1`,
     which covers time elapsed between events in the app.
   - New gate `Scripts/check-privacy-manifest.sh` maps source patterns to
     categories. It was shown red against the pre-fix manifest, where it named both
     call sites. GRDB 6.29.3 and MapLibre 6.27.0 each ship their own manifest
     (VERIFIED in the package checkouts).

## Owed by Chiu before submission — not code

| # | what | why |
|---|---|---|
| A1 | **A hosted privacy-policy URL** | App Store Connect requires one. No URL exists anywhere in the repository (VERIFIED by grep). The in-app notice is not a substitute. |
| A2 | **The App Privacy label** | The manifest declares nothing as collected, and that is Chiu's call (`handoff-testflight.md` T2). Geoapify keeps the request, which carries coordinates, for ≤ 24 h. Whether that counts as "collected" is a product decision. |
| A3 | **The visible "Beta / 測試版" label on Discovery** (`discovery_beta`) | App Review guideline 2.2 turns away beta or test content. Whether this label triggers it is **INFERRED** and depends on the reviewer. ADR 2026-09-18 (b) chose the beta framing, so only Chiu can change it. |
| A4 | **The reviewer's path** | The reviewer's phone has no geotagged photos and no trips, and `DemoSeeder` is DEBUG-only. Review notes and a demo video would show import → film. They should also say why background location needs *Always* (guidelines 2.5.4 and 5.1.5). |
| A5 | **The routing quota when the audience goes public** | Pre-launch.md 2026-08-29 (a) ends the open-endpoint acceptance automatically on a public release. The 2000/day ceiling is shared by every user. At ~58 requests per Iceland-sized film, that is about 35 such films a day before everyone gets dashed legs until UTC midnight. **INFERRED** from the two numbers. The ceiling holds either way; this is about capacity, not safety. |
| A6 | **`MARKETING_VERSION` is `0.1`** | Chiu set it on 2026-09-18 for TestFlight. A first App Store version is usually 1.0. |
| A7 | **Live recording ships, and its device checks were deferred to Capture Beta** | Recording is on S1 (ADR 2026-09-23 (d)). `device-test-P3.md` A–E cover background, dwell and battery, and they moved to Capture Beta on 2026-07-20. Chiu decides whether to run them first or ship without them. |

## Device checks this review adds to D1–D5

Run them in the same TestFlight session, and bring the data back with About → Export diagnostics.
- **iOS 17/18:** the deployment target is 17.0, and every run so far is on the iOS 26
  simulator. **UNKNOWN.** The cheapest check is one smoke pass on an iOS 17 or 18
  simulator.
- Already written elsewhere and collected here so one session runs them all:
  - `handoff-long-recording.md`: the swipe-away relaunch, and two-week replay time on a phone
  - `handoff-arch-review-2026-09-24.md`: background mid-export
  - `handoff-known-bugs.md`: Iceland day 12
  - `handoff-type2-round-trip.md`: Miyakojima ×3
  - `handoff-vietnam-crossing.md`
  - ADR 2026-09-19 (b): iCloud-only photos
  - `handoff-testflight.md`: T4 and T5

## Still open in code, not blocking

- `TripDetailModel.reload` reads every trackpoint on the main thread (arch review
  P2-13). INFERRED: long recordings may make the screen hitch.
- `RecordingView` redraws the whole path every second (`handoff-long-recording.md`).
