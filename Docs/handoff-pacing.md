# Pending — film duration and travel pacing

Two open pacing questions, in dependency order: film length must scale with trip
size (direction decided 2026-08-14, **rule not decided**), and the travel-pacing
experiment that is sequenced after it. **Neither is implemented and neither is an
ADR.**

*Moved verbatim out of `HANDOFF.md` on 2026-08-31 when that file was put on a
300-line budget (`Scripts/check-doc-budget.sh`). Nothing was edited; `HANDOFF.md`
carries the live summary and points here.*

---

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

