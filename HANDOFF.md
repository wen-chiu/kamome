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

## ✅ CLOSED — the camera continuity gate is green again (2026-08-08)

`762b8cb`. CI run 31181735522 failed `RecapCameraContinuityTests` on the
`new-zealand` fixture; it now passes on all six committed fixtures **and** on the
real Iceland/New Zealand dumps. `swiftlint --strict` clean, full suite green.
**Nothing about the gate was touched** — no threshold, no assertion, no tolerance.

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

Iceland is a film Chiu has already judged, so this is a visible change to it and
**he has not yet seen it rendered.** The beat removed contained no zoom. Offer the
before/after opening stills before treating it as settled.

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

## ▶ Owner product decisions — 2026-08-08 (Chiu)

Given in chat, recorded here so they are not lost. **Not yet promoted to
`Docs/decisions.md` or the spec — do that before building on them.**

- **The shipped app renders on Apple Maps. The souvenir map (MapLibre) is Chiu's
  own MVP path only.** World tile coverage is not a resource Kamome can fund up
  front, and a release must give every user a complete experience wherever they
  travelled. Vector-tile regions roll out progressively later.
- **Multi-region trips: no per-act region switching.** It complicates the code and
  makes the film visually inconsistent. The app is Apple Maps throughout; Chiu's
  MVP films stay MapLibre. Revisit after the MVP release lands and there is a
  reaction to judge.
- **Routing server: yes, but not now.** P3.5 is not shipping to the App Store;
  Chiu wants a self-releasable MVP first. When it ships, prefer a hosted API on a
  free tier. **Note:** routing is orthogonal to the base map — without snapping,
  legs render as dashed straight lines over Apple's tiles just as over MapLibre's.
  `MKDirections` is worth evaluating first (on-device, no server, no key); it is
  routing rather than map-matching, which for ordered EXIF stop pairs may be the
  better fit anyway. Unverified — check rate limits before committing.
- **Map labels: later, and Apple Maps supplies them for free.** `MKMapSnapshotter`
  renders place names, roads and POIs. The missing-`glyphs`-fontstack blocker
  applies **only** to MapLibre, i.e. only to Chiu's own films.
- **Third gate trip: after this CI branch closes**, rendered locally.
- **On-device render time: not a concern.** No uncapped-length film ships to the
  app; long films are Chiu's local MVP only.

**Standing ground rule (Chiu):** films that are already publishable must not get
worse as a side effect of a code change. Measure before/after on the real dumps
and say what moved.

### What this changes about `establishing`

It **promotes** the `LinearTimeline.pacing` coupling from a corner case to the
main path. `establishing` is the installed vector-tile region's extent, so on an
Apple-Maps build it is nil for **every** user — and today nil means no prologue
and a flat 30 s film. The one-line `guard` has to go, and the two meanings have to
separate: pacing is a story fact (stops, photographs) and must never depend on
tiles; the span cap is a rendering fact and should apply only when vector tiles
are the substrate, since Apple's map has no tile edge to fall off. See
`Docs/handoff-P3.5.md` §"Trips that span two map regions" for the ~8 harnesses
that use a nil extent to mean "short deterministic film".

---

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

## Base map — MapKit is what actually renders today

`RecapModel.snapshotProvider(for:)` picks the provider, and it is chosen **per
trip** by whether a `.pmtiles` region covers it (`RecapMapTiles.tilesURL`). No
region ⇒ `MapKitSnapshotProvider`. MapLibre is fully wired and its framework is
embedded in the app; the simulator simply has no region installed, so every
in-app recap there renders on Apple's map.

Two things to know before promoting MapKit to primary:

1. **Visual parity does not exist.** The souvenir-map look is a Kamome-authored
   style JSON that only MapLibre consumes; MapKit renders Apple's own tiles —
   the look rejected in the v1.5 pivot. Overlays, subject, chrome and the camera
   are renderer-independent and already work over either.
2. **No region also silently degrades pacing.** `establishing == nil` drops the
   film to the retired flat `target_duration_s` with no prologue — the documented
   defect at `LinearTimeline.swift:184`. Any MapKit-primary decision has to fix
   that first, or MapKit trips get a 30 s film for unrelated reasons.

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
