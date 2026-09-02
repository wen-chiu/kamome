# HANDOFF — live findings

**Updated 2026-09-01.** `main` carries PRs #16–#25. The cross-region crossing
beat, **crop-scaling** and **the title-card opening** are built and measured;
Chiu has judged crop-scaling (accepted) and has **not yet seen the opening.**

This file holds **only what is live**: open blockers, unfinished questions,
traps, and known bugs. Each entry is a summary and a pointer; the reasoning,
measurements and history live in the topic document it names.

**It is capped at 16 KB** (`Scripts/check-doc-budget.sh`). Over budget never means
delete — move the detail into a `Docs/` topic document and leave a pointer, or
move a closed section to `Docs/_archive/handoff-2026-08.md`. The cap exists
because a hand-trim from 1,961 to ~915 lines was back over 1,400 within days; see
`Docs/rule-rationale.md`.

Read `Docs/current-state.md` for the project snapshot and `CLAUDE.md` for the
standing rules first.

---

## 🔴 Blockers

### The shake and the ghosting — FIXED and accepted; two dials still open
Chiu's P0 (`Docs/decisions.md` 2026-08-30). `RecapRenderLoop` reprojects one
station per run of frames instead of cross-fading two cameras. Chiu watched the
before/after on 2026-08-31 and **accepted it**: travelling error 2.005 → 1.061,
frame-to-frame swing 1.402 → 0.747, stop beats pixel-exact again.

⏳ **Two for Chiu.** `snapshot_station_max_magnification` is **1.1**; 1.05 is
sharper at ~3× the snapshots. And a **new** artifact: a 0.747 sharpness step
exactly at the hold boundaries, where a pixel-exact parked station abuts a
magnified travelling one. §7's remedy (cross-fade *at a station boundary*) costs
no extra fetches and is **not built**, pending a judged render.
→ `Docs/handoff-crop-scaling.md` §1, §10.

### ⏳ The opening is built and unjudged — and the cost went UP
Beat 1 is a **held country frame under the title card** that **cuts** to beat 2
(Chiu 2026-08-31); beat 2 is one local journey; `bodySpanM` divides **beat 2**,
breaking the chain that made "widen the country" and "smudge the destination" one
knob. Snapshots went 367 → 51 → 178 — the 51 was cheap *because* the destination
was a smudge. ⚠️ A type-2 film now takes a different opening entirely (below); this
entry is the **local** film's opening, still unjudged.
→ `Docs/handoff-crop-scaling.md` §11, §12.

### ⏳ The type-2 film is BUILT and unjudged — one whole film exists
Chiu's three film types (2026-09-01, **not in `decisions.md`**): 1 local, 2 home →
one destination abroad, 3 multi-region (deferred). Type 2 is built: title card over
the flight frame → the aircraft crosses with the **camera still** → the arc closes
into the destination → the destination's local trip. The origin's drive is dropped
(`RecapTypeTwoFilm`), making every type-2 film `Docs/camera-arcs.md` §4 **Case C** —
predicted there, unbuilt until now.

    ~/Kamome-films/type2-2026-09-02/kamome-ishigaki-crossing.mp4   60.0s · 87s
    ~/Kamome-films/type2-2026-09-02/kamome-miyakojima.mp4          88.0s · 109s

`ishigaki-crossing`: 69.0 → **60.0 s**, body span 20.0 → **13.3 km**, snapshots
178 → **135**, of which the **opening is 1** — a still camera costs one snapshot at
any span, which is what makes the flight drawable. `miyakojima` is unchanged, which
is the evidence the change is confined to type-2 films.

🔴 **A long-haul frame often does not exist, and the limit is degrees of longitude,
not kilometres.** MapKit saturates at **~109°**; a 9:16 frame is 1.778× taller than
wide and runs off the poles first at low latitudes. **Taiwan→Iceland fails both at
every padding** — and Iceland is the acceptance film — so the frozen country card is
a **main path**. `crossing_flight_max_longitude_deg` is **70**, **interpolated**:
Auckland 53.2° frames well, Moscow 83.9° does not, nothing between was rendered.

🔴 **A car still drives across the sea** — the mode classifier is session 2 and was
out of scope. Not a regression, far more visible now the crossing opens the film.

⚠️ **Three defects the gate caught, one of which PASSED it**: framing the body from
the flight frame gave a 177.3 km body span and 100% overlap — perfect continuity,
and a still film. **Continuity passing is not the film being right.**
→ `Docs/handoff-type2-films.md` §3.

