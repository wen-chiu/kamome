# HANDOFF — live findings

**Updated 2026-08-31.** `main` carries PRs #16–#24.

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
stepping is the 晃動. Mechanism **VERIFIED** from `RecapRenderLoop.swift:93–118`
and `FrameCompositor.swift:90–93`; effect **INFERRED** — nobody has rendered the
falsifying pair yet.

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

### Film duration must scale with trip size
**The direction IS decided (Chiu 2026-08-14). The rule is NOT.** Every trip
currently presents exactly 8 stops and 24 photographs whether it has 10 stops or
65, because duration is clamped to the same 60–90 s window. A candidate
inversion reproduces all three of Chiu's targets, but its three parameters were
reverse-derived from three trips — which is exactly how `body_span_padding` and
`tier_skip_share` were derived, and both failed. The acceptance condition is
decided in advance and is in the doc.
→ `Docs/handoff-pacing.md`.

### Travel pacing in Variant A — an experiment, nothing decided
Chiu lost interest during Iceland's 4 min 47 s of driving; all three trips sit at
the same ~49% travel share, so what broke was an **absolute quantity**, not a
proportion. Sequenced *after* the duration inversion. `travel_max_s` is a
candidate name for a thing that does not exist — do not let it reach
`TrackingConfig.json`.
→ `Docs/handoff-pacing.md`.

### The badge's size is provisional
0.60× was chosen from a rendered sweep and draws at 94.5 px. ⏳ **Judged from a
still; Chiu reserved the right to revisit it from a film.** Everything else
about the badge is decided (`Docs/decisions.md` 2026-08-29).
→ `Docs/handoff-marker-badge.md` finding 6.

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

### Read a style value off the preset the app selects, never off the defaults
`RecapStyle`'s defaults are unrendered. This was got wrong twice from the same
source and cost a correction in the ledger both times. The app selects
`modernMinimal`.

### Nothing measures post-grade output
The guards assert **token** luminance; the viewer sees the frame **after the
film's grade**. The rule survives the grade today, but nothing checks that it
keeps doing so. Same class of gap as the golden-frame gates being unable to see
`MapKitSnapshotProvider`.
→ `Docs/handoff-marker-badge.md` finding 6c.

### Nothing asserts the end card's brand mark
`RecapMarkerDeckStillsTests` iterates `VehicleMarker.allCases` and *writes*
stills; it asserts nothing about them. The guarantee that the end card still
shows a bird currently rests on a human noticing. A golden still would close it.
→ `Docs/handoff-marker-badge.md` finding 6d.

### The no-reader token cluster is now four, and grows one at a time
`cardColor`, `cardTextColor`, `markerColor`, `markerAccentColor` — four tokens
nothing renders, plus five `RecapOverlayRendererTests` assertions that believe
they render against an opaque card. Counted deliberately so the next one to join
is the fifth rather than another isolated note.
→ `Docs/handoff-marker-badge.md` finding 7.

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

- 2026-08-30 finding N → `Docs/handoff-audit-2026-08-30.md`
- 2026-08-29 finding N → `Docs/handoff-marker-badge.md`
- 2026-08-21 finding N → `Docs/handoff-camera-arc-findings.md`
- "Pending experiment — travel pacing" → `Docs/handoff-pacing.md`
- anything older → `Docs/_archive/handoff-2026-08.md`

## Where the detail lives

| document | what is in it |
|---|---|
| `Docs/handoff-audit-2026-08-30.md` | the render-loop P0, the country beat, the duration comment, the owed sweep, the §0 question |
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
