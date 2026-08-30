# HANDOFF — current state

**Updated 2026-08-29.** `main` carries PRs #16–#19, #21 and #22. Written so a
fresh session can pick this up without being briefed by hand.

⚠️ **CI is blocked account-wide from 2026-08-29** (Actions spending limit) — a red
check right now is not a test failure. See finding 2.

Read `Docs/current-state.md` first for the project snapshot, then `CLAUDE.md`
for the standing rules — especially **§0, location data never leaves the device
by default**, as amended by the routing ADRs (`Docs/decisions.md` 2026-08-16 and
2026-08-20 (b)/(c)).

**This file holds only what is current**: live findings, open experiments, and
known bugs. Closed, resolved, and superseded sections were moved verbatim to
`Docs/_archive/handoff-2026-08.md` on 2026-08-21 — that file is history, never
current state.

---

## Findings — PO/Architecture session (2026-08-29)

Three things that outlive the session. Everything else it found is in
`Docs/decisions.md` 2026-08-27 (b) or in the commits, and is not repeated here.

### 1. Two rules, learned the expensive way

- **Read a style value off the preset the app actually selects (`modernMinimal`),
  never off `RecapStyle`'s defaults.** The defaults are unrendered. This was got
  wrong twice from the same source — the glow brief, then a PO draft of the
  appearance ADR — and cost a correction in the ledger both times.
- **The PO session does not write an ADR for a decision an engineering session is
  actively implementing.** It drafted one for the appearance decision in parallel;
  two entries for one decision in an append-only ledger is worse than none, and the
  later-dated one would have won while being the weaker. The draft was withdrawn.
  What the PO session should record instead is what the implementer will not see:
  cross-cutting consequences, spent guarantees, and what was left undecided.

### 2. 🔴 CI is blocked account-wide — a red check currently means nothing

From 2026-08-29, GitHub Actions jobs fail in ~3 seconds with **zero steps
executed**: the Actions **spending limit** is exhausted. `main` fails identically,
so this is not a signal about any branch. Until it is cleared, **local
`xcodebuild test` is the only verification there is, and a PR must say so** rather
than let a red check read as a broken suite. It recurs when the monthly allowance
runs out unless the limit is raised.

### 3. Awaiting Chiu — a rule this session may recommend and may not write

A branch ref has silently picked up another session's commits three times, and a
`git add -A` swept an unrelated file into an unrelated commit once. **Recommendation:
a standing rule in `Arch.md` — confirm the current branch before committing, and
stage explicit paths only, never `-A` or `.`** `Arch.md` is the engineering charter,
so per `PO.md` this is a recommendation. **It is not in force until Chiu says so.**

### 4. Known remaining duplication, reported not acted on

The 2026-08-29 trim moved four merged sessions' findings to
`Docs/_archive/handoff-2026-08.md` (1,961 → ~915 lines). Two overlaps are left, both
deliberate:

- **"Reference — Phase 4 scope…"** below restates `Docs/current-state.md`'s phase,
  camera and routing entries at greater length. It is left because
  `Docs/eng-session-camera-arc.md` cites the freeze it records, and because it
  carries reasoning the index does not. **If it moves, current-state must absorb
  the reasoning first** — do not simply delete it.
- **"Findings — PO/Architecture session (2026-08-21)"** is the working analysis that
  produced `Docs/camera-arcs.md`. Once Pass 1 has run and been judged, the design
  doc is the surviving form and that section should be archived.

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

## 🐛 Known and not fixed — the import date range clips at timezone edges (2026-08-18)

**Symptom you will meet:** a photograph taken early on the first morning of a
trip, or late on the last night, is missing from an imported trip — and the date
range plainly covers that day.

**Cause.** A photo's `creationDate` is an absolute instant. `ImportFlowModel.dayBounds()`
turns the picked days into instants with `Calendar.current`, which is the
*device's* zone at the moment of import. Import an Iceland trip while sitting in
Taiwan and the day boundary moves by eight hours, so "1 August" means 1 August in
Taipei — clipping the Icelandic small hours at each edge of the range.

**Why it is not fixed here.** Doing it properly needs each photograph's own
timezone, which PhotoKit does not hand over with `creationDate`; it would mean
reading EXIF `OffsetTimeOriginal` per asset, or inferring the zone from the
photo's coordinates. Both are real work, and the clipping is small — hours at two
edges of a multi-day range.

