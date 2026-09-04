# The type-2 opening: what landed, what was measured, what is still open

The retime, the boarding pass, the plane and the two flight-end marks — built
2026-09-03/04. **Decisions live in `Docs/decisions.md` 2026-09-03 (b) and
2026-09-04 (b)**, which win over anything here.

The brief this implemented is closed and archived:
`Docs/_archive/handoff-type2-opening-brief.md`.


All six items built; `./check.sh` green; the continuity gate green on **eight
fixtures × two cameras, 0 violations, 0 excused, no exemption added or widened.**
`zoom_transition_s` and `subject_length_px` are untouched.

## The four numbers that were asked for

Measured through `RecapTimelineReportTests` and
`RecapOpeningFramingTests.testHowFarTheAircraftTravelsAcrossItsOwnFrame`, offline,
on both crossing fixtures. Logs in `~/Kamome-wt/logs/retime-*.log`.

| | expected | measured |
|---|---|---|
| the trip starts | ≈12.5 s | **13.09 s** |
| departure dwell | ≈3.0 s target, 3.3–4.1 s inferred | **3.59 s on screen**, 2 photographs |
| the sprite | 24.5 %/s | **24.6 %/s** Auckland · **17.3 %/s** Ishigaki |
| the odometer at the end card | 269 km | **269 km** (was 9,024) |

**Three numbers, not one, and the report prints all three** — the brief's
inference was against the *priced* dwell and the film shows the *visible* one:

| | `auckland-crossing` | where it comes from |
|---|---:|---|
| priced | 3.19 s | `RecapDurationPlan` for 2 photographs, after its global fit |
| asked (the hold) | 3.99 s | priced + `2 × subject_park_s` |
| **on screen** | **3.59 s** | 3.00 s → 6.59 s; the hold's first park ramp plays under the title card |

The brief inferred ≈4.1 s for two photographs *before* the plan scales every
dwell to fit the film; scaled, it is 3.19 s. Nothing here was tuned to hit a
number — the cap is on photographs and the pricing produced the rest, which is
§2's rule.

Both fixtures produce the **same opening**, because everything in it except the
departure's photo count is content-independent:

    0.00–3.00s   title card
    3.00–6.59s   departure airport, 2 photographs
    6.59–10.59s  the crossing, camera still, boarding pass on screen
    10.59–13.09s the arc closes into the destination
    13.09s       the trip begins

⚠️ **13.09 s, not 12.5 s, and the brief predicted both.** §6 derived 12.5 from a
3.0 s departure beat; §2 then said *do not hard-code 3.0 s* and inferred the
pricing would land at 3.3–4.1 s. It lands at 3.59 s on screen, and
3.00 + 3.59 + 4.00 + 2.50 = **13.09**. **The retime obeyed §2, and §6's arithmetic
assumed the beat §2 forbade** — nothing is wrong, but the number to quote is
13.09.

**If that reads long, `departure_stop_max_photos: 1` is a config edit**, which is
the entire point of the key. It was not taken unasked: 2 is what the review said.

## The type-1 control, measured rather than argued

`miyakojima` was measured **on `main`** and again on this branch, same command,
same simulator (`~/Kamome-wt/logs/retime-control-branch.log`). Every line is
identical:

| | `main` | this branch |
|---|---:|---:|
| total | 60.00 s | 60.00 s |
| opening ends | 6.50 s | 6.50 s |
| car appears | 10.50 s | 10.50 s |
| first stop | 6.53 s | 6.53 s |
| first photo | 7.50 s | 7.50 s |
| longest still | 2.97 s @ 57.00 s | 2.97 s @ 57.00 s |
| established | 2,111.6 km | 2,111.6 km |
| body | 14.8 km | 14.8 km |
| zoom ratio | 142.84× | 142.84× |

And its continuity line is identical on both cameras:

    miyakojima region   60.0s · span 14.8 km · worst overlap 70% at 42.6s
                        · 0 violations · 1 permitted cuts · 0 excused · 0 arcs · type unknown
    miyakojima shipped  (the same)

`RecapJourneyCardTests.testTheTypeOneControlDrawsNoCardHidesNoLegAndCountsEveryKilometre`
holds the same three claims structurally — no boarding pass, no hidden leg, and
`traveledLocalDistanceM == traveledDistanceM` at every second of the film — so
the control is gated rather than only measured once.

🔴 **File size cannot settle this, and it was checked rather than assumed.** Two
renders of `miyakojima` **from `main`** differ from each other — 36,563,831 and
36,569,825 bytes, different MD5s — so the H.264 encoder is not deterministic run
to run and a checksum diff would prove nothing either way. The branch's render is
36,588,860 bytes, which is *outside* that 6 KB envelope; with n=2 on `main` the
envelope is not characterised, so **the byte count is not evidence in either
direction** and the deterministic measurements above are what the claim rests on.

## Two things that were not in the brief

🔴 **`Geo.distanceM` is equirectangular, and the card prints a distance.** It
scales longitude by the cosine of the first latitude only, so over Taipei →
Auckland it is **121 km short** — and the 8,755 km quoted throughout
`Docs/_archive/handoff-type2-films-tasks.md` is that number. Harmless for the camera, which uses
one consistent axis for everything; not harmless on something shaped like a
document (`CLAUDE.md` rule 5). `Geo.greatCircleM` was added **beside** it rather
than replacing it, because changing `distanceM` would move every `cumulativeM`,
stop anchor and body span on every film to fix a defect that only exists where a
figure is shown to a person. ⚠️ **No sweep was done** for other places a
`Geo.distanceM` result reaches a viewer.

