# HANDOFF — current state

**Updated 2026-08-04.** Branch `feature/typed-legs-routing`. Written so a fresh
session (or a fresh person) can pick this up without being briefed by hand.

Read `CLAUDE.md` first for the standing rules — especially **§0, location data
never leaves the device**, which constrains the fixture work below more than
anything else here.

Scope notes: `Docs/handoff-P3.5.md` is the Replay MVP work order;
`Docs/gate-P3.5-checklist.md` is the §6 gate runbook. This file is the *session
state* on top of them — what is done, what is open, and why.

---

## Committed on this branch

- `7fabb38` **fix(naming): a film can no longer be exported before its stops have
  names.** Closes the "Unnamed stop" item (see below). Also replaced the review
  harness's hardcoded `.prefix(3)` photo selection with the app's own
  `PhotoDeckSelector`, so a review render finally shows what the app shows.
- `71caf77` and earlier — see `git log`.

**Not merged to main:** PR #11 holds until the §6 gate passes (owner call).

## Uncommitted

Nothing but the new deck-budget guard if it has not been committed yet — check
`git status`. `Tests/Fixtures/trips/local/` is gitignored and always dirty by
design; that is real trip data and must never be added.

---

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

## Open: the deck budget (1-photo-per-stop)

**The defect.** Above roughly ten stops, every stop in the film shows a single
photograph. `total_duration_max_s` (90) caps the film, all dwells are scaled down
by one global factor, and `deck_photo_min_hold_s` (1.0) then truncates each deck
to what its window can afford at a second apiece.

Measured (`Tests/AppTests/RecapDeckBudgetTests.swift`, prints `KAMOME_DECK_BUDGET`):

| stops | shown/stop | photos reaching the screen |
|------:|-----------:|---------------------------:|
| 4     | 5–8        | 29 of 32                   |
| 10    | 1–2        | 19 of 80                   |
| 20    | 1          | 20 of 160                  |
| 40    | 1          | 40 of 320                  |

**Why CI never caught it.** The committed fixtures are Iceland 16 photos/6 stops
and New Zealand 13/3 — both sit just under the cliff.

**The guard now in CI**: `testARealScaleTripDoesNotCollapseToOnePhotoPerStop`
builds a 20-stop trip *arithmetically* (synthetic coordinates on a line, through
the real `ImportService`) and asserts the collapse does not happen. It is wrapped
in `XCTExpectFailure` because the defect is real and unfixed, so CI stays green
while the defect stays encoded — **the day someone fixes it the test will fail
with "expected failure but none recorded"**, which is the signal to delete the
expectation.

**Owner decision still needed** (Chiu). A 180 s long-cut was rendered as an
experiment (config reverted afterwards; films delivered 2026-08-04). Doubling the
film does not double the photographs — it splits stops into two classes, because
a stop's asked-for dwell is clamped at `stop_dwell_min_s` and the 1 s floor is a
step function:

- Iceland 18 stops: 90 s → 18 of 95 photos shown; 180 s → 52 of 95, but **10 of
  the 18 stops still show one photograph**.
- New Zealand 20 stops: 90 s → 20 of 86; 180 s → 45 of 86.

So the ceiling is not the only lever — `max_hold_fraction` (0.6) and the 1 s floor
both bind. Duration that scales with stop count attacks it more directly than a
fixed long cut.

---

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