**What to do if it bites.** Widen the picked range by a day at each end; the
clustering drops the extra photos anyway if they are not part of the journey.
Written down so the next person meeting a missing first-morning photo does not go
hunting for a clustering bug that is not there.

**Deliberately correct, do not "fix":** `dayBounds` widening the end to that
day's last second (there is no "lost the last day" bug), and the `min`/`max` swap
that makes an inverted range harmless.

## ⏳ Pending decision — film duration must scale with trip size (2026-08-14)

**The direction IS decided (Chiu 2026-08-14). The rule is NOT.** Do not implement
the shape below as though it were settled, and do not promote it to
`Docs/decisions.md` until it has been validated on renders — including on trips it
was not fitted to. Written here rather than as an ADR for exactly that reason.

### What was decided

> Film length must be **flexible, derived from how long the user's journey
> actually was**, so that different trips produce different films.
> — Chiu 2026-08-14

His targets, stated as durations — and **which of them have been watched**, which
is the whole point of rendering them before writing a rule:

| trip | trip stops | target | presented stops | status |
|---|---:|---:|---:|---|
| Miyakojima | 10 | 90 s | 8 | ✅ *"90 秒只適合宮古島"* — confirmed by statement |
| New Zealand | 20 | **150 s** | 15 of 20 | ⬜ **rendered, not yet judged** |
| Iceland | 65 | **210 s** | **21** of 65 | ✅ *"三分半鐘的那個版本是個不錯的折衷"* (2026-08-14) |

Films are in `~/kamome-renders/duration-targets/`; the Variant A and 90 s Variant B
sets are intact beside them.

**Iceland's anchor is 21 stops, not the 22 the arithmetic predicts.**
`keptStopCount` floors a division and 210 s lands at `21.999999999999996` in
IEEE754. So the film Chiu approved presents 21 stops, and a rule built to produce
22 would not be the film he watched. **Anchor on 21.**

That off-by-one is also a **third argument for the inversion below**: computing
duration *from* a stop count has no division to floor, so this entire class of
boundary artifact disappears rather than needing a guard.

### What the Variant B renders exposed

Every trip presents **exactly 8 stops and exactly 24 photographs**, whether it has
10 stops or 65 — Iceland's shipped edit is 12% of its stops and 24 of the 144
photographs its Variant A film shows. Measured 2026-08-13, all three trips.

**This is not a defect and not drift.** `StopPhotoAllocator.keptStopCount` is
`(duration − opening − end card) × max_hold_fraction ÷ presentation cost`, which
lands on 8 at the shipped `total_duration_max_s` of 90 s and on 11 at the 120 s the
2026-08-06 ADR quotes. The formula is fine. **Trip size simply never enters it**,
because duration is clamped to the same 60–90 s window for every trip.

### The shape recommended (NOT approved, NOT implemented)

**Invert the model.** Today duration is clamped and the stop count falls out of it;
instead let the trip earn a stop count and let duration fall out of *that*:

    duration = opening + end card + (earned stops × presentation cost) ÷ max_hold_fraction

Trip size then enters the model in exactly one named place. A second benefit:
`max_hold_fraction` stops deciding how many stops the shipped edit presents and
goes back to being purely a pacing knob — removing the double duty found on
2026-08-13.

Converting Chiu's three targets back through the existing arithmetic shows the
real intuition is about **places, not seconds**: 8 of 10 stops (80%), 15 of 20
(75%), 22 of 65 (34%). Growth must therefore be **sub-linear** — a 65-stop trip
does not earn 6.5× the film of a 10-stop one.

Candidate rule, statable in one sentence: **each doubling of a trip's stop count
earns ~7 more presented stops, floored at 8 and capped at 22.** That reproduces all
three targets exactly (10 → 8 → 90 s; 20 → 15 → 150 s; 65 → capped 22 → 210 s).

### ⚠️ The warning that matters more than the rule

**Those three parameters were reverse-derived from three trips, which is exactly
how `body_span_padding` and `tier_skip_share` were derived — and both failed.**
`body_span_padding` was fitted to Iceland and gave New Zealand 4.14×;
`tier_skip_share` needed 0.82 for Iceland and 0.5 for New Zealand and was deleted
for it.

The one property that makes this shape better is that it is **bounded at both ends
and sub-linear by construction**, so its failure modes are known rather than
discovered: it cannot explode on a huge trip or collapse on a tiny one. A bare
constant has no such property.

