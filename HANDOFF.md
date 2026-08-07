# HANDOFF — current state

**Updated 2026-08-06.** Branch `feature/typed-legs-routing`. Written so a fresh
session (or a fresh person) can pick this up without being briefed by hand.

Read `CLAUDE.md` first for the standing rules — especially **§0, location data
never leaves the device**, which constrains the fixture work below more than
anything else here.

Scope notes: `Docs/handoff-P3.5.md` is the Replay MVP work order;
`Docs/gate-P3.5-checklist.md` is the §6 gate runbook. This file is the *session
state* on top of them — what is done, what is open, and why.

---

## Committed on this branch

- `6f44b57` **docs(adr)** — the budget law, written down once (`Docs/decisions.md`).
- `ea32ce9` **feat(recap)** — kept-stop count derived from the film's duration.
- `69b5ad5` **fix(recap)** — stop pins sit on the route (two bugs, one symptom).
- `2b7b657` **fix(naming)** — landmark → town → address, never "Unnamed stop".
- `229ab39` and earlier — see `git log`.

**Not merged to main:** PR #11 holds until the §6 gate passes (owner call).

## Uncommitted — the experiments still under evaluation

Deliberately out of history until Chiu picks a direction. All flags ship `false`,
so none of it changes default behaviour:

- `StopPhotoAllocator.allocate` — the 0–3 variable allocation (Variant A).
- Uncapped duration (`RecapDurationPlan.uncapped`, `uncapped_enabled`).
- `RecapReviewGeocoder` — real stop names in pilots (`KAMOME_GEOCODE_STOPS=1`).
- `PHAsset.isFavorite` plumbed through `ImportPhoto` into `is_highlight`.
- The opaque ice layer (see the glacier tradeoff below).
- Quiet-stop pins for zero-photo stops (`LinearTimelineStopScene.quietStop`).

`Tests/Fixtures/trips/local/` is gitignored and always dirty by design; that is
real trip data and must never be added.

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
changed** — the fix lives behind `tiering_enabled`. Remove the expectation if and
when the tiering policy becomes the default.

**Superseded and gone:** `tier_skip_share` as a tuning knob (it needed 0.82 for
Iceland and 0.5 for NZ, which is what prompted the ADR). `StopWeighting`'s
waypoint threshold remains in the tree but was measured as far too conservative to
matter — 8 of 65 stops on Iceland — and is not the mechanism anything relies on.

**Measurement aids, marked temporary in-code:** `Export.withTotalDuration`,
`RecapDeckBudgetTests.testReportRealFixtureBudgetSweep` (`KAMOME_BUDGET_FIXTURE`,
`KAMOME_BUDGET_DURATIONS`), and `KAMOME_FORCE_DURATION_S` in the render harness.

---

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
