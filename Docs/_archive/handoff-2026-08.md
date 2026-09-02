# Archive — closed HANDOFF.md and CLAUDE.md sections (through 2026-08-21)

**Nothing in this file is current.** These sections were moved here verbatim on
2026-08-21 (documentation-governance pass; audit `Docs/_audit/audit-2026-08-21.md`)
because they describe closed, resolved, or superseded work. Current state lives in
`Docs/current-state.md`; live session state in `HANDOFF.md`; decisions in
`Docs/decisions.md` (append-only — the newest entry on a subject wins). Where a
section below carries an imperative ("do not reopen…"), it is the imperative of its
era, not of today; the SUPERSEDED banners mark the two known cases.

---

# Part 1 — sections moved from `HANDOFF.md`

## ▶ RESUME HERE — MVP desk renders, 3 of 3 rendered, review in progress (2026-08-13)

Branch `phase-3-recap`, suite green (197), `swiftlint --strict` clean. PR #11
(`phase-3-recap` → `main`) stays draft and **held** — now until **§6b**, per the
gate split below; #12 and #13 are merged into this branch.

**The §6 gate split into §6a / §6b on 2026-08-13** (Chiu). §6a is the film gate:
desk, **Variant A**, three trips, "is this worth publishing". §6b is the product
gate: real iPhone, **Variant B**, three trips, "does the app do this by itself".
Items in `Docs/handoff-P3.5.md` §6; ADR in `Docs/decisions.md` 2026-08-13. Neither
is downgraded below three trips.

### The task in flight

All three MVP films are rendered in **Variant A**, with real stop names:

| | Miyakojima | New Zealand | Iceland |
|---|---:|---:|---:|
| status | ✅ rendered | ✅ rendered | ✅ rendered |
| photos in dump | 53 (of 406 files) | 160 | 2300 |
| presented stops | 10 | 20 | 65 |
| photographs shown | 23 | 45 | 144 |
| stops with no photo | 0 | 0 | 0 |
| stops unnamed | 0 | 0 | 0 |
| film length | 103.7 s | 193.7 s | **598.7 s** |
| render cost | 3,110 frames / 149 s | 5,810 / 600 s | 17,960 / 1,782 s |
| dashed drive legs | 0 | 1 of 17 | **11 of 59** |

Films are in `~/kamome-renders/`. **That directory is §6a release output, not
scratch** — the first Miyakojima render was written to `/tmp` and swept before it
could be reviewed.

**Owner review — all three judged (Chiu 2026-08-13). See "§6a film review" below
for the verdicts and what they do and do not tick.** The one §6a item still open
is **≥ 1 published publicly**.

**Spans, measured** (env-gated `RecapTimelineReportTests`, same Variant A config
and installed region the films used):

| | established | body | ratio |
|---|---:|---:|---:|
| Iceland | 736.8 km | 294.7 km | **2.50×** |
| New Zealand | 845.3 km | 338.1 km | **2.50×** |
| Miyakojima | 47.2 km | 18.9 km | **2.50×** |

These match the `Deploy/regions.json` derived figures to the decimal, so the
derived numbers were right and the camera is doing exactly what is configured.
**That question is closed** — do not re-derive it, and do not treat the spans as
a diagnosis for anything.

**The render command** (Miyakojima shown; swap fixture, photo folder, and note
that `KAMOME_PILOT_SECONDS=9999` means "the whole film", not a pilot):

```
TEST_RUNNER_KAMOME_PILOT_FILM=miyakojima \
TEST_RUNNER_KAMOME_PILOT_SECONDS=9999 \
TEST_RUNNER_KAMOME_RECAP_MODE=full \
TEST_RUNNER_KAMOME_GEOCODE_STOPS=1 \
TEST_RUNNER_KAMOME_OSRM_BASE_URL=http://127.0.0.1:5100 \
TEST_RUNNER_KAMOME_TILES_PATH=$HOME/kamome-osrm/tiles \
TEST_RUNNER_KAMOME_TERRAIN_PATH=$HOME/kamome-osrm/terrain \
TEST_RUNNER_KAMOME_STOP_PHOTOS=$HOME/Desktop/Miyakojima \
TEST_RUNNER_KAMOME_RENDER_OUT=$HOME/kamome-renders \
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:KamomeTests/RecapPilotFilmTests
```

⚠️ **Write renders to `$HOME/kamome-renders`, not `/tmp`.** The Miyakojima film was
written to `/tmp` and swept before it could be re-reviewed; it costs 156 s to
regenerate, and Iceland would cost far more.

### Variant A vs Variant B

- **Variant A** = `KAMOME_RECAP_MODE=full`: every clustered stop presented, no
  duration cap, and `allocation_zero_share` forced to 0 so no stop shows a pin
  with no photograph. Desk MVP renders only.
- **Variant B** = shipped default (`recap_mode: highlight`), **unchanged and not
  in scope to tune**. Both overrides are harness-only; `TrackingConfig.json` is
  never edited between runs.

### Owner decisions carried in

- **Miyakojima EXIF: do not investigate.** 53 of 406 files carry GPS+timestamp;
  the rest were stripped at export. Chiu is checking the export source himself.
  Render from the 53 and re-run later if originals turn up.
- **Region headroom: do not fix this round.** After all three renders, *propose*
  (do not implement) making the headroom check automatic at trip-dump /
  region-install time. It has now caught 2 of 3 trips manually (Iceland,
  Miyakojima), which is the argument. The raw material exists:
  `Tools/tile-headroom.sh` computes the verdict and `exif-to-fixture.sh` already
  prints the trip bbox — they just need to meet.
- **iCloud grey-card resolver: untouched**, deferred to device testing.

### Local state that is not in git

- `~/kamome-osrm/tiles/` — `iceland-2026-08-08b`, `miyakojima-2026-08-09`,
  `new-zealand-2026-07-29`, `finland-2026-07-29`. Superseded regions parked in
  `~/kamome-osrm/tiles-superseded/` (outside the scanned directory).
- `Tests/Fixtures/trips/local/` — Iceland, New Zealand, **Miyakojima** dumps.
  Gitignored per §0; never commit them.
- OSRM `:5100` is `docker compose up -d` from `Deploy/`, healthy, restart-safe.

## ✅ §6a — CLOSED by owner (Chiu 2026-08-14)

All six items satisfied. **The remaining work on the Replay MVP is §6b**, the real
iPhone gate, plus the duration rule that has to land in front of it.

**The published film, recorded precisely because the wording matters:**

- **Iceland, Variant B, 210 s** — the duration-target render of 2026-08-14.
- **Shared privately to friends**, not posted publicly. The gate item reads "≥ 1
  published publicly"; Chiu judged the private share sufficient and closed the item
  on 2026-08-14. The intent — an unedited film in front of a real audience —
  is met; the literal wording is not. **Recorded as what happened rather than as
  what the item says, so a later reader does not go looking for a public post.**
- No external editing, which is the half of that item that was never in doubt.

### ⚠️ The app cannot reproduce the film that was published

Its 210 s came from `KAMOME_FORCE_DURATION_S`, a harness override pinning both
duration bounds by hand. **No rule in the product derives it**, and the shipped
`.highlight` path would render that same trip at 90 s and 8 stops.

So the duration rule (see "Pending decision" below) is not polish after the fact —
**it is what turns the published artifact into something the product actually
makes.** That is also why it sits in front of the §6b sitting rather than after it:
export time and memory are frame-count-bound, and 90 s → 210 s is 2,700 → 6,300
frames.

## ✅ §6a film review — all three judged (Chiu 2026-08-13)

**Place names are deliberately absent from this section.** The routing report this
was written from named the stops; per §0 and the same rule that gitignores
`*-names.json`, a place name is a record of where Chiu was and does not enter the
repository. Legs are identified by ordinal and by geometry, which is everything a
later reader needs. **Do not "helpfully" restore the names.**

### The verdicts

- **Iceland — a film he wants to keep.** *"這是我自己會想留著看的影片, 確實勾起我一點
  回憶."*
- **Miyakojima, New Zealand — 很好.**
- **Iceland's opening reads fine** (0–10 s), which settles the question below.
- **The one dashed leg that mattered — accepted.** See "Leg 12" below.

**What this ticks in §6a:** three trips reconstructed from EXIF; films Chiu wants
to keep; no external editing; the final "worth publishing" judgment. **What it
does not tick: ≥ 1 published publicly.** Nothing has been published yet, and that
is now the only §6a item outstanding.

### The car's late entry on Iceland was never an anomaly — CLOSED

Iceland is the only one of the three where the vehicle appears *after* the opening
ends and after the first stop's card and first photograph (9.33 s, against an
opening ending at 5.50 s). New Zealand and Miyakojima put the car on screen during
the opening (6.67 s of 9.00 s; 3.17 s of 5.50 s).