**Therefore the acceptance condition, decided in advance so it is not
re-litigated:** the rule must report what it produces for trips it was **not**
fitted to — Finland (3 stops), Margaret River (4), and the committed synthetic
fixtures — before any of it ships. Fitting three points and shipping is the failure
mode; validating on a fourth is the step this repo has twice skipped.

### Open sub-questions, none decided

- **Does a longer film mean more places, or also more photographs per place?**
  Measured 2026-08-14 and currently the former only: NZ at 150 s shows 43
  photographs across 15 stops (2.9 each) and Iceland at 210 s shows 63 across 21
  (3.0 each) — both pinned at `allocation_max_photos` (3). So duration buys stops
  and never buys depth. **This is a second, independent dimension**, and the rule
  should not be built assuming one answer. Iceland at 210 s still shows 63 of the
  144 photographs its Variant A film carries, out of 2300 in the dump.
- Is **stop count** the right measure of "how long the journey was", or should it
  be days, distance, or photograph count? Chiu's phrasing was "旅程多長". Stop
  count is what the arithmetic above uses because it is what the cost model already
  prices; that is a convenience, not an argument.
- **Iceland's longer run-in.** At 210 s the first stop arrives at 11.53 s against
  5.53 s in the 90 s cut — the opening still ends at 5.50 s, so there is ~6 s of
  travel before the first place. NZ barely moved (9.33 s vs 9.43 s). Chiu approved
  the 210 s film as a whole; whether that run-in specifically reads as breathing
  room or dead air was not called out either way.
- Do `total_duration_min_s` / `total_duration_max_s` survive as absolute bounds
  behind the earned-stops rule, or are the stop floor and cap now the only bounds?
- Does the same scaling apply to Variant A, which has no ceiling at all today?

## ⏳ Pending experiment — travel pacing in Variant A (2026-08-13) — NOTHING DECIDED

**Status: an experiment with a hypothesis, not a decision.** No config key is
changing, no code is changing, and `travel_max_s` below is a *candidate name for a
thing that does not exist*. Do not implement it, do not cite it as settled, and do
not let it leak into `TrackingConfig.json`. It earns a decision only if a render
Chiu watches says it should.

**Status (2026-08-14).** Still wanted, and Chiu has now named *when*: **the longer
the trip, the faster the vehicle should move in Variant A.** It is not a blocker —
all three films were accepted as they are — but it is no longer optional polish
either.

**Sequence it after the duration inversion above.** In `.full` this knob was always
safe (there is no duration cap for it to divide, so it moves only pacing — the
double duty found on 2026-08-13 is a `.highlight` problem). But the inversion
removes that double duty entirely, after which `max_hold_fraction` means one thing
in both modes and the experiment reads cleanly instead of needing a caveat.

It still interacts with the open §6a item: if Iceland is the film that gets
published, Chiu may want the faster-travel cut first. **That ordering is his call
and has not been made.**

**What Chiu observed** (2026-08-13, from the three Variant A films):
photographs hold his attention; **travel between stops does not, once the film is
long.** Miyakojima (1.7 min) and New Zealand (3.2 min) held; Iceland (10.0 min)
lost him during the driving. He asked whether the vehicle can move faster on
Iceland specifically.

**What the arithmetic says.** In `.full`, `RecapDurationPlan.uncapped` sizes the
body as `parked / max_hold_fraction`, so stop dwells take that share and **travel
gets whatever is left**. `max_hold_fraction` is 0.6 today, and being a ratio it is
scale-free:

| | photo time | travel time | travel share |
|---|---:|---:|---:|
| Miyakojima | 47.0 s | 44.7 s | 48.7% |
| New Zealand | 93.0 s | 88.7 s | 48.8% |
| Iceland | 300.0 s | **286.7 s** | 48.9% |

⚠️ **These are computed from the config, not printed by a harness.** The model
reproduces the rendered lengths (NZ 193.7 s exactly; Iceland 595.2 vs 598.7;
Miyakojima 99.2 vs 103.7, the deltas being the opening estimate), which is why it
is trusted this far — but it is derived, and the span/ratio prints landing in
`RecapTimelineReportTests` are the measurement that should replace it.

