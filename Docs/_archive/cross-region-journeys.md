# Cross-region journeys — requirements and design space

**Status: requirements decided by Chiu (2026-08-14), design NOT decided, nothing
built.** This is a scoped implementer guide in the shape of
`Docs/_archive/vector-tile-pipeline.md`, not an ADR. No entry goes into `Docs/decisions.md`
until something has been rendered and judged — the standing rule that unverified
work is never written as settled architecture.

Supersedes the two deferred stubs in `Docs/_archive/handoff-P3.5.md`: "Trips that span two
map regions" and the airport-departure animation noted beside it. Both are folded
in here.

---

## Why this is open now

The 2026-08-01 owner call was to defer this **until single-region trips had
rendered end to end**. That precondition is met: three trips rendered at the desk
and were judged, and §6a closed on 2026-08-14.

Then the **first real device import hit it immediately** — a Miyakojima trip whose
first day starts at a departure airport in another country.

### ⚠️ The part that is worse than one trip

The desk fixtures were built by `Tools/exif-to-fixture.sh` over **folders Chiu
assembled by hand** (`~/Desktop/<trip>`), which are already curated to the
destination. The app imports **a date range out of the whole photo library**.

Those are not the same input. Any trip reached by flying — which is all three §6b
trips — will pull its travel days in on device and will not pull them in at the
desk. **So this is not a Miyakojima quirk; it is the default behaviour of the
shipped import path for every overseas trip**, and the three device films are
likely to differ from their desk counterparts in exactly this way.

Confirmed on the first device film: a 135.5 s Miyakojima recap that opens on the
departure country, draws a dashed line across open sea, frames the island days at
a scale where the island is a smudge, and renders the whole thing on Apple's map.

### One cause, three symptoms

`RecapMapTiles.tilesURL(covering:)` requires **containment**, not overlap. A trip
whose bounding box spans two regions matches none, and the single `nil` produces:

1. **Apple's map instead of the souvenir map** — `RecapModel.snapshotProvider(for:)`
   falls back when no region covers the trip.
2. **A camera framed for the union.** The body span is sized against a journey
   hundreds of kilometres wide, so the part the trip is actually about is rendered
   too small to read.
3. **A dashed straight line across water** — the crossing is unroutable, so PD-2
   keeps raw geometry and draws it inferred. Honest, and precisely the artifact
   §6a's "no obvious sea-crossing straight line" exists to catch.

*(Two further symptoms of the same nil — no prologue, and a flat 30 s film — were
fixed on 2026-08-08 by `RecapPacing`. Only the three above remain.)*

---

## What Chiu decided (requirements, 2026-08-14)

These are **requirements, not designs.** How they are met is open.

1. **The user can choose which photographs make a trip** — by picking an album, or
   by selecting photographs directly — instead of only a date range.
   Chiu explicitly **rejected "just narrow the date range"** as the answer: *"這是
   短程旅行再扣掉頭尾 就更少東西 也不完整."* On a short trip, cutting the head and
   tail removes most of it.
2. **A flight leg is flown by a plane**, and **the plane moves faster than the car
   does.** The crossing should not be paced like driving.
3. **A sea crossing from a port is a ship**, and the app **works this out by
   itself** — *"符合直覺也不用使用者操作."*
4. **When the mode of a crossing cannot be determined, the seagull flies it** —
   Kamome's own logo, drawn as its own sprite.
5. The trip must not be reduced to its bounding box: the destination is what the
   film is about.

### Requirement 4 is the load-bearing one

The seagull is not a decoration, it is **honest provenance made visual.** Kamome
already refuses to draw a road it did not reconstruct — an inferred leg is dashed
so the viewer can see the app is guessing. A crossing whose mode is unknown is the
same claim in a different medium: *we know you went from here to there; we do not
know how.* A plane drawn over a ferry route would be a fabrication of exactly the
kind PD-1/PD-2 exist to prevent.

