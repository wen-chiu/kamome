# Findings — the contained-arc camera design (2026-08-21 PO session)

The working analysis that produced `Docs/camera-arcs.md`. **Nothing here is
settled** — no entry goes into `Docs/decisions.md` until a render has been judged.
Archive this once camera-arc Pass 1 has run and been judged; the design doc is
then the surviving form.

*Moved verbatim out of `HANDOFF.md` on 2026-08-31 when that file was put on a
300-line budget (`Scripts/check-doc-budget.sh`). Nothing was edited; `HANDOFF.md`
carries the live summary and points here.*

---

## Findings — PO/Architecture session (2026-08-21)

**Context.** Chiu opened the design conversation `CLAUDE.md` Phase 4 item 3 held
frozen: how the camera crosses a large spatial gap — the opening's
panorama-to-detail move and the cross-region flight, designed together rather than
tuned separately. The design is `Docs/camera-arcs.md`; the first engineering
session is `Docs/eng-session-camera-arc.md`. These are the findings that came out
of it, ordered by what can go wrong silently.

**Nothing here is settled.** No entry goes into `Docs/decisions.md` until a render
has been judged.

---

### 1. The 151-snapshot opening is 5 seconds of motion, not 9 seconds of opening

**Decision.** Cost the export as **the number of distinct pictures the camera
visits**, not as `frames ÷ interval` and not as a function of the opening's
length.

**Why.** `RecapRenderLoop` keys its snapshot cache by `CameraFrame` value, so a
held beat is one snapshot however long it is held. The shipped opening is
`opening_country_s` 3.0 + `zoom_transition_s` 2.5 + `opening_regional_s` 1.0 +
`zoom_transition_s` 2.5 = 9.0 s, of which only 5.0 s moves.

**Evidence.** Model: 1 + 75 + 1 + 75 = **152** distinct values, against the
**151 measured** by `RecapSnapshotBudgetTests` on the real Miyakojima dump. Within
one snapshot. Verified by reading `RecapRenderLoop`, `CameraPathPrologue` and
`Config/TrackingConfig.json` on 2026-08-21.

**Risk.** The obvious lever — shorten the opening — buys almost nothing, because
the holds are already free. Anyone reasoning from "the opening is 79% of the
budget" without this correction will reach for the wrong knob.

**Next.** `Docs/pre-launch.md` **item 5** (export-time estimate) must count
distinct camera values. `frames ÷ interval` is the exact arithmetic error
`RecapSnapshotBudgetTests` was written to correct, and it would under-count by
~3× on the opening.

### 2. Neither frozen number needs a new value — the design makes both irrelevant

**Decision.** Unfreeze `keyframe_interval_frames` (15) and the opening's
every-frame interval **by making them irrelevant to an arc**, not by tuning them.
Neither value changes.

**Why.** The fine interval exists to bound *geometric* mismatch in a cross-fade —
`RecapRenderLoop`'s own comment says the coarse interval "is sized for a **static**
camera". A contained arc rendered by cropping into a wide snapshot has no
geometric mismatch to bound: a station-boundary cross-fade is two identical
framings differing only in sharpness.

**Evidence.** Measured 191 total / 151 opening / 40 body; measured 176 at interval
30. Derived for the arc: ~45 total, ≈4.2×. Table with the measured/derived split
marked in `Docs/camera-arcs.md` §9.

**Risk.** The ≈4.2× is **derived, not measured**, and rests on a claim about how a
scaled zoom looks that only a render can settle. If it reads wrong, the 3.3× lever
is still there untouched.

### 3. No continuity exemption is needed — and the seagull is why

**Decision.** Do not write the "narrow, explicit exemption" that
`Docs/cross-region-journeys.md` anticipated. Make `permittedCutTimesS` unreachable
and assert that **nothing is excused**.

**Why.** `RecapCameraContinuityTests.groundOverlap` divides by the **smaller**
footprint, deliberately — *"a pure zoom scores 1.0 — and it should."* A
containment-preserving move is continuous **by the gate's own metric**, at any
zoom ratio. The exemption was needed because a crossing today is a smear at body
span; an arc is not.

**Evidence.** Read directly in `RecapCameraContinuityTests` on 2026-08-21,
including the comment explaining why an earlier draft's zoom-ratio divisor was
wrong.

**The connection `cross-region-journeys.md` does not spell out:** requirement 4 —
the seagull for an unmodelled crossing — is what makes *"every discontinuity is
narrated"* true, and **that** is what lets the exemption go to zero rather than be
written. Without an honest fallback, an un-narrated gap would still need
forgiving. Requirement 4 is load-bearing for the camera, not only for provenance.

**Risk.** `act_split_km` (25) may be right for "insert an arc" and wrong for "send
a bird" — a GPS dropout inside a continuous drive is not a journey between places.
If they diverge, **raise the one threshold; never add a second.**

**Next.** Free evidence nobody has collected: the gate already prints `%d
permitted cuts` per fixture. Whether any committed fixture exercises the exemption
at all is currently **UNKNOWN**.

### 4. The safe-zone gate is inherited, but the apex has to be sized for it

**Decision.** Size a crossing's apex so that **`CameraPath.confine` is a no-op**,
and assert it.

