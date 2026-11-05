# Inked towns — the film marks each town the car reaches, and ends on a souvenir map

**Verdict:** Needs refinement. It works on both maps and costs no name and no second of film; it is a first cut, and three choices are Chiu's (below).

Chiu, 2026-10-29: 「車子快到時，城鎮名才重點…『壓』上地圖，之後一直留著。片尾全路線停留的 1.5 秒裡，整張地圖蓋滿你走過的地方，本身就是一張紀念品地圖。」 The mark is hand-drawn ink, the way someone circles a place on a paper road map. Issue #337; ADR `2026-10-29-the-film-inks-each-town-the-car-reaches` (Draft until this is judged).

## Evidence — what you are looking at

Desk renders from the real renderer, 1080 × 1920, the shipped maps (`liberty-fork-r6` dark, `shipped-light`), stand-in photographs. All in `~/Kamome-films/2026-10-29-inked-towns-prototype/`:

- `clip/reach-new-zealand-dark.mp4`, `-light.mp4` — 9 s from 10.5 s into the film: the film's second town, from 2.1 s before its ink starts (12.59 s) until its name comes back inked after its first stop (about 18.2 s). The 20 s windows behind them, through the town's second stop and into the next town's, are in `clip/new-zealand-*/`.
- `clip/new-zealand-dark/sheet-pen.png` — the pen, full size, at 12.6, 12.7, 12.8, 12.9, 13.0 and 13.2 s. `sheet-reach.png` — the whole window, 12 frames.
- `stills/souvenir-new-zealand-dark-loop.png`, `-light-loop.png` — **the point of the work**: the last frame before the end card (125.6 s), every reached town that has room for its name inked.
- `stills/souvenir-new-zealand-*-underline.png` — the same frame with the underline.
- `stills/souvenir-new-zealand-dark-loop-trail-ink.png` — the same frame with the loop in the trail's cyan.
- `stills/compare-souvenir-dark-light.png`, `stills/compare-variants-close.png` — side by side.
- `stills/sheet-synthetic-names.png` — the loop round made-up names of every shape (three letters, a two-line park, CJK), off the map, with the room each name keeps drawn round it.
- `logs/report-*.log` — the timeline report for each fixture (`KAMOME_PLACE_INK`, `KAMOME_PLACE_ROOM`).

Style values are read off `RecapStyle.modernMinimal(_:)` and `RecapPlaceNameStyle`.

## What works

- **The names are a map's from the start, and the car marks them.** Nothing else in the film moves: with the ink taken off, every frame's overlays are what they were, and every hold, frame count and camera frame is the same at any draw time (`RecapPlaceInkTests`).
- **A pen, not a stamp.** The loop starts at the top right, runs left along the top, round the left end, back along the bottom and up, then on past where it began, rising off the loop as the pen lifts. It is thinner where the pen touches down and lifts, it leans a little and is a little lopsided, and each town's is its own (seeded by the name).
- **It lands as the car does.** It is complete as the stop's lead-in begins (13.2 s in the clip), so it is seen being drawn before the stop's own name takes the town's over. It fades with the town's name while the stop presents itself, and the name comes back inked.
- **Round the name, never the dot.** The car parks on the dot; the loop stays below it.
- **No name lost.** The loop reaches 17.6 px past a name's box, inside the 18 px every name already keeps, so the names drawn are the ones drawn before the ink existed, on every trip (`RecapPlaceInkDrawingTests`).
- **The accent on dark is a pen on a map.** The orange stands apart from the cyan trail; in the trail's cyan the same loop reads as more road (`souvenir-…-loop-trail-ink.png`).

## Blocking

None.

## For Chiu — three choices

1. **Loop or underline** (`compare-variants-close.png`). The loop says *I was here*; the underline is quieter, a note under a name. Both fit in the 18 px and cost no name.
2. **The ink.** First cut: the accent `#FF6A3D` on both maps.
   - Dark: the accent. The trail's cyan is the alternative and merges with the route.
   - Light: the accent *is* the trail there, so where the route runs past a name the loop touches it. It still reads, through the name's white halo, but less clearly than on dark. The existing palette has no third ink. Any other colour on light needs the CHARTER §7 case, and none is made here.
