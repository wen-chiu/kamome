# Eng brief — the type-2 opening is retimed, and the crossing carries a boarding pass

**Direction decided by Chiu 2026-09-02.** Written by the PO session 2026-09-03.
Design source: `Docs/design-reviews/2026-09-02-cross-region-opening.md` (today
only on `claude/cross-region-transition-design-9cbb5b` — land it, or copy it,
before this work merges; a decision whose review is on an unmerged branch is not
delivered). Engineering context: `Docs/handoff-type2-films.md`.

**Scope: type-2 films only.** No type-1 film may change. `miyakojima` is the
control and its render must come out identical — say so with a measurement, not
an argument.

---

## 0. Two things to clear before writing code

1. 🔴 **The mockup is not saved.** The review names Chiu's light "登機證樣式（完整）"
   ticket as the visual target and says to save it beside the film. It is not in
   `~/Kamome-films/type2-2026-09-02/`. **Ask Chiu for it and save it there
   before laying out the card** — otherwise you are inventing the target.
2. `Docs/current-state.md` is **STALE** (`check-staleness.sh`: names PR #29,
   #31 has merged). Your PR re-syncs it on the branch. `HANDOFF.md` has ~120
   bytes of headroom under its 16 KB budget — move something closed into
   `Docs/_archive/handoff-2026-08.md` rather than trimming a live line.

---

## 1. `crossing_beat_s` 6.0 → 4.0 — a re-decision, and the ADR must say what changed

`Config/TrackingConfig.json` → `4.0`. Mechanically trivial. The governance is not:

- **6.0 was chosen from a rendered sweep on 2026-09-02** and the closeout in
  `Docs/handoff-type2-films.md` records it as settled, with a ⭐ note that Chiu's
  two picks reproduce a **~16.5–17 %/s screen-speed rule** and that *"no new
  sweep is needed."* 4.0 s puts Auckland at **24.5 %/s**. Leaving both numbers in
  the tree is the contradiction `CLAUDE.md` forbids.
- **Write the ADR (`Docs/decisions.md`, dated 2026-09-03) saying what the
  constant now is**: the beat is no longer a screen-speed choice, it is **as long
  as the boarding pass needs to be read**, and the sprite's speed is a
  consequence. Without that sentence the next session reads "16.5 %/s validated"
  beside "4.0 s" and reopens a sweep Chiu has already closed.
- Add the row to `Docs/decisions-index.md` (gated).
- **Amend, in the same PR:** the `Docs/handoff-type2-films.md` closeout (§4 and
  the "stays 6.0" line), `HANDOFF.md` lines that say 6.0 survives, and
  `Docs/handoff-cross-region-crossing.md`'s "(6.0, …)". Tests asserting 6.0:
  `Tests/CoreTests/ConfigLoaderTests.swift:127` and the several harness literals.
- **Record the tie-break rule** (Chiu, via the review): if 24.5 %/s reads rushed,
  the answer is to **de-emphasise the sprite, never to re-lengthen the beat**.
  ⚠️ That is the same lever as handed-over item 3 (`subject_length_px` is
  absolute while the frame span moves 20×) — one decision, not two, and **not
  this round's**: `subject_length_px` changes every film.

## 2. The departure airport gets one or two photographs, not the full deck

**Do not hard-code a 3.0 s beat.** Cap the photographs and let the existing
pricing produce the beat — duration follows content, which is the rule
`RecapDurationPlan` exists to hold.

- New key in `Config/TrackingConfig.json` → `export.departure_stop_max_photos: 2`.
  **Do not reuse `waypoint_max_photos`** — that means "a stop this thin is a
  waypoint" and belongs to `StopWeighting`.
- Apply it in `RecapTypeTwoFilm.trimmedToTheDestination`, which already owns the
  departure stop. `LinearTimelinePacing.pacing` reads `stops.map(\.photos.count)`
  *after* the trim (VERIFIED), so the plan reprices itself with no other change.
- **Report the measured dwell.** INFERRED from the pricing arithmetic: 1 photo
  lands ≈3.3 s and 2 photos ≈4.1 s against the review's 3.0 s target (the
  `stop_dwell_min_s` floor and `first_stop_dwell_scale` both bind). If 2 reads
  long in the render, **1 is a config edit, not a code change** — that is the
  point of putting it in config.

## 3. The Journey Card — a boarding pass, during the crossing only

A new `OverlayContent` case (pure data, no CoreGraphics, no geo→pixel — the
narrow waist), emitted by `LinearTimeline.overlayContents` for the crossing beat
window only, drawn by a **new file** `RecapOverlayJourneyCardDrawing.swift`
(`RecapOverlayRenderer.swift` is 318 lines against a 400-line lint budget).
Visual tokens go in `RecapStyle` (identity, in code), never in
`TrackingConfig.json`.

Placement: the lower band the title card has just vacated. Layout details are
yours; the mockup is the target.

**Content — offline only, and nothing else:**