**Why.** `confine` is applied as a post-condition to every composed frame after
`openingEndsS` — its comment says explicitly that this "covers every beat by
construction, including any added later", so an arc inherits the guarantee. But a
confine that *fires* drags the frame off the arc and breaks containment: the clamp
and the arc would be fighting, and containment is what §3 depends on.

**Evidence.** At the apex the subject sits at `1 / padding` of the half-frame, so
padding ≥ 1.25 satisfies `camera_safe_zone_fraction` 0.8; at 1.5 it lands at 67%.
Arithmetic over `CameraPathCore.confine` and the config.

### 5. ⚠️ The body span is where per-act framing could come back

> ⚠️ **CORRECTED 2026-09-02 — the mechanism stated below was measured and is
> false.** The pan floor binds nowhere; the destination's scale comes from the
> opening. `Docs/handoff-cross-region-crossing.md` finding 1. The decision —
> one span per trip, never per segment — is unaffected.

**Decision.** **One span per trip still — but derived from the largest local
journey, not from the union.** Do not build a span per segment.

**Why.** `RecapDurationPlan.bodySpanM` floors the span at
`routeDistanceM / (travelS × camera_pan_window_fraction_per_s)`. On a cross-region
trip `routeDistanceM` includes the crossing, so the flight's distance is what
forces the destination to render as a smudge — symptom 2 of
`cross-region-journeys.md` in exact code terms. Removing the crossing from the
term fixes it without touching the locked "never adaptive" rule.

**Risk.** A span per segment is per-act framing, rejected 2026-08-02 at the cost
of a camera rebuild. It is *reachable* later — the arc shows the viewer the change
of scale, which is what the 2026-08-02 defect lacked — but only on render
evidence, and as a product decision. **Do not let it arrive as an implementation
detail of the crossing beat.**

**Next.** `FollowCamera`'s world clamp already collapses a route narrower than the
window to a single centred framing, which its own comment describes as desired. So
a short segment framed at the large segment's span is handled by machinery that
exists. Whether it *looks* right is UNKNOWN and is a Pass 2 render question.

### 6. The opening's middle beat is stale — as a consequence of the substrate ADR

**Decision.** With `establishing == nil`, the opening should be one hold plus one
arc. This is Pass 2, not Pass 1.

**Why.** The country and regional beats are **the same shot 1.47× apart, sharing a
centre** (`country_view_padding` 2.2 vs `wide_span_padding` 1.5, both framed on the
trip's own bounds when there is no region). They survive
`opening_collapse_zoom_ratio` (1.25) on a technicality and buy a 1 s hesitation
plus a second 2.5 s ease.

**Evidence.** `buildWideOpening`'s `establishing == nil` branch, read 2026-08-21.
The two-beat structure was justified in `decisions.md` 2026-08-09 by the region
being a genuinely different subject ("New Zealand's country beat survives because
its region is the whole country"). MapLibre was parked on 2026-08-15, so there is
no region.

**Risk.** This is **not** a reversal of the 2026-08-09 camera ADR — it is a
consequence of the 2026-08-15 substrate ADR. Anyone reading it as a reversal will
either defend a dead beat or reopen a settled zoom. `target_zoom_ratio` is
untouched: the established span still comes from the first beat.

### 7. A local trip's camera does not change at all

**Decision.** Fit every arc to a **local journey**. A trip with no discontinuity is
N = 1, has exactly one arc — the opening — and renders as it does today.

**Why.** This is what makes Pass 1 film-invariant and therefore cheap to judge:
the only variable is how the base map is produced. It also answers Chiu's question
directly — a user who never leaves the island sees an identical film.

**Evidence.** Today's opening is already a contained arc. `FollowCamera`'s world
clamp keeps the body frame's centre within ~0.06 × fitting-span of the trip
centre against a body half-width of ~0.44, so the body footprint's edge lands at
~0.50 against the regional beat's 0.75 — contained on both axes, and the two wide
beats are concentric by construction. **Arithmetic from source, not measured — the
engineering session must re-verify it on at least two fixtures before building,
because the whole of Pass 1 rests on it.**

### 8. A cross-region trip that *begins* with the crossing gets one move, not two

**Decision.** When the first local journey is degenerate — photographs start at the
departure airport, so segment 1 is a point — **the opening arc IS the first
crossing arc.** The film opens at the apex, the sprite crosses, the camera closes
into the destination.

**Why.** Fitted to a one-point segment the opening would establish on a 1,500 m
view of a terminal (the `camera_span_m` floor binding). That is almost certainly
what the first Miyakojima device film hit. And the merged move is a *better*
panorama than the padded one: it is showing the actual journey rather than a
rectangle around a bounding box.

**Open, not decided:** what counts as degenerate (recommend deriving it from
extent against `camera_span_m` rather than adding a tunable), and whether opening
on the departure reads right at all for a trip the film is not about. Both are
story judgements for Chiu, from a render.

---

### Delivery

- `Docs/camera-arcs.md` — the design, with the measured/derived split marked
  throughout and §11 listing what is still open.
- `Docs/eng-session-camera-arc.md` — the Pass 1 brief, ready to paste.
- `CLAUDE.md` Phase 4 item 3 — pointer added on Chiu's approval (2026-08-21). The
  freeze on both numbers **still stands**; the design makes them irrelevant to an
  arc rather than giving either a new value, and nothing changes until the Pass 1
  render has been judged.

