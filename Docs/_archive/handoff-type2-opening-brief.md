# Archived — the eng brief for the type-2 opening retime (2026-09-02)

**Nothing here is a work instruction.** Every item below was implemented and is
recorded in `Docs/decisions.md` **2026-09-03 (b)** and **2026-09-04 (b)**, which
win. Archived 2026-09-04 under ADR 2026-09-03's rule — closed work leaves the live
corpus — with the live half kept at
`Docs/handoff-type2-opening-retime.md`.


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

