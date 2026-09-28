# Reference — Phase 4 scope, the snapshot freeze, and the camera

Current, load-bearing reference. `Docs/_archive/eng-session-camera-arc.md` cites the
freeze recorded here, and this carries reasoning `Docs/current-state.md` does not.
**Do not delete it into current-state without absorbing the reasoning first.**

*Moved verbatim out of `HANDOFF.md` on 2026-08-31 when that file was put on a
300-line budget (`Scripts/check-doc-budget.sh`). Nothing was edited; `HANDOFF.md`
carries the live summary and points here.*

---


*Current, load-bearing reference, moved here when `CLAUDE.md` became a boot
file. `Docs/_archive/eng-session-camera-arc.md` cites the freeze recorded below.*

### Phase 4 scope (Chiu 2026-08-15)

Chosen over productisation deliberately: *"方便的產品都沒有這是足夠好的作品更吸引
人"* — a good enough artefact matters more than a convenient product, so the films
come first and export convenience is discussed after. Reordered 2026-08-15 around
the first outside feedback: **nobody mentioned the map; the most common request
was to change the vehicle.**

1. **Vehicle sprites** — the top community request, and the prerequisite for the
   cross-region plane/ship/seagull. The 8-direction technique and its art
   constraints are in `Docs/_archive/handoff-recap-visuals.md` §3; swapping a set is
   already a pure asset swap.
2. **Cross-region flight display** — `Docs/cross-region-journeys.md`. Every
   overseas trip hits this on device, because the app imports a date range from
   the whole library while the desk fixtures were hand-curated folders.
3. **Export that survives** — import and export must be **interruptible,
   observable and budgeted**. One design problem, not five fixes: the import
   cancel path, progress reporting, a trip-level routing budget, the unbounded
   date range, and the month-reset at `ImportSheet.swift:133`.

   ⚠️ **Measured 2026-08-15 — the obvious lever is the wrong one.**
   `RecapSnapshotBudgetTests` on the real Miyakojima dump (offline, all legs
   inferred): an 88 s / 2,640-frame film costs **191 snapshots — 151 of them in
   the 9 s opening**. The opening is 10% of the film and **79% of the snapshot
   budget**, because `RecapRenderLoop` snapshots it *every frame*
   (`movingUntilFrame = openingS × fps`) while the body gets one per interval.
   `keyframe_interval_frames` 15 → 30 therefore takes 191 → 176, **−8%**, not
   half. Running the opening at the coarse interval instead would be ~58
   snapshots, ≈3.3× cheaper — *derived from the measured split, not itself
   measured*. (Refined by the 2026-08-21 findings above: cost the export as the
   number of **distinct camera values**, not frames ÷ interval — the 151 is
   5 s of motion, not 9 s of opening.)

   🔓 **LIFTED 2026-09-01 — read this before the paragraph below.** Chiu judged
   the Pass 1 render and it merged (PR #26). Crop-scaling did not tune either
   number, it **removed their consumer**: snapshots are planned by
   `RecapSnapshotStations`, and `keyframe_interval_frames` now has **no shipping
   reader at all** (VERIFIED 2026-09-01). The measured 3.3× the paragraph below
   reasons about was superseded by a measured **2.1× fewer snapshots and 5.6×
   less wall clock** on the whole round (ADR 2026-08-31 (b)). The text below is
   the record of why the numbers were held, not a live instruction.

   🔒 **Both numbers were frozen — a recorded fact, not a pending change**
   (Chiu 2026-08-15). Neither `keyframe_interval_frames` (15) nor the opening's
   every-frame interval is to be touched, and the three-way render comparison is
   not owed. They were held for a design conversation about **how the camera
   crosses large spatial gaps** — the opening's panorama-to-detail move and the
   cross-region flight are the same problem.

   ➡️ **That conversation happened on 2026-08-21. The design is
   `Docs/camera-arcs.md`** (the *contained arc*; findings above; first
   engineering session `Docs/_archive/eng-session-camera-arc.md`). **The freeze still
   stands** — the design makes both numbers *irrelevant to an arc* rather than
   tuning them, so neither gets a new value, and nothing changes until Chiu has
   judged the Pass 1 render.

**Map work is NOT in Phase 4.** Tiles, labels and the tile server all left the
roadmap with the 2026-08-15 substrate ADR. What Chiu wants from "big cute place
names" is a **Kamome-drawn overlay** — iceboxed as "Place names as narrative
rhythm", substrate-independent, and the app already geocodes every stop.

**Routing is Geoapify — CLOSED 2026-08-20** (`Docs/decisions.md` 2026-08-20
(a)–(d); `Docs/_archive/routing-provider-selection.md` is the record of what was asked,
not an open question). §0's cost was accepted 2026-08-16 and stands. The scaling
trap that forced it: a self-hosted OSRM only routes the regions it preloaded — a
friend's Tokyo trip had no routable legs at all, because the Japan extract is
Kyushu. Snap-radius history: the 500 m radius was measured to be the wrong
mechanism — read `Docs/decisions.md` 2026-08-20 (d) before citing any older
snap-radius text.

### Camera architecture (rebuilt 2026-08-01 → 2026-08-02, Chiu)

The recap camera was rebuilt after the NZ device film. `CameraPathActs` framed
each act to its own bounds while timing came from a separate clock, so motion
came from **data shape** rather than spatial continuity. What replaced it, all
of which is load-bearing:

- **`FollowCamera`** — a dead-zone dolly, pre-simulated once at build time so
  `cameraFrame(atTime:)` stays pure and random-access. Inertia is simulation
  state, never a post-process. A world-bounds clamp keeps the frame inside the
  route's extent, and **yields to the subject** when the two disagree.
- **One span per trip**, from `RecapDurationPlan.bodySpanM`. Never adaptive —
  recomputing mid-film is what produced a 97× zoom-out before the end card.
- **`body_span_padding` (0.6) sizes the body separately** from the establishing
  shot (2026-08-08, superseding the 2026-08-02 wide baseline): the establishing
  shot frames the whole trip, the body follows the vehicle inside it.
  `camera_pan_window_fraction_per_s` is **0.35 and a genuine floor** (ADR
  2026-08-09 — an older note saying "stays 0.05" was stale).
- **`CameraPathActs` keeps only discontinuity detection** — a ferry is a fact
  about the journey; framing was a decision about the camera.
- **The opening** is country → region → body, the country beat framed to fit
  *inside* the tile extent, dropped entirely when the region is no wider than
  the trip. Held beats capped at ~1 s after the title card; the closing zoom is
  skipped when the body frame already matches the regional beat.
- **The ending** pulls back past the body (`end_reveal_padding` 1.9);
  `end_card_style` selects `.full` (free) or `.minimal` (held for a paid tier).

**Two gates guard all of it** (`RecapCameraContinuityTests`, offline, every
fixture, `base_url=""` for worst-case inferred legs):
- consecutive frames share ≥50% of their ground (measured ≥97%);
- the subject never passes 80% of the half-frame (measured 43–54%).
Do not relax either — they exist because a still frame is trivially correct and
a strobing one is only wrong *between* frames.