**The reading.** All three sit at the same share, so what broke was not a
proportion — it was **4 minutes 47 seconds of travel as an absolute quantity.**
88.7 s held; 286.7 s did not. That points at an absolute ceiling on travel time
rather than a per-trip constant, which matters because a per-trip constant is
exactly what the 2026-08-09 camera ADR rejected and for the same reason:
`body_span_padding` was reverse-derived from Iceland and told us nothing about the
next trip.

**The experiment, in order — measure the preference first, encode it second.**

1. A harness-only override for `max_hold_fraction` (same shape as
   `withAllocationZeroShare`), so `TrackingConfig.json` is untouched and the
   change reverts by deleting an env var.
2. **One Iceland render at 0.75.** Predicted: film 9.9 → 8.0 min, travel 4.8 →
   2.8 min, **photo time unchanged at 300 s**. Iceland costs ~30 min a render, so
   this is a single point, not a sweep.
3. Chiu watches it. If the pacing is right, the travel seconds it landed on
   (~169 s) become the evidence for a real tunable. If it is still slow, 0.85
   (travel 1.9 min) is the next point — watching for whether it starts to feel
   rushed.
4. Only then: a config key, its typed mirror, and `ConfigLoaderTests` assertions,
   per the standing no-magic-numbers rule.

**Does the vehicle actually move faster, or does the camera just pull back?**
It should genuinely move faster — **INFERRED from the code, not yet seen.** Since
2026-08-09 the body span comes from `target_zoom_ratio` (2.5) against the
established span; `camera_pan_window_fraction_per_s` (0.35) is only a **floor**,
and `HANDOFF` records that it does not bind on the real trips. So shortening
travel does not widen the span — the same ground stays in frame and the subject
crosses it in fewer seconds. The floor is the built-in safety: push travel short
enough and it takes over and widens the span instead of letting continuity break.
Rough arithmetic says Iceland has a lot of headroom before that happens, but that
is arithmetic, and the render is what settles it.

**Not decided by any of the above:** whether Iceland stays a Variant A trip at
all. Switching it to Variant B is a live alternative Chiu named, and the §6a/§6b
split means both films of the same trip exist anyway.

## 🟠 Open — the `KamomeCore_KamomeExportEngine` subject lookup still misses; it no longer crashes

