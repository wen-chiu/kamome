# HANDOFF — live findings

**Updated 2026-09-02.** `main` carries PRs #16–#31. The crossing beat,
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

## The gating rule, and where your half lives

**Chiu changed how this project is gated** (ADR 2026-09-02, read it first).
**Phase 4 has no hard gate** — he judges the film; **engineering owns that the
code does not break and that a release carries no security, licence or privacy
fault.** Never answer "is this ready?" with a film. **Your half is
`Docs/release-readiness.md`**, which supersedes `Docs/pre-launch.md` as the gate
and sorts every obligation by who can settle it.

The 2026-09-02 session's four findings live there in full: S2/S3, S3b, C1 and C2.
⚠️ **One is open on purpose:** whether the import flow warns *at the point of
import* — a screen a user may never open is not a warning.

**No new `Docs/eng-session-*.md`** (ADR 2026-09-02 §6): findings come here with a
pointer to a topic document.

---

## 🔴 Blockers

### The shake is CLOSED; two things it left are not
ADRs **2026-08-31**, **2026-08-31 (b)**. The 0.747 sharpness step at hold
boundaries is accepted as it stands, and `keyframe_interval_frames` is dead
config, one of three. → `Docs/handoff-crop-scaling.md`, `release-readiness.md` C1.

### ⏳ The type-2 film is BUILT and judged — PR #31
Title card over the flight frame → the aircraft crosses **camera still** → the
arc closes into the destination → the destination's local trip. The origin's
drive is dropped, making every type-2 film `Docs/camera-arcs.md` §4 **Case C**.
⚠️ The type is derived and **monotonic**, so `>= 2 ⇒ the type-2 form` holds only
while type 3 is deferred.

### ⏳ The type-2 opening is RETIMED and the crossing carries a boarding pass
**ADR 2026-09-03.** `crossing_beat_s` is **4.0, not 6.0** — the 4/6/9 sweep is
closed and the ⭐ screen-speed rule it validated (~16.5–17 %/s) still stands; it
stopped being what the constant *chooses*. The beat is **as long as the Journey
Card takes to read**, and the sprite's speed is the consequence. **If it reads
rushed, de-emphasise the sprite, never re-lengthen the beat.**

Measured: **trip starts 13.09 s** (not the brief's 12.5), departure **3.59 s / 2
photographs**, sprite **24.6 %/s**, odometer **269 km** where it read 9,024.

**ADR 2026-09-04** laid the pass out to Chiu's mockup, gave the crossing a
**plane** (one condition decides the pass and the airframe; every other crossing
keeps the seagull), and put a mark **and its country's name** on each end of the
flight from t=0 to the landing — the closeout's *"the wide flight frame loses the
viewer"*, answered. The mark's artwork is `Resources/Landmarks/`, a
**placeholder**, with a logged vector fallback.
🔴 **Neither place-name lock is thawed**: the base map still draws nothing
(blocked on a fontstack), and the icebox entry is a whole-film narrative system
rather than two endpoints. `crossing_flight_max_longitude_deg` stays 70.
🔴 **No classifier: a ferry gets the pass and the plane too** — session 2's line,
unmoved. ⏳ `subject_length_px` untouched on purpose. ⚠️ The mockup's `FLIGHT TIME`
is **not** restored — removed by decision.

⏳ **Four visual questions are with the designer** (the card's second accent, the
`DISTANCE` icon, the origin mark's 3.59 s cut, and which name wins at the
airport). → `Docs/design-reviews/2026-09-04-open-questions-type2-opening.md`.

🔴 **The review film harness drew a different film for a round.**
`RecapDemoFilmTests` passed no `crossingSubject:`, which `FrameCompositor` reads
as "draw the trip's own vehicle" — so `auckland-crossing` drove a **car** across
the Pacific while the app drew a gull. **`VehicleCatalog` never failed**: the
subject-lookup miss below is untouched and still unmeasured. **Both crossing
renderers lost their defaults** — a defaulted nil is the silent fallback, and 12
call sites now say which they want.
→ `Docs/handoff-type2-opening-retime.md`, `Docs/design-reviews/2026-09-02-cross-region-opening.md`.

🔴 **A long-haul frame often does not exist, and the limit is degrees of longitude,
not kilometres.** MapKit saturates at **~109°**; **Taiwan→Iceland fails at every
padding**, so the frozen country card is a **main path**.

🔴 Of the closeout's five handed over, **two are answered** (the wide frame
2026-09-04, the beat 2026-09-03). Live: a **union-derived sweep is owed**,
**`subject_length_px` is absolute while the frame span moves 20×**, the **mode
classifier**, and **the card sums every crossing** (harmless until type 3).
→ `Docs/handoff-type2-films.md` closeout.

---

## 🟠 Open — nobody is on these

### 🔴 `Geo.distanceM` is equirectangular, and nobody has swept who reads it
It scales longitude by the cosine of the **first** latitude alone, so it degrades
over a long diagonal: **121 km short** over Taipei → Auckland (VERIFIED
2026-09-03), which is the 8,755 km quoted throughout `handoff-type2-films.md`.
Harmless for the camera — `cumulativeM`, the dead zone, stop anchoring and the
body span are **one consistent axis** — and not harmless the moment a figure
reaches a viewer. `Geo.greatCircleM` sits beside it and the Journey Card uses it;
`distanceM` was deliberately **not** changed, which would move every film to fix
a printing defect. ⚠️ **The sweep is owed and cheap**: which other
`Geo.distanceM` results are shown to someone?
→ `Docs/handoff-type2-opening-retime.md`.