| field | source | note |
|---|---|---|
| `FROM` / `TO` region | `CountryExtent.containing(lat:lon:)` → ISO code → `Locale.localizedString(forRegionCode:)` | English name over the viewer-locale name (TAIWAN / 台灣) |
| dates | last origin photograph, first destination photograph | see the gap below |
| `DISTANCE` | the crossing leg's length, **labelled as the flight** | this is the 8,755 km retired from the odometer in §5 |
| flight number | the constant **`THX-9527`** | |
| ~~`FLIGHT TIME`~~ | **removed** — Kamome does not know departure or arrival times | printing one is a fabricated record (`CLAUDE.md` rule 5) |

- 🔴 **The flight number is a `static let` in code, not a config key.** Config is
  for tunables (rule 7); this must never vary. Derived per trip it stops being a
  joke and becomes a claim about a real flight. Comment it with that reason.
- 🔴 **The dates are not in `RecapTrip` today** (VERIFIED): `PhotoRef` is a
  pointer and `Stop` carries only a `dayLabel` string. Compose them in
  `RecapComposer`, which has `PhotoRefRecord.takenAt`, and carry them as story
  data. **Do not let the renderer or the timeline go looking for dates.**
- 🔴 **`CountryExtent` has six rows and returns nil outside them.** If either end
  has no row there is no honest region name: **draw no card**, and log which end
  failed — the *end*, never a coordinate or a place (§0). Both shipping fixtures
  (TW→NZ, TW→JP) resolve.
- ⚠️ `Locale.current` makes the card's names device-dependent, as
  `CountryExtent.localizedName` already is. Pin the locale in the desk harness or
  your renders are not reproducible.
- The `FROM` / `TO` / `DISTANCE` field labels stay English literals — a boarding
  pass is an English artefact. Deliberate, not an i18n oversight; say so in a
  comment.

## 4. The crossing's dashed leg is hidden between the arrival and the end card

`LinearTimeline.revealedLegs` already knows which leg is the crossing
(`LegRange.isCrossing`). Drop it from the reveal from the aircraft's landing
until the end card, then draw it again.

⚠️ **It will not show what the review's sentence implies, and that is expected.**
The end reveal was refitted on 2026-09-02 to the *destination's local journey*
(closeout §5) because the whole-route frame is unexpressible and killed the
Auckland render. So the redrawn dash runs off the frame edge rather than
bracketing both countries. **Implement it as decided, do not re-widen the end
reveal** — that is the bug — and put the frame in front of the designer.

## 5. Every kilometre figure in the film is the local trip — three surfaces, not one

The review decided the odometer. VERIFIED: the same whole-trip `stats.distanceM`
also feeds two other surfaces, so fixing only the HUD leaves 9,024 km on both
cards:

1. **HUD odometer** — `LinearTimeline` passes `path.traveledDistanceM(atTime:)`;
   subtract the crossing stretches already passed.
2. **Title card subtitle** — `RecapComposer.titleSubtitle` appends
   `stats.distanceM`, and it is on screen at 0–3 s.
3. **End card stats** — `RecapComposer.statsLines`, same source.

Apply the one rule to all three: **the film's kilometres are the local journey**;
the flight's distance appears exactly once, on the boarding pass, labelled as the
flight. On `auckland-crossing` that is **269 km**, not 9,024 km.

## 6. Do not touch

- **`zoom_transition_s`.** 🔴 The review's table budgets **1.5 s** for the arrival
  arc and calls it "unchanged". It is neither: the opening crossing's close is
  `entry.endS + config.zoomTransitionS` = **2.5 s** (VERIFIED,
  `CameraPathCrossing.buildArcs`), and that knob is shared with every film's
  opening closing zoom. **So the retimed opening is 12.5 s, not 11.5 s.** Ship
  12.5 and report it; 11.5 needs a separate key and a separate decision from
  Chiu, and changing the shared knob would retime every type-1 film and void the
  control render.
- `subject_length_px`, the camera, the map's framing, the title card, the arrival
  arc's shape, `crossing_flight_max_longitude_deg` (stays 70), and **map place
  names** (iceboxed; Chiu ruled the effort is not justified).

---

## Done means

- `./check.sh` green — including `check-dead-config.sh` (the new key needs a
  consumer outside `Core/ConfigLoader/`), `check-decisions-index.sh`,
  `check-staleness.sh`, and `Scripts/test-count.baseline` raised in the same
  commit as the tests that raise it.
- The continuity gate green on all eight fixtures with **no exemption added or
  widened**.
- **Three renders, and the film is the evidence** (`./check.sh` cannot see it):
  `auckland-crossing` (the judgement), `ishigaki-crossing` (the short crossing —
  the card must read there too), and `miyakojima` (**the type-1 control: it must
  be unchanged**).
- Report, as numbers: where the trip now starts (expect ≈12.5 s), the measured
  departure dwell, the sprite's %/s, and the odometer at the end card.

---

# What landed — 2026-09-03. Read this half if you are picking the retime up.

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
`Docs/handoff-type2-films.md` is that number. Harmless for the camera, which uses
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
  bug (`Docs/handoff-type2-films.md` §5). In front of the designer now.
- ⏳ **24.6 %/s** is the trade the ADR records. If it reads rushed, the answer is
  `subject_length_px`, never the beat.
