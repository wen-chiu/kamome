# HANDOFF — live findings

**Updated 2026-08-31.** `main` carries PRs #16–#24 and the cross-region
crossing beat (`f21b82f`) — **built and measured, not yet judged by Chiu.**

This file holds **only what is live**: open blockers, unfinished questions,
traps, and known bugs. Each entry is a summary and a pointer; the reasoning,
measurements and history live in the topic document it names.

**It is capped at 300 lines** (`Scripts/check-doc-budget.sh`). Over budget never
means delete — move the detail into a `Docs/` topic document and leave a
pointer, or move a closed section to `Docs/_archive/handoff-2026-08.md`. The cap
exists because a hand-trim from 1,961 to ~915 lines was back over 1,400 within
days; see `Docs/rule-rationale.md`.

Read `Docs/current-state.md` for the project snapshot and `CLAUDE.md` for the
standing rules first.

---

## 🔴 Blockers

### CI is blocked account-wide — a red check currently means nothing
From 2026-08-29 GitHub Actions jobs fail in ~3 seconds with **zero steps
executed**: the Actions spending limit is exhausted. `main` fails identically,
so this is not a signal about any branch. **Local `./check.sh` is the only
verification there is, and a PR must say so** rather than let a red check read
as a broken suite. Recurs when the monthly allowance runs out unless the limit
is raised.

### The shake and the ghosting are one mechanism, and the obvious fix is wrong
Chiu's P0 (`Docs/decisions.md` 2026-08-30): *"影片晃動感太明顯 不夠流暢 會有殘影."*
The base map is snapshotted every `keyframe_interval_frames` (15) and the 14
frames between are filled by **alpha-blending two snapshots of the same map at
two different geographic positions** — the double image is the 殘影, the 0.5 s
stepping is the 晃動.

✅ **CONFIRMED end to end 2026-08-30.** The falsification pair was rendered —
`miyakojima`, 10 s of body, identical but for the interval (15 vs 1) — and the
difference is a **sawtooth locked to the blend**: 0.07 at blend 0.00, rising
monotonically to 0.57 at the half-blend and back. At blend 0 the two clips are
the same picture, because that frame is a real snapshot either way. The
mechanism is not a hypothesis any more.

⚠️ **Do not "fix" this by lowering `keyframe_interval_frames`.** It is frozen,
it multiplies snapshot cost ~15×, and the right operation is reprojecting one
snapshot rather than cross-fading two.

→ **`Docs/handoff-audit-2026-08-30.md` finding 1** — the falsification test to
run first, the cost figures, and why crop-scaling is the fix.
**Read it before touching the render loop, the camera, or that config key.**

---

## 🟠 Open — nobody is on these

### The opening has never shown a country
`RecapModel.swift:204` builds `establishing` only from an installed `.pmtiles`
region; MapLibre was parked 2026-08-15 and nothing installs one, so it is
permanently `nil` and the "country" beat has always been *this trip × 2.2*.
VERIFIED. Parking MapLibre made this **easier** — Apple Maps is global, so the
original "never wider than the tiles we have" constraint is gone, and
`country_view_padding` is not frozen.
→ `Docs/handoff-audit-2026-08-30.md` finding 2.

### Content-derived pacing may be implemented but permanently dead
A shipping-path comment in `RecapModel.swift:201–203` has been shown wrong on
its first clause ("no region means … no prologue" — every film gets a prologue,
VERIFIED). If its *second* clause is true, content-derived pacing sits behind a
tile condition that can never be satisfied, and the film-duration question below
becomes an unlocking job rather than a design job. **UNKNOWN, worth an hour**;
the cheapest settling test is in the doc.
→ `Docs/handoff-audit-2026-08-30.md` finding 3.

### The subject lookup still misses; it no longer crashes
`VehicleCatalog.resolve` returns nil and the film silently draws the vector
seagull instead of the car. Same mechanism as the old bundle crash, different
symptom. **The rate and the trigger are still unmeasured** — two log lines now
ship specifically to name the next occurrence.
→ `Docs/handoff-subject-lookup.md`.

### A sweep is owed: which values were tuned against MapLibre?
Four defects now share one shape — a value chosen while MapLibre was the
substrate that silently degraded when Apple Maps became what ships. Each was
found **one film at a time, by accident**. The question that catches this class
is not "is this value good?" but **"what was this value tuned against?"**
**RECOMMENDATION, needs Chiu. Not scheduled, not started.**
→ `Docs/handoff-audit-2026-08-30.md` finding 4.