**So the classifier must be allowed to answer "I don't know", and that answer must
be cheap and good-looking rather than a failure state.** Design the seagull first
and the plane second; a classifier with no honest fallback will be tuned into
guessing.

---

## The reframing this suggests

> A journey that crosses regions is not one continuous trip to be framed as a
> whole. It is **N local journeys joined by discontinuities.**

Once the crossing is its own beat, the body of the film only has to frame — and
only has to find tiles for — the destination. That single change addresses all
three symptoms at once, which is why the flight animation is **the fix and not the
polish**: it is not a nicer way to draw the dashed line, it is what stops the
dashed line from setting the scale of the whole film.

The detection half already exists. `CameraPathActs` was deliberately reduced to
**discontinuity detection only** in the 2026-08-02 camera rebuild, and
`act_split_km` already cuts at a jump of this size. What is missing is the
presentation.

### ⚠️ The prior failure this must not recreate

**Per-act framing was tried and rejected on 2026-08-02.** From `CLAUDE.md`:

> `CameraPathActs` framed each act to its own bounds while timing came from a
> separate clock, so motion came from **data shape** rather than spatial
> continuity — acts collapsed onto the `camera_span_m` floor and the camera
> crossed 110 km between them.

and

> framing was a decision about the camera, and conflating them is what made acts
> visible to the audience.

The proposal here is not a repeat, and the difference has to stay sharp or it will
become one:

| rejected 2026-08-02 | proposed here |
|---|---|
| **every** act re-frames | **only a genuine discontinuity** re-frames |
| the trigger is a change in data shape | the trigger is an event the audience would recognise as a cut — a flight, a ferry |
| the cut is invisible to the viewer and reads as a camera fault | the cut is narrated, with a sprite crossing it |

**The rule to hold:** a re-frame is permitted only where the film *shows the
viewer* why the ground changed. If a segment boundary would pass without the
audience being told, it must not re-frame. Anything else rebuilds the act camera.

The two continuity gates (`RecapCameraContinuityTests`: ≥50% shared ground between
consecutive frames, subject inside 80% of the half-frame) will fail across a
discontinuity by construction, so they need an explicit, narrow exemption keyed to
a narrated crossing — **not a relaxed threshold.** Relaxing them is how a strobing
film passes.

---

## Classifying a crossing

The classifier is its own seam: leg + both endpoints in, a mode out, with the
confidence attached. Signals available today, cheapest first:

| signal | tells you | already in the tree |
|---|---|---|
| OSRM returned `NoSegment` | no road network — water, or off-extract | yes, logged per leg |
| implied pace (distance ÷ elapsed) | flight-scale vs ferry-scale speed | `ImportService.mode(for:)` |
| the gap exceeds `pace_unknowable_gap_s` (4 h) | pace carries **no** signal — do not infer from it | yes, and it will fire on most real crossings |
| the endpoint's reverse-geocoded name | airport vs port vs neither | `StopNamer` already names every stop |
| a POI category lookup at the endpoint | airport / marina / ferry terminal, typed rather than guessed from a string | **no** — and see the boundary note |

Two warnings worth having in advance:

- **Pace will usually be unknowable.** An overnight or half-day gap around a
  flight trips the 4 h ceiling, which exists precisely because elapsed time was not
  spent travelling. So speed alone will rarely classify a crossing; endpoint
  context will do most of the work. Do not "fix" the ceiling to make the classifier
  work — that ceiling is what stopped 7 of 9 New Zealand legs being typed as walks.
- **Name matching is brittle across languages.** "Airport" / "機場" / "空港" is a
  heuristic, not a type. A POI-category lookup is the honest version, and MapKit
  offers one — but **`import MapKit` is confined to `MapKitSnapshotProvider.swift`
  by standing boundary discipline.** A second MapKit consumer needs its own
  one-file confinement and a protocol seam, exactly as `StopGeocoding` did for
  CLGeocoder. Do not scatter it.

