# HANDOFF — live findings

**Updated 2026-09-02.** `main` carries PRs #16–#28. The crossing beat,
**crop-scaling** and **the title-card opening** are built, measured and **judged
by Chiu** (ADRs 2026-08-31, 2026-08-31 (b), 2026-09-01). The live line is the
**type-2 film form**.

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

## Findings — PO/Architecture session (2026-09-02)

**Chiu changed how this project is gated** (ADR 2026-09-02, read it before
planning work). **Phase 4 has no hard gate** — it closes when he judges a film,
and rule 7 is amended for that phase only. In exchange, **engineering owns that
the code does not break and that a release carries no security, licence or
privacy fault.** You may no longer answer "is this ready?" with a film.

**Your half is `Docs/release-readiness.md`** — new, superseding
`Docs/pre-launch.md` as the release gate (which keeps the reasoning). It sorts
every obligation by who can settle it: what `check.sh` holds, what is claimed but
enforced by nobody, and what only a device can answer. **Phase 4 item 3 is
dissolved** into it — that overlap is why "is item 3 done?" had no single answer.

Three findings VERIFIED there, none previously recorded:

- 🔴 **The app has no attribution string at all** — zero hits for `Geoapify`,
  `OpenStreetMap` or `Powered by` in either `.xcstrings`. Mandatory on the free
  plan: a licence condition. **No privacy notice string either.** → S2, S3.
- 🟠 **Dead config keys are three.** `export.total_duration_max_s` joins the two
  known ones, and it is the dangerous one — **film duration is an open question
  and this is the key anyone would reach for first.** → C1.
- ✅ **`RecapBudgetAndDemoTests`' export-time estimate is fixed** (C2), priced
  off `RecapRenderLoop.stations`: **0.79 s/snapshot → ~42 s for 53 stations**.
  That number is the input to `pre-launch.md` item 5; the device figure is
  still owed (`release-readiness.md` D2, D3).

**No new `Docs/eng-session-*.md`** (ADR 2026-09-02 §6): findings come here with a
pointer to a topic document.

---

## 🔴 Blockers

### ✅ CI is alive again as of 2026-09-01 — a red check means something now
From 2026-08-29 Actions jobs failed in ~3 s with **zero steps executed** (spending
limit). PR #26 ran `./check.sh` end to end in 5m44s and passed. **Treat a red
check as real again** — the dead-CI tell is ~3 s wall clock and `steps=0`.

### ✅ CLOSED — the shake, and the opening that came with it
Both judged and accepted by Chiu; the decisions, numbers and reasoning are ADRs
**2026-08-31** (the opening cuts out of a title card held over the country) and
**2026-08-31 (b)** (crop-scaling closes the P0). Detail:
`Docs/handoff-crop-scaling.md`.

What survives here as **live**, and only this:

- ⏳ The **0.747 sharpness step at hold boundaries** is *accepted as it stands*,
  not fixed. §7's remedy (cross-fade at a station boundary) costs no extra
  fetches and is not built. Revisit only if someone notices it in a film.
- ⚠️ **`keyframe_interval_frames` is dead config, one of three** — now gated by
  `check-dead-config.sh`. The test that divided by it was fixed 2026-09-02.
  → `Docs/release-readiness.md` C1, C2.

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
seagull instead of the car. Same mechanism as the old bundle crash, different
symptom. **The rate and the trigger are still unmeasured** — two log lines now
ship specifically to name the next occurrence.
→ `Docs/handoff-subject-lookup.md`.

### A sweep is owed: which values were tuned against MapLibre?
Five defects now share one shape — a value chosen while MapLibre was the
substrate that silently degraded when Apple Maps became what ships; the country
beat's `cappedToRegion` (fixed 2026-09-01) was the fifth. Each was found **one
film at a time, by accident**. The question that catches the class is not "is this
value good?" but **"what was this value tuned against?"**
**RECOMMENDATION, needs Chiu. Not scheduled.**
→ `Docs/handoff-audit-2026-08-30.md` finding 4.

### The country table has six rows; the title card has no country name yet
`CountryExtent` is a built-in table — Chiu chose it over MapKit/`CLGeocoder`, so
**no new §0 exception**: the lookup is point-in-box and no coordinate leaves the
process. **A country whose single box would be a lie is left out, not
approximated** (the US spans Alaska to Florida); unknown countries fall back
loudly. The name is available offline via `Locale.localizedString(forRegionCode:)`
— **so no persistence change was needed** — but wiring it into the card is not
done. → `Docs/handoff-crop-scaling.md` §11, §14.