### The film type is derived, and the reading is monotonic
An unrouted leg can only *add* a local journey, so a confirmed crossing means **at
least** a type 2. The first version returned `unknown` on any NULL leg, which
sounded careful and would have left the new form with **no test coverage at all** —
routing ships disabled, so every fixture was `unknown`. ⚠️ `>= 2 ⇒ the type-2 form`
is sound only while type 3 is deferred. Recorded: the same trip yields different
films on different days (sharpening ADR 2026-08-15's unmet export-record
requirement), and nothing tells a user re-exporting later would give a better film.

---

## 🟠 Open — nobody is on these

### Content-derived pacing may be implemented but permanently dead
A shipping-path comment in `RecapModel.swift:201–203` is wrong on its first clause
("no region means … no prologue" — every film gets one, VERIFIED). If its *second*
clause is true, content-derived pacing sits behind a tile condition that can never
be satisfied, and the film-duration question becomes an unlocking job rather than
a design job. **UNKNOWN, worth an hour**; the settling test is in the doc.
→ `Docs/handoff-audit-2026-08-30.md` finding 3.

### The subject lookup still misses; it no longer crashes
`VehicleCatalog.resolve` returns nil and the film silently draws the vector
seagull instead of the car. **The rate and the trigger are still unmeasured**;
two log lines ship to name the next occurrence.
→ `Docs/handoff-subject-lookup.md`.

### A sweep is owed: which values were tuned against MapLibre?
Five defects share one shape — a value chosen while MapLibre was the substrate
that silently degraded when Apple Maps became what ships. Each was found **one
film at a time, by accident**. The question that catches the class is not "is this
value good?" but **"what was this value tuned against?"**
**RECOMMENDATION, needs Chiu. Not scheduled.**
→ `Docs/handoff-audit-2026-08-30.md` finding 4.

### The country table has six rows; the title card has no country name yet
`CountryExtent` is a built-in table — Chiu chose it over MapKit/`CLGeocoder`, so
**no new §0 exception**. **A country whose single box would be a lie is left out,
not approximated** (the US spans Alaska to Florida); unknown countries fall back
loudly. The name is available offline via `Locale.localizedString(forRegionCode:)`
— **so no persistence change was needed** — but wiring it into the card is not
done. → `Docs/handoff-crop-scaling.md` §11, §14.

### 🔴 CONFLICT — the pan floor is *not* what makes the destination a smudge
`Docs/camera-arcs.md` §5 and `Docs/handoff-camera-arc-findings.md` finding 5 both
say the pan floor is the mechanism. **It is false**: `bodySpanM` returns
`established / target_zoom_ratio` (~274 km) against a floor of ~16 km, and across
six `establishing` configurations the ratio is `target_zoom_ratio` in every one —
so the floor binds **nowhere**. **Two documents still state the superseded
premise.** → `Docs/handoff-cross-region-crossing.md` finding 1.

---

## ⏳ Awaiting a Chiu decision

### §0 — two films of real trips are committed to this repository
`Docs/demos/phase3/kamome-p3-recap.mp4` and
`Docs/demos/phase3_5/kamome-recap-NZ-disaster.MP4`, while practice writes films to
`~/Kamome-films/`. They are phase demo artifacts the Rules of Engagement require,
so two rules pull against each other, and **they are not in §0's decided-exceptions
list.** Either they become a recorded exception or they move out. **No check gates
this one, deliberately** — gating it would pre-empt the owner call.
→ `Docs/handoff-audit-2026-08-30.md` finding 7.

### Film length: two questions, in this order
**Duration must scale with trip size — direction decided (Chiu 2026-08-14), rule
NOT.** Every trip presents 8 stops and 24 photographs whether it has 10 or 65.
The candidate inversion hits all three of Chiu's targets, but its parameters were
reverse-derived from three trips — how `body_span_padding` and `tier_skip_share`
were derived, and both failed.

**Then travel pacing**, nothing decided: all three trips sit at the same ~49%
travel share, so what lost Chiu on Iceland was an **absolute quantity**, not a
proportion. `travel_max_s` names a thing that does not exist.
→ `Docs/handoff-pacing.md` for both, including the acceptance condition decided
in advance.

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
**Recommendation: confirm the current branch before committing, and stage explicit
paths only — never `-A` or `.`** Per `PO.md` this is a recommendation until Chiu
says otherwise.

### `stop_weighting_enabled` — measure before removing
Reachable in **both** modes; the containment argument is empirical and has never
been tested on a flat photograph distribution. The removal criterion was decided
in advance (Chiu 2026-08-07) so it is not re-litigated, and **a removal PR must
not cite "provably contained"**.
→ `Docs/handoff-stop-weighting.md`.