**Where the classifier's answer belongs:** with the trip, not with the renderer. It
is a fact about the journey, in the same category as `stop.kind` and
`trip.source` — and like them it must survive into the database honestly. A schema
addition is likely; treat it as one, with the same "readers treat unknown as X"
discipline `stop.kind` used.

---

## Pacing a crossing

Requirement 2 asks the plane to move faster than the car. Today `CameraPath`
speed-warps all travel with one global factor, so a 400 km crossing consumes
travel budget in proportion to its length — on a short island trip it would eat
most of the film's motion.

**This interacts with the duration rule that landed in `b3093ad`**, and favourably.
`travelS` is what remains after the earned stop dwells; the camera crosses
`routeDistanceM` within it. A crossing that plays in its **own beat** stops
contributing to the body's distance term at all, which:

- gives the driving back its travel time,
- and makes `bodySpanM` more correct, since it is derived from route distance.

So per-mode speed and per-segment framing are the same change seen twice, not two
features. Build them together or the pacing knob will be tuned to compensate for
framing that is about to change.

**Do not add a per-mode speed constant before the segment beat exists.** It would
be a constant reverse-derived from one trip, which is how `body_span_padding` and
`tier_skip_share` were both built and both removed.

---

## Choosing the photographs (requirement 1)

A separate feature from everything above, and **complementary rather than
alternative**: selection gives the user control; the crossing beat is how the
product behaves when they do not use it. Neither removes the need for the other —
a user should not have to curate a trip to get a good film, and a user who wants
to curate should be able to.

Purely an **import-time** concern. `ImportService` takes a date range and queries
PhotoKit; adding other sources changes what feeds it and nothing downstream —
clustering, routing, the timeline and every renderer are untouched.

**Split by cost, because these are not one feature:**

| | what it is | cost |
|---|---|---|
| **pick an album** | list `PHAssetCollection`s, import that collection's assets | small — a list and a fetch |
| **select photographs** | a multi-select grid over a candidate set, with the trip previewed as it changes | a real UI, and the interesting design question is what it previews |

**Recommend the album path first.** It answers Chiu's actual complaint at a
fraction of the cost, and many people already keep a trip as an album. Free-form
selection is worth doing but is a design pass, not a flag.

**Related machinery that already exists:** the Limited Photo Library path already
shows a banner and a limited-library picker (Phase 3), so there is precedent for a
picker in this flow — and Limited Photo Library is itself a §6b gate item, so the
two will be exercised in the same sitting.

---

## Open questions — none decided

- **Does a crossing count as a presented stop** for the earned-stop rule, or is it
  free? It has a duration and it occupies film time; if it is free the film runs
  long, and if it is priced the destination loses a place.
- **What does the map show under a crossing** whose midpoint no installed region
  covers? Options none of which is chosen: fly over a neutral field with no base
  map; fly over the destination region's edge; merge the two regions into one
  PMTiles; or build a region per trip.
- **Multi-leg journeys** — a trip with two flights, or a flight plus a ferry, is
  not obviously N=2. How many discontinuities before the film is a list rather
  than a journey?
- **The return leg.** A round trip ends where it began; whether the film flies home
  or ends at the destination is a story question nobody has asked.
- **Does the seagull carry the brand or dilute it?** Using the logo as a diegetic
  sprite is a brand decision as much as a UI one.

## What must not happen

- **Do not relax the camera continuity gates** to let a discontinuity through. A
  narrow, explicitly narrated exemption, or nothing.
- **Do not reintroduce per-act framing** for anything other than a crossing the
  film shows the viewer.
- **Do not let the classifier guess.** The seagull is the answer to uncertainty;
  a confident wrong sprite is worse than an honest unknown one.
- **Do not widen `pace_unknowable_gap_s`** to make speed classification work.
- **Do not scatter `import MapKit`.** One file, one seam, as `StopGeocoding` did.
- **Do not treat photo selection as the fix for cross-region trips.** It is user
  control; the product still has to behave when it is not used.
