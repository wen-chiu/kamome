# The contained arc — how the camera crosses a gap

**Status: design recommended by the PO/architecture session (2026-08-21), NOT
decided, nothing built.** A scoped implementer guide in the shape of
`Docs/cross-region-journeys.md`, not an ADR. **No entry goes into
`Docs/decisions.md` until something has been rendered and judged** — the standing
rule that unverified work is never written as settled architecture.

This document resolves the design conversation `CLAUDE.md` Phase 4 item 3 held
open: *"how the camera crosses large spatial gaps — the opening's
panorama-to-detail move and the cross-region flight are the same problem, and
will be designed together rather than tuned separately."*

Read `Docs/cross-region-journeys.md` first — its requirements (Chiu 2026-08-14)
are inputs here and are not re-opened. This document is the **presentation** half
it left open, plus the opening, which turns out to be the same thing.

⚠️ **Code facts below were read on 2026-08-21 and are named by symbol, never by
line number**, because other sessions are working in this tree. Re-verify each
one before relying on it. As of 2026-08-21 nothing under `Core/ExportEngine` was
modified in the working tree, so this work did not collide with the routing or
sprite sessions at the time of writing.

---

## 1 · The premise this corrects

The two moves were held together on the belief that both "cross a distance far
larger than the frame." **The opening does not cross distance.** On the shipped
path (`establishing == nil`, since MapLibre was parked) `buildWideOpening` frames
both wide beats **concentric with the trip**: the country beat at trip-bounds
centre × `country_view_padding` (2.2), the regional beat at the same centre ×
`wide_span_padding` (1.5). The 2026-08-08 `wideBeat` correction exists precisely
to stop the opening translating — *"a zoom, or nothing at all, but never a journey
across the map."*

So the opening crosses **scale**; a flight crosses **distance**.

What actually unites them is narrower and more useful:

> **The destination is not visible in the source frame.**

There is one move that solves that, and it solves both: open out until source and
destination are in one frame, then close in. **The opening is the degenerate case
where the two ends are the same place.** That is why unifying them is safe rather
than forced — and it is also why the unification stops at the camera (§6).

## 2 · The cost model this design is built on

`RecapSnapshotBudgetTests` measured, on the real Miyakojima dump, offline:
an 88 s / 2,640-frame film costs **191 snapshots — 151 of them in the 9 s
opening**. `CLAUDE.md` records this and freezes both `keyframe_interval_frames`
and the opening's every-frame interval pending this conversation.

**The 151 is not because the opening is 9 s long.** `RecapRenderLoop` keys its
snapshot cache by `CameraFrame` value, so a held frame is one snapshot however
long it is held. The opening's beats are `opening_country_s` 3.0 + `zoom_transition_s`
2.5 + `opening_regional_s` 1.0 + `zoom_transition_s` 2.5 = 9.0 s, of which
**5.0 s is moving camera**:

```
1 (country hold) + 75 (2.5 s ease) + 1 (regional hold) + 75 (2.5 s ease) = 152
```

against 151 measured — the model reproduces the measurement to within one
snapshot. Therefore:

> **Export cost is the number of distinct pictures the camera visits.** Not the
> film's length, not the opening's length. Holding is free; only moving costs.

Shortening the opening buys almost nothing. Only changing **how motion is
rendered** does. Everything below follows from this.

## 3 · The primitive: a contained arc

One camera move, defined by a source frame and a destination frame:

1. open out to an **apex** — the smallest frame containing both footprints, padded;
2. translate while wide;
3. close back in.

Span interpolates **geometrically** — `CameraPath.lerp` already does this, and its
comment already explains why (equal metre-steps burn the apparent zoom in the
first third and then crawl).

The invariant, and the whole design in one sentence:

> **At no moment does the screen contain ground that the previous moment did not
> also contain, somewhere in it.**

Three consumers already exist in the tree, each written separately today: the
opening's closing zoom, the end reveal (`end_reveal_padding` 1.9 — an arc
outward), and a crossing (currently a smear at body span). **This is consolidation
of three existing cases, not a speculative abstraction** (`Arch.md` §6,
`PO.md` "simple + explicit + replaceable").

### What it looks like, for a crossing

