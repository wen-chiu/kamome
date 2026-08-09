# HANDOFF — current state

**Updated 2026-08-08.** Branch `feature/typed-legs-routing` (PR #12 → `phase-3-recap`;
PR #11 is `phase-3-recap` → `main` and holds until the §6 gate). Written so a fresh
session (or a fresh person) can pick this up without being briefed by hand.

Read `CLAUDE.md` first for the standing rules — especially **§0, location data
never leaves the device**, which constrains the fixture work below more than
anything else here.

Scope notes: `Docs/handoff-P3.5.md` is the Replay MVP work order;
`Docs/gate-P3.5-checklist.md` is the §6 gate runbook. This file is the *session
state* on top of them — what is done, what is open, and why.

---

## ⏳ AWAITING OWNER REVIEW — round 3 renders, nothing closed (2026-08-08)

**No bug here is closed until Chiu has reviewed the rendered before/after.**
Round 3 supersedes rounds 1 and 2; review round 3 only.

| round | Iceland opening | car | first photo | establishing → body |
|---|---|---|---|---|
| before any fix | 5.50 s | 4.27 s | 8.90 s | 291.5 → 291.5 km (**no zoom**; 120 km sideways slide) |
| 1 (PR #12) | 3.00 s | 1.77 s | 6.50 s | 291.5 → 291.5 km (slide removed, still flat) |
| 2 | 6.50 s | 5.27 s | 9.90 s | 921.1 → 736.8 km = 1.25× |
| **3 (current)** | **5.50 s** | **4.27 s** | **8.90 s** | **736.8 → 294.7 km = 2.50×** |

Round 3 is Chiu's ask after seeing round 2: **open at the whole-trip framing
(737 km) and zoom in to the close body shot**, rather than opening wider still and
zooming only slightly. It needed `body_span_padding` split out of
`wide_span_padding` — see CLAUDE.md, the wide baseline is superseded.

**New Zealand changed in round 3**, having been identical through rounds 1–2:

| | round 2 | round 3 |
|---|---|---|
| opening | 6.50 s | **9.00 s** |
| car | 5.27 s | **7.77 s** |
| first photo | 7.70 s | **10.20 s** |
| establishing → body | 845.3 → 510.6 km (1.66×) | **845.3 → 204.2 km (4.14×)** |

`body_span_padding` is global, so NZ's body tightened too and its country beat now
survives, giving a three-stage opening (country → regional → body) and a 4.14×
zoom. **Nobody asked for this and it has not been judged** — it is a consequence,
not a decision. If NZ's opening is now too long or its body too tight, the lever
is `body_span_padding`, or making it per-trip.

**Car timing follows the opening** and was not touched: 1.77 s (round 1) → 5.27 s
(round 2) → 4.27 s (round 3), always `openingS − zoom_transition_s`.

### What it actually was

Not the enum migration, not the naming commit, not the stop pins. The bisect in
the previous version of this section was chasing a regression that was not one:
**every fixture had this defect from the moment the wide baseline landed**, and
New Zealand was simply the first whose numbers crossed the floor.

`cappedToRegion` refuses to frame ground the installed tiles cannot draw. When a
trip nearly fills its region — the real Iceland ring road does, and NZ's bounding
box is 205 km wide by 74 km tall so the widest *portrait* frame fitting inside it
is only 41 km — that cap lands on the same span the body camera uses. The "wide"
establishing beat is then no wider than the body: there is no establishing shot to
be had. It stayed centred on the trip anyway, so the closing zoom had no zoom left
in it and was a pure translate from the middle of the trip to its start.

| fixture | pan ÷ span across a snapshot | verdict |
|---|---:|---|
| new-zealand | 0.69 | ❌ over the 0.60 floor |
| nz-real | 0.46 | passed, same defect |
| iceland (committed) | 0.32 | passed, same defect |
| iceland (real, 65 stops) | 120 km at a flat 291.5 km span | passed, same defect |

**Two things were wrong, one behind the other.**

1. A wide beat that cannot contain the trip must frame the journey's *start* — an
   establishing shot with nothing wider to say should establish where the trip
   begins. Beats that can contain the trip are untouched, so the ordinary case
   (region wider than the trip) keeps country-then-region exactly as before.
2. `bodyFrame` claimed to be "what the follow simulation converges on" and was
   only where the dolly *starts*. The vehicle waits at the route's origin through
   the opening — `buildTimeline` gives that stretch an explicit `.travel(0, 0)`,
   so it is stationary but **not parked** — and the dead-zone spring runs the whole
   time and settles on the dead-zone boundary around it, 25 km away on NZ. Both
   the wide beat's anchor and the closing-zoom decision were reading it.
   `FollowCamera.restingFrame` now states the simulation's fixed point in closed
   form and `bodyFrame` delegates to it.

`FollowCameraRestingFrameTests` measures prediction against simulation on every
fixture (0–43 m committed, 669 m worst case on the real Iceland dump = 0.46% of a
144 km frame) and measures the seam itself. Do not let those drift.

### Effect on the real films — checked against the ground rule

Measured with the installed regions, before vs after:

| trip | change |
|---|---|
| New Zealand (20 stops) | **none, in any respect** |
| Iceland (65 stops) | drops a 2.5 s beat that held span flat at 291.5 km while panning 120 km sideways; everything downstream starts 2.43 s earlier; total length unchanged at 90 s |

Iceland is a film Chiu has already judged, so this is a visible change to it.
Rendered before/after delivered 2026-08-08; **awaiting his review.**

**Byte comparison cannot answer the NZ question.** A control render — identical
code, run twice — produced a *larger* file-size spread (7.11 vs 7.43 MB) than
before-vs-after did (7.11 vs 7.31 MB). The MP4/MapLibre path is **not
byte-deterministic**, so pixel identity is not available as evidence. The
"unchanged" claim rests on the timeline and camera-path measurements, which are
identical across all three runs (opening ends 6.50 s · first stop 6.70 s · first
photo 7.70 s · car 5.27 s). Say it that way; do not claim pixel identity.

### The test that was pinning the bug

`testOpeningCollapsesBeatsThatDoNotMoveTheCamera` built its extent from the trip's
own bounds — but that sample route is a straight north-south line, so the box had
**zero longitude extent**, `containedSpanM` came out 0, and both wide beats floored
onto `camera_span_m`: a 1.5 km frame for an 89 km trip, and what "still ran" was a
45 km translate across thirty frame-widths. It now uses a snug region with actual
area, which collapses the beats *and* zooms, as the test says it does.

**Worth keeping:** a synthetic extent built from a synthetic route can be
degenerate in ways real map regions never are. A region has area.

### Still true from the old section

- **Fixture shadowing is real.** `RecapTripFixtures.tripFixture` prefers
  `Tests/Fixtures/trips/local/<name>.json` (real dumps, gitignored per §0) over the
  committed fixture. Local and CI therefore test different geometry — NZ is 20
  stops locally, 3 on CI. To reproduce CI, move `local/` **outside the repo**
  (not to a dotfile inside it — only `Tests/Fixtures/trips/local/` is gitignored)
  and re-run.
- **`850a995` does not compile.** A parallel session's push swept in an
  uncommitted edit and CI died at lint before building. Harmless at the tip;
  `git bisect` across it will hit it.

---

## ▶ Substrate decision — OSRM + MapLibre, behind swappable boundaries (2026-08-08)

**Canonical text and full rationale: `Docs/decisions.md` 2026-08-08.** Summary:

> The MVP rendering and routing substrate is OSRM + MapLibre because it is
> already implemented and validated against real trips. The application must keep
> routing and rendering behind stable boundaries so future releases may substitute
> MKDirections + Apple Maps without changing the story model or replay pipeline.
>
> Pixel Art remains a post-MVP visual differentiation path enabled by retaining
> MapLibre.

**Do not re-open or re-argue this.** MapLibre is retained precisely because it is
the only substrate that keeps the Pixel Art / custom-map identity path viable —
a deliberate trade-off. Any Apple Maps evaluation happens after MVP validation
and is settled by **rendered A/B comparison**, never by reasoning about
story-model independence.

**Deferred by decision, not by blocker** — do not pick up opportunistically, even
if one looks like a quick win while you are in the area:

- MKDirections integration
- the Apple Maps substrate (MKMapSnapshotter / MKDirections / any Apple-Maps
  rendering path)
- Pixel Art theme implementation (spike branch stays parked)
- an Apple-Maps label workaround as a MapLibre glyph substitute

MapLibre place labels stay iceboxed on the glyph/fontstack problem. **That Apple
Maps supplies labels for free is explicitly out of scope as an argument.**

**Superseded:** an earlier 2026-08-08 note here recorded "the app ships Apple
Maps, MapLibre is Chiu's own MVP path". That is no longer the decision.

### What this changes about `establishing` — now core-path, not a prerequisite

`establishing` is a single `RecapBounds?` carrying **two unrelated facts**:

| fact | kind | read by |
|---|---|---|
| how long the film runs / how stops are weighted | **story** | `LinearTimeline.pacing` |
| how wide the camera may frame before it runs off the tiles | **render** | `CameraPath.cappedToRegion` |

Pacing must never query tile coverage. The span cap legitimately must. Because
they share one parameter there is no way to have one without the other, and a
trip no installed region covers falls back to a flat 30 s film with no prologue.

On the committed substrate this is a **core-path defect**, not an Apple-Maps
prerequisite: any trip outside the four installed dogfood regions hits it.

## ▶ Pre-Phase-2 blocker — OSRM hosted-endpoint TOS unverified (2026-08-08)

The OSRM **demo/hosted endpoint's terms of service for commercial use have not
been verified.** Not urgent for the personal-use MVP (the desk harness points at
a local server), but it is a **blocker on routing-endpoint configuration work
before Phase 2** — shipping an app that calls a public demo endpoint is a
licensing question, not an engineering one. Resolve before any release that
routes on someone else's server. Related, still open: the shared-token auth work
in `Docs/handoff-P3.5.md`, which must ship server and app halves together.

## ✅ CLOSED — lint split (2026-08-07, landed as `4460d8d` / `850a995` / `6ae62a7`)

**Status: `swiftlint --strict` is clean project-wide (0 violations, 141 files),
full suite green (249 tests, 0 failures), both `RecapCameraContinuityTests` gates
pass.** The 10 violations tracked below are all fixed. Verified with:

```
XCODE_DEFAULT_TOOLCHAIN_OVERRIDE=/Library/Developer/CommandLineTools swiftlint lint --strict
```

**What actually shipped, vs. the plan this section used to describe:** the
`CameraPath.init` extraction alone (`openingPlan`, as originally planned) got the
initialiser from 82→71 lines — nowhere near the ≤50 limit, because most of the
82 lines were comments (excluded from the count either way). Getting
`CameraPath.swift` clean needed the full "option 1" struct/statics split below
*and* two more initializer extractions (`bodySpan`, `simulatedTrack`) beyond what
was written here. Left as a record for next time a "roughly N lines" estimate
shows up in a handoff: re-derive it from `swiftlint --strict` output, don't trust
the arithmetic.

| file | was | now |
|---|---|---|
| `Core/ExportEngine/CameraPath.swift` | file 555, struct body 325, init 71 | 0 violations |
| `Tests/AppTests/RecapDemoFilmTests.swift` | file 447, class 283, func 63 | 0 violations |
| `Tests/CoreTests/CameraPathTests.swift` | file 404, class 301 | 0 violations |
| `Core/ExportEngine/FollowCamera.swift` | func 71 | 0 violations |
| `Tests/CoreTests/RecapPacingTests.swift` | class 253 | 0 violations |

### `CameraPath.swift` — "option 1" landed as designed

Moved `Position`, `Phase`, `TimelineEntry`, `Hold`, plus the pure statics
(`distance`, `travelSeconds`, `coordinate(atDistance:route:cumulativeM:)`,
`smoothstep`, `stopAnchors`, `cappedToRegion`, `bodyFrame`, `confine`) into a new
file, `Core/ExportEngine/CameraPathCore.swift` — an `extension CameraPath`
alongside the existing `CameraPathActs.swift` / `CameraPathPrologue.swift`
pattern. `bodyFrame` and `confine` went `private static` → `static`, same as the
existing statics in that file; nothing else changed access level. No instance
member moved or widened — the construction/sampling split Chiu rejected earlier
stays rejected.

Two more pure-static extractions came out of the initializer beyond the original
plan, once "extract `openingPlan`" alone proved insufficient (see above): `bodySpan`
(the provisional-timeline + capped-span calculation) and `simulatedTrack` (the
per-frame body-camera simulation), both also in `CameraPathCore.swift`. Both took
>6 positional parameters, so each got a small request struct
(`BodySpanRequest`, `TrackRequest`) rather than tripping
`function_parameter_count` — same shape as `OpeningRequest`/`OpeningPlan` in
`CameraPathPrologue.swift`.

### The other four files — mechanical, same recipe throughout

Every fix was "split a class/file, or extract one self-contained function,"
never a behavior change:

- **`FollowCamera.track`** (71-line function): the per-frame physics step
  extracted into a private `step(_:point:parked:constants:)`, carrying state
  through a new `SimState` struct and constants through `StepConstants` — the
  `for` loop in `track` now just calls `step` once per frame. Same computation,
  same order, nothing behavioral changed.
- **`CameraPathTests.swift`** (file 404, class 301): the "Dead-zone follow
  camera" `MARK` section (10 tests) moved to `CameraPathContinuityTests.swift`
  as `extension CameraPathTests`. Its fixtures (`straightRoute`, `longRoute`,
  `exportConfig`) went `private` → internal (no `private` keyword) since
  `private` is file-scoped and the extension is a different file — the same
  constraint that shaped the `CameraPath.swift` split above.
- **`RecapPacingTests.swift`** (class 253, only 3 over): the "Opening sequence"
  `MARK` section (3 tests) moved to `RecapPacingOpeningSequenceTests.swift` the
  same way; `config`, `deck`, `timeline`, `establishing` went internal.
- **`RecapDemoFilmTests.swift`** (file 447, class 283, func 63): `GPXFilmParser`
  (self-contained, unrelated to the class) moved to its own file unchanged.
  `photoTile(index:)` never used `self`, so it became a free function in
  `RecapDemoFilmAssets.swift` — the call site didn't even need to change.
  `importedRecap`'s per-stop photo-selection loop became
  `RecapDemoFilmTests.stopPhotoSelections(detail:full:)` in
  `RecapDemoFilmStopPhotos.swift`, returning a `StopPhotoSelections` struct
  (three dictionaries would have tripped `large_tuple`).

**Ran `xcodegen generate` after adding each new file** — the `.xcodeproj` is
generated and didn't pick up new files under `Tests/AppTests` until regenerated
(silent "cannot find X in scope" otherwise; `Core/ExportEngine` picked up its new
file without regenerating, so this is inconsistent — worth remembering, not worth
chasing down further right now).

### Two gates guard `CameraPath.swift` — reconfirmed green, not just assumed

`RecapCameraContinuityTests` samples `cameraFrame(atTime:)` frame by frame (≥50%
shared ground) and the subject-margin gate samples `position(atTime:)` (≤80% of
the half-frame). Both ran and passed after the full split, not just after the
`openingPlan` step.

### Landed

Both commits are in (`4460d8d` CameraPath split, then the other four files), plus
`6ae62a7`'s `RecapMode` migration. The push gave CI its first verdict on these 90
commits, and it came back red on the continuity gate — see the closed section at
the top of this file for what that turned out to be.

**The claim this section originally made — "both gates pass" — was true locally
and false on CI**, because of fixture shadowing. That is the third instance in one
session of validating under a different configuration than CI enforces
(`swiftlint` without `--strict`; the macos-15 / Xcode-26.6 gap; this). **Check
local-vs-CI parity explicitly; do not assume it.**

---

## Committed on this branch

- `762b8cb` **fix(recap)** — the opening hands over to where the camera is
  (continuity gate green; see the closed section at the top).
- `6ae62a7` **refactor(config)** — one `RecapMode`, replacing three booleans.
  `recap_mode: "highlight"` replaced `tiering_enabled`, `uncapped_enabled`,
  `photo_allocation_enabled` and `tier_skip_share` — **those keys no longer
  exist**; earlier notes in this file that mention them describe history.
- `4460d8d` / `850a995` **refactor(recap)** — the `swiftlint --strict` split.
  ⚠️ `850a995` does not compile in isolation.
- `94a864e` **feat(import)** — `PHAsset.isFavorite` plumbing and the opaque ice
  layer.
- `6f44b57` **docs(adr)** — the budget law, written down once (`Docs/decisions.md`).
- `ea32ce9` **feat(recap)** — kept-stop count derived from the film's duration.
- `69b5ad5` **fix(recap)** — stop pins sit on the route (two bugs, one symptom).
- `2b7b657` **fix(naming)** — landmark → town → address, never "Unnamed stop".
- `229ab39` and earlier — see `git log`.

**Working tree is clean as of 2026-08-08 and PR #12's CI is green** (run
31250437647). `RecapReviewGeocoder` and the quiet-stop pins referenced by earlier
versions of this section landed with the commits above — verify against
`git status` rather than trusting this list.

**Not merged to main:** PR #11 (`phase-3-recap` → `main`) holds until the §6 gate
passes (owner call). PR #12 stacks on it.

`Tests/Fixtures/trips/local/` is gitignored and always dirty by design; that is
real trip data and must never be added — nor moved to another path inside the
repo, which is not covered by the ignore rule.

## "Unnamed stop" — CLOSED 2026-08-04

Verified on the iPhone 17 Pro simulator against the real 170-photo Iceland
library imported through the actual S1 → S3 flow (18 stops):

- wait for naming, then export → **18 of 18 stops named**;
- with the gate temporarily removed → the export screen opens with **6 of 18
  still unnamed**, which is the original failure reproduced.

What went wrong before, and the lesson worth keeping: the 2026-08-03 throttle fix
was reported green against `GeocodePolicy` alone — a pure struct with no queue,
no retry and no database — while `StopNamer` owned a concrete `CLGeocoder` and
was therefore unreachable from any test. **The desk render path never geocodes at
all** (`RecapDemoFilmTests.importedRecap` builds an in-memory DB and reads
`stop.name ?? "Unnamed stop"`), so no amount of desk rendering could ever have
verified it. Naming runs only from `TripDetailModel.load()`.

Now in place:

- `App/Services/StopGeocoding.swift` — the protocol seam; `CLGeocoderStopGeocoder`
  is the only place CLGeocoder lives.
- `StopNamer` reports `Progress`; S3 shows "Identifying stops… n of N" and
  disables the film button until every stop has left the queue.
- `Tests/AppTests/StopNamerTests.swift` — three deterministic tests over a stub,
  plus `testLiveGeocoderNamesStops` (env-gated, real network, passed 3/3 on the
  simulator). The throttle test was validated by *reverting the fix*: without it
  the third lookup fires 1.5 ms after the second.

---

## Deck budget — RESOLVED 2026-08-06 (`ea32ce9`, ADR in `Docs/decisions.md`)

**The defect.** Above roughly ten presented stops, every stop showed a single
photograph: the duration ceiling scaled all dwells down by one global factor and
`deck_photo_min_hold_s` then truncated each deck to what its window could afford.

**The fix.** How many stops a film may present is now *derived from its duration*
rather than configured — see the ADR for the formula and the reasoning. A 120 s
film keeps 11 stops for a 65-stop trip and a 20-stop trip alike, each showing 3
photographs, with no per-trip tuning.

**The evidence, kept because it is what the law was built from:**

| trip | presented stops | film | photos per stop |
|---|---:|---:|---|
| Iceland | 65 | 30 / 60 / 90 / 180 / 195 s | **1 at every length** |
| Iceland | 25 | 195 s | 1 |
| Iceland | 14 | 195 s | 2 |
| Iceland | 7 | 195 s | 6 |
| New Zealand | 20 | 90 s | 1 |
| New Zealand | 20 | 195 s | 2.9 mean |

Duration alone never fixed it — above ~20 presented stops no watchable length
works, so the lever is *how many stops the film presents*.

**Why CI never caught it.** The committed fixtures are Iceland 16 photos/6 stops
and New Zealand 13/3, both just under the cliff.
`RecapDeckBudgetTests.testARealScaleTripDoesNotCollapseToOnePhotoPerStop` builds a
20-stop trip arithmetically and guards it. It is still wrapped in
`XCTExpectFailure` **because it measures the default policy, which has not
changed** — it skips itself under `.highlight` (see `RecapDeckBudgetTests`), which
is now the shipped `recap_mode`. Remove the expectation only when the default mode
is one that provably prevents the collapse for every trip size.

**Superseded and gone:** `tier_skip_share` as a tuning knob — the config key no
longer exists (it needed 0.82 for Iceland and 0.5 for NZ, which is what prompted
the ADR). `StopWeighting`'s
waypoint threshold remains in the tree but was measured as far too conservative to
matter — 8 of 65 stops on Iceland — and is not the mechanism anything relies on.

**Measurement aids, marked temporary in-code:** `Export.withTotalDuration`,
`RecapDeckBudgetTests.testReportRealFixtureBudgetSweep` (`KAMOME_BUDGET_FIXTURE`,
`KAMOME_BUDGET_DURATIONS`), and `KAMOME_FORCE_DURATION_S` in the render harness.

---

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

## Phase 2 (real app release) — parked, not blockers for Phase 1

Phase 1 is Chiu's own desk-rendered films at release visual quality. These three
matter only for an App Store release and are deliberately not being solved now
(Chiu 2026-08-05):

- **On-device render time is unmeasured.** Iceland at 6m44s is 12,110 frames and
  took ~1000 s on this Mac. The only budget ever discussed is "<90 s for a 30 s
  film". A long film on a phone could be tens of minutes — this is the single
  biggest viability risk for uncapped mode on device.
- **Routing endpoint.** The app ships `matching.base_url: ""`, so a real user's
  film is dashed everywhere while desk pilots (pointed at a live OSRM) draw solid.
  Either ship a server, bundle route data, or accept dashed — a product decision.
- **Device-representative run.** No import→Trip Detail→export run has ever been
  done with the experimental modes on. iCloud-resident photos, memory and thermals
  at 12k frames are all untested.

## Base map — MapLibre is the substrate; MapKit is the uncovered-trip fallback

**Framing corrected 2026-08-08** (`Docs/decisions.md`). MapLibre is the committed
MVP substrate. `MapKitSnapshotProvider` is **not** a candidate primary — it is the
fallback that keeps a trip outside the installed regions from rendering blank
frames.

`RecapModel.snapshotProvider(for:)` picks per trip by whether a `.pmtiles` region
covers it (`RecapMapTiles.tilesURL`). No region ⇒ `MapKitSnapshotProvider`. The
simulator has no region installed unless `KAMOME_TILES_PATH` is set, so an in-app
recap there renders on Apple's map — a **test-environment** artifact, not the
product's substrate. The review harnesses (`RecapReviewScene`) require a region
and therefore always exercise MapLibre.

Two things that remain true and matter:

1. **Visual parity does not exist, and is not expected to.** The souvenir-map look
   is a Kamome-authored style JSON only MapLibre consumes; MapKit renders Apple's
   own tiles — the look rejected in the v1.5 pivot. Overlays, subject, chrome and
   the camera are renderer-independent and work over either. Any future
   substrate comparison is settled by **rendered A/B**, per the ADR.
2. **The fallback silently degrades pacing.** `establishing == nil` drops the film
   to the retired flat `target_duration_s` with no prologue. On the committed
   substrate that makes every uncovered trip a 30 s film for reasons that have
   nothing to do with its content — see the `establishing` split above. This is
   the core-path defect, and it is what makes the fallback currently dishonest
   rather than merely plainer.

## Fixtures and the §6 gate — Stage 0

`Tools/exif-to-fixture.sh` re-run 2026-08-04 with `exiftool` 13.55 (Homebrew).
**This mattered more than expected:** the previous run used `mdls`/Spotlight,
which saw only **170** of the Iceland folder's geotagged photos. exiftool sees
**2300**. Every measurement taken against the old dump was against a 13×
under-sample.

Current local dumps (gitignored, `Tests/Fixtures/trips/local/`):

| fixture       | photos | span    | stops |
|---------------|-------:|--------:|------:|
| `iceland`     | 2300   | 318.2 h | **65** |
| `new-zealand` | 160    | 272.2 h | **20** |

New Zealand really is 160 — only 160 of its 1272 jpegs carry GPS. That is the
data, not the tool.

**The unresolved tension, stated plainly.** Stage 0 wanted real-scale fixtures so
bugs like the deck budget reach CI. But `exif-to-fixture.sh` writes to a
gitignored directory *on purpose* — a real dump is a record of where a person
was, and §0 forbids committing it. **A gitignored fixture cannot run in CI by
definition.** These two requirements cannot both be met by committing a real
dump; that is precisely what went wrong on 2026-08-02.

The split adopted here:

- **Real dumps** drive desk review and gate renders (`KAMOME_PILOT_FILM`,
  `KAMOME_STOP_STILL`, `KAMOME_TIMELINE_REPORT`), which is what Stage 0 is
  actually for.
- **CI guards generate their own scale** — `RecapDeckBudgetTests` proves nothing
  about the defect depends on *where* the stops are, only how many there are and
  how many photographs each carries.

**Still missing for §6:** three real trips → shareable films, ≥1 published,
limited-photo re-check on device, stable MP4 export. Two real trips exist as
dumps (Iceland, New Zealand); the third is not collected. Photo sources live at
`~/Desktop/Iceland` and `~/Desktop/NZ` — outside the repo, deliberately.

---

## Environment gotchas that cost time

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
- OSRM on `:5100` serves the merged extract but is **not** in
  `~/kamome-osrm/docker-compose.yml` (only taiwan:5002 and australia:5001 are), so
  it is started ad hoc and will not come back on its own.
- Tiles/terrain: `~/kamome-osrm/tiles`, `~/kamome-osrm/terrain`.
- `simctl addmedia` fails with LaunchdSimError 133 unless the device is actually
  booted — boot it first, the error does not say so.

## Tile regions need establishing headroom, not just coverage (2026-08-08)

**A region that merely covers a trip renders a flat opening.** Derivation and
numbers: `Deploy/regions.json` `_establishing_headroom`. The rule:

    containedSpan(region) >= wide_span_padding x fittingSpan(trip)   (1.5x)

`containedSpan` is the widest **portrait** frame fitting inside the region, so for
a wide region it is bounded by *latitude*: `0.5625 x latExtent`. In latitude the
rule is **2.67×** the trip's fitting span.

Two things that cost a tile build each:

1. **This was briefly 1.875×.** While the body span also used `wide_span_padding`,
   the establishing beat and the body were the same expression, so the only zoom
   available came from a third, wider *country* beat that had to beat the regional
   beat by `opening_collapse_zoom_ratio`. Iceland was rebuilt to 1637 km of
   latitude for a shallow 1.25× zoom sitting on the collapse threshold. Splitting
   `body_span_padding` out removed the need entirely: the zoom now comes from
   regional → body, the region can be **smaller** and the zoom **deeper** (2.5×).
   If `body_span_padding` ever returns to ≥ `wide_span_padding`, this goes back to
   1.875×.
2. **A margin on the trip's own bbox is the wrong mechanism** and can shrink
   coverage: 1.4× Iceland's trip bbox is 365 km tall, smaller than the 518 km
   region it already had. There is also no code that sizes coverage to a trip —
   regions are hand-authored in `Deploy/regions.json`.

`Tools/tile-headroom.sh` reports this for any `.pmtiles`, and `build-tiles.sh`
runs it after every build so a region that will render flat is visible at build
time rather than in a finished film.

### Size cost, and the Phase 2 flag

Iceland **158.7 MB → 159.5 MB (+0.5%)** for 518 km → 1322 km of latitude — cheap
because the added area is open sea and empty tiles dedupe in PMTiles. (Measured
with `ls`. An earlier version of this section said +11%; that mixed `du` disk
blocks with `ls` bytes and was wrong.)

**Flagged for Phase 2, not solved now:** a margin that falls on **land** is
different in kind, and not only for size. The Geofabrik extract stops at the
country, so a neighbouring landmass inside the bounds has no OSM data and
**renders as ocean**. Iceland's margin is open sea so it does not bite here; a
continental region cannot be widened this way without widening the extract too.

**Local tile state:** `~/kamome-osrm/tiles/iceland-2026-08-08b.pmtiles` is the
1.5× build the harnesses now pick up. Superseded regions are parked in
`~/kamome-osrm/tiles-superseded/` (outside the scanned directory, so they cannot
be selected by accident): the original whole-island build, and the abandoned
1.875× one.

**Terrain was not rebuilt.** `iceland-terrain.pmtiles` still covers the old island
bounds, so the establishing shot's outer margin has no hillshade. It is open sea,
so nothing is visibly missing — but a wider terrain build is the honest follow-up.

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
