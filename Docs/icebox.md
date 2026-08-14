# Icebox — ideas deliberately not in the current sprint (spec §1.4/§9)

Entries move out of here only via a spec version bump.

## Creator b-roll export (post-v1 wedge candidate)
Travel creators pay for tools and their shares self-advertise. But they want
**material control, not finished TikToks**: 4K, transparent-background,
speed-adjustable map-animation b-roll that drops into their own edit. Higher
price point than consumer per-trip export (§1.6). Do not build a template
library for them.

## Group trips (v2 at the earliest)
Merging several phones' tracks into one recap is genuinely viral, but sync +
merge + everyone-must-install is a cold-start and infra trap for a solo dev.
Revisit only after fork loop (Phase 6) proves organic sharing.

## Auto trip detection (arm-nothing capture)
Passive tier v2: detect trip start with zero user action (first SLC fix far
from home region → "looks like you're on a trip — recording?" notification).
Needs the Capture Beta tier proven first; also raises the App Review bar (§6 —
current posture is "only between explicit Start/End").

## Google Timeline importer — dropped as redundant (owner 2026-07-20)
Was Phase 4 scope; cut. Photo-EXIF import already reconstructs *past* trips and
in-app capture (Capture Beta) covers *new* ones, so a Timeline parser adds
Google-export format-drift maintenance for little unique value. The
`imported_timeline` `trip.source` value stays reserved for forward-compat only.
Thaw only if real user demand for Timeline import appears. (`decisions.md`
2026-07-20 Replay MVP repositioning.)

## Subscription vs. transactional — decided, kept for the record
$4.99/mo subscription dies of churn at 2–4 trips/year usage. Transactional
per-trip export + yearly unlock-all + creator tier is the model (§1.6).

## Premium video styles / fork-count analytics
From spec v1.2 §1.6 — still parked.

## Video clips in the recap (post-P3-gate candidate)
Auto-excerpt short clips from videos the user shot mid-trip and play them at
their stop's hold (the clip replaces the photo card; the hold stretches to
clip length, still counted inside `export.max_hold_fraction`). Fits the
minimum-effort vision — zero editing by the user. Hard constraints when
thawed: **deterministic** excerpt selection (seed by trip id; §4.5 is a
deterministic frame pipeline with golden-frame tests, and re-exporting must
reproduce the same video), 2–3 s per clip (tunable), muted (consistent with
the no-music call), cap clip count. Blocked on: §4.5 steps 2–5 landed and the
<90 s render budget measured — per-frame video decode + composite is the
single biggest render-cost risk in the whole pipeline. (Decision record:
`decisions.md` 2026-07-17.)

### Place names as narrative rhythm (2026-08-02, Chiu)