**Retitled and corrected 2026-08-28.** This entry stood as "🔴 intermittent bundle
crash (2026-08-13)" and described an unguarded `fatalError` reached through
`Bundle.module` in `Core/ExportEngine/RecapCarSprite.swift:75`. **That mechanism
no longer exists** — its own closing line ("the eventual fix is small and
defensive — a non-trapping bundle lookup") was carried out two days later and the
entry was never updated. Kept, not deleted: the *lookup* still misses, and the
same miss now degrades a film silently instead of crashing it.

### The history, as observed (2026-08-13)

`Fatal error: unable to find bundle named KamomeCore_KamomeExportEngine`, thrown
during map-renderer creation — after the region resolves, before any frame is
drawn. Hit **2 of 3** New Zealand render attempts; never on Miyakojima, never on
the Iceland run — so it read as trip-correlated rather than evenly random.
Cleared on retry, and again under `-retry-tests-on-failure`. The resource bundle
**is** present in the built `Kamome.app`, so it was a runtime lookup failure, not
a packaging fault. (Those are this file's own 2026-08-13 figures, kept verbatim;
no wider tally is recorded in the repository.)

### What changed the symptom — VERIFIED from the tree, 2026-08-28

| when | commit | what |
|---|---|---|
| 2026-08-15 | `b44a7fc` | "the sprite fallback stops being unreachable" — the trap is replaced by a non-trapping resolver |
| 2026-08-16 | `e2a1478` | `RecapCarSprite.swift` deleted; the resolver is generalised into `VehicleResourceBundle` (`Core/ExportEngine/SpriteDirection.swift:43`). Its message: "`Bundle.module` does not return." |

`grep -rn "Bundle.module" --include="*.swift" .` returns **only comments** — no
call site anywhere in the repository, and no `fatalError` or `try!` in
`Core/ExportEngine`. **The crash as this entry described it cannot recur.** The
generated accessor still exists in DerivedSources, as it does for every target
with resources, but nothing calls it.

### What the same lookup does now — observed 2026-08-28

`VehicleCatalog.resolve` returns nil and `VehicleSubjectRenderer.make` draws the
vector seagull. **Whether `VehicleResourceBundle.resolved` was itself nil is
UNKNOWN** — nothing recorded it, which is the gap the new log line closes. Four
`RecapStopStillTests/testRenderSubjectStill` runs differing only in
`TEST_RUNNER_KAMOME_ROUTE_COLOR` produced three cars and one gull
(`light-C-deeper`, `~/Kamome-wt/logs/render-light-C-deeper.log`); the test passed
in 25.8 s with no retry.

**VERIFIED here, not taken on report:**

- The still really is the fallback. Diffing it against the re-render at >8/255 on
  any channel gives **9,291 differing pixels of 2,073,600, all inside one
  126×131 box** — the subject and nothing else. Crops confirm gull vs car.
- **Nothing distinguished the run.** Stripped of timestamps, pids and paths, the
  two console outputs are identical **line for line**; the only differences are
  the colour, the output path and the elapsed seconds.
- The harness could not have told anyone either: `RecapReviewScene` prints
  `KAMOME_REVIEW subject <id> at <n>px` **before** calling `make`, so it reports
  what was asked for, and `KAMOME_SUBJECT_STILL … (se drawing)` derives the
  direction from the heading, not from what was drawn.
- The bundle carries `Vehicles/` and nothing else (`Package.swift`,
  `resources: [.copy("Resources/Vehicles")]`), so a whole-bundle miss would
  degrade **only** the subject. The single-box pixel diff is therefore consistent
  with a whole-bundle miss and **cannot discriminate** it from missing art.

### Same mechanism — established. Same trigger — UNKNOWN.

Same bundle name, same lookup, same code lineage, same point in the sequence
(map-renderer/compositor construction), same intermittency, both cleared by a
re-run. `b44a7fc` is exactly the commit that would turn the one symptom into the
other. That is enough to call it **one mechanism with two symptoms**.

It is **not** enough to call it one root cause. Neither occurrence was diagnosed,
and two things argue for caution: the crash tracked New Zealand and is recorded
above as never having fired on the Iceland run, while this miss *was* Iceland; and
`VehicleResourceBundle` is *stricter* than `Bundle.module` was — it accepts a
candidate only if `Vehicles/vehicles.json` is findable inside it, so a bundle
directory that exists but does not answer a resource query fails here and would
have succeeded there.

### Two hypotheses tested and weakened — 2026-08-28

**An install/launch race: WEAKENED, and it was the leading idea.** The tempting
mechanism was that the bundle being probed is a directory written moments before
the process launched. **MEASURED** on iPhone 17 Pro over four runs: a run whose
build produces a changed product installs into a **brand-new container**, taking
the old one with it (`9979C474-…` 22:24:56 → `D4A52666-…` 22:27:12 →
`E91959A1-…` 22:29:19), and the installed
`Kamome.app/KamomeCore_KamomeExportEngine.bundle` carries the install time rather
than the build time. **But a run that compiles nothing does not reinstall at
all** — a fourth run with 0 `SwiftCompile` and 0 packaging tasks left
`E91959A1-…` untouched. The four appearance renders differed only in environment
variables, so on that evidence the app was installed once and reused across them,
and no install sat next to the failing launch. INFERRED for that batch — no
install record from it survives — but it points away from the race, not towards
it.

**A build-work difference: RULED OUT.** `light-C-deeper`'s build did more than
`light-A`/`light-B`'s — two `CompileXCStrings` and four `CopyStringsFile` against
one and two. That is a real difference and it is **not** the discriminator: the
clean re-render (`render-light-C-rerender.log`) ran the *same* heavier pattern
and drew the car.

### What was done about it, and what was not

**Done (this change).** `VehicleSubjectRenderer.make` now logs the miss
(`KamomeLog.recap.error`) instead of degrading in silence, per Arch.md §5, and
the doc comment that called this "a state no test can arrange" is corrected.
`KamomeLog` reaches the xcodebuild console on the simulator — the routing lines
in every render log prove it — so the next occurrence names itself in the same
file a reviewer already reads.

**Done, approved (Chiu, 2026-08-28): the lookup now says what it tried.**
`VehicleResourceBundle.resolved` logs a one-shot trace naming, per candidate, the
URL and — the fact both incidents lacked — **whether the nested bundle was on
disk**, which is what separates an install-timing fault from a packaging one.
Scope as approved: failure path only (a process that resolves logs nothing),
filesystem paths only (nothing derived from a trip, so §0 is not engaged), and
shipped rather than reached for afterwards, because an intermittent failure has
to be instrumented *before* it happens.

The walk moved into `VehicleResourceBundle.resolve(hosts:)` so the message can be
exercised — `resolved` is a lazily-initialised global with no seam, and a
diagnostic that can never be shown to fire is one nobody should trust. Order and
acceptance rule are unchanged. Two tests hold the contract in
`RecapSubjectOrientationTests`: a host with no manifest produces
`…KamomeCore_KamomeExportEngine.bundle: not on disk`, and a resolving lookup
produces an **empty** trace.

**Two lines, not one, when it next fires:** the bundle trace once per process,
and `VehicleSubjectRenderer.make`'s per-subject line naming the consequence. One
says why, the other says what the viewer will see.

**Still not measured:** the rate, and the trigger. The next occurrence is what
this exists to catch.

**Stale references left alone, deliberately.** `Docs/current-state.md` is the
synced index and its neighbouring sections are being rewritten on
`feature/p4-appearance-follows-system`, so **two** lines there belong to the pass
that re-syncs it, not to this change: the blockers entry "🔴 intermittent …
bundle crash", and "worktrees fix it but silently skip half the secrets guard
(`HANDOFF.md` 3e)" — struck above, closed by `2d221e0`.
`Docs/gate-P3.5-checklist.md`
and `Docs/handoff-P3.5.md` describe a closed phase and are history.
`Docs/decisions.md` 2026-08-15 records the `Bundle.module` mechanism as it stood
and is append-only — it is not wrong, it is superseded.

## `stop_weighting_enabled` — reachable in BOTH modes, containment only empirical

**Corrected 2026-08-07.** An earlier note in this file claimed it was "unreachable
by construction" under `.highlight`. **That was wrong**, and the error was
overclaiming a structural property from two datasets. Chiu asked for the verdict
to be split per mode, which is what exposed it. Classified separately, both
answers are *empirical*, and neither is safe to rely on for a removal PR.

### Under `.highlight` — NOT dead by construction. Empirically zero on big trips only.

Tiering keeps the top `keptStopCount` stops by score, and `StopWeighting` demotes
stops with ≤ `waypoint_max_photos` (2) *and* a short dwell. Those sets are disjoint
**only while the trip has more stops than the film can keep** — because then only
heavily-photographed stops survive the cut.

**When a trip has fewer stops than the budget keeps, every stop survives, including
two-photo ones, and `StopWeighting` fires.** Measured at a 120 s film
(`keptStopCount` = 11):

| fixture | stops | waypoints under `.highlight` + weighting |
|---|---:|---:|
| Iceland | 65 | 0 |
| New Zealand | 20 | 0 |
| **Margaret River** | **4** | **1** ← fires |
| Finland | 3 | 0 |

So the "0 waypoints" result on Iceland and NZ is a consequence of those trips being
*large*, not of the filters being mutually exclusive. A short trip reaches it.

### Under `.full` — non-dead, and the containment is empirical too.

It fires: 8 of 65 on Iceland, 1 of 20 on NZ. The claim that its targets are always
inside the allocator's bottom-`allocation_zero_share` (40%) zeroing is **not
structural**: the allocator ranks by *relative* score, so whether a two-photograph
stop lands in the bottom 40% depends on the distribution of the rest of the trip.
On a trip where most stops carry two photographs, a two-photograph stop can rank
well above the 40th percentile and be given photos by the allocator that
`StopWeighting` then strips.

Iceland and New Zealand both have long, heavily-skewed tails (2 → 252 photographs),
which is exactly the shape that makes containment hold. **It has not been shown to
hold on a flat distribution, and no such trip has been tested.**

### What this means before running `.full` on new data

Chiu intends to use `.full`. Margaret River, Miyakojima and the WA trip have **not**
been measured under it. `StopWeighting` applies *after* the mode in
`RecapComposer`, so it can strip photographs the allocator granted — the mechanism
is live, not theoretical.

### The removal criterion (Chiu 2026-08-07) — decided in advance so it is not re-litigated

Two **separate** questions, to be measured separately on Margaret River,
Miyakojima and the WA trip under `.full`:

1. **Structural eligibility** — does `stop_count <= keptStopCount` reliably predict
   when `StopWeighting` fires? This is the technical question above: *can* the code
   path execute, and is there a rule that says when.
2. **Perceptual impact** — when it *does* fire, is the rendered film perceptibly
   different? Render both ways and compare the actual output, not the stop table.

They are complementary, not alternatives. A path can be technically live and
visually irrelevant.

**The criterion: if question 2 comes back "not distinguishable" consistently across
all three trips, that is grounds to remove the feature outright — regardless of
whether the code path still technically executes.** A live-but-invisible branch is
not a reason to keep configuration surface.

Conversely, a single trip where the film is visibly different keeps it, and the
answer to question 1 then decides whether the trigger needs to become structural
rather than incidental.

**A removal PR must not cite "provably contained".** It must either measure the new
datasets, or make the containment structural (e.g. run the classifier *before*
allocation, or fold its threshold into the allocator's scoring).

**Not removed** (Chiu 2026-08-07): timing and review scope, decided separately after
the `RecapMode` migration lands and passes CI.

## Open question — RecapMode may be two axes, not one (Chiu 2026-08-06)

`RecapMode` is being introduced as a two-case enum (`highlight` | `full`).
**Deliberately no placeholder cases**: every `switch` over it is exhaustive with
no `default:`, so the compiler forces every call site to be revisited when a case
is added. That is the extensibility mechanism — not speculative cases sitting
unused.

The note worth keeping: the next variant Chiu has in mind — *full stop coverage,
zero photographs* — mixes **two independent axes**:

| axis | today's cases differ on it |
|---|---|
| which stops survive | `highlight` keeps ~11, `full` keeps all |
| how many photographs each gets | `highlight` gives 3, `full` gives 0–3 |

"Full stops, no photos" is the first combination that needs one axis without the
other, and a third case would encode a *pair* of choices as a single name. If a
fourth follows, `RecapMode` should probably split into two orthogonal enums rather
than grow. **Not acting on this now** — recorded so the pressure is recognised
when it arrives instead of being rediscovered.

## Known cosmetic tradeoff — flat glacier (Chiu 2026-08-06: leave it)

`Config/RecapThemes/modern-minimal.json` draws the `ice` layer **opaque**
(`#4e5c64`) to kill the pale cross over Vatnajökull — a z6 tile seam where the ice
polygon runs into the tile buffer and both neighbours draw the overlap
(diagnosed `71caf77`). An opaque fill cannot double-blend.

The cost: `hillshade` is layer 1 and `ice` is layer 5, so **the glacier renders
flat, without terrain texture**. Chiu has seen it and chosen to keep it for now —
cosmetic polish, not urgent. The proper fix is clipping the landcover buffer in
Planetiler and rebuilding all four regions, which keeps translucency; do not do
that rebuild without asking.

## Environment gotchas that cost time

- ⚠️ **Routing is Geoapify since 2026-08-20** (`Docs/decisions.md` 2026-08-20).
  The OSRM entries below describe the parked local server (`Deploy/`), kept as
  the self-hosted fallback — they are not the shipped routing path.
- **The desk render path and the app disagree about routing.** `matching.base_url`
  ships `""`, so the shipped app reconstructs **no** legs and draws everything
  dashed; the desk harness defaults to `http://127.0.0.1:5100` and reconstructs
  most of them. A film that is dashed everywhere is almost certainly an app-config
  artifact, not a regression.
- **`RouteMatchService` logs the wrong base URL** when a reconstructor is injected
  (which every desk harness does): it prints `config.matching.baseURL`, so the log
  says `"(none — matching disabled)"` in the same run where legs reconstruct
  against a live OSRM. `App/Services/RouteMatchService.swift:39`. Unfixed; it is
  the line you would otherwise trust to answer "which server did this build ask?".
- **Agent shells here are sandboxed.** `curl` to localhost and `docker ps` fail
  with what look like "server is down" errors even when the server is running.
  Confirm through a test run, not through curl.
- **OSRM on `:5100` is compose-managed and restart-safe** — corrected 2026-08-09.
  It is the `osrm` service in **`Deploy/docker-compose.yml`** (container
  `kamome-osrm`, `restart: unless-stopped`, healthcheck green), so it comes back
  on its own provided Docker Desktop starts at login. Start it with
  `cd Deploy && docker compose up -d`.

  The stale claim this replaces — "started ad hoc, will not come back" — was
  reading `~/kamome-osrm/docker-compose.yml`, a **legacy file** carrying only
  taiwan:5002 and australia:5001. Nothing runs from it; the per-region servers
  were replaced by the single merged extract when `Deploy/` landed (`0924eca`).
  It is outside the repo and harmless, but it is what to ignore when checking
  whether routing is up. `docker ps` is the answer, not that file.
- Tiles/terrain: `~/kamome-osrm/tiles`, `~/kamome-osrm/terrain`.
- `simctl addmedia` fails with LaunchdSimError 133 unless the device is actually
  booted — boot it first, the error does not say so.
- **Fixture shadowing is real.** `RecapTripFixtures.tripFixture` prefers
  `Tests/Fixtures/trips/local/<name>.json` (real dumps, gitignored per §0) over the
  committed fixture. Local and CI therefore test different geometry — NZ is 20
  stops locally, 3 on CI. To reproduce CI, move `local/` **outside the repo**
  (not to a dotfile inside it — only `Tests/Fixtures/trips/local/` is gitignored)
  and re-run.
- **`850a995` does not compile.** A parallel session's push swept in an
  uncommitted edit and CI died at lint before building. Harmless at the tip;
  `git bisect` across it will hit it.
- The desk render command (env-gated `RecapPilotFilmTests`, Variant A) is
  preserved in `Docs/_archive/handoff-2026-08.md` under "▶ RESUME HERE
  (2026-08-13)". Films go to `~/kamome-renders/`, never `/tmp`.

## The seam is bounded by the collapse rule, not by taste

`FollowCameraRestingFrameTests.testTheOpeningHandsOverWithoutAJump` asserts the
one-frame step at the opening→body seam is within
`export.opening_collapse_drift_fraction` (15%) of the frame. That is not a chosen
number: when the closing zoom plays it ends exactly on the live track and the seam
is ~0, and when it is *collapsed*, `isEffectivelyTheSame` is what permitted the
collapse — so its drift allowance is precisely the largest cut the design allows.
Margaret River sits at 8.6% of that 15%.

An earlier version asserted a flat "under 5% of the frame", which was fine while
the seam was always a cut and started failing the moment `body_span_padding` made
the closing zoom a real 2.5× move.

## Reference — Phase 4 scope, the snapshot freeze, and the camera (carried from `CLAUDE.md`, 2026-08-21)

*Current, load-bearing reference, moved here when `CLAUDE.md` became a boot
file. `Docs/eng-session-camera-arc.md` cites the freeze recorded below.*

### Phase 4 scope (Chiu 2026-08-15)

Chosen over productisation deliberately: *"方便的產品都沒有這是足夠好的作品更吸引
人"* — a good enough artefact matters more than a convenient product, so the films
come first and export convenience is discussed after. Reordered 2026-08-15 around
the first outside feedback: **nobody mentioned the map; the most common request
was to change the vehicle.**

1. **Vehicle sprites** — the top community request, and the prerequisite for the
   cross-region plane/ship/seagull. The 8-direction technique and its art
   constraints are in `Docs/handoff-recap-visuals.md` §3; swapping a set is
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

   🔒 **Both numbers are frozen — a recorded fact, not a pending change**
   (Chiu 2026-08-15). Neither `keyframe_interval_frames` (15) nor the opening's
   every-frame interval is to be touched, and the three-way render comparison is
   not owed. They were held for a design conversation about **how the camera
   crosses large spatial gaps** — the opening's panorama-to-detail move and the
   cross-region flight are the same problem.

   ➡️ **That conversation happened on 2026-08-21. The design is
   `Docs/camera-arcs.md`** (the *contained arc*; findings above; first
   engineering session `Docs/eng-session-camera-arc.md`). **The freeze still
   stands** — the design makes both numbers *irrelevant to an arc* rather than
   tuning them, so neither gets a new value, and nothing changes until Chiu has
   judged the Pass 1 render.

**Map work is NOT in Phase 4.** Tiles, labels and the tile server all left the
roadmap with the 2026-08-15 substrate ADR. What Chiu wants from "big cute place
names" is a **Kamome-drawn overlay** — iceboxed as "Place names as narrative
rhythm", substrate-independent, and the app already geocodes every stop.

**Routing is Geoapify — CLOSED 2026-08-20** (`Docs/decisions.md` 2026-08-20
(a)–(d); `Docs/routing-provider-selection.md` is the record of what was asked,
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