**That is the documented second sequence, not a defect.**
`LinearTimeline.subjectArrivalStartS` specifies two orderings chosen by what the
trip opens on (Chiu 2026-07-31), and Iceland is simply the first real trip whose
journey *starts at* a photo-bearing stop:

    opening → [first stop's pin/title/photos] → car appears → first leg
    opening → car appears → first leg

The rationale in that comment still holds — a car that appears only to park a
moment later at the origin reads as a false start, and no dwell tuning fixes a
sequencing choice. **Chiu watched it and confirmed it reads correctly.** The
2026-07-31 decision is now validated on a real render rather than only specified.

### Dashed legs — the honest ones, and the one that was a judgment call

Iceland: **10 dashed drive legs of 58 routable** (64 legs = 58 drive + 6 walk; all
6 walks dash by design). Corrected from an earlier count of 11 taken off the
render log.

| cause | count | verdict |
|---|---:|---|
| `NoSegment` | 9 | **Correct behaviour, no action.** These cluster on glacier tongues and national-park interiors — photo positions with no drivable segment near them. OSRM answered correctly; drawing them dashed is the honest-provenance rule working, not a defect. |
| detour-gate rejection | 1 | **Leg 12 — accepted by Chiu.** |

**Leg 12, and why it was the only real question.** 17.5 km of straight line
standing in for 61.6 km of routed road (3.5×, over the 2.5× threshold) on a
stretch where the road rounds a bay — so the straight line crosses **water**.
§6a's item reads "no obvious sea-crossing straight line", and this is one.

**Chiu accepted it (2026-08-13):** the film is honest about not knowing, and one
such leg does not cost the film. ⚠️ **This is a judgment on one instance, not a
new rule.** The §6a item's wording still says what it says; a future trip with a
longer or more prominent water crossing is not covered by this precedent and gets
its own call. Do not cite this as "water crossings are fine".

**The mechanism worth remembering.** The detour gate rejected that route as
implausible — but in fjord and peninsula terrain a 3.5× road *is* the real
geography, not a bad EXIF fix. And the fallback for "this route looks implausible"
is a straight line, which here is **more** implausible than the route it rejected.
The safety mechanism's failure mode is worse than what it prevents. Nothing is
being changed about it now; this is recorded so the next person meeting a dashed
leg over water knows it may be the gate and not the data.

### New Zealand's single dashed leg — deferred, but it found a real gap

Leg 14, within a town: **0.4 km routed vs 0.1 km straight (4.6×)**, detour gate.
**Chiu: 沒關係, 我根本沒發現** — revisit if a similar issue surfaces later.

Worth keeping anyway, because it is the cheapest finding here: **the detour gate is
a pure ratio with no absolute floor**, so 300 m of difference on a 100 m leg trips
the same threshold that protects against a 300 km fabrication. An absolute floor
would remove this class outright at no risk — and would **not** help Leg 12, whose
44 km absolute difference is real. Two separate problems; only this one is cheap.

Miyakojima: **zero dashed drive legs** (9 of 9 reconstructed); its one dashed leg
is a walk.

**Attribution method, since it is not obvious it is sound:** `matchTrip` awaits
legs sequentially, so the k-th `[routing] route:` line is the k-th routable leg.
Cross-checked three ways — 58 route lines for 58 routable legs, 10 failures for
exactly 10 dashed drive legs, and every failure landing on the ordinal of a leg
the timeline independently reports as dashed. Same alignment held on NZ.

**Also reconfirmed:** the `RouteMatchService.swift:39` base-URL log lie reproduced
exactly — `matchTrip … against "(none — matching disabled)"` in the same run where
48 legs routed fine. Second confirmed sighting; still unfixed, still the line you
would otherwise trust.

## ✅ REVIEWED AND APPROVED — recap camera (2026-08-09)

Chiu reviewed the round-4 renders and approved both. **This closes the camera
work only** — the §6 Replay MVP gate is untouched and still open (see below).

| | established | body | zoom | opening | country beat |
|---|---|---|---|---|---|
| **Iceland** | 736.8 km | 294.7 km | **2.50×** | 5.50 s | no |
| **New Zealand** | 845.3 km | 338.1 km | **2.50×** | 9.00 s | **yes** |

### Owner decision — the wider establishing shot wins (Chiu 2026-08-09)

New Zealand's opening runs 9.00 s because its country beat survives: its installed
region is the whole country while the trip is the South Island, so there genuinely
is wider context to show. The alternative was cutting NZ's region to ~1.5× its
trip, which collapses that beat and gives a 5.50 s opening at the same 2.50×.

**Chiu chose the wider establishing shot.** A longer opening is the price of
showing where the journey sits in the country, and that is what the establishing
shot is for. **No code or region change** — the rendered behaviour is the decision.

The earlier "9.00 s is too long" note is withdrawn: it was raised when the opening
was long *and* the zoom was wrong (4.14×). With the zoom corrected the length is
paying for something.

### The mechanism, and why the constant it replaced could not work

`body_span_padding = 0.6` was reverse-derived from one trip (736.8 / 2.5 / 491).
Algebraically it is `wide_span_padding / target_zoom_ratio`, so it only produced
2.5× for a trip whose opening establishes on its **regional** beat. New Zealand
establishes on a **country** beat much wider than its trip, so the same constant
gave 4.14×.

Now `body = established / target_zoom_ratio` (2.5), where `established` is the
span of the opening's *first* beat — the picture at t=0. Each trip divides its
own, so the ratio holds whatever the geometry. This was only possible because
`buildWideOpening` took a `bodySpanM` parameter it never read: removing it lets
the opening be built **before** the body span rather than after.

### The pan floor is a floor now, and that matters

Deriving the body purely from the ratio broke the continuity gate on **128
assertions** — Iceland moved 34.5 km per snapshot across a 57.8 km frame, 39% of
the picture surviving against a 40% floor. A tight frame does not slow the vehicle
down; it just means more of the screen is replaced each second.

`camera_pan_window_fraction_per_s` is restored to **0.35** (its value before the
2026-08-02 wide baseline set it to 0.05) and is now a genuine **lower bound**.
Previously it was computed and discarded — `min(max(raw, cameraSpanM), ceiling)`
meant the ceiling always won, so it had not decided anything in months. As a floor
it yields the ratio wherever that is safe and overrides it where it is not: a trip
whose establishing shot is too tight to divide simply does not zoom, instead of
strobing. It does **not** bind on either real trip, so both land at exactly 2.50×.

### New Zealand's country beat is real, not a side effect

Asked explicitly, so measured explicitly. `countryAddsContext` is

    contained(region) > fittingSpan(trip) × wide_span_padding × opening_collapse_zoom_ratio
    845.3 km          > 340.4 × 1.5 × 1.25 = 638.2 km          → true

**The body span is not among its inputs**, under either the old formula or the
new one. It survives because NZ's installed region is the whole country while the
trip is the South Island — there genuinely *is* wider context to show. Iceland has
no country beat only because its region was deliberately cut to 1.5× for headroom.

**So the fix does not shorten NZ's 9.00 s opening, and cannot.** Opening length is
beats × holds + transitions; it is independent of the body span. If 9.00 s is too
long, the lever is the region, not the camera: cutting NZ's region to ~1.5× its
trip collapses the country beat, giving a 5.50 s opening and an established span
of 510.6 km — **still 2.50×**, because the ratio divides whatever it establishes
on. That is a product choice between a wider establishing shot and a shorter
opening, and it has not been made.

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

> ⚠️ **SUPERSEDED by `Docs/decisions.md` 2026-08-15** (MapLibre is parked, Apple
> Maps is what ships). Kept verbatim as the historical record; do not act on the
> standing instructions below.
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

> ⚠️ **MOOT since `Docs/decisions.md` 2026-08-20** — the provider is Geoapify and
> its terms were read (2026-08-20 (b)). Kept as the historical record.
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

> ℹ️ Superseded in role by `Docs/pre-launch.md`, which now carries the
> pre-submission list.
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

> ⚠️ **SUPERSEDED by `Docs/decisions.md` 2026-08-15** (MapLibre is parked, Apple
> Maps is what ships). Kept verbatim as the historical record; do not act on the
> standing instructions below.
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

---

# Part 2 — sections moved from `CLAUDE.md`

## Replay MVP repositioning (spec v1.7, 2026-07-20, Chiu) — READ FIRST

Long-term vision unchanged (Kamome auto-remembers a journey and directs it
into a film worth rewatching). But the **first release is smaller and
verifiable — the Replay MVP:** pick a past trip's photos → reconstruct from
EXIF place+time → snap to real roads (OSRM, already landed) → souvenir-map
recap → **MP4** → share. Two-layer evolution: (1) Replay MVP, (2) Story
Director (auto-select/narrative/hero/music) — build the MVP without blocking
layer 2. `decisions.md` 2026-07-20. Consequences:

- **Phase 3.5 renamed → Replay MVP**; **photo-EXIF import pulled forward**
  into it (was old P4). Work order = `Docs/handoff-P3.5.md`, resequenced:
  **Photo EXIF Import first** → MapLibre souvenir map → Modern Minimal (the
  ONE MVP theme) → vehicle follow-cam (primary dynamic, NOT "always-centred"
  dogma) → basic photo deck (0.8 s, explicitly *basic*) → **three-real-trip
  dogfood** → TestFlight.
- **P3.5 gate is now a product release gate** (three real trips → shareable
  films, in-app only, no DB edits / no CapCut; ≥1 published; limited-photo on
  device; stable MP4 export; per-trip time *product-acceptable*, the single
  <90 s number retired). Map-vs-Apple side-by-side = design review, NOT the
  gate. "Worth publishing," not "prettier map." Three trips is hard, never one.
- **MP4 is the launch format; GIF demoted to non-blocking.**
- **P3 device items redistributed (none faked passed):** export/S5-UX/
  limited-photo → Replay MVP gate; 2 h drive + region-resume → Capture Beta
  (`Docs/device-test-P3.md` re-tagged).
- **P5 Passive Capture Tier renamed → Capture Beta**, moved *after* the video
  product; inherits the tracking/battery device gates; only place "Arm once,
  forget it" is validated. **P4 Import & Matching renamed → Story Director**
  (EXIF half moved to MVP; Story Director is **deterministic — no AI/LLM
  tokens** (scoring/selection over trip data); Google Timeline importer
  **dropped** as redundant — EXIF import + in-app capture cover it).
- **Honest provenance:** schema v2 `trip.source` (recorded | imported_photos |
  imported_timeline) lands with the MVP; UI labels imported trips
  "reconstructed from photos"; low-confidence legs render inferred.

## Recap visual pivot (spec v1.5, 2026-07-19, Chiu)

*(Phase/gate framing here is superseded by the Replay MVP section above — kept
for the substrate ADR + boundary-discipline detail, which still hold.)*

Chiu rejected the P3 demo's Apple-tile look — Kamome is a **travel
storytelling engine**, not a GPS visualizer (now spec §0 rule 6: every
motion/visual decision must serve the journey's narrative; a replay must be
recognizably Kamome without branding). Vision:
`Docs/kamome-animation-vision.md`. Consequences:

- **P3 scope frozen as the pipeline milestone** — its machinery (CameraPath,
  OverlayTimeline, compositor, encoders, S5) all survives. Gate items
  unchanged (device: 2 h drive, limited-photo re-check, < 90 s budget, S5
  UX); the "Chiu posts one recap" share-worthiness item moved to P3.5.
- **New Phase 3.5 — Recap Visual System** (spec §7), strictly sequenced:
  OSRM matching §4.4 (pulled forward; route must never be straight lines
  between GPS points) → MapLibre substrate → Modern Minimal theme.
- **Substrate ADR** (decisions.md 2026-07-19): MapLibre Native +
  self-hosted vector tiles (Planetiler → PMTiles, same extracts as OSRM),
  Kamome-authored style JSON per theme. Implementer guide:
  `Docs/vector-tile-pipeline.md` — includes the **quality bar** (must be
  clearly better-designed than Apple Maps for replay, judged side-by-side
  vs. the P3 artifact, Chiu signs off; unreachable bar ⇒ reopen the ADR).
- **Boundary discipline, not premature abstraction** (Chiu): no generic
  multi-renderer interface. `RecapSnapshotProviding` already is the
  boundary (`import MapKit` lives only in `MapKitSnapshotProvider.swift`;
  MapLibre types get the same one-file confinement). Deferred gaps, built
  only when their consumer exists: pitch/bearing in the snapshot request
  (isometric camera), `RecapTheme` overlay tokens (defined during Modern
  Minimal). Engine ↔ theme fully decoupled; Modern Minimal is the first
  theme, never a structural assumption.

**Prototype validation (2026-07-20, `Docs/prototype/`, decisions.md
2026-07-20).** Direction de-risked in a throwaway web prototype on Chiu's
real 170-photo Iceland trip; owner sign-off "收斂回 app". Locked constraints
for §4.5/§7 (no architecture change — they constrain existing components):
(a) base map = **real geometry + subtractive style** = 紀念品地圖 (reaffirms
substrate ADR; abstract map rejected); (b) stop photos = **rotating deck at
the place**, hero cross-fades 3–8 photos at **0.8 s each** (OverlayTimeline);
(c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle
is the subject, close heading-up zoom) — the prototype's one unmet item;
top-down car default, seagull/scooter/bike swappable. Positioning restated →
spec header v1.6 ("stories you can relive and share"). Forward directions
recorded: photo-EXIF import first (prototype IS that importer, §4.7), video
"beads" (auto-trim 2–3 s, muted), beat-synced royalty-free music.

### What the export numbers actually said (2026-08-15, device)

| trip | frames | snapshots | export | per snapshot |
|---|---:|---:|---:|---:|
| Miyakojima | 4,065 | ~~271~~ **wrong** | 270 s | ~~≈1.0 s~~ **wrong** |
| New Zealand | 4,635 | ~~309~~ **wrong** | 600+ s | ~~≈1.9 s~~ **wrong** |

⚠️ **These two columns are not merely estimates — the method is wrong, and the
measured numbers are in the Phase 4 section above.** Do not average the two sets
and do not quote these. Only `frames` and `export` are real.

The counts were computed as `frames ÷ keyframe_interval_frames`, which assumes one snapshot every interval
for the whole film. `RecapRenderLoop` snapshots the **opening every frame**
(`movingUntilFrame = openingS × fps`), so the real count is higher and the real
per-snapshot cost lower — in the same proportion for both rows, so the
substrate comparison's ordering survives and the absolute figures do not.
`Tests/AppTests/RecapSnapshotBudgetTests.swift` counts them through the shipped
loop; replace this table with measured numbers when a device run is next made.

**Export time ≈ snapshot count × snapshot cost; nothing else is the bottleneck.**
Both films ran on Apple Maps, so every snapshot was an `MKMapSnapshotter` **network
fetch**. MapLibre reads local `.pmtiles` from disk, and **has never been measured on
device** — the souvenir map may be substantially faster, not merely different.

That reopens tile provisioning as a *performance* question, not only a visual one.
The honest comparison is **one large reusable download** versus **small fetches on
every export**, not download versus none. A user who makes one film may be better
off on Apple's map. Regions are 3 MB (Miyakojima) to 640 MB (New Zealand).

**The export also fails if the app is backgrounded or the screen sleeps.**
*(Addressed 2026-08-15: `ExportLifecycleGuard` holds the idle timer and a
background-task assertion for the render's duration, and cancels cleanly at a
frame boundary if iOS reclaims the assertion. This is not resumable export —
`AVAssetWriter` cannot resume across process death, and that remains a project.)*

### Two 2026-08-01 blockers — both closed

1. Multi-day inter-day legs typed `.walk` — **fixed** 2026-08-02 by
   `import.pace_unknowable_gap_s`.
2. iCloud-optimised photos resolving to empty cards — **mitigated** (option C): the
   resolver still downloads nothing, but the recap screen names the shortfall.
   Option B (actually fetching originals) stays iceboxed.

## Phase 3 history (recap pipeline, spec §4.5/§7) — started 2026-07-16

Gate restructure (decisions.md 2026-07-16, Chiu): the 2 h drive
(`Docs/device-test-P1.md`) and the limited-photo-access re-check moved from
Phase 3 *preconditions* to Phase 3 *gate items* — P3 dev is fixture-driven,
but **P3 cannot close without both**. *(Superseded 2026-07-20: the 2 h drive
moved to Capture Beta; the limited-photo re-check stays as a Replay MVP gate
item.)* The 2026-07-16 smoke drive surfaced:

- Road deviation in the polyline is expected (sparse drive sampling + ε=15 m
  display simplification); fix is OSRM matching (§4.4, P3 stretch / P4 core),
  raw points are retained — do NOT tighten sampling config for this.
- Phantom-trip guard landed (PR #7, CI green): `trip.min_duration_s` /
  `trip.min_distance_m` in `TrackingConfig.json`; `TrackingSession.end()`
  discards sub-minimum recordings (`TripGuard`, Core/TripComposer). PR #7
  also fixed the local smoke's stale missing-key expectation.
- P3 milestone branch `phase-3-recap` (stacked on PR #7): `KamomeExportEngine`
  target started with `CameraPath` (§4.5 step 1 — speed-warp to
  `export.target_duration_s`, per-stop holds pinned on-route, smoothstep
  easing, new `export.max_hold_fraction` tunable caps holds on stop-dense
  trips).
- §4.5 steps 2, 4, 5 landed 2026-07-18 (three commits on `phase-3-recap`):
  frame renderer (`RecapFrameCompositor` + `RecapRenderLoop`, keyframe
  snapshots cross-faded per `export.keyframe_interval_frames`, projection
  travels with `MapSnapshot` so MKMapSnapshotter's `point(for:)` stays
  authoritative; `FlatSnapshotProvider` keeps golden-frame gates
  deterministic), title/end cards as new OverlayEvent kinds (photos toggle
  gates stop cards only — decisions.md 2026-07-18 recap-chrome, **confirmed
  by Chiu**; chrome-free export = separate future option, never this
  toggle), `RecapQRCode`, and `RecapExporter` → H.264 MP4 +
  decimated GIF with progress/cancel. New export tunables: frame size,
  camera_span_m, keyframe_interval_frames, title_card_s, end_card_s.
  S5 landed 2026-07-19: `RecapComposer` (trip DB → cards; recap geometry
  goes through Douglas-Peucker at simplify.epsilon_m), `RecapModel`/
  `RecapView` (photos toggle labeled "停留照片卡" + always-on chrome note,
  MP4/GIF picker, progress/cancel, share sheet, render-time readout), film
  button on S3. Render-loop snapshot prefetch + `video_bitrate_mbps` (5)
  landed after 2026-07-19 benchmarks (sim: pipeline 22.8 s, snapshots
  0.67 s each, demo end-to-end 34.6 s). Demo artifact:
  `Docs/demos/phase3/` (perth fixture, real tiles). QR payload =
  `kamome://route/<id>` placeholder until P6/P7.
  Remaining for P3 (all need the physical device, `Docs/device-test-P3.md`
  F–H): render budget < 90 s via S5 readout, S5 UX pass, 2 h drive,
  limited-photo re-check.
- Recap product decisions (decisions.md 2026-07-17, Chiu): overlay moments
  (stop cards, and later route-attached photo fly-bys) are **timeline events**
  built alongside CameraPath in step 2 — don't hardwire rendering to
  `holdingStopIndex`. S5 gets a photos on/off toggle (route-only animation =
  overlay events off) — P3 scope. Route-photo fly-bys = P3 stretch after the
  render budget is proven; video clips in recap = icebox (deterministic
  excerpts only — random breaks golden-frame CI).
- Photo fixes landed 2026-07-16: route-attached photos (stop_id NULL) get an
  S3 strip; Selected-Photos access shows a banner + limited-library picker;
  re-match preserves highlights. Limited-access box stays unticked until Chiu
  re-checks on device.
- Evening dwell_pause without dwell_resume was benign (parked until End
  Trip). Region-resume got its first hardware proof on the 2026-07-19 drive
  and **failed half-open**: resume fired, iOS suspended the app ~10 s after
  the region-exit wake, 32 min / 13 km lost (straight line in the recap,
  second stop unrecordable). Fix landed on `phase-3-recap` (decisions.md
  2026-07-19 region-resume): background-flag re-assert on resume, trip-long
  significant-location-change safety net, `sampling.recovery_gap_s` (60)
  silent-death watchdog, engine-side resume now also restarts GPS
  (`resumeActiveTracking`). New CSV events `region_exit` / `gps_recover`.
  Re-validation = device-test-P3 item C (needs the physical device).
- Stop detection redesigned after the 2026-07-18 17:04 drive missed both real
  stops (ADR 2026-07-18): DwellDetector is streak-based (age-based span check
  never fired on sparse real sampling); engine never dwell-pauses mid-walk;
  `StopDeriver` (TripComposer) adds silence-gap + walk-visit (loop-closure)
  stops at trip end. Trip stop semantics = live ∪ derived; new dwell tunables
  gap_min_s / visit_min_s / visit_return_radius_m.
- `stop.kind` wired (ADR 2026-07-18 stop-kind): `dwell` | `walk_visit` via
  `StopKind`; silence-derived = dwell (detection ≠ kind); pre-existing rows
  say "auto" — readers treat unknown as dwell. Compositor renders walk visits
  with walking duration/trace (recovered via time overlap with the walk
  segment — no Place/Visit abstraction, owner decision). Next-drive
  validation items tracked in `Docs/device-test-P3.md` (A–E). POI naming
  (MKLocalSearch → geocode fallback) = next standalone PR after the first
  end-to-end replay; do not block compositor on it.

## 🔴 P0 — the app died on someone else's device (2026-08-15) — mechanism closed

*(Moved from `CLAUDE.md` 2026-08-21. The structural closure is recorded in
`Docs/decisions.md` 2026-08-15; the still-open remainder — date selection — lives
under Phase 4 item 3, and whether the diagnosis on the other device was completed
is not recorded anywhere — see `Docs/current-state.md` Blockers.)*

The first person other than Chiu to install Kamome could not use it: with a large
photo library the app dies outright, and date selection misbehaves. **This is the
first outside signal the product has ever received and it takes priority over all
planned work.** Leading hypothesis is a build shipped with a LAN `matching.base_url`
that does not resolve on their network — `matchTrip` awaits legs sequentially, so
more photos means more stops, more legs, and more back-to-back timeouts. Not
confirmed. Diagnose before fixing; the fixes differ completely.

⚠️ That device belongs to someone else. Read only what identifies the failure;
**never copy their photographs, place names, coordinates or identifiers into this
repo** — §0's reasoning applies at least as strongly to a third party.

**The mechanism is now structurally closed, whatever the trigger was**
(2026-08-15, `decisions.md`). Still diagnose — a LAN URL and a slow provider need
different follow-ups — but the app can no longer be held by either:
- `AppConfig.loadOrDie` **refuses a release build** whose `matching.base_url` is
  not empty or `https`, and CI refuses the committed one. A debug run against
  `http://192.168.x.x` is untouched, which is what device testing needs.
- Import returns when the trip is saved; routing runs detached, is cancellable
  per leg, and is bounded by `matching.trip_budget_s` for the whole trip.
  The import sheet's Close button is always enabled.
- A dashed film now says **which** of four things happened — no road route, the
  provider unreachable, rate-limited, or the budget ran out. Only the first is
  the journey being drawn honestly; the other three are worth retrying.

Date selection misbehaving is **not** addressed — the month-reset in
`ImportSheet.linkEndToStart` and the unbounded range are still open, under
Phase 4 item 3.


---

# Archived 2026-08-29 — four findings sections whose work has merged

Moved verbatim from `HANDOFF.md`. **Nothing here is current state.** Each records
the working notes of a session whose code is on `main` and whose decisions, where
any were made, live in `Docs/decisions.md`. They are kept because the *reasoning*
is sometimes the only record of why a number is what it is — not because anything
in them is an instruction.

What was still live in them was carried forward before the move: the unexplained
3× raster, the appearance value's persistence gap, the subject-lookup miss and the
two open asks against PR #22 all remain in `HANDOFF.md` or `Docs/current-state.md`.

## Findings — PO/Architecture session (2026-08-20)

**Context.** Chiu ran the Geoapify survey on 2026-08-19 and selected the provider.
ADR: `Docs/decisions.md` 2026-08-20. These are the items the survey did not close,
or closed differently from how it reported them. Ordered by what can go wrong
silently.

---

### 1. ⚠️ SUPERSEDED 2026-08-20 (d) — the mechanism below was measured and does not hold

**Read `Docs/decisions.md` 2026-08-20 (d) first.** Geoapify accepts no snap-radius
parameter, and measurement shows a 500 m radius would have accepted every wrong-road
case (they snap 44–132 m away) while the benign ones snap 465–477 m away. `radiuses=500`
was not guarding this band on OSRM either. The class it *did* guard — no road anywhere
near the waypoint — Geoapify rejects natively with `400 No suitable edges`.

**Standing instruction: the detour gate stays at 2.5, nothing new is built for this in
the migration PR, and the Iceland film is the test.** The rest of this item stands —
the gate still moves out of the provider file, and `.rateLimited` still stays.

### 1 (as originally written). The migration PR carries **two** policies out of `OSRMRouteProvider`

**Decision.** `matching.route_waypoint_radius_m` (500 m) is Kamome honesty policy,
exactly like the detour-ratio gate, and it must be carried across deliberately.

**Why.** `OSRMRouteProvider.requestURL` sends `radiuses=` per waypoint — "photos sit
beside roads, not on them". Under OSRM, a waypoint further than 500 m from a road
returns `NoSegment`, so the leg draws **dashed**. Geoapify's `/v1/routing` has a
different URL shape and **no snap-radius parameter was tested.** Chiu's own survey
measured what happens without one: a waypoint 1 km off-road returned **200, 20.33 km
for an 11.29 km leg, ratio 2.247**.

**Evidence.** `matching.route_max_detour_ratio` is **2.5**; 9.05 km straight × 2.5 =
22.62 km allowed vs 20.33 km returned → **the wrong-road route passes the gate**, is
stored by `setMatchedPolyline`, and draws as solid road. The 2 km case (2.007) passes
too. Verified by arithmetic over the survey's own table and `Config/TrackingConfig.json`.

**Risk.** Do **not** respond by tightening the ratio. Legitimate routes measured
1.15–1.49 and wrong-road routes 2.0–2.25, which looks separable — but a fjord or
peninsula drive is legitimately 2–4×, and Iceland is made of them. The ratio cannot
distinguish a wrong road from an indirect one; the snap radius can, because it acts
before a route exists.

**Next.** First establish whether Geoapify `/v1/routing` accepts a per-waypoint snap
radius (one parameter on the existing survey script). **If it does not, stop and
bring it to Chiu** — "a photo 1 km from a road draws dashed" vs "draws a road the
traveller did not take" is a product decision, not an implementation detail.

---

### 2. 🟠 Do not delete `RouteProviderFailure.rateLimited`

Geoapify produces no 429, no `Retry-After`, and no rate-limit headers at 28.7 req/s;
overload arrives as TCP reset. The case becomes unreachable code on this provider.
**Keep it, and keep both strings.** The pre-launch Cloudflare Worker (`Docs/pre-launch.md`)
is the natural place to throttle and *can* emit a real 429 — the distinction is
recoverable in a component already planned. Arch.md §7.2/§7.3: a case you merely
believe is dead is one you have not tested.

---

### 3. ✅ DECIDED 2026-08-20 — the retry sentence stays; the copy work is smaller than it looked

Chiu asked for "再匯出一次會有幫助" to be dropped. That sentence lives on
**`recap_routing_budget_detail`** only:

> The trip ran past our time limit. What's already matched is saved — export again
> and it picks up from there.

That is Kamome's own budget, and the promise is **verified true in code**:
`RouteMatchService.shouldReconstruct` requires `segment.matchedPolyline == nil`, so a
second run skips every leg already matched and genuinely resumes. "Kamome only
promises what Kamome controls" — this is the one promise that survives.

The pair the survey actually undermined is `unreachable` / `rate_limited`, and
**neither contains that sentence.** `recap_routing_unreachable_detail` ("we just
can't reach the routing service right now") already describes a TCP reset fairly.
So the copy work is smaller than it looks: nothing has to be rewritten, and
`.rateLimited` simply stops being reachable (item 2).

**Chiu confirmed this reading on 2026-08-20.** So: **no string is edited.**
`recap_routing_budget_detail` keeps its retry promise, `recap_routing_unreachable_detail`
stands as written, and `.rateLimited` simply becomes unreachable on this provider
(item 2 — keep the case).

---

### 3b. ✅ DECIDED 2026-08-20 — walks route on a walking profile and draw solid

**His question**, recorded as asked: OSRM and Geoapify only carry car roads, so a
hiking trail or footpath has no route; since Kamome must support every travel mode
including walking and public transit, a walk off the road network should **draw a
road that was not walked, rather than a dashed line**.

**Two facts change the question before it is answered.**

1. **A recorded walk already draws solid.** `RecapComposer.provenance(for:)` dashes
   raw geometry only on `.exif` / `.timeline` segments. A `.gpsHifi` / `.gpsPassive`
   walk is `.recorded` → **solid**, drawn on the trace the phone actually saw, which
   is more accurate than any road-snapped version. The dashed-walk problem exists
   **only for photo-imported trips**, where the input really is 2–5 photo positions.
2. **"Only car roads" is Kamome's decision, not the provider's limit.**
   `RouteMatchService.shouldReconstruct` returns false for `.walk`, `.cycle`,
   `.transit`, `.unknown` — PD-8, and its comment says why: *snapping a stroll to
   the nearest street invents a journey.* **That reasoning was written against a
   car-profile server.** OSM carries `highway=path` / `footway` / `steps`, and a
   hosted provider exposes profiles the self-hosted four-region car graph never had.

**Chiu decided (2026-08-20): the recommendation below, as written.** Spec amended to
**v1.8**, new §4.4.1 — journeys are multi-modal by design, car ships first. Do not fabricate.
Get the same outcome honestly by **routing walks on a walking profile** — a real
footpath drawn solid is both what Chiu wants and what PD-1/PD-2 allow. Then the
residual dashed cases (a beach, a glacier, a field, indoors) are rare rather than
pervasive.

**Test before deciding — one row on the existing survey script:** does Geoapify
`/v1/routing` accept `mode=walk` / `mode=hike`, and does it return trail geometry
for a known trail?

**Transit is a different problem and must not ride along.** A Shinkansen leg routed
on any road profile draws the **expressway** — a different line in a different place,
claimed as real. Chiu's own cross-region decision already contains the honest answer:
known endpoints, unknown path, its own sprite and its own beat
(`Docs/cross-region-journeys.md`, requirement 4).

**⚠️ §0 consequence, and it is Chiu's call.** Walk legs are currently **never sent
anywhere** — `shouldReconstruct` refuses them, so they have never left the device.
Routing them would send a person's city wandering to a third party, which is more
intimate than the drive legs the 2026-08-16 ADR accepted.

---

### 3c. 🟠 The album path is promoted — it is now the privacy notice's control (2026-08-20)

Selecting an **album** at import (`Docs/cross-region-journeys.md` requirement 1, the
cheap half — "a list and a fetch") is no longer just a cross-region convenience. Chiu's
privacy decision states the notice will say a **date range** decides what is sent
*and* that the user can control which places are given **by choosing an album**.

**A notice may not promise a control the app does not offer.** So the album path ships
with the notice, or the notice does not mention it. Free-form photo selection remains
a later design pass — do not bundle them.

ADR: `Docs/decisions.md` 2026-08-20 (c).

---

### 3d. ✅ DECIDED 2026-08-20 — the reindeer sets are **choosable subjects**

Chiu's decision: option **(a)**. `reindeer-cute` and `reindeer-deer` become
user-selectable subjects, like `car-toy`, not crossing art like `plane` / `boat` /
`seagull`.

**Reason, so it is not re-litigated:** the crossing set exists to describe honestly
*how a crossing was actually made*, and Kamome would never infer a reindeer. A
reindeer is a decorative choice, and changing the vehicle is the most common
community request.

Work: a `vehicles.json` entry each with `"selectable": true` and both locale names,
then the two pinned tests — `testTheSubjectsAUserMayChooseAreExactlyThese` and
`testEligibilityIsTheFlagAloneAndArtCannotNarrowIt` — updated. Per `Arch.md` §7.5 the
rule genuinely moved, so the reason goes in the commit message. The 18 PNGs commit
with it, not before.

---

### 3e. 🔴 PROCESS — two sessions shared one working tree, and a verification claim was contaminated (2026-08-20)

**What happened.** The sprite/key session reported `KamomeCoreTests 222 → 229 (+7)`
and attributed it to *"parametric tests now iterating 12 subjects instead of 10"*.

**That is impossible as stated, and it is checkable in one line.**
`VehicleCatalogTests.swift` is **XCTest** (`import XCTest`, zero `@Test`
annotations). **XCTest counts test methods, not loop iterations** — adding two
subjects to a suite that loops over subjects internally cannot change the count at
all. And `git show c0d4583 -- Tests/ | grep -c '^+.*func test'` returns **0**: that
commit added no test methods; it changed three lines of one pinned expectation.

**Where the +7 actually came from.** The **routing session's** uncommitted
`Tests/CoreTests/RouteReconstructionTests.swift` was sitting untracked in the same
working tree and growing while the sprite session measured. `Tests/CoreTests/` is a
directory glob in `project.yml`, so an untracked `.swift` file there is compiled into
the test target. It now carries 14 test methods. The same contamination explains
`swiftlint` going 160 → 163 files.

**Why this matters more than the number.** The sprite session's Level 1 evidence —
"338 tests, 0 failures", "0 violations, 163 files" — is partly a claim about **code
it did not write, did not review, and which was changing under it.** None of it is
wrong; none of it is attributable either.

**The rule this needs.** `Arch.md` §7.4 requires reporting the test count and
flagging any change. Add to it in practice: **before quoting a count, state whether
the tree contains uncommitted work from another session, and exclude it or say you
could not.** §9 already says a fixture that is local, uncommitted or divergent is a
red flag to stop and report — the same applies to sources.

**For Chiu, not the implementer:** two sessions in one checkout will keep producing
this. A git worktree per session removes it entirely and costs nothing.

#### ✅ CLOSED 2026-08-21 by `2d221e0` — ~~the worktree fix silently disables half the new key guard~~

**The subsection that stood here is struck, not edited.** It said
`testTheSecretsFileIsNotTracked` reads `<repoRoot>/.git/index`, that a worktree's
`.git` is a *file* so the read fails and the test throws `XCTSkip`, and that the
local half of the key guard therefore never runs in the setup this project now
recommends. **`2d221e0` ("fix(test): the secrets guard resolves the git index in
a worktree too", on `main` since PR #16) fixed exactly that**: `gitIndexURL`
resolves a worktree's `gitdir:` pointer, absolute or relative, and reserves
`XCTSkip` for the one honest case of no `.git` at all.

**Re-measured 2026-08-29 in a worktree, by running it rather than reading it**
(`.claude/worktrees/nice-pare-08dedf`, `.git` a file pointing at
`Kamome/.git/worktrees/nice-pare-08dedf`):

    -only-testing:KamomeTests/RoutingKeyTests
    Test Case '-[KamomeTests.RoutingKeyTests testTheSecretsFileIsNotTracked]' passed (0.001 seconds)
    Executed 10 tests, with 0 failures (0 unexpected)

**Passed — 10 executed, 0 skipped.** And the pass is not vacuous: the guard scans
the index for the NUL-terminated byte string `Config/Secrets.xcconfig`, and that
worktree's 44,845-byte index **contains that needle exactly once**, at offset
3914, as the prefix of the tracked `Config/Secrets.xcconfig.example`. For the
test to pass rather than skip, it had to resolve the pointer, read those bytes,
find the occurrence and reject it on the NUL check. A skip or an unreadable index
could not produce this result.

**The habit this cost:** the stale claim was carried forward on 2026-08-29 by
quoting this section instead of running the test — a repo document treated as
current state when the code had moved four days earlier. §7 already says
verification is not self-certified; the same applies to citing someone else's.

---

### 4. ✅ DONE — `matching.trip_budget_s` — measure it, do not pick a number

**Resolved (doc note 2026-08-21):** the measurement happened. Commit `1cedbd2`
("fix(routing): trip_budget_s 60 -> 120, from a measured 58-leg run") set the
budget exactly as this item asked, and `Config/TrackingConfig.json` now carries
**120**. The original item follows as the record.

Survey latency: 0.48–2.53 s a leg cold, 440–840 ms back-to-back with connection
reuse (which `URLSession.shared` gives us). Iceland is 58 legs → somewhere between
**≈35 s and ≈88 s, derived arithmetic not a measurement**, against a 60 s budget.

`matchTrip` already logs `STOPPED after N legs — trip_budget_s exhausted`. **The
first real Iceland import against Geoapify is the measurement.** Read the line, then
set the number, and say in the commit which run it came from.

---

### 5. 🟡 Untested and cheap: the waypoint cap on a GET-only endpoint

`POST /v1/routing` returns 404 — the endpoint is **GET-only**. `matching.chunk_size`
is 100 waypoints, which becomes ~2 KB of query string, and Geoapify's own per-request
waypoint cap for `/routing` was never probed. Same script, one more row.

---

### 6. ℹ️ The 1500 m map-matching ceiling is a **Capture Beta** item, not a today item

The survey concluded that sparse photo points defeat the matcher. They do not reach
it: EXIF legs go through `RouteReconstructing.route` (`/v1/routing`); only `.gpsHifi`
/ `.gpsPassive` reach `/v1/mapmatching` (`RouteMatchService.route`). Where it will
bite is Capture Beta, and specifically the known region-resume hole (2026-07-19:
32 min / 13 km lost), which returns **200 with points silently unmatched**. Same for
`matching.timeout_s` (10 s) against a measured 9.6 s for 1000 points.

---

### 0. ✅ Reviewed — the key plumbing already in the working tree

`Config/Base.xcconfig` + `Secrets.xcconfig.example` → `Info.plist` → `AppConfig`,
with `apiKey` deliberately outside `Matching.CodingKeys` and a test proving the
committed file cannot supply one. A keyless build degrades into routing-off, which
is an existing designed state with copy already written, and the release guard is
unchanged. **No architecture objection** — the boundary held and `OSRMRouteProvider`
was correctly left alone.

Two notes rather than objections: `matching.apiKey` is carried but not yet used by
any request, so the next commit is exactly the one items 1–3 below constrain; and
`"replace-me"` is a magic string, justified in its doc comment but still a string.

---

### 0b. 🔴 §0 — do not log the request URL when the new provider misbehaves

`/v1/routing` is **GET-only**, so the request URL will contain **both the API key and
real trip coordinates** in its query string. The natural move when a new provider
returns something surprising is to log the URL. §0 forbids it — `KamomeLog` may name
*which* stop failed, never its coordinates — and it would put the key in the device
log beside them.

The existing logs are already correct and should be the pattern: `OSRMRouteProvider`
logs `config.baseURL` (host only), never the built URL. **Keep it that way in the
new provider file**, and if a full URL is ever needed to debug, redact both before it
reaches `KamomeLog`.

---

### 7. ✅ RESOLVED 2026-08-21 (was: ⚠️ CORRECTED 2026-08-20 — the sprite tree holds three different things, not one)

**Resolution (VERIFIED 2026-08-21):** the three things landed as separate commits —
`6cc6543` (the 46 re-centred files) and `c0d4583` (the reindeer sets as choosable
subjects, per decision 3d, with manifest entries). `git status` is clean of PNGs.
The correction below stands as the record of why one commit would have been wrong.

**A merge session reported these as landed in `4ed8774`. They were not** — that commit
carried an *earlier* pass. Verified on `main` at `7b563d7`, the working tree still holds:

| | what | why it is its own commit |
|---|---|---|
| **46 modified** | boat, car-toy, car-white, drone, plane-3d re-runs | pixels only, sets already declared — same shape as `4ed8774` |
| **1 of those** | **`car-red/logo.png`** | car-red is the **reference proportion** the whole catalogue is sized against (`Vehicles/README.md`) **and** the default subject (NULL ⇒ car). Not a routine re-encode. |
| **18 untracked** | **`reindeer-cute/`, `reindeer-deer/`** — two entirely new sets | **`vehicles.json` does not mention reindeer.** Art with no manifest entry is bytes nothing can select, and which subjects a user may choose is pinned by a test on purpose. A new subject is a product decision, not an asset drop. |

So: **not committable as one change.** `./Tools/center-sprites.py --check` first.


## Findings — engineering session, three visual checks (2026-08-22)

**Context.** `Docs/eng-session-P4-visual.md`, run on `feature/p4-visual-checks`
off `main`. Three cheap visual changes Chiu judges by looking, plus the stale
`XCTFail`. Ordered by what can go wrong silently.

**Films for review** (outside the repo, §0 — renders of a real trip). All three
are the same Iceland dump, `car-toy`, 21 stops, 64 legs, 211.5 s:

| | `~/Kamome-films/` | what varies |
|---|---|---|
| A | `2026-08-22-cartoy-light/kamome-iceland.mp4` | today's shipping look, halo removed · 472 s |
| B | `2026-08-22-cartoy-dark-x2/kamome-iceland.mp4` | dark, displayScale 2 · 491 s |
| C | `2026-08-22-cartoy-dark-x3/kamome-iceland.mp4` | dark, displayScale 3 · 475 s |

**Stills** (seconds each, since finding 6 was fixed), same frame t=114.3 s:
`2026-08-27-subject-stills/` — the 225/180/157.5 sweep plus the seagull;
`2026-08-27-appearance/{light,dark}/` — the light-vs-dark pair at displayScale 2,
which is the only place that axis has been compared on equal terms.

---

### 1. The halo was the configured glow, and the brief's premise was wrong

**Decision.** `RecapStyle.modernMinimal` no longer sets a glow alpha
(`a58942d`). The pass and its style properties stay.

**Why.** `RecapStyle()` has `routeGlowColor` alpha 0 — but nothing renders the
neutral default. Both the app (`UI/Recap/RecapModel.swift:202`) and the desk
harness (`Tests/AppTests/RecapDemoFilmTests.swift:63`) select
`RecapStyle.modernMinimal`, which set **alpha 0.32** with
`routeGlowWidthMultiple` **3.0**. The glow pass ran on every frame of the
2026-08-21 film.

**Evidence.** Measured on frame t=120 s of that film, against the preset's own
numbers — VERIFIED, not inferred:

| | measured in the film | the preset says |
|---|---:|---:|
| core stroke width, min over the curve | 17 px | `routeWidthPx` 17 |
| band ÷ core, median of 917 columns | 3.12 | multiple 3.0 |
| halo colour over terrain | (150, 183, 186) | (150, 184, 187) |

The colour figure is the glow at alpha 0.32 composited over the de-graded
terrain sample and re-graded; it lands within 1/255 on all three channels. After
the fix, the same measurement on film A gives band ÷ core **1.14** — a single
stroke plus its antialiased edge.

**Why it inverted.** The preset's comment says it was tuned against the dark
subtractive souvenir map, where translucent light-blue over near-black reads as
*light*. MapLibre was parked 2026-08-15 and films render on Apple Maps' light
base, where the same mid-blue composites **darker** than the terrain. Same code,
opposite effect — a consequence of the substrate ADR, the same class as finding
6 of 2026-08-21, **not** a defect in `RecapOverlayRouteDrawing`.

**Risk.** The glow is the right treatment again the day a dark base returns, and
film B shows a dark base is now one parameter away. Whoever turns that on must
re-judge the trail, not assume the glow should come back with it.

### 2. ⚠️ The golden-frame and continuity gates cannot see `MapKitSnapshotProvider` at all

**Decision.** `MapKitSnapshotScaleTests` was written because the brief's
proposed verification could not have worked.

**Why.** The golden-frame gates render on `FlatSnapshotProvider`, which carries
its own projection and its own `RecapStyle()`. `RecapCameraContinuityTests` runs
offline over `CameraFrame`s and never renders. **Neither touches the shipping
base-map provider.** Every other `MapKitSnapshotProvider` reference in the suite
is an env-gated bench.

**Risk, and it is wider than this task.** Apple Maps has been the shipping
substrate since 2026-08-08, and the type that produces it has no always-on test.
A projection error there is invisible to CI, and invisible in a still frame.

### 3. 🔴 MapKit may raster at a scale nobody asked for — measured, cause UNKNOWN

**What happened.** The first scale-2 render was refused by the provider's own
guard: MapKit returned a **1620x2880px image for a 540x960pt canvas — 3x**, the
simulator device's native scale.

**What was then measured** (`MapKitSnapshotProbeTests`, live SDK):

- `point(for:)` answers in the **point canvas the snapshotter was given** — a
  540x960pt canvas puts the region's centre at (270, 480). VERIFIED across
  scales 1/2/3. This is what the correction rests on, and it means the factor is
  `widthPx / canvasWidth` — the *requested* scale — never the raster scale.
- Scales 1/2/3 × spans 20/200/900 km × 8 concurrent requests: **every one
  honoured the request exactly.** The deviation did not reproduce.

**So the trigger is UNKNOWN** and is treated as something MapKit may do rather
than something Kamome can prevent. The guard now refuses only a **non-uniform**
raster, where no single factor maps canvas to frame; a uniform one at any scale
is resampled into the frame and the labels still arrive at the requested size
(`f995b13`).

**Cheapest thing that would settle it:** re-run the scale-2 film and watch for a
second occurrence. One deviation in three renders is not a rate.

### 4. The keyed path works — the 2026-08-21 UNKNOWN is closed

**VERIFIED.** All three renders routed against Geoapify with the key in
`Config/Secrets.xcconfig`, through the app's own configuration. No 401, no
locally-run Worker:

    matchTrip: 58/64 legs routable, budget 120s
    matchTrip: 50/58 legs reconstructed; 8 have no road route, 0 unreachable,
               0 rate-limited, 0 never asked

**Better than the reference run**, which reported 49/58 and 1 unreachable. The
1 unreachable was the timeout it named as retryable, and it routed this time —
so 50 solid legs, and the reference film's own reading of it was right. The 8
without a road route are identical, and the detour-gate rejection is
byte-identical (61.6 km routed vs 17.5 km straight, 3.5×), which is a good
cross-check that this is the same trip through the same policies.

Reproduced on all three renders. Nothing here reopens ADR 2026-08-20 (d).

### 5. displayScale changes label *density*, not only label size

**Reported, not decided — this is Chiu's judgement.**

Labels roughly double from scale 1 to scale 2, as predicted. But MapKit also
chooses **fewer** of them, and the effect is strong by scale 3:

| | scale 1 | scale 2 | scale 3 |
|---|---|---|---|
| Sauðárkrókur | present, small | present, ~2× | **absent** |
| Blönduós | present | absent | absent |
| Akureyri | present | present | large, **collides with the route line** |

Scale 2 reads as the balance; scale 3 buys size by spending the place names the
souvenir map is partly made of. Road-network detail thins at 3 as well. Both
knobs are env overrides (`KAMOME_MAP_APPEARANCE`, `KAMOME_MAP_DISPLAY_SCALE`),
**not** config keys — nothing is shipped until Chiu picks one.

### 6. ✅ FIXED 2026-08-27 — `RecapPilotFilmTests` and `RecapStopStillTests` could not run at all

**Was:** `RecapReviewScene.make` threw `SetupError.noRegion` when no `.pmtiles`
region covered the trip, so since 2026-08-15 both harnesses depending on it were
dead — the one that limits a render to N seconds, and the only one that writes
stills. Every review render this session had to be a full 211.5 s film, ~8
minutes each, which is why `KAMOME_SUBJECT` was wired into `RecapDemoFilmTests`
(`cad1dba`) rather than reused.

**Fixed in `78a910e`**, and the rule now has **one** implementation
(`ReviewSubstrate`) because two copies had already proved they get corrected
separately: `77b71b4` fixed the `RecapDemoFilmTests` copy and did nothing for
this one. Stills now render in under a minute, which is what made the
subject-size sweep (`57a5692`) cheap enough to do properly.

**The lesson worth keeping:** a rule stated twice is a rule that will be fixed
once. Both copies here were wrong, in different directions — one `XCTFail`ed and
carried on, the other threw.

### 7. ✅ DECIDED 2026-08-27 — the subject shrinks 30%, the mark does not follow

`export.subject_length_px` **225 → 157.5** (Chiu, from a 225/180/157.5 still
sweep on the film he had just watched), and the seagull's `length_fraction`
**0.7 → 1.0** so the mark holds its current 157.5 px rendered size. `57a5692`.

**Why the mark was asked about rather than left to follow:** at 0.7 of the new
base it would render at 110.25 px, and 112.5 px (0.5 of the old base) is the size
rejected on 2026-08-18 for reading too small.

⚠️ **Carry this forward:** pinning at 1.0 discards the relational intent
`cb14ae8` built the fraction for. The mark is now the same length as a vehicle
and **will** follow the base fully next time it moves — today's size survives
only because the base fell by the reciprocal. If `subject_length_px` changes
again, the mark's size is a fresh judgement, not something this value protects.

The film sprite is `seagull/omni.png`; `logo.png` beside it is only the S3 picker
thumbnail.

---
### 8. 🔴 IF DARK SHIPS, `a58942d` REOPENS — the halo verdict is light-only

**Not acted on. Do not touch `RecapStyle` on this.**

`a58942d` turned the glow off **because the base was light**, and its own message
says the pass "is the right treatment again the day a dark base returns". Chiu
accepted "the halo is gone" from film A, which was rendered **light**. That
acceptance is therefore not a settled result on a dark base — the glow was
designed for one and inverted only on the other.

So the appearance choice is not just a look decision: **picking dark reopens a
closed one.** The mechanism is intact and one line away (`routeGlowColor` alpha
in `RecapStyle.modernMinimal`), which is why it was kept rather than deleted.

**Evidence for the choice, rendered 2026-08-27:** two stills, light and dark, both
at displayScale 2, same frame (t=114.3 s), same subject size — one variable.
`~/Kamome-films/2026-08-27-appearance/{light,dark}/`. Chiu had never compared the
axis on equal terms: film A was light *and* scale 1, while B and C were both dark.

**Cheapest thing that would settle the glow question if dark is chosen:** render
that same still twice on the dark base, glow alpha 0 vs 0.32. Minutes, now that
`RecapStopStillTests` runs.

### 9. ⚠️ PROCESS — a wide `git add` committed a wrangler cache file

`Deploy/worker/.wrangler/cache/wrangler-account.json` was swept into `78a910e` (pre-rewrite `bbf08c4`), a
commit about substrate fallback. The Cloudflare account id in it is **not a
secret** — it is in dashboard URLs and authenticates nothing.

**Why it still mattered:** it is a 32-hex string, and this project's key-leak
check is "zero 32-hex hits over the pushed range" — used three times since
2026-08-21. One permanent false positive there teaches people to skip the check.
CI never would have caught it and was **not** widened: its guard greps
`*.xcconfig` for the routing key specifically, and that narrowness is deliberate.

Chiu chose to rewrite the branch (nothing had reached `main`);
`backup/p4-visual-prerewrite` at `0d7de54` is the pre-rewrite tip, his to delete
after the PR merges. `.wrangler/` is now gitignored (`834b0fc`).

**The habit worth changing:** `git add -A` was used for every commit this session.
It is why an unrelated file rode along in a commit whose message says nothing
about it.



## Findings — engineering session, the film follows the system appearance (2026-08-28)

**Context.** `Docs/eng-session-appearance.md` (the `Arch.md` §12 design, written
before any code), on `feature/p4-appearance-follows-system` off `main` at
`87d1d4e`. Chiu's decision of 2026-08-27: the film follows the device's system
appearance, and light mode gets an orange trail. **The first change in this series
that moves shipped behaviour.**

Both values that were Chiu's are now **closed** (2026-08-29): the orange is
candidate **B**, `RecapStyle.routeAccent` `#FF8A5B`, and the glow **stays off on
dark**. See `Docs/decisions.md` 2026-08-27.

**Stills for review** (outside the repo, §0 — renders of a real trip), all Iceland,
`car-toy` at the shipped 157.5 px, displayScale 2, the same frame the subject sweep
used: `~/Kamome-films/2026-08-28-appearance/`.

### 1. ✅ CLOSED 2026-08-29 — the orange is `#FF8A5B`, and the constraint the brief could not know

`RecapStyle.routeAccent` is **`#FF8A5B`** and its own comment calls it "the trail's
brand colour" — it is the validated web prototype's `--route`
(`Docs/prototype/recap_engine.html`), already shipped in Kamome as the active
progress dot and the stop's strap line. So "the trail is orange" is not a new
direction: it is the prototype's direction, which the dark souvenir map's cyan
overrode in 2026-07-22.

The constraint that follows: **the trail and the end card's mark are in the same
film.** `chromeAccentColor` `(0.95, 0.55, 0.32)` draws the brand mark and the
closing line (`RecapOverlayChromeDrawing:137,239–241`). The file already carries
two near-miss oranges, which is exactly what `routeAccent`'s comment says the
accent exists to prevent. Whichever candidate wins there is a case for collapsing
the pair — **that is Chiu's call and was not done here.**

Sweep candidates (`Docs/eng-session-appearance.md` §6): **A** = `chromeAccentColor`
exactly, **B** = `routeAccent` `#FF8A5B`, **C** = `(0.96, 0.42, 0.15)`, deeper, as
the hedge against a pale base. **Chiu chose B** (2026-08-29), so the film keeps one
warm accent rather than gaining a fourth. Collapsing `chromeAccentColor` into it
remains open and is still his.

### 2. 🔴 CORRECTS finding 8 — the glow was **not** "one line away"

`HANDOFF.md` finding 8 (2026-08-27) says the retired glow is "one line away
(`routeGlowColor` alpha in `RecapStyle.modernMinimal`)". It is not, and the
difference matters to the A/B it proposes.

`a58942d` did not zero the alpha on the glow's own colour. It replaced the line
with `style.routeGlowColor.copy(alpha: 0)` — the alpha of the **plain default's**
blue `(0.13, 0.45, 0.95)`. The retired pass was `(0.22, 0.62, 0.92)` at α0.32.
Raising that alpha would therefore have restored *a different blue* than the one
Chiu once accepted on the dark map, and the A/B would have been measuring two
changes while reporting one.

Closed by `RecapStyle.retiredGlowColor`, which holds the original colour so the
dark preset's alpha is genuinely the only variable. **VERIFIED from `git show
a58942d`,** not inferred.

The A/B it enabled has since been judged: **the glow stays off on dark** (Chiu,
2026-08-29). On dark the pass works exactly as designed — it lifts the terrain
beside the trail by `(8,29,29)`, compositing *lighter* than the ground, which is
the opposite of what it did on light — and he chose the trail without it anyway.

### 3. ⚠️ Three `RecapStyle` tokens have no consumer, and one test helper is a no-op

Grep-verified across `Core UI App Tests` on 2026-08-28:

| token | readers |
|---|---|
| `cardColor` | none — only `RecapAtmosphereTests` and `RecapRenderTestCase` assert/set it |
| `cardTextColor` | none — same |
| `markerColor` | **none at all**; its declaration is the only occurrence in the repository |

They belonged to the stop label's pill, removed on 2026-07-31 when the label was
restyled to the prototype's unplated `.clabel`. The comment above them still said
"still used by the stop label's pill" — corrected in place, tokens left alone.

The consequence worth knowing: **`RecapRenderTestCase.opaqueCardStyle` is
identical to `RecapStyle()`.** Its doc comment says it makes "chrome panels at
full opacity so their pixels are exactly white", and it is used by five assertions
in `RecapOverlayRendererTests` that believe they are rendering against an opaque
card. They are not — nothing reads the token. Those tests may still be sound for
other reasons; **nobody has checked**, and that check is not this change.

Removing the three tokens touches four test files and is its own change.

### 4. ⚠️ The reproducibility ADR is met in shape, **not** in persistence

`Docs/decisions.md` 2026-08-15 requires export variation to be chosen at the
composition boundary, held constant, **and persisted with the export**. The first
two are met and are the reason the design looks the way it does. The third is not:
`Core/Persistence/AppDatabase.swift` has **no export table** — the seed feature
that would create one is deferred by the same ADR.

So today: re-exporting the same trip on a device whose appearance has changed
produces a different film, and the only record of which one you have is the
`KamomeLog.recap.notice("film: …")` line, which now names the appearance.
**Stated, not solved.** When the export record lands it has exactly one obvious
field to carry. Do not read the design doc's §4.1 as a claim that the ADR is
satisfied.

### 5. The souvenir map would have got the light palette — closed before it shipped

`RecapModel.snapshotProvider` still returns `MapLibreSnapshotProvider` when a
`.pmtiles` region covers the trip. Nothing installs one today, so it never fires —
but with the film following the device, a light-mode phone with tiles installed
would have drawn an orange trail and a light-tuned grade over a **near-black**
map. That is the halo defect's mechanism (`a58942d`) running the other way.

`MapRendererCapabilities.fixedAppearance` closes it: the souvenir map declares
`.dark`, `RecapModel` resolves `fixedAppearance ?? requested`, and a new always-on
test holds both halves. The MapLibre half of that test **does compile and run** in
this build — verified by its positive control failing, not assumed from the
`#if canImport`.

### 6. ℹ️ `Docs/current-state.md` passes its staleness check and is still behind

Its "Last synced" line names 2026-08-21, which **is** the newest ADR in
`Docs/decisions.md`, so the protocol in `CLAUDE.md` reports it fresh. But its
*Active work* section still says the three visual checks are "NOT YET RUN" and
lists PRs #16/#17 as open; #18 has since merged and those checks are done.

The staleness protocol keys on the ADR ledger alone, so a session that only ran
the check would trust a stale Active-work section. Not fixed here — this is a
governance-session edit, and the file says as much.

### 7. MEASURED — Chiu's fjord, in numbers, and the trail against the sea

Every figure below is a pixel probe of the rendered stills at **row y = 657**, the
north-coast trail west of Sauðárkrókur, after the grade and vignette
(`~/Kamome-wt/pixel`, source `~/Kamome-wt/pixel.swift`). Same frame (t=114.3 s),
same camera, displayScale 2. **VERIFIED by measurement, not by looking.**

| appearance · trail | solid, composited | dashed (α0.55) | the sea beside it |
|---|---|---|---|
| light · cyan `#6BDEFA` *(today)* | `(92,190,218)` | `(102,188,217)` | `(115,184,216)` |
| light · **A** `#F28C52` | `(205,121,77)` | `(164,149,140)` | `(115,184,216)` |
| light · **B** `#FF8A5B` | `(216,120,84)` | `(170,148,144)` | `(115,184,216)` |
| light · **C** `#F56B26` | `(208,94,40)` | `(166,134,120)` | `(115,184,216)` |
| dark · cyan, glow 0 | `(92,190,218)` | `(62,126,169)` | `(26,49,113)` |
| dark · cyan, glow 0.32 | `(92,190,218)` | `(61,138,189)` | `(34,78,142)` |

**The fjord, quantified.** On today's light base the solid trail differs from the
ocean beside it by **(23, 6, 2)** — one channel, by 9%. That is the measured form
of "not distinguishable from a fjord". Every orange candidate separates it by more
than 100 on two channels.

### 8. 🔴 On the light base the dashed leg is indistinguishable from the solid one

**The finding this session did not go looking for.** Today, light base: solid
`(92,190,218)`, dashed `(102,188,217)`. **Δ = (10, −2, −1).** The two are the same
colour to any viewer. Honest provenance (PD-1, spec §0) is *not reaching the
viewer* in a shipped light film — the distinction survives only in the dash gaps
and the stroke width, and see finding 9 for what happens to the gaps.

Why: α0.55 over a **bright** background lands almost on top of the full-alpha
colour, because the backdrop is already near the trail's own luminance. Over
near-black it lands well below it — dark, dashed `(62,126,169)` against solid
`(92,190,218)`, clearly the weaker claim. **This is the halo inversion again**, in
a second token: an alpha-derived treatment tuned on a dark base behaves oppositely
on a light one. Worth stating as a rule, because it will keep happening.

**What the oranges do to it.** All three fix the invisibility and are clearly
weaker than their solid. Chroma (max−min channel) at *this* sample point:

| | solid chroma | dashed chroma, at y=657 | terrain there, for scale |
|---|---:|---:|---:|
| A `#F28C52` | 128 | 24 | 54 |
| B `#FF8A5B` | 132 | 26 | 54 |
| C `#F56B26` | 168 | 46 | 54 |

⚠️ **Do not read that column as a property of the alpha rule — it is a property of
what the leg crosses**, and I nearly recorded it as the former. At α0.55 the
backdrop shows through, and this particular leg crosses a pale **blue-grey**
terrain patch `(210,212,216)`, which pulls a warm stroke toward grey. Measured on
the same shipped preset (candidate B) where a dashed leg crosses **green/beige**
instead — the south coast near Vík in `stop-light` — the dashed stroke is
`(198,158,112)`, chroma **86**, unmistakably orange. So the honest range for B's
dashed leg is roughly **26–86 depending on terrain**, not 26.

What survives as a genuine input to the choice: C's deeper start gives its dashed
variant more colour to lose, so it holds hue on the worst backdrop where A and B
do not. ⏳ Chiu's call, and it need not be a straight pick of the three — keeping A
or B and raising `routeInferredAlpha` on light gets to the same place. Nothing was
changed on this.

### 9. 🟠 The dashes read at the stop camera and **not** at the travelling one

Printed by the harness on every subject still: **43 legs revealed, 8 dashed ·
longest 17.5 km = 4.0% of the frame width (span 432 km).**

4.0% of 1080 px is **≈43 px**. The dash cycle is `routeInferredDashPx` 26 +
`routeInferredGapPx` 22 = **48 px**. So at the wide travelling camera the *longest*
inferred leg in this film is shorter than one on-off cycle, and the other seven are
shorter still: it renders as **one stub**, not as a dashed line.

⚠️ **I first wrote this as "the dashed convention does not work", and that was
wrong** — the stop stills falsified it before it was committed. During a stop beat
the camera is far closer, and in `stop-light` the inferred stretch on the south
coast near Vík resolves into **unmistakable dashes** beside the solid trail, in a
clearly lighter orange. So the honest statement is about *where in the film*, not
about the convention:

- **Travelling shots (span ~432 km):** provenance is carried only by the stroke
  being thinner and paler. The dashes are not visible as dashes.
- **Stop beats:** the dashes read exactly as designed.

Whether that matters is a product question — a viewer sees both, and the stop beat
is where the film asks to be read closely. **Nothing changed.** The dash lengths
are style, not config, and stated at the 1080 reference width; resizing them
against the camera span is Chiu's call, not the appearance change's.

The 17.5 km leg is the detour-gate rejection — 61.6 km routed against 17.5 km
straight, the same one the 2026-08-21 and 2026-08-22 runs named. Routing was
byte-identical again this session: **50/58 legs reconstructed, 8 with no road
route, 0 unreachable, 0 rate-limited.**

### 10. ⚠️ A render silently drew the fallback marker instead of the car

Four light stills, identical but for `KAMOME_ROUTE_COLOR`. Three drew the car
sprite; the **`light-C-deeper`** run drew the **vector seagull fallback** — white,
on a light base, close to invisible. The test passed in 25.8 s with no retry and
**nothing in the console said the sprite set had not loaded.**

`VehicleSubjectRenderer.make` falls back to `.marker` when `VehicleCatalog.resolve`
returns nil, and its doc comment says that "only fires when the app's own resource
bundle cannot be found — a state no test can arrange". **That claim is now false by
observation.** Whether it is the same resource-bundle problem as the intermittent
`KamomeCore_KamomeExportEngine` crash below is *suggestive, not established*.

> **Answered 2026-08-29 — read the bundle-lookup entry below instead of this
> paragraph.** The spawned task settled it as far as the evidence goes: **one
> mechanism, two symptoms** (the crash's `Bundle.module` trap was removed on
> 2026-08-15 and the same lookup has returned nil ever since), but **not one root
> cause** — the trigger is still UNKNOWN, and two tested hypotheses came back
> negative. Consequence 1's diagnostic is built; so is a second one that names
> which candidate the bundle lookup tried. Consequence 2 was acted on: the token
> is ink on light, and is being swept for a navy.

Three consequences:

1. A review still can be materially wrong while looking fine, and a reviewer would
   have no way to know. `KamomeLog` is in `KamomeConfig`, which `KamomeExportEngine`
   already depends on, so the diagnostic is about one line — **not added here**,
   because this change does not touch that file. Spawned as its own task.
2. `fallbackMarkerColor` (white) joins the list of tokens that arguably must differ
   by appearance — §5 of the design doc had it as "fallback-only"; this render is
   the counter-example. Product call.
3. `light-C-deeper` was **re-rendered** into `light-C-deeper-rerender/` so the
   sweep Chiu judges is clean. The affected still is kept beside it as the
   evidence. The trail pixels are byte-identical between the two runs — only the
   subject differed.

### 11. The chrome and the deck, on a light base — reported, not judged

`title-{light,dark}` and `stop-{light,dark}`. The brief's point stands: these
survived on light, but "survived" was not "was judged", and now there is a pair.

- **The title card works in both, differently.** The dark scrim
  (`chromeScrimColor`, α0.55 + centre boost) fades seamlessly into a dark base and
  reads as a deliberate letterbox band on a light one. Neither is broken; the dark
  one is the more elegant of the two. **No change made.**
- **`labelTextColor` is white type** and on the light base it is close to its
  limit over pale terrain — `labelShadowColor` is what is holding it up, which is
  what its comment says it is for ("a bright photograph or a pale glacier"). Worth
  Chiu's eye.
- **`labelPinColor` is cyan** `(0.35, 0.85, 0.95)` — the same colour family as the
  water, on the light base, exactly the trap the trail was in. In `stop-light` the
  pin sits on the coast at Reykjavík. Not in the brief's list, and not changed.
- **`deckMatteColor`** (the white photo keyline) reads on both. The deck itself
  was rendered with the gradient stand-ins — `KAMOME_STOP_PHOTOS` was not set, and
  the harness says so on the console — so this is a **layout** check, not a check
  of how a photograph sits on a light base.
- Stop names read "Unnamed stop": `RecapReviewGeocoder` is opt-in and was off.
  Expected, not a regression.

**Verification worth noting.** `stop-light` and `stop-dark` used **no colour
override at all** — only `KAMOME_MAP_APPEARANCE`. One value selected the light
Apple Maps base *and* the orange trail, and its solid stroke measures
`(216,120,84)`, matching candidate B exactly. That is the shipped path working end
to end, not a harness-only result.

### 12. ✅ 2026-08-29 — two more tokens were in the water, and the enumeration was wrong twice

Chiu approved the direction; the **values are candidates** for him, rendered into
`~/Kamome-films/2026-08-29-tokens/`.

**`fallbackMarkerColor` → ink `(0.11, 0.13, 0.19)` on light.** Finding 10 is the
reason this is not cosmetic: the marker only appears when the vehicle artwork
cannot be loaded, and *the wrong still survived review because a white gull on a
light base is hard to see*. So the token's job now includes being noticed.
Measured, with the sprite path deliberately bypassed:

| | marker, composited | terrain beside it | luminance gap |
|---|---|---|---:|
| light, **white** (what happened by accident) | `(216,218,222)` | `(211,213,217)` | **~5** |
| light, **ink** (the candidate) | `(25,32,48)` | `(212,213,218)` | **~180** |
| dark, white (unchanged) | `(216,218,222)` | `(91,115,152)` | ~105 |

Ink rather than the trail's orange, deliberately: a warm gull would sit on the warm
trail it is travelling along and read as styling rather than as a fault. The value
is `markerOutlineColor`'s, reused so the film gains no new colour, and only `fill`
matters — the shipped `.seagull` is a single stroked arc that reads neither
`accent` nor `outline`.

**`labelPinColor` → the trail's own hue on light.** Not a new rule: the dark preset
had followed it silently all along — `(0.35,0.85,0.95)` is within **0.07** of
`trailOnDark` on every channel. Left cyan on Apple Maps it is a water-coloured dot
sitting on a coastline. Dark is deliberately untouched, so the change is one
appearance wide.

⚠️ **The part worth carrying forward is how the enumeration failed.** The design
doc's palette table (§5) got two answers wrong, both the same way: I judged each
token by *where it is drawn* rather than by *what it is drawn on*.
`fallbackMarkerColor` was written off as "fallback-only" and the fallback fired by
itself the same day. `labelPinColor` was never enumerated at all — the brief did
not list it and it is not part of the trail. The question that catches both is not
"does this token matter?" but **"what does this colour sit on, on each base?"**
Anyone auditing the remaining tokens should ask it that way.

Both are held by new always-on guards, each shown red by a positive control — as
*rules*, not values: the pin must sit in the trail's hue family (not equality, since
the dark pin is deliberately a shade off), and the fallback marker must contrast
with its base by luminance (not "must be this ink", since what has to be true is
that it is visible).

**The pin, measured** (stop beat, light base): the cyan pin composited to
`(77,186,211)` beside a sea of `(100,179,218)` — **Δ = (23, 7, 7)**, which is the
*same margin* that made the trail read as a fjord. The trail's hue puts it at
`(216,120,84)`, Δ from that sea `(116, 59, 134)`.

### 13. ⏳ OPEN — solid versus dashed, asked as its own question

Chiu asked for this to be judged separately rather than absorbed into the colour
pick, because it is a **product rule** (PD-1, spec §0): recorded versus
reconstructed-from-photos has to reach the viewer.

**First, what the orange already did.** The defect in finding 8 was cyan-specific.
On light, cyan solid `(92,190,218)` vs cyan dashed `(102,188,217)` — Δ `(10,−2,−1)`,
the same colour. With the chosen `#FF8A5B` the two are plainly different at every
alpha tried. **The provenance defect this session measured is closed by the trail
change**; what is left is a preference about how much weaker a guess should look.

**The sweep** — stop beat, light base, `routeInferredAlpha` the only variable, all
sampled at one pixel over the same terrain (`~/Kamome-films/2026-08-29-tokens/`).
Solid is `(216,120,84)` in every row:

| `routeInferredAlpha` | dashed, composited | Δ from the solid | chroma |
|---|---|---|---:|
| 0.40 | `(192,170,121)` | `(24, 50, 37)` | 71 |
| **0.55** — ships today | `(198,158,112)` | `(18, 38, 28)` | 86 |
| 0.70 | `(203,145,103)` | `(13, 25, 19)` | 100 |

Monotonic and exactly the trade you would expect: **lower alpha separates it from
the solid, higher alpha keeps more of the trail's own hue.** There is no value that
maximises both, so it is a judgement, not a calculation.

**Two things that constrain the judgement, and neither is alpha.**

1. At the **travelling camera** the dashes do not resolve at all (finding 9 — a
   43 px leg against a 48 px cycle), so colour is the *only* provenance cue there,
   and no alpha changes that. If Chiu wants the guess legible during travelling
   shots, the lever is dash geometry against camera span, which is a separate
   question with its own render.
2. **This cannot be gated.** The separation that matters is the *composited*
   difference, which depends on the terrain the leg crosses — the whole point of
   finding 8's correction. At style level the only expressible rules are the ones
   `testInferredLegsStayDerivedFromTheTrailInEveryAppearance` already holds (same
   hue, weaker alpha, thinner, actually dashed). A rendered gate over
   `FlatSnapshotProvider` would *pass on the exact defect this session found*,
   because a flat synthetic background is not Apple Maps' terrain — so it would
   buy confidence rather than coverage, and is deliberately not added.

**Nothing changed.** `routeInferredAlpha` stays 0.55 until Chiu says otherwise.

---


## Findings — engineering session, the silent subject fallback (2026-08-29)

**Context.** The task 2026-08-28's finding 10 spawned: make the marker fallback
loud, and find out whether it is the bundle crash wearing a different symptom.
Both answered below and in the bundle-lookup entry. Chiu then approved the
resolution diagnostic and asked for two changes to the marker itself.

**Renders for review** (outside the repo, §0): `~/Kamome-films/2026-08-29-fallback-navy/`,
five stills and a `README.md` with the numbers. Same trip, same frame (t=114.3 s)
as every subject still since the size sweep; the failure visual is *forced*, so it
is judged on purpose rather than by accident.

---

### 1. ✅ FIXED — the stand-in had become larger than the thing it stands in for

`fallbackMarkerLengthPx` was a hard-coded **170** while ADR 2026-08-27 moved
`export.subject_length_px` **225 → 157.5**. From that day the fallback seagull
rendered **12.5 px longer than the car**, and nothing failed, because the two
numbers sat side by side with nothing tying them together. Chiu noticed it by
looking.

**The fix is the relationship, not the number.** `fallbackMarkerLengthFraction`
(default **1**) replaces the absolute, and `fallbackMarkerLength(subjectLengthPx:)`
is the one place it is applied. At ≤ 1 the marker is at most the subject, whatever
the subject becomes — the inversion is now structurally impossible rather than
merely corrected. Deliberately the same shape as `length_fraction` in
`vehicles.json`, whose own comment gives this exact reasoning; the manifest cannot
supply this one, because the fallback fires precisely when the manifest could not
be read.

`subjectLengthPx(configured:)` keeps its `max` as defence for a fraction above 1,
and keeps its signature, so no probe call site moved.

**Positive control, run rather than reasoned.** With the fraction set to 1.2 the
new guard fails at all five swept subject lengths —
`("135.0") is greater than ("112.5")` and so on up to `("360.0") is greater than
("300.0")` — and passes at 1. The neighbouring wiring test passed either way,
which is correct: it holds the wiring, the new one holds the bound.

### 2. `RecapRenderTestCase:57`'s `configured: 300` is consistent, not stale — reported, not changed

Asked to look at it and say what I found rather than update it silently. What I
found is that **300 is not a leftover shipped value in this file — it is this
file's own fixture.** `RecapRenderTestCase` builds its `TrackingConfig.Export`
with `subjectLengthPx: 300` (line ~119), and `vehicleHalfPx` clears
`configured: 300`. The probe clears exactly what the render under test draws, so
the two agree and nothing is wrong. 300 is also the suite-wide convention for a
synthetic subject: `CameraPathTests`, `RecapPacingTests`, `RecapEncoderTests`,
`LinearTimelineTests`, `RecapMarkerDeckStillsTests` and `RecapFollowCamStillsTests`
all use it.

**What is true is the reading risk**, and it is the same one that has now cost
this project four times: a number in a test file that resembles a shipped value
but is not one. Changing it would mean changing the fixture too, which moves what
the golden-frame probes render and clear — a real change, for no defect.
**Left alone.**

### 3. ⏳ OPEN — which navy, and the constraint stated as a number

Chiu wants the marker blue rather than the near-black ink. The constraint is
**luminance, not hue**: `testTheFallbackMarkerContrastsWithItsBaseMap` asserts
< 0.35 on light and > 0.65 on dark, and says in its own comment that it is
asserting visibility rather than an ink.

Measured on the rendered stills, in 0–255 units, against the terrain within 6 px
of the stroke:

| candidate | hex | gull L | beside | **gap** | guard |
|---|---|---:|---:|---:|---|
| white — what shipped until 2026-08-28 | `#FFFFFF` | 217.4 | 191.0 | **26.4** | ✗ |
| the ink, today | `#1C2130` | 34.0 | 190.9 | **156.9** | ✓ |
| A · near | `#17204A` | 34.0 | 190.9 | **156.9** | ✓ |
| B · deep | `#1B2A5B` | 41.5 | 190.9 | **149.4** | ✓ |
| C · bright | `#23407F` | 58.3 | 190.9 | **132.6** | ✓ |

**All three navies clear the guard — run, not calculated** (one temporary edit to
the preset per candidate, reverted; logs `~/Kamome-wt/logs-fallback-diag/guard-*.log`).
A bright cyan `#4FC3F7` was run as a control and **failed at 0.683**, so the guard
bites and is not pinning today's value.

Two things the table does not say. **The white baseline was rendered rather than
recalled** — 26.4 against 156.9 is the argument for the change, in the same frame
and the same units. And **clearing the bar is not clearing the water trap**: the
bar is brightness, the trap is hue, and `navy-C-bright` is included to show where
that begins, not as a recommendation.

**Chiu picks; nothing is committed.** The pick replaces one line in
`RecapStylePresets.modernMinimal(.light)`.

### 4. ⚠️ Base-versus-preset has now bitten four times, and the fourth is the sharp one

The glow "verified fact" quoted the neutral default's alpha 0; the PO session's
ADR quoted the neutral default's blue; both times the shipped preset said
something else. The third was spotting that the ink lives in the preset while the
base `RecapStyle.fallbackMarkerColor` is still white.

**The fourth is worse than a stale reading, and it is live.** `modernMinimal(.dark)`
**does not set `fallbackMarkerColor` at all.** The dark film therefore draws the
base default — white — and the guard's dark assertion (`> 0.65`) passes on a value
nobody wrote for dark. White happens to be right there. That is not the same thing
as it being chosen.

Two consequences worth Chiu's decision, neither acted on:

1. **Changing the base default silently changes the dark film.** This is the
   mechanical reason a navy goes in the light preset — not merely a procedural one.
2. `RecapStyle()`'s neutral defaults are load-bearing for the golden-frame gates
   (its own comment says so) *and* are the dark preset's palette by omission. Those
   are two jobs. Whether `.dark` should state its marker colour explicitly, or the
   base should be documented as "the dark preset's value, and the gates'", is a
   small design question — **reported, not folded into the colour sweep.**

### 5. 🔵 CARRY — the fault gull and the narrator gull are the same bird

`Docs/cross-region-journeys.md` requirement 4 — *"the load-bearing one"* — wants a
seagull as the **narrator of an unmodelled crossing**: honest provenance made
visual, *"we know you went from here to there; we do not know how"*. Its own words
are that this answer "must be cheap and **good-looking** rather than a failure
state."

The marker is being styled in the opposite direction: since 2026-08-28 it is
partly a diagnostic, and it has to say *something went wrong* at a glance.

**They are different objects** — the narrator is the `seagull` subject in
`vehicles.json` (omni sprite, `length_fraction` 1.0), the fault is
`VehicleMarker.seagull`, a stroked vector arc from `RecapStyle`. **A viewer cannot
tell them apart**, and that is the collision: the same bird would mean "we could
not classify your crossing" in one film and "the artwork failed to load" in
another. Nobody has decided which reading wins, and the navy pick makes the fault
bird more distinctive, not less.

**Noted at Chiu's instruction; deliberately not designed for.**

---


---

# Archived 2026-08-31 — closed sections from `HANDOFF.md`

*Moved when `HANDOFF.md` was put on a 300-line budget. History, never a work
instruction.*

## Findings — engineering session, the film follows the system appearance (2026-08-28)

**Context.** `Docs/eng-session-appearance.md` (the `Arch.md` §12 design, written
before any code), on `feature/p4-appearance-follows-system` off `main` at
`87d1d4e`. Chiu's decision of 2026-08-27: the film follows the device's system
appearance, and light mode gets an orange trail. **The first change in this series
that moves shipped behaviour.**

## Findings — PO/Architecture session (2026-08-29)

Three things that outlive the session. Everything else it found is in
`Docs/decisions.md` 2026-08-27 (b) or in the commits, and is not repeated here.

### 1. Two rules, learned the expensive way

- **Read a style value off the preset the app actually selects (`modernMinimal`),
  never off `RecapStyle`'s defaults.** The defaults are unrendered. This was got
  wrong twice from the same source — the glow brief, then a PO draft of the
  appearance ADR — and cost a correction in the ledger both times.
- **The PO session does not write an ADR for a decision an engineering session is
  actively implementing.** It drafted one for the appearance decision in parallel;
  two entries for one decision in an append-only ledger is worse than none, and the
  later-dated one would have won while being the weaker. The draft was withdrawn.
  What the PO session should record instead is what the implementer will not see:
  cross-cutting consequences, spent guarantees, and what was left undecided.

### 2. 🔴 CI is blocked account-wide — a red check currently means nothing

From 2026-08-29, GitHub Actions jobs fail in ~3 seconds with **zero steps
executed**: the Actions **spending limit** is exhausted. `main` fails identically,
so this is not a signal about any branch. Until it is cleared, **local
`xcodebuild test` is the only verification there is, and a PR must say so** rather
than let a red check read as a broken suite. It recurs when the monthly allowance
runs out unless the limit is raised.

### 3. Awaiting Chiu — a rule this session may recommend and may not write

A branch ref has silently picked up another session's commits three times, and a
`git add -A` swept an unrelated file into an unrelated commit once. **Recommendation:
a standing rule in `Arch.md` — confirm the current branch before committing, and
stage explicit paths only, never `-A` or `.`** `Arch.md` is the engineering charter,
so per `PO.md` this is a recommendation. **It is not in force until Chiu says so.**

### 4. Known remaining duplication, reported not acted on

The 2026-08-29 trim moved four merged sessions' findings to
`Docs/_archive/handoff-2026-08.md` (1,961 → ~915 lines). Two overlaps are left, both
deliberate:

- **"Reference — Phase 4 scope…"** below restates `Docs/current-state.md`'s phase,
  camera and routing entries at greater length. It is left because
  `Docs/eng-session-camera-arc.md` cites the freeze it records, and because it
  carries reasoning the index does not. **If it moves, current-state must absorb
  the reasoning first** — do not simply delete it.
- **"Findings — PO/Architecture session (2026-08-21)"** is the working analysis that
  produced `Docs/camera-arcs.md`. Once Pass 1 has run and been judged, the design
  doc is the surviving form and that section should be archived.

---



---

## Moved from HANDOFF.md on 2026-09-01 (closed)

### CI outage 2026-08-29 → 2026-09-01

### ✅ CI is alive again as of 2026-09-01 — a red check means something now
Actions failed account-wide from 2026-08-29 (spending limit) in ~3 s with **zero
steps executed**; PR #26 then ran `./check.sh` green on a runner in 5m44s.
**Treat a red check as real.** The dead-CI tell is ~3 s wall clock and `steps=0`.

### Three gaps the badge work left on record
Nothing measures **post-grade** output; nothing asserts the end card's **brand
mark**; and the **no-reader token cluster is four**.
→ `Docs/handoff-marker-badge.md` findings 6c, 6d, 7.

### The badge's size is provisional
0.60× was chosen from a rendered sweep and draws at 94.5 px. ⏳ **Judged from a
still; Chiu reserved the right to revisit it from a film.** Everything else
about the badge is decided (`Docs/decisions.md` 2026-08-29).
→ `Docs/handoff-marker-badge.md` finding 6.