The car reaches the airport and parks. The frame holds a beat. Then the ground
begins to fall away — the same picture, only more of it, the island shrinking
toward the middle of the screen while the sea opens around it. Somewhere in that
pull-back the destination slides into frame from the far edge; by the widest point
both islands are on screen at once, small, with the dashed line between them and
the plane starting along it. The plane crosses. Then the ground comes back up, the
arrival island growing until it fills the frame, and the camera is already
following the car — the same follow camera, the same span, as if it had never
left. **There is no cut.**

## 4 · What the arc is fitted to: the local journey

`Docs/cross-region-journeys.md` reframes a journey as **N local journeys joined by
discontinuities**. That reframing is what makes one primitive serve every trip:

> Every arc is fitted to a **local journey**. The opening arc closes into the
> first one; a crossing arc goes from one to the next; the end reveal opens out of
> the last one.

### Case A — a local trip (N = 1). **Nothing changes.**

The whole trip is the one local journey. There is exactly one arc — the opening —
fitted to the trip's own bounds, exactly as `buildWideOpening` does today.

**Today's opening is already a contained arc.** Verified by geometry on
2026-08-21: `FollowCamera`'s world clamp keeps the body frame's centre within
~0.06 × fitting-span of the trip centre, and the body half-width is
~0.44 × fitting-span, so the body footprint's edge lands at ~0.50 against the
regional beat's 0.75 — contained, on both axes. The two wide beats are concentric
by construction.

**Consequence: a user who never leaves the island sees an identical film.** Only
the rendering changes (§7). This is what makes Pass 1 in §10 film-invariant and
therefore cheap to judge.

### Case B — a cross-region trip whose first segment is a real journey (N ≥ 2)

Opening arc into segment 1 → one crossing arc per discontinuity → end reveal.
The opening establishes on the **first local journey, never the union bounding
box** (`cross-region-journeys.md` requirement 5).

The film therefore opens on the departure. That is honest and it is what makes
the flight mean anything: **you cannot arrive somewhere if the film never showed
you leaving.**

### Case C — a cross-region trip that *begins* with the crossing

The common real shape: photographs start at the departure airport, so segment 1 is
one point. Fitted to it, the opening would establish on a 1,500 m view of a
terminal (the `camera_span_m` floor binding). This is almost certainly what the
first device film hit.

**Rule: when the first local journey is degenerate, the opening arc *is* the first
crossing arc.** The film opens at the apex — both places on screen, the dashed
line between them — the sprite crosses, and the camera closes into the
destination. One move, not two.

This is worth noticing rather than merely tolerating: it is exactly the
"panorama → detail" the opening was always trying to be, except the panorama is
**earned** — it is showing the actual journey rather than a padded rectangle
around a bounding box.

**Open: what counts as degenerate.** A stop count, an extent in metres, or "no
routable leg". Recommend deriving it from extent against `camera_span_m` rather
than adding a tunable. Not decided.

## 5 · Body span, and the per-act-framing line

**This is the sharpest risk in the design and it must not be blurred.**

`RecapDurationPlan.bodySpanM` floors the span at
`routeDistanceM / (travelS × camera_pan_window_fraction_per_s)`. On a cross-region
trip `routeDistanceM` includes the crossing, so **the flight's 450 km is what
forces the destination to render as a smudge** — symptom 2 of
`cross-region-journeys.md`, in exact code terms. Giving the crossing its own beat
removes its distance from the term.

The tempting next step — a span per segment — is **per-act framing, rejected
2026-08-02 at the cost of a camera rebuild.**

**Recommendation (conservative, and the one to build):**

> **One span per trip still, but derived from the largest local journey rather
> than from the union.**

