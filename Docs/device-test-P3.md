# Phase 3 device validation — stop semantics + battery (next real drives)

Tracked validation items (Chiu, 2026-07-18). These ride any drive on a
build ≥ the stop.kind commit; the formal 2 h gate drive checklist stays
`Docs/device-test-P1.md`. Findings → `Docs/decisions.md`.

## ⚠️ Redistribution 2026-07-20 (Replay MVP repositioning — history preserved, nothing marked passed)

Per `decisions.md` 2026-07-20, these items were **split by destination**. Every
checkbox below stays exactly as it was — **unchecked items remain unchecked**;
this section only records *which gate each item now belongs to*.

- **→ Capture Beta (Phase 5)** — tracking / background / battery, no longer on
  the release path: **A, B, C, D, E**, and **H's 2 h continuous drive**. These
  validate live capture, which the Replay MVP does not ship.
- **→ Replay MVP gate (Phase 3.5)** — export / photo, still blocking release:
  **F** (reframed — no longer a single < 90 s pass/fail; now *per-trip export
  time recorded and product-acceptable* across the three dogfood trips), **G**
  (S5 UX / progress / cancel / share), and **H's limited-photo re-check**.

Do not fake a pass on either side. Capture Beta items get executed when the
passive tier is built; Replay MVP items get executed on the three-real-trip
dogfood day (see `Docs/handoff-P3.5.md` §6).

## A. Park → walk ~20 min loop → return → drive  · **→ Capture Beta**
- [ ] Walking trace preserved (walk segment visible, no gap)
- [ ] Stop appears at End Trip with `kind = walk_visit`, pinned near the car
- [ ] NO `dwell_pause` in the CSV during the walk

## B. Park → sit in car ≥ 3 min → then walk  *(known edge, expected to fail)*  · **→ Capture Beta**
- [ ] Confirm behavior: dwell fires while sitting; walk within 150 m is
      swallowed by the pause → walk trace lost
- Future fix: activity-aware resume (icebox). Do NOT fix pre-emptively.

## C. Park with GPS silence ~10 min → drive away  · **→ Capture Beta** (region-resume re-validation)
- [ ] Stop recorded with full duration (arrival backdated across the gap)
- [ ] CSV shows `dwell_pause` → `dwell_resume` (either ~3 min after parking
      or at return-to-car; resume ≤ ~1 min after leaving the 150 m region)
- [ ] **Region-based resume works on real hardware** — 2026-07-19 drive:
      resume fired but the app was suspended ~10 s later; 32 min lost
      (decisions.md 2026-07-19 region-resume). Fix landed (background-flag
      re-assert + trip-long SLC net + `sampling.recovery_gap_s` watchdog).
      Re-test on a build ≥ that commit:
      - [ ] `region_exit` appears in CSV at drive-away
      - [ ] Trackpoints continuous after resume (no multi-minute gap)
      - [ ] Any `gps_recover,<gap_s>` events noted here: ______
            (none = resume held on its own; present = the net caught a
            suspension — either way the leg must be recorded)

## D. Traffic jam / true standstill ≥ 3 min  · **→ Capture Beta**
- [ ] Note whether a false stop (short `dwell_pause`/`dwell_resume` pair +
      spurious stop row) appears, and what the road situation actually was
- Tunables on trial: `dwell.window_s` 180 / `dwell.radius_m` 80.
  Do NOT pre-tune without this data.

## E. Battery  · **→ Capture Beta**
- [ ] Battery % logged across the drive (CSV) — compare against the
      ≤ 5 %/8 h trend target (P1 checklist)
- [ ] Note stop-heavy vs highway split; screen use
- Silence-timer GPS pause (LocationService-level) is designed but NOT
  built — build only if these measurements say it matters.

## F. §4.5 render budget  · **→ Replay MVP gate (reframed 2026-07-20)**

**Reframed:** no longer a single "< 90 s" pass/fail. Now *per-trip export time
recorded (S5 readout) and judged product-acceptable* across the three dogfood
trips (`handoff-P3.5.md` §6). The simulator baselines below stay as a rough
sanity reference only.
Simulator baselines (2026-07-19, M-series Mac — treat as optimistic):
frame+encode pipeline 22.8 s (900 frames @ 1080×1920, 5k-vertex route,
24 stops); map snapshots 0.67 s each; full demo render 34.6 s end-to-end
with snapshot prefetch. Device measurement path: S5 shows "算圖耗時 N 秒"
after every export — no instruments needed.
- [ ] Export a recap of the longest real trip on the device; note the
      S5 render-time readout here: ______ s
- [ ] If > 90 s: check whether it's snapshot-bound (poor network) or
      CPU-bound (compositing) before touching anything — prefetch depth
      and keyframe_interval_frames are the knobs, in that order.

## G. S5 user-experience validation  · **→ Replay MVP gate**
- [ ] S3 (trip detail) → film button → S5 sheet opens
- [ ] "停留照片卡" toggle ON: exported video shows stop cards with photos
      where the trip has matched photos
- [ ] Toggle OFF: no stop cards, but title card AND end card (QR) still
      present — this is the signed-off contract, decisions.md 2026-07-18
- [ ] MP4 export → share sheet → file plays in Photos/Messages
- [ ] GIF export → share sheet → animates in Messages
- [ ] Cancel mid-render returns to idle, no stray files, re-export works
- [ ] Render-time readout appears and looks plausible (item F)

## H. Former Phase 3 hard gates — **split 2026-07-20**
- [ ] **2 h continuous drive**  · **→ Capture Beta** — per `Docs/device-test-P1.md`
      checklist on a build ≥ this branch (also feeds A–E above)
- [ ] **Limited photo access re-check** (Selected Photos)  · **→ Replay MVP gate** —
      banner + picker flow on S3 works on device; after adding photos via the
      picker, a re-exported recap picks them up on stop cards (CLAUDE.md
      2026-07-16 item stays unticked until this passes)
