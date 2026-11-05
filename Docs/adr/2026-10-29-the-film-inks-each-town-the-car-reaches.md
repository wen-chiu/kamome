# The film inks each of the trip's towns as the car reaches it, so the end route hold is a souvenir map

**Status:** Draft — Chiu decides it on the prototype (#337)
**Supersedes:** ADR 2026-10-02-the-film-names-the-trips-own-towns §2 (when names show) and §4 (look), in part; nothing else in it

## Context

Chiu, 2026-10-29: names stay on the map from the opening, as now — *「這就像是地圖一樣本來一開始就是會有城鎮名」* — and *「車子快到時，城鎮名才重點…『壓』上地圖，之後一直留著。片尾全路線停留的 1.5 秒裡，整張地圖蓋滿你走過的地方，本身就是一張紀念品地圖。」* The mark is hand-drawn ink, the way someone circles a place on a paper road map: not a larger size, not a new font. This is the "places in ink" half of the proposal on #327 (closed); the day stamp of #334 stays rejected.

- A larger name would pop its neighbours: ADR 2026-10-02 §3 resolves overlaps over every name (VERIFIED, code).
- A ring on the town's dot would sit under the parked car, which is why the name keeps `dotGapPx` from it (VERIFIED, code).

## Decision (first cut; INFERRED until Chiu judges the prototype)

1. **When.** A town is reached at the first moment, in film order, that the film presents one of its stops: a hold's lead-in, or a quiet stop's passing label. Its ink draws over `export.place_name_ink_draw_s` (0.6 s, INFERRED) and finishes as that lead-in begins, so it is seen before the stop's own name takes the town's over.
   - If the road in is shorter than the pen — measured from the end of the last hold or crossing, or from when the names are fully up — the ink draws as the town's name returns, when that stop has finished presenting itself. New Zealand: 8 of 11 towns before the lead-in, 3 as the name returns (the other fixtures are in the PR).
   - Once inked, a town stays inked through the end reveal and `end_route_hold_s`. A town never reached is never inked. Each journey's towns are reached on their own side of a crossing.
2. **The waist.** `RecapPlaceName.ink`, 0…1 at the frame's time (Chiu approved the field, 2026-10-29). The timeline says when; the renderer decides how ink looks.
3. **Look** (`RecapPlaceNameStyle`, tokens): a hand-drawn loop round the **name**, never the dot. The pen goes on along its length, runs past its start and lifts away outside it, so the loop stays open; its wander is seeded by the name through FNV-1a. It is drawn under the name's halo. Ink is the accent `#FF6A3D` on both maps: on the light map that is the trail, and on the dark map the trail's cyan would read as more road. The underline is the alternative.
4. **No name changes.** The ink reaches at most 17.6 px past a name's box, inside the 18 px every name already keeps, so the names drawn are the ones drawn before, on every trip (VERIFIED, `RecapPlaceInkDrawingTests`).
5. Unchanged: title card, end card, flight frame and boarding pass, the stop's own label, the HUD, the film's length.

## Rejected

- **A larger name, or a bolder one, for a reached town:** pops neighbours in and out (§3).
- **A new face:** a CJK face would have to be bundled, which is a dependency.
- **A ring on the dot:** under the parked car the moment it is drawn.
- **"Reached" as the car within some distance of the town:** a new tunable, and it would ink towns the film only drives past.
- **A looser loop** (more lean and wander, needing 23.6 px round every name): it cost New Zealand's end route hold one of its four names (VERIFIED, `KAMOME_PLACE_ROOM`).
- **The ink in the dark trail's cyan:** offered to Chiu as a still; first cut is the accent.

## Consequences

- A film with the photo cards off presents no stop, so it inks no town: its end hold is the plain named map (Chiu's to judge).
- A name that loses an overlap is not drawn, so its ink is not either: the souvenir map marks the towns the frame has room to name. New Zealand's end route hold names, and inks, 4 of its 11 towns (VERIFIED, render). Marking the others is a change to which names are drawn, so it is Chiu's, not this ADR's.
- Tests: `RecapPlaceInkTests` (six), `RecapPlaceInkDrawingTests` (four). The report prints `KAMOME_PLACE_INK` per fixture; stills from `RecapInkedTownsStillsTests`. Renders: `~/Kamome-films/2026-10-29-inked-towns-prototype/`.
- Owed after Chiu's verdict: whole films (New Zealand dark and light, Iceland's first ~40 s), this ADR to Decided with `Docs/current-state.md` synced, and a device re-export.