This keeps the locked rule literally intact ("One span per trip, from
`RecapDurationPlan.bodySpanM`. Never adaptive"), fixes the actual symptom, and
needs no new concept. A short segment framed at the large segment's span is
handled by machinery that already exists: `FollowCamera`'s world clamp collapses a
route narrower than the window to a single centred framing, which its own comment
describes as the desired behaviour.

**Open (owner decides from a render): is a span per local journey needed?** It is
reachable later without rebuilding the act camera, because the arc *shows the
viewer* the change of scale — which is precisely what the 2026-08-02 failure
lacked. Do not build it pre-emptively. If renders show short segments framed too
wide, that is the evidence to reopen it, and it should be reopened as a product
decision, not a tuning pass.

## 6 · What is NOT unified

The camera is one primitive. **The narration is not**, and forcing it would be the
mistake:

| | opening arc | crossing arc |
|---|---|---|
| subject on screen | no — parked at the route's start and deliberately undrawn | yes — the classified sprite is the point |
| what rides it | the title card | a dashed inferred leg + plane / ship / seagull |
| apex comes from | a product choice (how much context to show) | geometry (it must contain both ends) |
| duration comes from | the opening budget | the duration plan (see the open question in `cross-region-journeys.md`) |

That split is the existing seam — overlay moments are timeline events
(`decisions.md` 2026-07-17), and `LinearTimeline` / `RecapOverlayRenderer` own
them. **The camera must not learn what a plane is.**

One genuine difference follows from the table, and it sets the parameters:

> **The opening is motion without a subject; the crossing is motion with one.**

Motion nobody is following wears out — this is the "frozen opening" symptom the
2026-08-01 rebuild fought, and why the third opening beat was deleted. So the
opening's arc should be **short**, and a crossing's arc **can be long**.

### The middle beat should go (STALE, not a reversal)

With `establishing == nil`, the country and regional beats are **the same shot
1.47× apart, sharing a centre** (2.2 vs 1.5). They survive
`opening_collapse_zoom_ratio` (1.25) on a technicality and buy a 1 s hesitation
plus a second 2.5 s ease.

The two-beat structure was justified by the region being a genuinely different
subject — `decisions.md` 2026-08-09: *"New Zealand's country beat survives because
its region is the whole country while the trip is the South Island."* With tiles
parked (2026-08-15) there is no region. **The beat is stale as a consequence of
the substrate ADR, not as a reversal of the camera ADR.** When tiles return, the
region beat comes back as the arc's *start*, not as a separate beat.

`target_zoom_ratio` is untouched by this: the established span still comes from
the first beat, so `body = established / 2.5` is unchanged.

## 7 · The rendering rule: an arc is scaled, never cross-faded

Because the arc is contained, **every intermediate frame is a sub-rectangle of the
apex snapshot.** So:

> Render an arc by **cropping into a wide snapshot**, not by blending two
> snapshots. Take a **zoom station** roughly every 1.5× of zoom for sharpness, and
> cross-fade only at a station boundary — where both snapshots are the *same
> framing* and differ only in resolution.

Three consequences, in order of importance:

1. **Cost stops depending on the arc's duration** and depends only on its zoom
   ratio. How long the move takes becomes a free film decision.
2. **`keyframe_interval_frames` stops being a quality knob for arcs.** The
   interval exists to bound *geometric* mismatch in a cross-fade; a scaled arc has
   no geometric mismatch to bound. A station-boundary cross-fade is a sharpness
   resolve, not a double exposure.
3. **The map softens; the film's own graphics do not.** Trail, sprite, labels and
   chrome are drawn per frame through `MapSnapshot.point`, so only the base map
   is resampled. Whether a soft map under sharp Kamome graphics reads as on-brand
   or as broken is **a look, and must be judged, not asserted** (§10).

**Architecturally this is confined to Layer 1 and the compositor.** `MapSnapshot`
already carries its own projection closure, so a cropped view is expressible as a
*derived* `MapSnapshot` — same `CGImage`, composed projection — and the
compositor's draw call takes a source rect. The Story layer, `LinearTimeline` and
the camera math are untouched. **The move (§3–§6) and the rendering (§7) are
independent changes and must be shipped and judged separately** (§10).

### ⚠️ Updated 2026-08-28 — the projection this rests on gained a second half

PR #18 changed `MapKitSnapshotProvider` underneath this section. Re-read it before
building anything here; the design still holds, but the arithmetic has one more
term.

- **`point(for:)` answers in the *point canvas* MapKit was given, not in pixels.**
  The provider now composes a point→pixel correction (`pixel(_:displayScale:)`),
  and the canvas is `pointSize(widthPx:heightPx:displayScale:)`. So a crop-scaled
  arc composes **two** corrections, not one, and the *derived* `MapSnapshot` this
  section calls for must carry both. A missing multiply here is invisible in a
  still frame and drifts in motion — which is exactly why that function is named
  rather than inlined.
- **`pointSize` throws rather than rounding** when the scale does not divide the
  frame exactly, and `displayScale` is an **`Int`** for the same reason. A crop
  factor is therefore not free: whatever geometry an arc asks for has to stay
  expressible. (1.5 divides 1080×1920 arithmetically but is not reachable without
  widening the type against a documented reason.)
- **MapKit may return more pixels than were asked for.** Measured once on
  2026-08-22: a 540×960 pt canvas came back at 1620×2880 px — 3×, the simulator's
  native scale, not the 2 requested. Not reproduced in 18 probe snapshots; trigger
  **UNKNOWN**. For this design that is mostly *good* news — a station snapshot may
  hold more real detail than its requested scale implies, which is the resource
  §7 spends. **But an arc must read a station's actual pixel dimensions back
  rather than assuming them**, and it must not defeat the provider's guard, which
  rejects a **non-uniform** raster because no single factor can correct one.
- **Appearance is now a required provider input** (ADR 2026-08-27, merged in
  PR #21). `MapKitSnapshotProvider(appearance:)` has **no default**, precisely so a
  test cannot inherit the simulator's setting, and `RecapStyle.modernMinimal` is now
  a function of the appearance too — the light trail is `#FF8A5B`, the dark one the
  cyan, and the glow stays off on both. A renderer that cannot honour an appearance
  declares `MapRendererCapabilities.fixedAppearance` and wins.
  **Pass 1 therefore passes one explicitly and holds it across all three clips** —
  one variable, and the variable is how the base map is produced. Say which you
  chose.

Known artifact to expect and judge: a station snapshot cropped in shows *that
station's* level of map detail magnified — labels and road widths scale up, and no
new roads appear until the next station loads.

## 8 · The two gates: **no exemption, none at all**

Not a narrow one. The design removes the need for one instead of widening it.

**Overlap gate.** `RecapCameraContinuityTests.groundOverlap` divides by the
**smaller** footprint, deliberately and with its reasoning in the test: *"a pure
zoom scores 1.0 — and it should. Zooming loses no geography."* A
containment-preserving move is therefore continuous **by the gate's own metric**,
at any zoom ratio.

Assert the invariant rather than a threshold:

> For any two frames sampled a snapshot interval apart, **the tighter must lie
> entirely inside the looser.**

Stronger than the 0.50 / 0.40 floors, and cheaper to check.

**Safe-zone gate.** Unchanged for the opening — the scan starts at
`journeyStartS`, and the subject is parked and undrawn before it. For a crossing,
the subject sits at `1 / padding` of the half-frame at the apex, so **apex padding
≥ 1.25** satisfies the 80% limit; at 1.5 it lands at 67%.

The assertion an implementer must add: **size the apex so `CameraPath.confine` is
a no-op.** A confine that fires drags the frame off the arc and breaks
containment — the clamp and the arc would be fighting.

**`permittedCutTimesS`.** It should become unreachable, and the gate should be
made to **fail rather than forgive** — i.e. assert that no violation is excused.

Here is the connection `cross-region-journeys.md` does not spell out, and it is
why requirement 4 is load-bearing in a second way:

> **The seagull — the honest sprite for an unmodelled crossing — is what makes
> "every discontinuity is narrated" true, and that is what lets the continuity
> exemption go to zero instead of being written.**

Without an honest fallback, an un-narrated gap would still need forgiving.

⚠️ **Watch one thing.** `act_split_km` (25) may be the right threshold for
"insert an arc" and the wrong one for "send a bird" — a GPS dropout inside a
continuous drive is not a journey between places. If they diverge, **raise the one
threshold; never introduce a second.** Two thresholds is how `act_split_km`
becomes a tunable nobody can reason about.

**Unknown, and cheap to close:** whether any committed fixture currently exercises
`permittedCutTimesS` at all. The gate already prints the count per fixture
(`%d permitted cuts`) — one free line from a run someone is making anyway.

## 9 · What it costs

Measured rows are from `RecapSnapshotBudgetTests` on the real Miyakojima dump,
offline. Derived rows are arithmetic over the §2 model and are **not measured**.

| | opening | body | total | vs today |
|---|---:|---:|---:|---:|
| today (**measured**) | 151 | 40 | **191** | — |
| `keyframe_interval_frames` 30 (**measured**) | — | — | 176 | −8% |
| opening at the coarse interval (the held lever, derived) | ~18 | 40 | ~58 | ≈3.3× |
| **arc + crop-scale** (derived) | **~3–5** | 40 | **~45** | **≈4.2×** |
| …plus one crossing arc (derived) | | | ~55–63 | ≈3.0–3.5× |

**The 3.3× that was being held is not spent on this design — the design subsumes
it.** The lever was held because optimising the implementation of a transition
about to be redesigned is waste. That was correct, and it turns out the redesign
removes the reason the lever existed at all (§7, consequence 2).

Both frozen numbers can therefore be **unfrozen by being made irrelevant** rather
than by being tuned. Neither needs a new value.

**This touches `Docs/pre-launch.md` items 3 and 5.** Export time is snapshot-bound
at 0.72–1.55 s per snapshot on device, so a ~4× reduction in snapshot count is a
product-level change to export duration, and the export-time estimate in item 5
must count *distinct camera values*, not `frames ÷ interval` — the same arithmetic
error `RecapSnapshotBudgetTests` was written to correct.

## 10 · How to build and judge it — two passes, one thing at a time

Chiu decides from rendered output. These are deliberately separable so each pass
changes exactly one variable.

### Pass 1 — rendering only. The film does not change.

Crop-scale the opening **exactly as it stands today** (§4 Case A: it is already a
contained arc). No change to pacing, duration, beats, spans or the camera.

**The cheapest thing to render, and the only question reasoning cannot answer:**
one fixture's **opening, 9 s, three ways, side by side** —

1. as-is, fine-sampled (151 snapshots);
2. coarse interval, cross-faded (the janky baseline);
3. crop-scaled from ~3 zoom stations.

270 frames, not a full export. The cheapest possible version of (3) needs no
pipeline change at all: **one snapshot at the country span, cropped in over 9 s,
no overlays** — a throwaway harness.

**What it decides:** does a scaled zoom read as a dolly, and how soft is too soft.

### Pass 2 — the move. This one is a product change and needs sign-off.

Only if Pass 1 reads right: drop the middle beat, make the opening one hold plus
one arc, build the crossing arc on the same primitive, and take the crossing's
distance out of the body span (§5, conservative option).

The opening goes ~9.0 s → ~6.5 s, which feeds `RecapDurationPlan` and changes
every film's shape. **Judge it on a cross-region trip, not a desk fixture** — the
desk fixtures are hand-curated folders and do not contain the crossing
(`cross-region-journeys.md`, "the part that is worse than one trip").

## 11 · Open questions — none decided

- **Case C's degenerate threshold** (§4) — what makes a first segment too small to
  establish on.
- **Span per local journey** (§5) — conservative option first; reopen only on
  render evidence.
- **Does the opening-on-the-departure read right** (§4 Case B) — six seconds of
  Taoyuan before a Miyakojima film is a story judgement, not a geometry one.
- Everything `Docs/cross-region-journeys.md` §"Open questions" already lists —
  whether a crossing is a presented stop, multi-leg journeys, the return leg, and
  whether the seagull carries the brand or dilutes it. None are answered here.

## 12 · What must not happen

- **Do not relax either continuity gate.** The design's whole claim is that it
  needs no exemption; a threshold change means the arc is not contained, and the
  arc is what should be fixed.
- **Do not re-introduce per-act framing.** §5 is the line; a span that changes
  where the film does not show the viewer why is the 2026-08-02 defect.
- **Do not make the camera aware of transport modes.** §6.
- **Do not tune `keyframe_interval_frames` as part of this.** It becomes
  irrelevant to arcs; changing it is a separate judgement about the body.
- **Do not ship §7 and §3–§6 as one change.** Two variables, two renders, or
  neither can be judged.
- **Do not write any of this into `Docs/decisions.md`** until a render has been
  judged.
