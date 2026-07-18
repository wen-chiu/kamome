# Phase 3 device validation — stop semantics + battery (next real drives)

Tracked validation items (Chiu, 2026-07-18). These ride any drive on a
build ≥ the stop.kind commit; the formal 2 h gate drive checklist stays
`Docs/device-test-P1.md`. Findings → `Docs/decisions.md`.

## A. Park → walk ~20 min loop → return → drive
- [ ] Walking trace preserved (walk segment visible, no gap)
- [ ] Stop appears at End Trip with `kind = walk_visit`, pinned near the car
- [ ] NO `dwell_pause` in the CSV during the walk

## B. Park → sit in car ≥ 3 min → then walk  *(known edge, expected to fail)*
- [ ] Confirm behavior: dwell fires while sitting; walk within 150 m is
      swallowed by the pause → walk trace lost
- Future fix: activity-aware resume (icebox). Do NOT fix pre-emptively.

## C. Park with GPS silence ~10 min → drive away
- [ ] Stop recorded with full duration (arrival backdated across the gap)
- [ ] CSV shows `dwell_pause` → `dwell_resume` (either ~3 min after parking
      or at return-to-car; resume ≤ ~1 min after leaving the 150 m region)
- [ ] **Region-based resume works on real hardware** — still unproven

## D. Traffic jam / true standstill ≥ 3 min
- [ ] Note whether a false stop (short `dwell_pause`/`dwell_resume` pair +
      spurious stop row) appears, and what the road situation actually was
- Tunables on trial: `dwell.window_s` 180 / `dwell.radius_m` 80.
  Do NOT pre-tune without this data.

## E. Battery
- [ ] Battery % logged across the drive (CSV) — compare against the
      ≤ 5 %/8 h trend target (P1 checklist)
- [ ] Note stop-heavy vs highway split; screen use
- Silence-timer GPS pause (LocationService-level) is designed but NOT
  built — build only if these measurements say it matters.