---

## ⚠️ Traps — read before you touch these

### A dead CI run looks like a passing one until you read the step count
Actions failed account-wide 2026-08-29 → 2026-09-01 (spending limit) in ~3 s with
**zero steps executed**, so `main` failed identically and no branch's check
carried information. CI is alive again (PR #26, 5m44s, green). **The tell is ~3 s
wall clock and `steps=0`** — anything with steps is a real signal.

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
`Config/Secrets.xcconfig` (no routing key → `drive/inferred`, straight lines not
roads) and no `Tests/Fixtures/trips/local/`. A before/after across worktrees is
then two different films and it looks plausible. Copy both, then count
`drive/reconstructed` in each log. **A render comparison without a "these two
must be identical" control row is not evidence.**
→ `Docs/handoff-crop-scaling.md` §3.

### ⚠️ CORRECTED — there is no render length limit; that was simulator contention
A whole film renders here: 2,070 frames in 96 s through `RecapRenderLoop`, 99 s
through `RecapExporter`. The earlier "70 s renders are SIGKILLed" claim was wrong
— six `xcodebuild` processes were competing for one simulator inside a
five-minute window, and the "control" run on `main` was confounded the same way.
**A control that shares the confound manufactures confidence.** Run
`pgrep -fl xcodebuild` before trusting any render result, and one at a time.
→ `Docs/handoff-crop-scaling.md` §9.

### Read a style value off the preset the app selects, never off the defaults
`RecapStyle`'s defaults are unrendered. This was got wrong twice from the same
source and cost a correction in the ledger both times. The app selects
`modernMinimal`.

---

## 🐛 Known bugs and accepted costs

- **The import date range clips at timezone edges** (2026-08-18). A photo from
  the first morning or last night of a trip can go missing. Cause is
  `Calendar.current` in `ImportFlowModel.dayBounds()`; a proper fix needs
  per-photo timezone. Workaround: widen the picked range by a day at each end.
- **`RecapMode` may be two axes, not one** (Chiu 2026-08-06). "Full stops, zero
  photographs" is the first variant needing one axis without the other. Recorded,
  not acted on.
- **Flat glacier** (Chiu 2026-08-06: leave it). The `ice` layer is opaque to kill
  a z6 tile seam, so the glacier renders without terrain texture. Cosmetic; the
  proper fix is a Planetiler rebuild — do not do that without asking.

→ all three: `Docs/handoff-known-bugs.md`.

---

## Older citations

`Docs/decisions.md` cites findings as **"`HANDOFF.md` <date> finding N"**. Those
sections moved on 2026-08-31: 2026-08-30 → `Docs/handoff-audit-2026-08-30.md`
(PO audit) or `Docs/handoff-cross-region-crossing.md` (the crossing session);
2026-08-29 → `Docs/handoff-marker-badge.md`; 2026-08-21 →
`Docs/handoff-camera-arc-findings.md`; travel pacing → `Docs/handoff-pacing.md`;
anything older → `Docs/_archive/handoff-2026-08.md`.

## Where the detail lives

| document | what is in it |
|---|---|
| `Docs/handoff-audit-2026-08-30.md` | the render-loop P0, the country beat, the owed sweep, the §0 question |
| `Docs/handoff-cross-region-crossing.md` | the crossing beat, the pan-floor correction, the snapshot bill |
| `Docs/handoff-crop-scaling.md` | crop-scaling, the budget split, the opening measurement |
| `Docs/handoff-type2-films.md` | the type-2 film: what MapKit can frame, the classifier, the open form |
| `Docs/handoff-marker-badge.md` | the fallback badge: what was decided, and the four gaps it left |
| `Docs/handoff-camera-arc-findings.md` | working analysis behind `Docs/camera-arcs.md` — **nothing settled** |
| `Docs/handoff-pacing.md` | film duration and travel pacing |
| `Docs/handoff-subject-lookup.md` | the silent subject fallback |
| `Docs/handoff-stop-weighting.md` | the removal criterion |
| `Docs/handoff-known-bugs.md` | the three items above, in full |
| `Docs/environment-gotchas.md` | routing, simulators, fixture shadowing, what `docker ps` answers |
| `Docs/phase4-reference.md` | Phase 4 scope, the snapshot freeze, the camera architecture |
| `Docs/rule-rationale.md` | why each rule in `CLAUDE.md` exists |
| `Docs/_archive/handoff-2026-08.md` | history — never a work instruction |
