# HANDOFF — live findings

**Updated 2026-09-02.** `main` carries PRs #16–#28. The crossing beat,
**crop-scaling** and **the title-card opening** are built, measured and **judged
by Chiu** (ADRs 2026-08-31, 2026-08-31 (b), 2026-09-01). The live line is the
**type-2 film form**.

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

### ✅ CLOSED — the shake, and the opening that came with it
Judged and accepted by Chiu; reasoning in ADRs **2026-08-31** and **2026-08-31 (b)**.
Detail: `Docs/handoff-crop-scaling.md`. Live remainder, and only this:

- ⏳ The **0.747 sharpness step at hold boundaries** is *accepted as it stands*, not
  fixed. §7's remedy costs no extra fetches and is not built. Revisit only if
  someone notices it in a film.
- ⚠️ **`keyframe_interval_frames` is dead config, one of three** — now gated by
  `check-dead-config.sh`. → `Docs/release-readiness.md` C1, C2.

### ⏳ The type-2 film is BUILT and judged — PR #31
Chiu's three film types (2026-09-01, **not in `decisions.md`**): 1 local, 2 home →
one destination abroad, 3 multi-region (deferred). Type 2: title card over the
flight frame → the aircraft crosses **camera still** → the arc closes into the
destination → the destination's local trip. The origin's drive is dropped, making
every type-2 film `Docs/camera-arcs.md` §4 **Case C**. `ishigaki-crossing`:
69.0 → **60.0 s**, span 20.0 → **13.3 km**, snapshots 178 → **135**, opening **1**.
Films: `~/Kamome-films/type2-2026-09-02/`.

The type is **derived, never stored**, and **monotonic**: an unrouted leg can only
*add* a local journey, so a confirmed crossing means at least a type 2. ⚠️ `>= 2 ⇒
the type-2 form` holds only while type 3 is deferred, and the same trip yields
different films on different days — sharpening ADR 2026-08-15's unmet export record.

✅ **`crossing_beat_s` stays 6.0** (Chiu, 4/6/9 sweep). ⭐ His two picks are **the
same screen speed to within 5%** (17.25 vs 16.33 %/s of frame width), so
`frameShare / target_screen_speed` is validated by his eye on two films 29× apart —
**no new sweep is needed** when this is revisited.

🔴 **A long-haul frame often does not exist, and the limit is degrees of longitude,
not kilometres.** MapKit saturates at **~109°**; a 9:16 frame runs off the poles
first at low latitudes. **Taiwan→Iceland fails at every padding**, so the frozen
country card is a **main path**.

🔴 Three handed over: **the wide flight frame loses the viewer** at long haul
(mirror of `handoff-P3.5.md` §"Map reference labels"; threshold stays 70 and is
probably wrong — **Chiu is deciding**); **a union-derived sweep is owed** (the end
reveal was the third such quantity, after the body span and beat 2); and
**`subject_length_px` is absolute while the frame span moves 20×**.
→ `Docs/handoff-type2-films.md` closeout.

---

## 🟠 Open — nobody is on these

### Content-derived pacing may be implemented but permanently dead
A shipping-path comment in `RecapModel.swift` is wrong on its first clause. If its
*second* clause is true, content-derived pacing sits behind a tile condition that
can never be satisfied. **UNKNOWN, worth an hour.**
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
say the pan floor is the mechanism. **It is false**: across six `establishing`
configurations the ratio is `target_zoom_ratio` in every one, so the floor binds
**nowhere**. **Two documents still state the superseded premise.**
→ `Docs/handoff-cross-region-crossing.md` finding 1.

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

### The crossing beat — three things still defaulted
Open, and Chiu's: whether the crossing seagull stays a choosable trip subject (it
ships `selectable: true` against the `plane`/`boat` precedent); whether the apex
wants a hold; and Case C — a trip that *begins* with the crossing — **is now built**
(2026-09-02, every type-2 film). ✅ `crossing_beat_s` 6.0 **has** now survived a
judged film.
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

**Two render traps moved to `Docs/_archive/handoff-2026-08.md` on 2026-09-02** and
both still bite: a worktree renders a different film (`Config/Secrets.xcconfig` and
`Tests/Fixtures/trips/local/` are gitignored), and there is **no** render length
limit — the SIGKILLs were six `xcodebuild` processes on one simulator, so
`pgrep -fl xcodebuild` first and render one at a time.

### A dead CI run looks like a passing one until you read the step count
Actions failed account-wide 2026-08-29 → 2026-09-01 (spending limit) in ~3 s with
**zero steps executed**, so `main` failed identically and no branch's check
carried information. CI is alive again (PR #26, 5m44s, green). **The tell is ~3 s
wall clock and `steps=0`** — anything with steps is a real signal.

### Continuity passing is not the film being right
The gate measures **ground overlap between consecutive frames**, so a camera that is
wrong in a way that does not *move* passes it perfectly. Measured 2026-09-02: a
body span derived from the wrong beat came out at 177.3 km against 13.3 km and
scored **100% frame-to-frame overlap** — a flawless score, and a still film with the
destination a smudge. **When a change re-derives a span, a frame or a padding from a
different beat, the gate is not the check**: read `span` on its own line, and render.

### Do not restyle `VehicleMarker.seagull` in place
It is **also the Kamome wordmark's bird on the end card**. The obvious badge
implementation would have silently turned the brand mark on every end card into
a blue disc, and no test asserts the end card's mark shape. The bare gull now has
three consumers: the brand mark, the fault badge (its own case), and the
cross-region narrator that has not been built.
→ `Docs/handoff-marker-badge.md` finding 5b.

### `Docs/camera-arcs.md` §8 states an invariant no arc can satisfy
"No exemption, none at all" cannot hold for an arc that re-frames across a
discontinuity; the gate's `permittedCutTimesS` is the mechanism that does hold, and
it has never needed to excuse anything (0 excused on all eight fixtures).
→ `Docs/handoff-cross-region-crossing.md`.

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
| `Docs/handoff-audit-2026-08-30.md` | the render-loop P0, the country beat, the owed sweep |
| `Docs/handoff-cross-region-crossing.md` | the crossing beat, the pan-floor correction |
| `Docs/handoff-type2-films.md` | the type-2 film, what MapKit can frame, the closeout |
| `Docs/handoff-crop-scaling.md` | crop-scaling, the budget split, the opening |
| `Docs/handoff-type2-films.md` | the type-2 film: what MapKit can frame, the classifier, the open form |
| `Docs/handoff-marker-badge.md` | the fallback badge and the gaps it left |
| `Docs/handoff-camera-arc-findings.md` | working analysis behind `camera-arcs.md` — **nothing settled** |
| `Docs/handoff-pacing.md` | film duration and travel pacing |
| `Docs/handoff-subject-lookup.md` | the silent subject fallback |
| `Docs/handoff-stop-weighting.md` | the removal criterion |
| `Docs/handoff-known-bugs.md` | the three items above, in full |
| `Docs/environment-gotchas.md` | routing, simulators, fixture shadowing |
| `Docs/phase4-reference.md` | Phase 4 scope, the camera architecture |
| `Docs/rule-rationale.md` | why each rule in `CLAUDE.md` exists |
| `Docs/_archive/handoff-2026-08.md` | history — never a work instruction |