Brief landmark title cards — "Lake Tekapo" — inserted between travel and stop
beats as a storytelling device. **Distinct from static map labels**: this is
narration with its own timing, not annotation the map carries continuously, and
the two answer different questions ("what am I arriving at" vs "where am I
right now"). Raised while comparing span/label options for the legibility
problem; parked so the two are not conflated. The static-label counterpart is
scoped in `handoff-P3.5.md` §"Map reference labels" — wanted, blocked on a
fontstack, and to be done as a real pass rather than an afterthought.

### Drive-by photos for thin stops (2026-08-14, Chiu)

A stop carrying only one photograph does not make the car park. The journey keeps
moving and the photograph runs along the top or bottom of the frame while travel
continues. Chiu's framing: *"會不會讓畫面更流暢"*.

**Cheaper than it sounds, because the architecture was built for it.** The
2026-07-17 decision record already names this: overlay moments are *timeline
events* built alongside `CameraPath`, explicitly so that rendering is **not**
hardwired to `holdingStopIndex`, and "route-attached photo fly-bys" are named
there as the second kind. `CLAUDE.md` carries it as a P3 stretch deferred until
the render budget was proven. So this is building the second event kind the
timeline was designed to carry, not re-architecting anything.

**It is also a real answer to the depth-versus-breadth question** (`HANDOFF.md`,
duration scaling). A one-photograph stop currently costs the full presentation
overhead — the label lead, both deck zoom ramps, park in and out — about 3.4 s of
dwell to show one picture. A drive-by costs approximately **zero dwell**, because
it plays during travel that was already being paid for. That frees budget for the
stops that deserve dwelling, instead of forcing a choice between more places and
more photographs per place.

**Interaction to respect when this is thawed:** it changes what *counts* as a
presented stop, which is the input to the duration rule — not the rule's shape, so
the two are compatible. Build the rule first; do not let the rule assume every
presented stop costs a park.

### `first_stop_dwell_scale` is scale-dependent in effect (2026-08-14)

The first stop of a film gets `first_stop_dwell_scale` (0.55) of the dwell a later
stop earns, because the prologue has just ended and no travel has been shown yet —
a full-weight first stop makes the film feel stuck right as it starts. That
rationale is about **pacing at the top of a film and is scale-invariant in
intent.**

**Its effect is not.** On a long film 55% of a generous dwell still clears
`deck_photo_min_hold_s`; on a short one it falls under. Surfaced when duration
started scaling with trip size (2026-08-14): a 4-stop trip earns a 60 s film and
its decks come out **[2, 6, 6, 6]** — the first stop alone drops below the floor.

**Chiu accepted that outcome rather than fixing it**, on the grounds that no
small-trip film has ever been rendered and deciding a film's depth blind from
arithmetic is the thing that whole process exists to avoid.
`RecapDeckBudgetTests.testASmallTripShowsWholeDecks` was updated to the new
expectation deliberately.

**When it is thawed:** the fix is a floor on the *first stop's* dwell rather than a
flat fraction, or a scale that relaxes as the film shortens — a different knob from
duration, and one that should be judged on a rendered small-trip film rather than
on the arithmetic that surfaced it. Rejected at the time: raising
`total_duration_min_s` to ~71 s, which would have flattened the bottom of the
duration range and partly undone the scaling it was meant to protect.

### Photo eligibility filters — documents, and a share-safe cut (2026-08-14, Chiu)

Two requests, one subsystem. Today **nothing filters photographs at all** — no
`mediaSubtypes` check and no Vision anywhere in the tree — so a photograph of a
menu or a signboard competes with a landscape on equal terms.

1. **Exclude documents.** Chiu, from watching the three films: photographs of
   landmark plaques and restaurant menus surface in the decks.
2. **A share-safe cut** — scenery only, no faces and no documents, so a film can
   be published without exposing anyone who would rather not appear.

**Feasibility splits unevenly, and the split is the useful part:**

| predicate | mechanism | cost |
|---|---|---|
| screenshots | `PHAsset.mediaSubtypes.contains(.photoScreenshot)` | **nearly free** — one predicate at import |
| documents/menus photographed with the camera | Vision `VNRecognizeTextRequest` + a text-density heuristic | real work; these are ordinary photographs, not screenshots |
| faces | Vision `VNDetectFaceRectanglesRequest` | comparable to the above, same insertion point |

All three are **on-device** and involve no network, so this strengthens rather
than strains the §0 posture.

**Architecturally it is one clean stage**: a photo-eligibility predicate between
import and `StopPhotoAllocator`, with each rule independently toggleable. It does
not touch the timeline, the camera, or any renderer.

**The rabbit hole to price before starting** is not the API, it is (a) running
Vision across a real library — Iceland's dump is 2300 photographs, so this must be
bounded, cached and off the render path — and (b) threshold tuning, because a
false positive silently eats a good photograph and nobody will know why. The
screenshot half has neither problem and could be pulled forward on its own if a
cheap win is wanted.

### iCloud photo download for the recap deck (option B, 2026-08-02, Chiu)

Option C landed: the resolver downloads nothing and the recap screen *names* the
shortfall (`recap_photos_missing`). B is the real behaviour — fetch the
originals so the deck is never blank — and it is a feature, not a flag flip:
`warm` loops every deck photo sequentially, so an unbounded download behind a
progress bar that reports *render* progress would replace a visible bug with an
invisible hang. It needs its own phase (progress, cancel, graceful fallback to
the grey matte).

**Do the copy-catalog pass at the same time** (Chiu): zh-Hant first, as the rest
of the app's strings are. Flagged then because B is the first thing since the
import sheet to add real user-facing prose.