### 🔴 CONFLICT — the pan floor is *not* what makes the destination a smudge
`Docs/camera-arcs.md` §5 and `Docs/handoff-camera-arc-findings.md` finding 5 both
say the pan floor is the mechanism. **It is false**: `bodySpanM` returns
`asked = established / target_zoom_ratio` (~274 km) against a floor of ~16 km.
Measured 2026-08-31 across **six** `establishing` configurations, from `nil` to an
extent far wider than the trip, the ratio is `target_zoom_ratio` (2.50×) in every
one — the floor binds **nowhere**, so this is a property of the function, not a
fact about one fixture. **Two documents still state the superseded premise.**
→ `Docs/handoff-cross-region-crossing.md` finding 1,
`Docs/handoff-crop-scaling.md` §4.

---

## ⏳ Awaiting a Chiu decision

### §0 — two films of real trips are committed to this repository
`Docs/demos/phase3/kamome-p3-recap.mp4` and
`Docs/demos/phase3_5/kamome-recap-NZ-disaster.MP4`, while practice writes films
to `~/Kamome-films/`. They are phase demo artifacts the Rules of Engagement
require, so two rules genuinely pull against each other, and **they are not in
§0's decided-exceptions list.** Either they become a recorded exception or they
move out. Otherwise checked and clean; **no check gates this one, deliberately** —
gating it would pre-empt the owner call.
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

### The shipped camera nearly touches the safe zone on the crossing
`RecapCameraContinuityTests` now scans **both** cameras (2026-09-02) — the
synthetic `establishing` extent and the `nil` the app actually ships. Two
results, and the second is yours:

- ✅ The old trap's premise is **gone** — body span is now identical in both.
- ⏳ **New, and yours.** The shipped camera frames the subject looser, and on
  `ishigaki-crossing` reaches **79.8% against the 80% limit** — a pass by 0.2
  points. **Nothing was relaxed to get it.** Whether 79.8% is acceptable is a
  bar question, not an engineering one.

→ `Docs/handoff-cross-region-crossing.md` finding 2, which is corrected there.

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
A 2026-08-31 entry here claimed a 70 s `RecapPilotFilmTests` render is SIGKILLed
on this Mac. **Wrong, not merely over-broad.** Re-run clean, 2026-09-01, whole
`ishigaki-crossing`: pilot **2070/2070 frames in 96 s**; `RecapExporter` via
`RecapDemoFilmTests` **2070 frames, 38.9 MB, 99 s**. The six failures all fell in
one five-minute window with **six xcodebuild processes on one simulator** (a
background script still alive, plus foreground runs launched believing it dead).

**Keep the reasoning, not the number.** A control run on `main` reproduced the
failure and was read as proof the defect was pre-existing. It shared the
confound, so it manufactured confidence instead of removing it. `pgrep -fl
xcodebuild` before trusting any render result.

### Read a style value off the preset the app selects, never off the defaults
`RecapStyle`'s defaults are unrendered. This was got wrong twice from the same
source and cost a correction in the ledger both times. The app selects
`modernMinimal`.

### Three gaps the badge work left on record
Nothing measures **post-grade** output; nothing asserts the end card's **brand
mark** (`RecapMarkerDeckStillsTests` writes stills and asserts nothing, so "the
end card still shows a bird" rests on a human noticing); and the **no-reader token
cluster is four**, counted so the next one to join is the fifth.
→ `Docs/handoff-marker-badge.md` findings 6c, 6d, 7.

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

`Docs/decisions.md` cites findings as **"`HANDOFF.md` <date> finding N"**. Those
sections moved on 2026-08-31: 2026-08-30 → `Docs/handoff-audit-2026-08-30.md`
(PO audit) or `Docs/handoff-cross-region-crossing.md` (the crossing session);
2026-08-29 → `Docs/handoff-marker-badge.md`; 2026-08-21 →
`Docs/handoff-camera-arc-findings.md`; travel pacing → `Docs/handoff-pacing.md`;
anything older → `Docs/_archive/handoff-2026-08.md`.

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