### The crossing costs 182 snapshots, and that is Pass 1's bill
Measured through the shipped loop: `ishigaki-crossing` goes **185 → 367
snapshots** when the crossing is established — one per frame over a 180-frame
arc, very nearly doubling the film's budget. On device that is 133–287 s
becoming 264–569 s for a 69-second film. **This is the number camera-arc Pass
1's crop-scaling has to refund**, and it is now measured rather than estimated.
The opening stays 151 in every row; if that moves, something touched the
prologue.
→ `Docs/handoff-cross-region-crossing.md` finding 10.

### 🔴 CONFLICT — the pan floor is *not* what makes the destination a smudge
`Docs/camera-arcs.md` §5 and `Docs/handoff-camera-arc-findings.md` finding 5
both say the pan floor is the mechanism. **Measured on the shipped path, that is
false**: `asked` is ~274 km against a pan floor of ~16 km, so the floor never
binds and taking the crossing out of it changes the body span by nothing.
`target_zoom_ratio` over the establishing shot is what sets the body span.
**Two documents still state the superseded premise.**
→ `Docs/handoff-cross-region-crossing.md` finding 1.

---

## ⏳ Awaiting a Chiu decision

### §0 — two films of real trips are committed to this repository
`Docs/demos/phase3/kamome-p3-recap.mp4` and
`Docs/demos/phase3_5/kamome-recap-NZ-disaster.MP4`, while current practice
writes films to `~/Kamome-films/` deliberately. They are phase demo artifacts,
which the Rules of Engagement require — so two rules genuinely pull against each
other. **They are not in §0's decided-exceptions list.** Either they become a
recorded exception or they move out; what should not persist is a standing rule
saying one thing and the tree saying another.

Checked and clean: `Docs/tests/` is gitignored, the prototype ships a
placeholder, and `Scripts/check-location-data.sh` now enforces both halves that
*are* decided. **No check gates on this one, deliberately** — gating it would
pre-empt the owner call.
→ `Docs/handoff-audit-2026-08-30.md` finding 7.

### Film length: two questions, in this order
**Duration must scale with trip size — direction decided (Chiu 2026-08-14), rule
NOT.** Every trip presents exactly 8 stops and 24 photographs whether it has 10
or 65, because duration is clamped to one 60–90 s window. The candidate
inversion reproduces all three of Chiu's targets, but its parameters were
reverse-derived from three trips — exactly how `body_span_padding` and
`tier_skip_share` were derived, and both failed.

**Then travel pacing**, an experiment with nothing decided: all three trips sit
at the same ~49% travel share, so what lost Chiu on Iceland was an **absolute
quantity**, not a proportion. `travel_max_s` names a thing that does not exist —
do not let it reach `TrackingConfig.json`.
→ `Docs/handoff-pacing.md` for both, including the acceptance condition decided
in advance.

### The badge's size is provisional
0.60× was chosen from a rendered sweep and draws at 94.5 px. ⏳ **Judged from a
still; Chiu reserved the right to revisit it from a film.** Everything else
about the badge is decided (`Docs/decisions.md` 2026-08-29).
→ `Docs/handoff-marker-badge.md` finding 6.

### The crossing beat — four things this session refused to default
The film is built and measured but **unjudged**. Open, and Chiu's: whether the
crossing seagull stays a choosable trip subject (it ships `selectable: true`
against the `plane`/`boat` precedent); whether the apex wants a hold; whether
`crossing_beat_s` 6.0 survives a judged film (it is reasoned, not measured); and
Case C — a trip that *begins* with the crossing — is not built.
→ `Docs/handoff-cross-region-crossing.md` finding 9.

### A staging rule for `Arch.md` — recommended, not in force
A branch ref has silently picked up another session's commits three times, and a
`git add -A` swept an unrelated file into an unrelated commit once.
**Recommendation: confirm the current branch before committing, and stage
explicit paths only — never `-A` or `.`** `Arch.md` is the engineering charter,
so per `PO.md` this is a recommendation. **Not in force until Chiu says so.**

### `stop_weighting_enabled` — measure before removing
Reachable in **both** modes; the containment argument is empirical and has never
been tested on a flat photograph distribution. The removal criterion was decided
in advance (Chiu 2026-08-07) so it is not re-litigated, and **a removal PR must
not cite "provably contained"**.
→ `Docs/handoff-stop-weighting.md`.

---

## ⚠️ Traps — read before you touch these

### Do not restyle `VehicleMarker.seagull` in place
It is **also the Kamome wordmark's bird on the end card**. The obvious badge
implementation would have silently turned the brand mark on every end card into
a blue disc, and no test asserts the end card's mark shape. The bare gull now has
three consumers: the brand mark, the fault badge (its own case), and the
cross-region narrator that has not been built.
→ `Docs/handoff-marker-badge.md` finding 5b.

