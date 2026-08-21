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