⚠️ **The two flight figures are deliberately different, and it is not a bug.**
The pass prints the **great circle** (8,876 km) because it prints a distance; the
cards subtract the **equirectangular** length (8,755 km) because `TripStats`
built their total that way. Subtracting one from the other puts **148 km** on the
cards where the journey is 269. Nothing in the film shows both, so no viewer is
handed two numbers that fail to add up. Asserted in `RecapJourneyCardTests`.

## The PO review — 2026-09-04

Three blockers, all closed: ADR 2026-09-03 §3 said 12.5 s where the measurement is
13.09 (corrected in the ledger); `HANDOFF.md` had 12 bytes of headroom (four
closed restatements moved to `Docs/_archive/handoff-2026-08.md`, 15,954 now); and
the type-3 footnote below is written into the closeout as handover item 5.

**The mockup arrived**, so the pass is no longer engineering's layout. It is
rebuilt to 登機證樣式（完整）: stub **left** at 0.173 of the width with the gull,
flight number under an orange rule, and the dates; a **0.312** ticket rather than
the 0.46 panel of the first pass; ends named large over their local names; a
dashed arc bowing between a filled origin dot and an open destination ring with
the aircraft riding it; a hairline over a labelled bottom row.

Two departures from the picture, both deliberate:

- 🔴 **`FLIGHT TIME 04:00` is not drawn.** The mockup predates its removal (Chiu
  2026-09-02, `CLAUDE.md` rule 5 — Kamome does not know it). The row keeps the
  mockup's rhythm with two fields instead of three. **Do not restore it from the
  picture.** Same for `KM-523`: the constant is `THX-9527`.
- ⚠️ **The card's orange is the mockup's `#FF6A3D`, not the film's `#FF8A5B`.**
  `RecapStyle` warns against near-misses of one accent and this is knowingly a
  second. Chiu supplied the hex as part of the target; one edit collapses them.

## What was on screen, and why two true statements disagreed

🔴 **The car across the Pacific was a harness gap, not the subject-lookup bug.**
VERIFIED 2026-09-04, and it is worth the paragraph because the obvious diagnosis
was wrong:

- `KAMOME_REVIEW crossing subject` is printed by **`RecapReviewScene`**, a
  *stills* harness. **No film log has ever carried that line** — every occurrence
  in `~/Kamome-wt/logs/` is a stills run, and all read `seagull`.
- `RecapDemoFilmTests.renderFilm` built its `FrameCompositor` **without
  `crossingSubject:`**, which defaults to nil, and `FrameCompositor` documents nil
  as *"a film whose caller supplied none draws its own vehicle across the
  crossing."* `RecapModel` passes it.

So the app drew a gull and the review film drew a car, and both statements were
true of **different renderers**. `VehicleCatalog.resolve` never failed and
`HANDOFF.md`'s subject-lookup miss is **untouched and still unmeasured**. Fixed by
passing the renderers; the harness now prints `KAMOME_DEMO_FILM crossing subject`
and `flight subject` so a film log can never be silent about this again.

## The pass, redrawn from the film — 2026-09-04

Chiu accepted the rest of the film and revised the card twice: a mockup, then two
reference tickets after watching it (`~/Kamome-films/type2-2026-09-04/pass-*.png`).
The second pass is what ships. Detail in ADR 2026-09-04 §8–§9; what matters when
picking this up:

- 🔴 **Both references print `FLIGHT TIME 04:00` and `KM-523`, and neither is
  drawn.** The field was removed on 2026-09-02 under rule 5 and the flight number
  is the constant `THX-9527`. This has now been declined twice, from progressively
  better-looking pictures. **Do not restore either from a reference.**
- 🔴 **The DATE row is the trip's range**, and the crossing-dates pipeline is
  deleted rather than parked. Semantically the row moved from the *flight* to the
  *journey* — honest, and named in the ADR as a shift somebody should look at.
- The notches are on the **outer edges**. On the tear line a hole reads as a disc,
  because whatever the map shows fills it.
- **One type size across both ends.** They were fitted independently and even sat
  at different baselines.
- The **dark ticket is palette-only**. The dark reference has no stub; building
  that would be a second drawing path for one object.

### Two bugs, and one thing that was never broken

- Right-aligned tracked type was a letter-space short: CoreText's kern adds
  advance after the last glyph too, so `textWidth` is wider than the ink.
- **The Chinese names were never missing.** `Region` suppresses a local name equal
  to the English one, and the desks render in an English locale. Fixed by pinning
  the review harnesses to `zh-Hant` — `Region`'s rule is correct and untouched.
  ⚠️ Both review harnesses now pin the same locale; two desks on two locales is
  the drift that keeps costing rounds.

## Still open, and each is Chiu's

- ✅ **The mockup arrived and the pass is rebuilt to it** (2026-09-04) — see
  above for the two deliberate departures.
- ⏳ **The plane is as oversized as the car was.** `subject_length_px` is
  deliberately unchanged this round (Chiu: judge the form first); on an 8,891 km
  frame the aircraft is about the size of Taiwan, and that is expected in this
  render rather than something to fix in passing.
- ⏳ **The redrawn end-card dash runs off the frame edge**, exactly as §4 said it
  would. Implemented as decided; **do not re-widen the end reveal** — that is the
  bug (`Docs/_archive/handoff-type2-films-tasks.md` §5). In front of the designer now.
- ⏳ **24.6 %/s** is the trade the ADR records. If it reads rushed, the answer is
  `subject_length_px`, never the beat.
