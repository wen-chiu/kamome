# Device runbook — every check that only a phone can answer

**Created 2026-09-28** by pulling the "owed on the phone" items out of eleven
documents where each was the last line of its own section. This is the actual
critical path: no desk session can close any row below, and most of the open
work in `HANDOFF.md` waits on one of them.

**How to use it:** one TestFlight or Debug build, one sitting, top to bottom.
Tick a row by writing the date and the evidence (a log line, a screenshot path
outside the repo, or "Chiu judged"). The detail document is where the full
steps are. Tracked by issue #112. A row that fails becomes a `desk` issue;
when every row in a group is ticked, archive the detail document in the same PR.

§0 applies: screenshots and films of real trips stay in `~/Kamome-films/`, and
no coordinate goes into this file. Numbers only.

Before starting: About → **Export diagnostics** carries every log line named
below, numbers only (ADR 2026-09-24 (d)). Confirm first, on a **Release** build,
what `OSLogStore` returns outside a debugger.

---

## A. Release gate — D1–D5 (`Docs/release-readiness.md` Tier 3)

| # | check | pass means | detail |
|---|---|---|---|
| D1 | start an export, **lock the screen**, wait | the export survives, or fails loudly and a second export can start | `release-readiness.md` D1; iOS 26 cannot render MapLibre in the background, so "survives" means pause/resume (`handoff-export-performance.md` §9) |
| D2 | per-trip export time and peak memory at full frame count | numbers recorded for three trips; feeds the export estimate | `render cost:` line, and `render memory:` for peak footprint and lowest headroom (#161, no Xcode needed); also judges `prefetch_depth` / `composite_concurrency` |
| D3 | seconds per snapshot on current hardware | `render substrate:` mean recorded; `snapshot_timeout_s` = 60 checked against it | `handoff-export-performance.md` §9 — owed: the `render network` line after the one-download-per-tile fix (#105) |
| D4 | Limited Photo Library | import and export work with a limited selection | `device-test-P3.md` H |
| D5 | the S5 export sheet, device half | the desk review's items hold on a phone | `design-reviews/2026-09-25-s5-export-sheet.md`, `device-test-P3.md` G |

**Results 2026-09-28.** Phone: iPhone16,2 (15 Pro Max), iOS 26.4.2, build **0.2 (1)**.
⚠️ That build **predates #105 and #110**: its diagnostics have no `render network`
line and no `export stages` line (VERIFIED), so D2/D3 below price the old
every-tile-~9× fetch path. Main-branch numbers are still owed.

- **D1 — ✅ passed once (Chiu).** Locked the screen once mid-export; the export
  did not stop. One lock only, on the old build.
- **D2 — ½.** The time half: a real trip, Standard, 30 stops, 34 legs.
  - `film: 298.7s · 8960 frames`, `render plan: 670 stations`
  - `render cost: 745.9s total` (snapshots 4876.3 s summed, wait 522.2 s,
    composite 861.4 s, encode 44.0 s)
  - `render thermal: fair → serious · 508s at serious or above`
  - 185.9 MB MP4
  - **Peak memory not recorded**: the app logs none. Chiu will run it from Xcode.
    One trip of three.
- **D3 — ½, old build.** `render substrate: 658 snapshots (0 failed) · mean 7.40s
  · peak in flight 9 · requests 21807 / 2302 distinct · 10935 refetched`.
  - The render waited on tiles for 70% of its time (522 of 746 s), and each tile
    was requested about 9.5 times: the #105 symptom.
  - Mean 7.40 s is under `snapshot_timeout_s` = 60.
  - **Owed: one export on a build from `main`**, with its `render network` line.
- **D4 — simulator only; the device run is declined by Chiu (accepted risk).**
  Setup: iOS 17.5 simulator, current `main`, 16 synthetic photos at public landmarks.
  - Limit Access… with 6 photos: the trip was built from those 6 only, and the
    banner "Kamome can only see selected photos · Select More Photos" showed.
  - Adding 3 through that banner: the new photos joined the stops at once.
  - The export (short, 60 s) carried the added photo on its stop card
    (VERIFIED from frames).
  - Cancel mid-render returned cleanly to the sheet.
  - Also seen on iOS 17.5: launch, the first-run notice and Home all work.
  - Photo analysis fails on the simulator (`Could not create inference context`)
    and falls back to the pick by time. INFERRED to be simulator-only.
  - Found: the title-date bug (#131).
- **D5 — ✅ Chiu ran it** on the phone.

## B. TestFlight verifications (`handoff-testflight.md`)

| # | check | pass means |
|---|---|---|
| T4 | S3, the recap screen, the Discovery beta — light and dark; one film per mode | captures taken; report what reads badly, do not restyle |
| T5 | fresh install, dismiss the first-run notice | the app does not background itself |

## C. Films fixed in code, owed a phone export

| check | pass means | detail |
|---|---|---|
| Miyakojima re-export | log reads `film type one destination abroad` and the homecoming line; Chiu judges | `handoff-type2-round-trip.md` |
| MapLibre snapshotter crash | three full exports of the longest trip, no new `Kamome-*.ips` | same |
| Iceland day 12, plane over land | the Skógar → pool leg draws no plane | `handoff-known-bugs.md` |
| Vietnam: Taiwan → Vietnam leg | the stored verdict is read from the log; which of the three causes it is | `handoff-vietnam-crossing.md` |
| Stop-zone days (schema v14) | a trip opened after v14 has every stop's zone; an Iceland film exported in Taipei shows the same `Day N` | `_archive/handoff-arch-review-2026-09-24.md` round 2 |

## D. Features with device numbers UNKNOWN

| check | pass means | detail |
|---|---|---|
| Vision auto-pick | probe run on Iceland, local and iCloud; before/after screenshots for Chiu | `handoff-photo-analysis.md` (full steps) |
| Photo picks (ADR 2026-09-25 (b)) | pick 1–5 per stop and hide a stop; the film follows | same |
| iCloud photo download | transfer size, peak memory of a full-mode film, cellular cost, Optimize Storage on | ADR 2026-09-19 (b) |
| Country rule scan time | seconds per 50k photos on a phone (Mac: 0.32 s) | ADR 2026-09-25 |
| Crash-safe recording | kill the app mid-recording; the trip comes back | `handoff-long-recording.md` |
| Restart while recording (#245) | restart the phone mid-recording, leave it locked while carrying it > 1 km, then unlock: no `Kamome` crash in Analytics Data, the trip resumes | #245 |
| Merge-gap pacing | a multi-day `merge_gap` leg paces acceptably; is `merge_gap_min_m` = 500 right | same |
| Export after backgrounding (P0-1) | backgrounding mid-export fails the export, a second one can start | `_archive/handoff-arch-review-2026-09-24.md` |
| Subject lookup miss rate | count fallback badges over ten exports (desk: 1 in 5) | `handoff-subject-lookup.md` |

Also from the 2026-09-28 release review: an **iOS 17/18** pass (a simulator
can settle it first, #127), and the two-week recording's replay time on a phone
(`handoff-long-recording.md`).

## E. Chiu's own steps, in this order (`HANDOFF.md` 🔴)

1. `./check.sh --release <.xcarchive>` with the real key in the environment.
2. **Then** rotate the Geoapify key (S7). Never the other way round.
