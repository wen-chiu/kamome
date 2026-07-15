# Phase 1 device test — checklist (Chiu signs off; spec §7 Phase 1 gate)

The unit gates (GPX replay) pass in CI. This manual test is the remaining
Phase 1 gate criterion and needs a physical iPhone, a car, and ~2 h.

## Build preconditions (decisions.md 2026-07-12: must land before this drive)

- [ ] Always-permission priming + background location flow (landed Phase 2).
- [ ] Dwell region-resume in `LocationService` (decisions.md 2026-07-15) —
      without it the first dwell pause turns GPS off permanently and the rest
      of the trip is lost. GPX replay cannot cover the CoreLocation side, so
      the two ≥ 5 min stops below are the real test of it.

## Setup

- [ ] Build to device from Xcode (free personal team is fine, 7-day profile).
- [ ] Charge to 100%; note starting battery %.
- [ ] Location permission: grant **When In Use** at first Start, then accept
      the in-app priming sheet → choose **Always** in the iOS dialog. Screen
      lock during the drive is part of the test.
- [ ] Motion & Fitness permission: grant when prompted.

## Drive (~2 h, mixed route)

- [ ] Press Start (vehicle: car 🚗) at the trailhead; screen off, phone pocketed/mounted.
- [ ] Drive ≥ 45 min including highway and city streets.
- [ ] Make 2 deliberate stops of ≥ 5 min (coffee, viewpoint) — engine should
      dwell-pause (HUD stop count +1 within ~3 min of stopping).
- [ ] After each stop, confirm tracking **resumes** on driving off: HUD
      distance ticks again within ~1 min of leaving the 150 m region
      (region-exit → GPS back on; this is the dwell region-resume path).
- [ ] Take a ≥ 10 min walk mid-trip (parking lot → shop and back).
- [ ] Drive home; press End Trip.

## Verify afterwards

- [ ] Battery drain over the session: ______ % (target trend: ≤ 5%/8 h ⇒ ~1.5% for 2 h; record actual).
- [ ] Route polyline visually continuous — no straight-line gaps across the drive.
- [ ] Stop count == 2 (±0) and stops are where you actually stopped.
- [ ] Walk shows as its own segment (check trip row exists; segment-level UI lands in Phase 2 —
      verify via DB export or debugger if needed).
- [ ] App killed mid-drive (swipe away) → relaunch: known Phase 1 limitation, gap expected;
      note behavior for the §9 relaunch-stitching work.

## Sign-off

- Date / route / phone model: ____________________
- Battery result: ______
- Verdict (pass / tune config and repeat): ______

Findings go to `Docs/decisions.md` (config tuning) or `Docs/icebox.md` (scope).