### The continuity gate has never measured the shipped camera
`RecapCameraContinuityTests` passes a synthetic `establishing` extent, and its
own comment claims that is "the same code path, not a stub." **It is not** — a
non-nil `establishing` takes the other branch and activates `cappedToRegion` in
three places. The shipped app has passed `establishing: nil` since 2026-08-15;
on one fixture the two differ by **18.6 km vs 274 km of body span**. Not changed,
deliberately: `nil` is more forgiving, so swapping would weaken the gate — a bar
move for Chiu. The cheap fix is to scan **both**.
→ `Docs/handoff-cross-region-crossing.md` finding 2.

### `Docs/camera-arcs.md` §8 states an invariant no arc can satisfy
"The tighter must lie entirely inside the looser" fails across the apex by
construction — an arc opens out and closes back in. The property survives in two
halves and `RecapCrossingArcTests` asserts it that way. **§8 should be
reworded**; not done, because that is a design document.
→ `Docs/handoff-cross-region-crossing.md` finding 4.

### Read a style value off the preset the app selects, never off the defaults
`RecapStyle`'s defaults are unrendered. This was got wrong twice from the same
source and cost a correction in the ledger both times. The app selects
`modernMinimal`.

### Three gaps the badge work left on record
All in `Docs/handoff-marker-badge.md`, findings 6c, 6d and 7.

- **Nothing measures post-grade output.** The guards assert *token* luminance;
  the viewer sees the graded frame. The rule survives the grade today, and
  nothing checks that it keeps doing so.
- **Nothing asserts the end card's brand mark.** `RecapMarkerDeckStillsTests`
  *writes* stills and asserts nothing about them, so the guarantee that the end
  card still shows a bird rests on a human noticing. A golden still closes it.
- **The no-reader token cluster is four** — `cardColor`, `cardTextColor`,
  `markerColor`, `markerAccentColor` render nowhere, plus five
  `RecapOverlayRendererTests` assertions that believe they render against an
  opaque card. Counted so the next one to join is the fifth, not another
  isolated note.

---

## 🐛 Known bugs and accepted costs

- **The import date range clips at timezone edges** (2026-08-18). A photo from
  the first morning or last night of a trip can go missing. Cause is
  `Calendar.current` in `ImportFlowModel.dayBounds()`; a proper fix needs
  per-photo timezone. Workaround: widen the picked range by a day at each end.
- **`RecapMode` may be two axes, not one** (Chiu 2026-08-06). "Full stops, zero
  photographs" is the first variant needing one axis without the other. Not
  acting on it — recorded so the pressure is recognised when it arrives.
- **Flat glacier** (Chiu 2026-08-06: leave it). The `ice` layer is drawn opaque
  to kill a z6 tile seam, so the glacier renders without terrain texture.
  Cosmetic; the proper fix is a Planetiler rebuild — do not do that without
  asking.

→ all three: `Docs/handoff-known-bugs.md`.

---

## Older citations

`Docs/decisions.md` is append-only and cites findings as **"`HANDOFF.md` <date>
finding N"**. Those sections moved on 2026-08-31 and the ledger cannot be
corrected, so they resolve here:

- 2026-08-30 finding N → `Docs/handoff-audit-2026-08-30.md` (PO audit) or
  `Docs/handoff-cross-region-crossing.md` (the crossing session)
- 2026-08-29 finding N → `Docs/handoff-marker-badge.md`
- 2026-08-21 finding N → `Docs/handoff-camera-arc-findings.md`
- "Pending experiment — travel pacing" → `Docs/handoff-pacing.md`
- anything older → `Docs/_archive/handoff-2026-08.md`

## Where the detail lives

| document | what is in it |
|---|---|
| `Docs/handoff-audit-2026-08-30.md` | the render-loop P0, the country beat, the duration comment, the owed sweep, the §0 question |
| `Docs/handoff-cross-region-crossing.md` | the crossing beat: the P0 confirmation, the pan-floor correction, the snapshot bill |
| `Docs/handoff-marker-badge.md` | the fallback badge: what was decided, and the four gaps it left |
| `Docs/handoff-camera-arc-findings.md` | the working analysis behind `Docs/camera-arcs.md` — **nothing settled** |
| `Docs/handoff-pacing.md` | film duration and travel pacing |
| `Docs/handoff-subject-lookup.md` | the silent subject fallback |
| `Docs/handoff-stop-weighting.md` | the removal criterion |
| `Docs/handoff-known-bugs.md` | the three items above, in full |
| `Docs/environment-gotchas.md` | routing, simulators, fixture shadowing, what `docker ps` answers |
| `Docs/phase4-reference.md` | Phase 4 scope, the snapshot freeze, the camera architecture |
| `Docs/rule-rationale.md` | why each rule in `CLAUDE.md` exists |
| `Docs/_archive/handoff-2026-08.md` | history — never a work instruction |