3. **`place_name_ink_draw_s`**, 0.6 s (INFERRED). On New Zealand 8 of 11 towns draw on the road in and 3 as the name returns; a slower pen moves more towns to the second path. The table below is every fixture.

## Also for Chiu — what the first cut could not do without a cost

- **A looser loop costs a name.** Rendered first with more lean and wander, the loop needed 23.6 px round every name. Measured on New Zealand, that dropped a name on 31 of 1,226 sampled frames, and on the end route hold (4 names → 3). The first cut stays tight so that frame keeps all four. If the loop should breathe more, that is the trade.
- **The souvenir map names 4 of New Zealand's 11 towns.** At the end hold's span the other seven lose overlaps (ADR 2026-10-02 §3, unchanged), so they are neither named nor inked. *「整張地圖蓋滿你走過的地方」* is, at that zoom, four marks. Marking the others — for example an inked dot with no name — would change which names are drawn, so it is a decision, not a tweak.
- **A film with the photo cards off inks nothing.** It presents no stop, so no town is reached.

## Per fixture (timeline report, not a render)

Measured 2026-10-29 with `RecapTimelineReportTests` (`logs/report-*.log`), `place_name_ink_draw_s` 0.6 s, desk routing. Names drawn are counted every third frame through a flat projection at the camera's span, not MapLibre's Mercator, so they count rather than draw (INFERRED, close at these spans). "Before" is the 18 px room every name kept until now.

| fixture | towns | inked before the lead-in | as the name returns | never reached | names drawn, before → after | end route hold |
|---|---|---|---|---|---|---|
| new-zealand | 11 | 8 | 3 | 0 | 5,194 → 5,194 | 4 → 4 |
| iceland | 12 | 10 | 2 | 0 | 4,555 → 4,555 | 5 → 5 |
| miyakojima | 3 | 3 | 0 | 0 | 631 → 631 | 3 → 3 |
| miyakojima-round-trip | 5 | 3 | 2 | 0 | 755 → 755 | 4 → 4 |
| nz-real | 7 | 5 | 2 | 0 | 2,768 → 2,768 | 3 → 3 |
| finland | 3 | 2 | 1 | 0 | 768 → 768 | 3 → 3 |
| margaret-river | 4 | 3 | 1 | 0 | 1,116 → 1,116 | 4 → 4 |
| ishigaki-crossing | 3 | 1 | 2 | 0 | 332 → 332 | 1 → 1 |
| auckland-crossing | 5 | 3 | 2 | 0 | 896 → 896 | 2 → 2 |

Every town on every fixture is reached, and no name is lost. On New Zealand, the three towns inked as the name returns are the first town, whose stop the film opens on (VERIFIED, report), and two towns whose first stop comes straight after another stop's hold: for one of them the road between is 0.02 s (VERIFIED, `KAMOME_PILOT_HOLDS`); the other is INFERRED to be the same case, which its holds would settle. The other fixtures were not broken down.

## Recommendations

- Judge the dark clip first: it is where the loop reads best. Then the light still, where the ink and the trail share a colour.
- Judge the end hold at phone size. At 1080 × 1920 shown small, the loop's lift is a hairline.

## Polish

- The car crosses the name while the pen draws when the road runs under the town's dot (the clip, 12.7–12.9 s). The car is drawn above everything; nothing here changes that.
- On a two-character CJK name the overrun is short, because the top edge is short.

## Kamome identity

Hand-drawn ink on the emotional axis, over the map's structural layer, in the film's one accent: no new face, no new colour, and the stamp Chiu rejected (#334) is not in it. It turns the end hold, which already showed the whole route, into the souvenir he described.

## Recommendation

The loop, in the accent on dark, at 0.6 s. On light, decide whether the shared ink is acceptable. Then Stage 2: whole films, New Zealand dark and light and Iceland's first ~40 s, with this ADR moving to Decided.
