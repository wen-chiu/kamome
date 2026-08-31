# HANDOFF — live findings

**Updated 2026-08-31.** `main` carries PRs #16–#25. The cross-region crossing
beat and **crop-scaling** (camera-arc Pass 1) are both **built and measured, not
yet judged by Chiu.**

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

### The shake and the ghosting — FIXED, awaiting Chiu's judgement of the render
Chiu's P0 (`Docs/decisions.md` 2026-08-30): *"影片晃動感太明顯 不夠流暢 會有殘影."*
The loop alpha-blended two snapshots of the same map at two different positions;
the double image was the 殘影, the 0.5 s stepping the 晃動.

**`RecapRenderLoop` no longer cross-fades.** It plans **stations**
(`RecapSnapshotStations`) — one snapshot per run of frames — and reprojects each
onto each frame. A reprojected frame is geometrically exact, so there is nothing
to fine-sample against and nothing to blend wrongly.

Measured against an interval-1 reference by the 2026-08-30 method (`miyakojima`
body 20–30 s): **the frame-to-frame swing — what 晃動 actually is — falls from
1.402 to 0.077**, and travelling error from 2.005 to 0.818. A level of error that
never changes is softness, not shake. `ishigaki-crossing` goes **367 → 51**
snapshots (14 opening + 25 arc + 12 body), 7.2×; on device, 4.4–9.5 min of export
becomes 37–79 s. The cost is a uniformly slightly softer map — a look, and
**Chiu's to judge**; the dial is `snapshot_station_max_magnification`.
⏳ **Films:** `~/Kamome-films/2026-08-31-crop-scaling/judgement/{before,after}/`.
→ **`Docs/handoff-crop-scaling.md`** — the table, the budget split, the two
opening proposals, and the worktree trap that invalidated the first comparison.

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

### ⏳ The opening: two design questions are Chiu's, and nothing was built
Crop-scaling refunded the crossing's 182-snapshot bill (367 → 51), so that item
is closed. The **opening** was measured but deliberately not changed: where a
country's extent comes from, and how beat 2's frame is defined, are proposals for
Chiu (`Arch.md` §7). Both proposals, with costs and offline behaviour, are in the
doc. ⚠️ **One §0 point was not foreseen**: a MapKit/CLGeocoder country lookup
sends a real coordinate off-device to draw a wider opening — a *new* exception,
so a product decision, not an implementation detail.
→ `Docs/handoff-crop-scaling.md` §4–§5.

### 🔴 CONFLICT — the pan floor is *not* what makes the destination a smudge
`Docs/camera-arcs.md` §5 and `Docs/handoff-camera-arc-findings.md` finding 5
both say the pan floor is the mechanism. **Measured on the shipped path, that is
false**: `asked` is ~274 km against a pan floor of ~16 km, so the floor never
binds and taking the crossing out of it changes the body span by nothing.
`target_zoom_ratio` over the establishing shot is what sets the body span.
**Two documents still state the superseded premise.**

⚠️ **Widened 2026-08-31: the ratio is 2.50× in *six* configurations**, from
`establishing: nil` to an extent far wider than the trip. The floor binds
**nowhere**, not merely on the shipped path — so this is a property of
`bodySpanM`, not a fact about one fixture.
→ `Docs/handoff-cross-region-crossing.md` finding 1,
`Docs/handoff-crop-scaling.md` §4.

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
It passes a synthetic `establishing` extent; the shipped app has passed `nil`
since 2026-08-15, which takes the other branch — **18.6 km vs 274 km of body
span** on one fixture. Not changed, deliberately: `nil` is the more forgiving
configuration, so swapping would weaken the gate, and that is a bar move for
Chiu. Re-confirmed still true 2026-08-31. The cheap fix is to scan **both**.
→ `Docs/handoff-cross-region-crossing.md` finding 2.

### `Docs/camera-arcs.md` §8 states an invariant no arc can satisfy
"The tighter must lie entirely inside the looser" fails across the apex by
construction — an arc opens out and closes back in. The property survives in two
halves and `RecapCrossingArcTests` asserts it that way. **§8 should be
reworded**; not done, because that is a design document.
→ `Docs/handoff-cross-region-crossing.md` finding 4.

### A worktree renders a different film — two gitignored paths decide it
`git worktree add` carries no gitignored files, so a worktree has no
`Config/Secrets.xcconfig` (no routing key → `drive/inferred`, straight lines
instead of roads) and no `Tests/Fixtures/trips/local/`. A before/after across
worktrees is then two different films, and it looks plausible — the first
crop-scaling comparison read 4.08 where the answer had to be ~0. Copy both, then
count `drive/reconstructed` in each log. **A render comparison without a "these
two must be identical" control row is not evidence.**
→ `Docs/handoff-crop-scaling.md` §3.

### A 70-second MapKit render is killed on this machine — on `main` too
`RecapPilotFilmTests` at 70 s dies with `Test crashed with signal kill` ~94 s in;
`-retry-tests-on-failure` does not recover it. **Reproduced identically on
`main`**, so it is not crop-scaling. Render judgement clips as ≤25 s windows.

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
| `Docs/handoff-crop-scaling.md` | crop-scaling: the interval-1 comparison, the budget split, the opening measurement and its two open proposals |
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