### Content-derived pacing may be implemented but permanently dead
If the second clause of a `RecapModel.swift` comment is true, it sits behind a
tile condition that can never be satisfied. **UNKNOWN, worth an hour.**
→ `Docs/handoff-audit-2026-08-30.md` finding 3.

### The subject lookup still misses; it no longer crashes
`VehicleCatalog.resolve` returns nil and the film silently draws the vector gull.
**Rate and trigger still unmeasured** — and **not** what drew the car across the
Pacific (2026-09-04). → `Docs/handoff-subject-lookup.md`.

### A sweep is owed: which values were tuned against MapLibre?
Five defects share one shape — a value chosen while MapLibre was the substrate,
silently degraded when Apple Maps became what ships, each found **one film at a
time, by accident**. The question is **"what was this value tuned against?"**
**RECOMMENDATION, needs Chiu. Not scheduled.**
→ `Docs/handoff-audit-2026-08-30.md` finding 4.

### The country table has six rows; the title card has no country name yet
`CountryExtent` is a built-in table, so **no new §0 exception**, and a country
whose single box would be a lie is left out rather than approximated. The name is
available offline — the **boarding pass** now uses it (ADR 2026-09-03) — but the
*title card* still shows trip title + dates. → `Docs/handoff-crop-scaling.md` §11.

### 🔴 CONFLICT — the pan floor is *not* what makes the destination a smudge
**Two documents still state the superseded premise**; measured, the ratio is
`target_zoom_ratio` in every configuration and the floor binds nowhere.
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

### The crossing beat — two things still defaulted
Open, and Chiu's: whether the crossing seagull stays a choosable trip subject (it
ships `selectable: true` against the `plane`/`boat` precedent), and whether the
apex wants a hold. ✅ Case C is built and ✅ `crossing_beat_s` is 4.0.
→ `Docs/handoff-cross-region-crossing.md` finding 9.

### A staging rule for `Arch.md` — recommended, not in force
A branch ref has silently picked up another session's commits three times, and a
`git add -A` swept an unrelated file into an unrelated commit **twice** (latest
2026-09-03, a MapLibre `Package.resolved` churn, amended out before the PR).
**Confirm the branch before committing; stage explicit paths, never `-A`.**
A recommendation until Chiu says otherwise (`PO.md`).

### `stop_weighting_enabled` — measure before removing
Reachable in **both** modes; the containment argument is empirical and has never
been tested on a flat photograph distribution. The removal criterion was decided
in advance (Chiu 2026-08-07) so it is not re-litigated, and **a removal PR must
not cite "provably contained"**.
→ `Docs/handoff-stop-weighting.md`.

---

## ⚠️ Traps — read before you touch these

**Two render traps are in `Docs/_archive/handoff-2026-08.md`** and both still
bite: a worktree renders a different film (`Config/Secrets.xcconfig` and
`Tests/Fixtures/trips/local/` are gitignored), and there is **no** render length
limit — the SIGKILLs were six `xcodebuild` processes on one simulator, so
`pgrep -fl xcodebuild` first and render one at a time.

### A dead CI run looks like a passing one until you read the step count
Actions failed account-wide 2026-08-29 → 2026-09-01 (spending limit) in ~3 s with
**zero steps executed**, so no branch's check carried information. **The tell is
~3 s wall clock and `steps=0`.**

### Continuity passing is not the film being right
The gate measures **ground overlap between consecutive frames**, so a camera that
is wrong without *moving* passes perfectly. Measured 2026-09-02: a body span
derived from the wrong beat came out at 177.3 km against 13.3 km and scored
**100%** — a still film with the destination a smudge. **When a change re-derives
a span, a frame or a padding, the gate is not the check**: read `span`, and render.

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
sections moved on 2026-08-31; the map from each date to the file that now holds
it is in `Docs/_archive/handoff-2026-08.md`, "Resolving older citations".

## Where the detail lives

| document | what is in it |
|---|---|
| `Docs/handoff-audit-2026-08-30.md` | the render-loop P0, the country beat, the owed sweep |
| `Docs/handoff-cross-region-crossing.md` | the crossing beat, the pan-floor correction |
| `Docs/handoff-crop-scaling.md` | crop-scaling, the budget split, the opening |
| `Docs/handoff-type2-films.md` | the type-2 film, what MapKit can frame, the closeout |
| `Docs/handoff-type2-opening-retime.md` | the retime, the boarding pass, the measured numbers |
| `Docs/handoff-marker-badge.md` | the fallback badge and the gaps it left |
| `_archive/handoff-camera-arc-findings.md` | working analysis behind `camera-arcs.md` — **nothing settled** |
| `Docs/handoff-pacing.md` | film duration and travel pacing |
| `Docs/handoff-subject-lookup.md` | the silent subject fallback |
| `Docs/handoff-stop-weighting.md` | the removal criterion |
| `Docs/handoff-known-bugs.md` | the three items above, in full |
| `Docs/environment-gotchas.md` | routing, simulators, fixture shadowing |
| `Docs/phase4-reference.md` | Phase 4 scope, the camera architecture |
| `Docs/rule-rationale.md` | why each rule in `CLAUDE.md` exists |
| `Docs/_archive/handoff-2026-08.md` | history — never a work instruction |
