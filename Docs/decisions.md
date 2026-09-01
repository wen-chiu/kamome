# Kamome — Architecture Decision Records

Append-only. Format: date, context, decision, alternative rejected. Decisions
already made in the spec (GRDB over SwiftData, MapKit over Mapbox, XcodeGen,
OSRM, Supabase — spec §2.2/§11.1) are not repeated here.

## 2026-07-12 — GRDB 6.x, not 7.x

**Context:** Spec mandates GRDB. The dev Mac currently has only Command Line
Tools with Swift 5.10 (macOS 14.4 cannot run Xcode 16, which needs 14.5+).
GRDB 7 requires a newer toolchain than local Swift 5.10.
**Decision:** Pin `GRDB.swift` at `from: "6.29.0"`.
**Rejected:** GRDB 7.x — revisit (one-line bump in `Package.swift`) once the
Mac is upgraded and Xcode 16 is installed; before Phase 1 device work ideally.

## 2026-07-12 — Core code lives in a root SwiftPM package (KamomeCore)

**Context:** No local Xcode means `xcodebuild` cannot run on this machine yet.
Core logic (persistence, config) has no UIKit/SwiftUI dependency.
**Decision:** `Package.swift` at repo root defines `KamomePersistence` +
`KamomeConfig` (paths still `Core/…` per spec §8); the XcodeGen app project
consumes them as a local package. Core builds locally with `swift build`.
**Rejected:** all sources directly in Xcode targets — would make every core
change unverifiable without Xcode/CI round-trips.

## 2026-07-12 — `kamome-smoke` executable mirrors the Phase 0 gate tests

**Context:** Command Line Tools ship no XCTest, so `swift test` fails locally.
The XCTest suites still exist and run in CI via the Kamome scheme.
**Decision:** A small `.executableTarget` (`swift run kamome-smoke`) re-runs
the same checks (schema v1, 50k round-trip < 2 s, config load, missing-key
failure) for local proof. CI remains the canonical gate.
**Rejected:** CI-only verification (too slow a feedback loop); rewriting tests
without XCTest (would fork the test suite).

## 2026-07-12 — Generated `.xcodeproj` is gitignored

**Context:** Spec §11.1: project is generated from `project.yml`, never
hand-edited. Committing it invites hand-edits and merge noise.
**Decision:** Ignore `*.xcodeproj`; `xcodegen generate` is step one of the
verification commands and of CI.
**Rejected:** committing the generated project for open-in-Xcode convenience.

## 2026-07-12 — postGenCommand downgrades project format for Xcode 15.4

**Context:** The dev Mac ended up with Xcode 15.4 (not 16). xcodegen 2.45
emits project format `objectVersion = 77`, which Xcode 15.4 cannot open, and
xcodegen has no spec option to control it (`xcodeVersion`/`objectVersion`
options verified ineffective).
**Decision:** `options.postGenCommand` seds `objectVersion` 77 → 56 on every
`xcodegen generate`. We use no 77-only features; Xcode 16+ (CI) reads 56 fine,
so the same generate works everywhere.
**Rejected:** pinning an older xcodegen via brew (fragile, fights upgrades);
requiring Xcode 16 locally (blocked: it was unavailable for this setup);
a wrapper script (would change the canonical `xcodegen generate` command).
Remove the postGenCommand when local Xcode reaches 16+.

## 2026-07-12 — Phase 1 device-test gate deferred (owner decision)

**Context:** Both Phase 1 unit gates pass in CI. The remaining criterion — a
~2 h physical drive with battery measurement — needs Chiu's car and calendar,
unavailable for at least a week. Blocking all work on it serves nothing;
silently skipping it would violate §0 rule 1.
**Decision:** Chiu (product owner, 2026-07-12) defers the device test: Phase 1
merges on unit gates alone, and the device sign-off becomes a **hard
precondition for starting Phase 3** (whose gate is device-bound anyway).
Before the drive happens, the Always-permission priming + background location
flow must land, or the drive would only measure a known limitation.
Checklist: `Docs/device-test-P1.md`.
**Rejected:** holding PR #2 open for a week (blocks fixture-testable Phase 2);
dropping the criterion (it guards the POC's core risk, §9 row 1).

## 2026-07-14 — Xcode 26.6 upgrade: objectVersion workaround removed

**Context:** Chiu upgraded the dev Mac to Xcode 26.6 (required to deploy to a
modern iPhone). Xcode 26 reads xcodegen's native objectVersion-77 format.
**Decision:** Removed the `postGenCommand` sed (2026-07-12 ADR above,
superseded). Local simulator destination is now `iPhone 17 Pro` — under
Xcode 26, `name=iPhone 15` no longer resolves (implied `OS=latest`).
GRDB stays pinned at 6.x: it builds clean on the new toolchain and a major
bump deserves its own change, not a rider on a phase PR.
**Rejected:** bumping GRDB to 7 in the same breath.

## 2026-07-12 — S4 photo reorder deferred (needs schema v2)

**Context:** §5 S4 lists "reorder photos", but schema v1's `photo_ref` has no
order column — ordering falls out of `taken_at`.
**Decision:** Phase 2 ships S4 with rename/note/highlight/delete (+ merge via
timeline swipe). Reorder waits for a forward migration v2 adding
`photo_ref.order_idx`, bundled with the next schema change rather than
shipping a migration for one cosmetic feature.
**Rejected:** schema v2 now (migration churn mid-phase for a non-gate feature).

## 2026-07-12 — Walk threshold raised to 6 km/h; mid band is non-evidence

**Context:** §4.1's literal defaults ("<4 km/h = walk, 4–20 = cycle/unknown")
misclassify normal walking — humans walk 4–5.5 km/h, and GPS-derived speeds
wobble around the true value. Fixture walk loops (4–4.5 km/h) proved it.
**Decision:** `speed_walk_max_kmh: 6` in config (tunables exist to be tuned).
The 6–20 km/h band classifies as cycle only on bicycle trips; otherwise it is
*inconclusive* — it freezes the current mode rather than confirming `unknown`
segments, so speed wobble can never split a segment.
**Rejected:** spec-literal 4 km/h walk ceiling (fails on real walking);
confirmable `unknown` segments (caused 7-way splits on the flapping fixture).

## 2026-07-12 — Derived speeds use a 30 s displacement baseline

**Context:** GPX replay (and any GPS without Doppler speed) must derive speed
from positions. Adjacent-fix deltas at ±12 m urban noise make a stroller look
like a cyclist (~10 km/h phantom speed).
**Decision:** Speed = displacement over the trailing
`speed_smoothing_window_s` (30 s) baseline; OS-provided Doppler speeds are
instead smoothed by a rolling mean. Never both — double smoothing smears
short bursts past `mode_confirm_s` and creates phantom segments.
**Rejected:** per-fix derived speeds (noise-dominated); median per-step speed
(still noise-dominated at walking pace).

## 2026-07-15 — Dwell resume via CLLocationManager region monitoring, not CLMonitor

**Context:** §2.3 pauses GPS at a dwell and resumes on exit of a
`dwell.region_radius_m` (150 m) region, naming `CLMonitor`. The engine side
existed (`processWhilePaused`), but `LocationService` only ever stopped GPS —
on a real device the first dwell ended tracking permanently. GPX replay never
caught it because the harness pushes samples straight into the engine.
**Decision:** `CLLocationManager.startMonitoring(for: CLCircularRegion)` +
`didExitRegion` in the existing delegate. `CLMonitor` is an async/actor API
that persists named monitors across launches — more machinery for one region
at a time (boring tech, §0). Region events require **Always** authorization,
so below Always (or if monitoring is unsupported, or `monitoringDidFail`
fires) GPS simply stays on during the pause and the engine detects the exit
from fixes — correct, just without the battery win.
**Rejected:** `CLMonitor` per the letter of §2.3 (revisit if we ever monitor
many regions); pausing GPS unconditionally (a When-In-Use user would strand
the trip at the first coffee stop).

## 2026-07-12 — Config loader module is `Core/ConfigLoader`, not `App/`

**Context:** Spec §8 lists "config loader" under `App/`. A loader inside the
app target cannot be unit-tested without booting the app, and Phase 1+ core
modules will need typed config without importing the app.
**Decision:** Types + parsing live in `KamomeConfig` (`Core/ConfigLoader/`);
`App/` keeps only the startup wiring (`AppConfig.loadOrDie()`), which is where
"fail loudly at launch" happens.
**Rejected:** loader entirely in `App/` per the letter of §8.

## 2026-07-15 — Spec v1.3: battery-moat pivot (passive tier, import; fork deferred)

**Context:** Strategy review (Chiu, 2026-07-15): road trips happen on a known
road network, so sparse, near-free location signals (significant-location-
change + CLVisit) can be map-matched back to full route fidelity — a
structural battery advantage Relive's off-network scenario cannot copy. The
same matching pipeline unlocks importing past trips (Google Timeline / photo
EXIF), killing the cold-start problem. The v1 bet becomes "will anyone pay for
a trip animation" (capture + import + recap), tested before the fork bet.
**Decision:** Spec bumped to v1.3. New Phase 4 = Import & Map Matching
(matching promoted from optional stretch to core), new Phase 5 = Passive
Capture Tier (v1 = Phases 0–5, TestFlight at the Phase 5 gate). Plans & Fork
moves to Phase 6, backend to Phase 7. Phase 1's adaptive engine is kept as the
high-fidelity tier — no rework of merged code. Monetization stance recorded as
transactional (per-trip export), not subscription. `Docs/icebox.md` created.
**Rejected:** replacing the Phase 1 engine with passive-only (single-day
turn-fidelity drives and off-network roads still need it, and it ships today);
keeping fork as the POC-completing killer feature ahead of import (import
acquires users with zero network; the fork loop needs one — §9).

## 2026-07-16 — Phase 3 starts now; device drive + photo-access check become P3 gate items

**Context:** 2026-07-16 smoke drive (two short sessions, ~20 min + ~24 min)
reviewed with the drive-test CSV. Findings: (a) route polyline deviates from
the road — expected from 50 m drive sampling + ε=15 m display simplification;
the planned fix is OSRM matching (§4.4, P3 stretch / P4 core) and raw points
are retained, so no config change now; (b) a 2-second phantom trip was saved —
`TrackingSession.end()` has no minimum-trip guard, and a zero-distance trip is
a degenerate input for the §4.5 speed-warped camera path; (c) a photo taken
during the trip never appeared: route-attached photo_refs (stop_id NULL) were
rendered nowhere, and under Selected-Photos access the app offered no
limited-library picker, so camera shots stayed invisible (limited-access gate
check caught a real gap — box stays unticked until the re-check); (d) the
evening dwell_pause without dwell_resume was benign (Chiu: parked until End
Trip), so region-resume remains unproven either way.
**Decision (Chiu):** Phase 3 (recap video) development starts now — its gate
is fixture-driven and device-independent until the final on-device export
check. The 2 h drive (`Docs/device-test-P1.md`) and the limited-photo-access
re-check move from Phase 3 *preconditions* to Phase 3 *gate items*: P3 cannot
close without them, and the drive rides the device build the P3 gate needs
anyway. Photo fixes landed same day (route-photos strip in S3 +
limited-library picker banner; re-match preserves highlights). Phantom-trip
guard (min duration/distance, tunables in `TrackingConfig.json`) is a P3 work
item.
**Rejected:** deferring the drive to Phase 4 (dwell region-resume and the
battery-moat numbers must be proven before more phases stack on the tracking
engine); tightening sampling config to fix road deviation (costs battery;
matching is the designed fix).

## 2026-07-18 — Speed evidence gated by accuracy; geocoded names need address context

**Context:** 2026-07-18 drive (Taoyuan, 17 km / 1.6 h urban, artifacts in
`Docs/demos/`). Two data bugs: (a) top speed showed 495 km/h — a 3-second GPS
glitch cluster (137 m jumps, h_acc 43–49 m, inside the 50 m keep filter)
carried CoreLocation's own `speed` = 137.4 m/s, and `TripStats` trusted raw
per-fix speeds, violating the spirit of the 2026-07-12 displacement-baseline
ADR; real top speed from clean fixes was ~61 km/h. (b) The stop was named
「臺灣島」— Apple's geocoder answers ordinary Taiwan coordinates with
island-scale features (via `areasOfInterest` and feature-only placemark
`name`s). Positives: phantom guard discarded a 50 s accidental start on
device; battery 100% → 100% unplugged over 1 h 40 m (zero `battery_change`
events); photo permission flow + route-photo strip worked.
**Decision:** (a) `TripStats` top speed = displacement over the trailing
`speed_smoothing_window_s` (mirrors the engine, incl. the ⅓-window warm-up
rule), computed only from fixes with h_acc ≤ new `filter.speed_max_h_acc_m`
(25); OS speeds are never used for the stat — position glitches leak into
them. Glitchy fixes still draw the route. (b) Stop naming trusts placemark
`name` only when address context exists (thoroughfare or subLocality non-nil)
and the name differs from coarse fields; fallback chain thoroughfare →
subLocality → locality; `areasOfInterest` dropped entirely (pure logic in
`StopDisplayName`, Core/TripComposer). MKLocalSearch POI naming → icebox.
**Rejected:** clamping top speed to a plausibility cap (shows the cap, hides
the bug); tightening `filter.max_h_acc_m` (glitch fixes are position-useful);
a blocklist of island names (fragile, market-specific). Note: stats_json of
already-recorded trips is not recomputed — POC-phase trips are throwaway.

## 2026-07-17 — Recap video: route photos in, export gets a photos toggle, video clips parked

**Context:** Product discussion (Chiu, 2026-07-17) on §4.5 as the flagship
share feature. Three proposals: (1) route-attached photos (stop_id NULL —
scenery shot from the car, roadside pull-over) should surface in the recap,
not just stop-pinned highlights; (2) two export outputs — a clean route-only
animation and the full version with photos; (3) embed short clips from videos
the user shot mid-trip, auto-excerpted, to make the recap livelier. Guiding
vision restated: minimum-effort trip capture and sharing.
**Decision (Chiu; scheduling delegated to Claude):**
- **Route photos in the recap** — accepted. As the camera passes a
  route-attached photo's projected position on the polyline, a small photo
  card floats in and out *without pausing* (contrast with the large held stop
  card). Scheduled as **P3 stretch**: lands after §4.5 steps 2–5 prove the
  render budget. But the overlay-event model is generalized **now**, in step
  2: photo/stop-card moments are timeline events computed alongside
  `CameraPath`, not hardwired to `holdingStopIndex`, so stretch items slot in
  without reworking the frame loop. Density cap is a config tunable (no magic
  numbers).
- **Photos toggle on export** — accepted, **P3 scope**. One pipeline, one S5
  switch: overlay events off = route-only animation (also the privacy-
  friendly share, and a step toward the icebox creator-b-roll wedge); on =
  stops + route photos.
- **Video clips** — idea accepted, **parked in icebox** until the P3 gate
  establishes real render numbers. Design constraints recorded there: clip
  selection must be deterministic (seeded by trip id — §4.5 is a
  deterministic frame pipeline with golden-frame tests, and re-exports must
  reproduce), clips run 2–3 s (tunable), muted, counted inside
  `max_hold_fraction`.
**Rejected:** random clip excerpting (breaks determinism and golden-frame
CI); 4–5 s clips (one clip would eat 15 %+ of a 30 s video); putting route
photos in the P3 gate (render budget for the base pipeline is unproven —
visual sugar stacks on a working frame loop, not before it).

## 2026-07-18 — Fork demoted from positioning language to mechanism

**Context:** Two rounds of external product review (GPT + Claude, 2026-07-17/18)
converged on the same judgment: "GitHub for road trips" is engineer-brain
framing. Ordinary travelers don't fork — they save routes and get inspired
(Pinterest psychology: Save / Inspired by / Get this route has low interaction
cost and low psychological commitment; Fork implies obligation to execute).
The spec had already absorbed the rest of that debate in v1.3 (battery moat,
import as acquisition hook, passive tier = v1, transactional monetization,
fork gated behind §10's ≥1-organic-fork criterion) — but the positioning line,
the §1.5 "killer feature" label, and the §4.5 end-card copy still carried the
v1.2 fork-first language. The end card is a P3 deliverable (ExportEngine
step 4), so the copy decision was due now, not at P6.
**Decision (Chiu):** Spec v1.4. Fork remains the underlying mechanism —
`.kamome` interchange file, `plan.forked_from` lineage, §3.1 schema all
unchanged — but it is no longer the product's marketing identity. Positioning
rewritten to memory-engine framing ("you don't have to remember the app; it
remembers the journey"). All user-facing copy uses **Save / Get this route /
Inspired by**; "fork" survives only in internal names (code, schema, §1.3
loop names). Three spec edits: positioning line, §1.5 row label (killer
feature → P6 bet), §4.5 end card ("Fork this route" → "Get this route").
S6/S7 screen wording is settled at P6 when those screens are built.
**Rejected:** renaming the `.kamome` schema fields or fork-loop internals
(churn with zero user-facing value); re-litigating the rest of the
GPT/Claude debate (v1.3 already absorbed the convergent conclusions — the
next data point is the P3 gate, not more positioning documents); adding an
AI prose diary or a generic badge/passport system (icebox; the 環島 badge in
§1.7 is already the correctly-scoped milestone feature).

## 2026-07-18 — Stop detection redesigned around real stops: streaks, walk visits, silence gaps

**Context:** Second real drive (17:04 export, `Docs/tests/`): a ~20 min temple
visit and an ~8 min 7-11 stop produced **zero** recorded stops. Three causes:
(a) the dwell window "must span the full duration" check required a sample in
the one-second sliver at the window boundary — dense GPX fixtures always have
one, sparse real sampling (10–50 m distance filters) almost never does, so
the live detector was structurally dead on hardware; (b) the temple was a
*walking* stop — the engine correctly made a 21 min walk segment (spread
≤ 50 m), and even a fixed dwell detector would have paused GPS mid-walk and
discarded the walking trace; (c) at the 7-11 the parked phone got zero
location callbacks for 586 s (distance filter), and a sample-driven detector
cannot see silence. Chiu (product): walking-around stops are stops on a road
trip, and the walking pace should be kept.
**Decision:** Three-part redesign. (1) `DwellDetector` keeps a
stayed-within-radius **streak** evicted by geometry, not age; it votes once
the streak spans `window_s`. (2) The engine **never dwell-pauses during a
confirmed walk segment** — walking IS recap material. (3) New `StopDeriver`
(Core/TripComposer) adds stops at trip end: **silence gaps** (≥
`dwell.gap_min_s` with displacement ≤ `dwell.radius_m`) and **walk visits**
(walk segment bracketed by vehicle segments, ≥ `dwell.visit_min_s`, ending
within `dwell.visit_return_radius_m` of its start — loop closure, not wander
extent, separates a visit from an A→B walk; trailhead loops range far and
still end at the car; a final-destination walk derives nothing). Derived
stops dedupe against live stops by time overlap; trip stop semantics are now
**live ∪ derived** (Phase 1 gate tests updated accordingly — perth still
exactly 4). Replaying the real 17:04 GPX yields the temple (+975 s, 29 min)
and the 7-11 (+2884 s, 11 min).
**Rejected:** fixing only the streak rule (would have made the temple worse —
dwell-pause would kill the walk trace); wander-extent radius for walk visits
(perth's legitimate walk loops range 274–460 m); live wall-clock silence
timers in the engine (breaks replay determinism; a `LocationService`-level
timer for the battery win is a possible follow-up needing device proof).
**Known limitations:** park-then-sit ≥ 3 min *before* walking still
dwell-pauses and loses the subsequent walk trace (needs activity-aware
resume; icebox); HUD stop count shows live stops only until End Trip;
`drive_s` still includes silence-gap time.

## 2026-07-18 — Recap chrome: photos toggle gates stop cards only; title/end cards always render

**Context:** §4.5 step 4 adds a title card (trip name, dates, distance) and an
end card (stats + "Get this route" QR) to the recap. The 2026-07-17 decision
says the S5 photos toggle off means "route-only animation = overlay events
off" — written before title/end cards existed as events.
**Decision (Claude implementation call; confirmed by Chiu 2026-07-18):** the
toggle gates **photo moments** (stop cards, later route-photo fly-bys).
Title/end cards are trip *chrome*, not photo moments, and always render:
dropping the end card would silently remove the share hook (§1.3 loops) from
exactly the exports users make when they want a clean route video. Toggle
semantics live in `OverlayTimeline.build(photosEnabled:)`; card copy is
caller-supplied strings so wording stays app-side ("Get this route", spec
v1.4 §4.5) and localizable.
**Rejected:** gating all overlay events (kills the share hook); a second
toggle for chrome (S5 stays one-switch simple; revisit only if users ask).
**Chiu (2026-07-18 review):** agreed as stated; additionally — a completely
clean export with no trip chrome, if ever wanted, must be a **separate
explicit option**, never a reuse of the photos toggle. S5 labels must make
it obvious the toggle controls photo overlays only. Locked by gate test
`testPhotosOffKeepsEndCardShareHook`.

## 2026-07-18 — stop.kind = what happened, never how it was detected

**Context:** The recap must render a walking visit (card + walking
duration/trace) differently from a plain dwell. Schema v1 reserved
`stop.kind` but every save wrote `"auto"`. GPT review (relayed by Chiu)
flagged a modeling trap: `silence` as a kind would mix "what happened" with
"how we detected it."
**Decision:** `StopKind` enum (TrackingEngine): `dwell` and `walk_visit`
only. Silence-gap-derived stops are `dwell` — the phone sat somewhere; GPS
silence is merely the evidence. Detection mechanism is deliberately not
persisted; if evidence ever demands it, a `detection_method` column rides
the next schema migration (alongside `photo_ref.order_idx`, per the
2026-07-12 reorder ADR). Kind flows engine/deriver → `NewStop` →
`stop.kind`; rows from builds before this change carry `"auto"`, and
readers treat unknown kinds as `dwell`. No new Place/Visit abstraction
(owner decision: Stop + time-overlap is sufficient for P3; the walk trace
is recovered from the walk segment sharing the stop's time span).
**Rejected:** `silence` as a user-facing kind; a `detection_method` column
now (migration churn with no reader); Place/Visit entities before the
compositor proves what it actually needs.

## 2026-07-19 — Recap visual pivot: P3 frozen as pipeline milestone, Phase 3.5 opened

**Context:** Chiu reviewed the P3 demo artifact
(`Docs/demos/phase3/kamome-p3-recap.mp4`) and rejected the visual
direction: Apple Maps tiles + a polyline read as GPS debug output, not
travel storytelling. Full product direction recorded in
`Docs/kamome-animation-vision.md` (TravelBoast-class animated replay,
premium/Apple-like, real road fidelity, interchangeable themes).
**Decision (Chiu, 2026-07-19):**
- **P3 scope is frozen as the pipeline milestone.** Its remaining gate
  items (2 h drive, limited-photo re-check, on-device render budget via
  S5 readout, S5 UX pass) validate tracking and the engine — all of which
  survive the substrate swap — and still gate P3 close. The
  share-worthiness gate item ("Chiu posts one recap and it doesn't
  embarrass him") moves to Phase 3.5, where it belongs now.
- **Phase 3.5 — Recap Visual System** opens as its own phase (spec §7),
  sequenced: OSRM matching (§4.4, pulled forward from P4) → MapLibre
  substrate → Modern Minimal theme. No renumbering of P4–P7 (v1.3 already
  renumbered once; downstream references stay stable).
- **Replay engine ↔ rendering theme: fully decoupled.** Modern Minimal is
  merely the first theme implemented, not a structural assumption.
  Nothing theme-specific may leak into the replay engine.
- **Two new spec-level principles** (spec §0 rule 6): a Kamome replay
  must never look like Apple/Google Maps with an animated route on top
  (recognizable identity without branding), and Kamome is a travel
  storytelling engine, not a vehicle animation engine — every camera
  movement, pause, transition, and effect must serve the narrative of the
  journey. This is the judgment criterion for all future motion decisions.
**Rejected:** reopening P3 (holds tracking validation hostage to a
multi-week visual effort); deferring visuals to P4+ polish (the recap is
the marketing engine — §4.5 "over-invest here" already says so).

## 2026-07-19 — ADR: recap substrate = MapLibre Native + self-hosted vector tiles

**Context:** The vision requires a base map Kamome fully controls
(colors, typography, what is *omitted*) and route rendering that always
follows real roads. `MKMapSnapshotter` cannot be restyled at all — no
amount of overlay work gets a recognizable Kamome look out of Apple's
cartography. Implementer guide: `Docs/vector-tile-pipeline.md`.
**Decision:** Recap base maps render via **MapLibre Native (iOS)** over
**self-hosted vector tiles** (OSM extracts → Planetiler → PMTiles, same
regional extracts as OSRM) with a **Kamome-authored MapLibre style JSON
per theme**. MapKit remains the map for interactive app screens (S2 HUD,
S3 detail) — this ADR covers the recap substrate only; §2.2 Maps row
updated accordingly.
**Renderer/engine boundary (audited 2026-07-19):** `import MapKit`
appears in exactly one ExportEngine file (`MapKitSnapshotProvider.swift`);
everything else consumes `MapSnapshot` (CGImage + projection closure) via
`RecapSnapshotProviding`. **That protocol already is the boundary** — the
MapLibre implementation is one new file (`MapLibreSnapshotProvider`)
conforming to it, with MapLibre types equally confined. Known gaps,
deliberately deferred until their consumer exists (owner decision — no
speculative multi-renderer `MapProvider` interface with one real
implementation; the correct boundary can't be known before the second
renderer arrives):
1. *Camera attitude* — the snapshot request has center/span only, no
   pitch/bearing. Extend additively when the isometric camera lands.
2. *Theme-owned overlay treatment* — route casing/color, marker art, card
   chrome are currently compositor-side constants. A `RecapTheme` value
   (design tokens, not a renderer interface) gets defined when Modern
   Minimal is built, driven by what that theme actually needs.
Boundary discipline is the rule: MapLibre types must never leak past the
provider file; CI may enforce via a lint/grep gate.
**Quality bar (the whole point — this justifies the operational burden):**
MapLibre + a Kamome style sheet must produce output *clearly
better-designed than native Apple Maps for journey replay*. Concretely:
zero business-POI noise; deliberate use of empty space (subtractive
cartography — show only what serves the journey); distinctive road/route
treatment; recognizable Kamome identity with branding stripped (spec §0
rule 6). Judged per `Docs/vector-tile-pipeline.md` §"Quality bar":
side-by-side stills vs. the P3 Apple-tiles artifact at matched
camera positions, reviewed by Chiu; a style sheet that fails
side-by-side is not shippable, and if the bar proves unreachable the
substrate decision itself gets revisited. Golden-frame CI improves:
checked-in tiles + style are bit-stable, unlike Apple's live tiles.
**Rejected:** fully custom renderer (needed for Style 1's hand-illustrated
world eventually, but months of asset + engine work before the first
share-worthy export; revisit when Style 1 is scheduled); restyling
MapKit (impossible — no styling API); Mapbox (metered, closed);
generic three-way renderer abstraction designed upfront (premature —
rewritten the day the second real renderer arrives).

## 2026-07-19 — Drive finding: region-resume died after wake; recovery watchdog added

**Context (evening drive, `Docs/tests/2026-7-19/`):** First hardware proof
of the §2.3 region-exit resume (device-test-P3 item C) — and it failed
half-open. Timeline from the CSV + trip DB (trip 13:51–15:09): dwell
correctly detected at the drive-through (stop 春日路372號, 14:29–14:36,
`dwell_pause` 14:34:15), region-exit resume fired (`dwell_resume`
14:36:56), GPS restarted and delivered exactly **two** coarse fixes
(h_acc ≈ 39 m, no speed/course) at 14:36:56 and 14:37:06 — then nothing
until 15:09:25, when the phone was unlocked to end the trip. The ~10 s of
delivery matches the region-exit background wake window: iOS suspended
the app when the wake expired, despite `startUpdatingLocation()` having
been called during it. Result: 32 min / ~13 km of driving lost, the
second real stop never observable (StopDeriver correctly derives nothing —
a silence gap spanning kilometers is not a stop), recap shows a straight
gray line, and the post-resume segment saved as `unknown` with 3 points.

**Decision — three layers, all landed on `phase-3-recap`:**
1. `resumeAfterDwell` re-asserts `allowsBackgroundLocationUpdates`
   (`applyBackgroundCapability()`) *before* restarting updates — a session
   started inside a background wake without the flag in effect dies with
   the wake.
2. **Trip-long significant-location-change monitoring** as a safety net
   (the §1.8 passive-tier primitive, ~zero battery): SLC fixes keep waking
   the app even when suspended, giving the recovery watchdog execution
   windows. Stopped at `stopUpdates()`.
3. **Silent-death watchdog** (`sampling.recovery_gap_s`, default 60): if a
   delivered fix arrives ≥ that long after the previous one while actively
   tracking (never while dwell-armed — GPS is off on purpose there), the
   standard session is presumed dead and restarted, background flag
   re-asserted. Self-limiting: the restart's immediate fix resets the gap.
   Bonus: an SLC fix escaping the 150 m region now resumes the engine even
   if the region-exit event never arrives (`TrackingSession` calls the new
   `resumeActiveTracking()` on the dwellPaused→recording transition).

New CSV events for the next drive: `region_exit` (exit event delivered),
`gps_recover,<gap_s>` (watchdog fired). Item C in `Docs/device-test-P3.md`
stays open until a drive shows dwell_pause → region_exit → continuous
trackpoints with no gps_recover (or a gps_recover that proves the net
works). Worst case if iOS keeps suspending: route degrades to SLC
granularity (~500 m) instead of a 32-minute hole — map matching (§4.4,
P3.5) can reconstruct that; it cannot reconstruct absence.

**Rejected:** `UIApplication` background task around the resume (buys
≤ 30 s, doesn't fix the steady state, drags UIKit into the location
layer); restarting updates on *every* delivered fix (restart → immediate
fix → restart loop); tightening sampling config (unrelated — this was
session death, not filter tuning).

## 2026-07-19 — Owner call: continue into Phase 3.5 while P3's device items stay open

**Context.** The four remaining P3 gate items (device-test-P3 F–H: render
budget < 90 s via the S5 readout, S5 UX pass, 2 h drive re-run, limited-photo
re-check) all require the physical iPhone, which is not available to the
current dev sessions. Chiu directed work to continue rather than idle on
hardware availability.

**Decision.** P3 is **not closed** — nothing is marked passed that didn't
run. Its checklist stays open in `Docs/device-test-P3.md` and must be
executed before P3.5's own gate can be judged (both gates need the same
device day anyway: the < 90 s budget must be re-proven on the MapLibre
substrate regardless). Meanwhile Phase 3.5 fixture-driven work proceeds on
`phase-3-recap`, in spec order: OSRM matching app-side first.

**Why this is safe.** P3.5 step 1 (matching) and step 2 (substrate) are
exactly the parts that need no hardware; the P3 device items neither block
nor are blocked by them. The risk of building on an unvalidated pipeline is
bounded: the 2026-07-19 smoke drive already exercised the export end-to-end
(34.6 s demo artifact), so what remains unproven on device is budget/UX
polish, not mechanism.

## 2026-07-19 — §4.4 map matching: app side landed, server-side deferred to setup doc

P3.5 step 1, app half. `KamomeRouteMatching` (Core/RouteMatching) is the
fourth Core module: `EncodedPolyline` (precision-5 codec — the
`segment.matched_polyline` storage format), `RouteMatchProviding` (the
boundary; OSRM types confined to `OSRMMatchProvider.swift` exactly like
MapKit in `MapKitSnapshotProvider.swift`), `OSRMMatchProvider` (chunked
`/match`, ≤ `matching.chunk_size` pts/request, per-segment worst-confidence
gate at `matching.confidence_min`, injectable transport so CI replays
recorded responses — no live server in tests, ever).

Consumers: `RouteMatchService` (App) matches drive/scooter segments
post-completion (fire-and-forget at End Trip; idempotent retry at recap
export) — walks stay raw on purpose, feet ignore the drivable network.
`RecapComposer.route` prefers decoded matched geometry at the tighter
`matching.display_epsilon_m` (5 m — 15 m would visibly cut snapped corners;
raw OSRM density would blow the §4.5 render budget), raw Douglas-Peucker at
`simplify.epsilon_m` remains the per-segment fallback, which doubles as the
§4.4 "inferred" degradation.

`matching.base_url` ships **empty = disabled**: no server exists yet.
Bringing one up (Docker, Taiwan + Australia extracts, validation steps,
device ATS note) is `Docs/osrm-setup.md` — the first task for the next
session. **The route-follows-roads claim is unvalidated until someone runs
that doc against the perth fixture**; the P3.5 gate's golden-frame
road-network assert stays open until then.

**Rejected:** matching cycle segments with the car profile (wrong network
graph — needs the bike profile, future provider); a `matched` boolean
column (`matched_polyline IS NULL` already says it); blocking recap export
on matching success (§4.4 forbids it).

## 2026-07-20 — Recap visual system validated on real data via a web prototype

**Context.** Before committing the Swift recap-visual work (Phase 3.5, spec
§4.5/§7), the direction was de-risked in a throwaway HTML/JS prototype driven
by Chiu's **real 170-photo, 13-day Iceland ring-road trip** (not synthetic
fixtures). Three iterations were built and reviewed live; owner sign-off:
"prototype 蠻成功的，現在可以收斂回到 app 本身." Full writeup, the data
pipeline, and the engine source are in `Docs/prototype/`.

**Decisions (each constrains an existing component — no new architecture):**

1. **Base map = real geometry + hand-written subtractive style.** Chiu's
   formula: *真幾何 ＋ 手寫減法樣式 = 紀念品地圖* (souvenir map). Real coastline/
   glacier/terrain geometry (so the place is recognizable — the fully-abstract
   v1 was rejected as unidentifiable) styled subtractively (no POI, no road
   labels, chosen colours) so it never reads as a map app. This is the exact
   MapLibre substrate ADR (2026-07-19) — the prototype is now the "before"
   evidence for the Phase 3.5 quality-bar side-by-side, and the reason the
   substrate is non-negotiable. Route precision is a later OSRM concern (§4.4)
   and does not gate the look.

2. **Stop photos = a rotating deck at the stop location.** Not the current
   single stop-card. Camera eases to the place; a 3-card fan blooms with the
   hero **cross-fading through all of that stop's 3–8 photos**, progress dots,
   dwell scaled to photo count. Chiu revised per-photo hold **1.0 s → 0.8 s**.
   Owner-confirmed *not* a full-screen takeover — "bead floating on the map."
   Owner in `OverlayTimeline` / §4.5 stop-card work; photos from `photo_ref`
   (§4.3), `is_highlight` leads.

3. **`CameraPath` must be a vehicle-locked follow-cam** (the prototype's one
   unmet item). Chiu: "只有路線移動而已沒有帶入車子" — a wide route-draw is not
   enough; the **vehicle must be the subject** at a close, heading-up zoom with
   the map/route moving underneath. Needs the near-terrain detail vector tiles
   give at zoom. Wide shots reserved for title/end/day-transitions. Top-down
   car is the default marker; seagull (brand mascot) / scooter / bike swappable
   — the seagull is no longer forced as the moving marker.

**Forward directions recorded (not yet scheduled):** photo-**EXIF import first**
(the prototype pipeline *is* that importer, §4.7 — and the only way to dogfood
recap quality on past trips before the next drive; Google Timeline import
backlogged); **video clips as auto-trimmed (2–3 s), muted, hard-capped "beads"**
after the photo version ships (deterministic excerpts only, golden-frame-safe);
**royalty-free beat-synced music** — bundled library + offline beat maps, recap
events quantized to the beat grid in CameraPath/OverlayTimeline, free = silent
export (user adds platform music), premium = in-app track (§1.6 transactional).

**Positioning restated by owner** and lifted into the spec header (v1.6):
"Kamome turns your road trips into stories you can relive and share" — a
storytelling/memory product, built first for Chiu's own use (hates organizing,
wants the trip to auto-become a film).

**Rejected:** the fully-abstract base map (v1 — unrecognizable); a fixed
top/bottom photo slot (v2 — photos must live at the place); forcing the seagull
as the moving vehicle marker (car is the default, seagull stays the mascot);
letting users hand-trim recap video clips (variable length → hard cap instead);
bundled copyrighted music (royalty-free + optional silent export only).

## 2026-07-20 — Replay MVP repositioning: photo-import recap ships first; capture → Capture Beta; Story Director & Plans deferred; honest provenance

**Context.** Product-strategy re-confirmation (Chiu, 2026-07-20). The long-term
vision is unchanged — *Kamome automatically remembers a journey and directs it
into a travel film worth rewatching* — but the earlier framing (spec ≤ v1.6)
made the **first release** a passive-capture "v1" (Phases 0–5, TestFlight at the
Phase 5 passive-tier gate). That over-promises: it commits the launch to
12-day zero-touch background capture and imperceptible battery, neither proven,
and gates the whole product behind hardware Chiu cannot always run. The web
prototype (2026-07-20 ADR above) meanwhile proved that **sparse geotagged photos
alone** reconstruct a recognizable, share-worthy trip once snapped to roads.

**Decision.** Ship a smaller, publishable, verifiable product first — the
**Replay MVP**: *pick a past trip's photos → reconstruct from EXIF place + time →
snap to real roads (OSRM, already landed) → souvenir-map recap → MP4 → share.*
Product evolution is two layers, and the architecture must not block layer 2:
1. **Replay MVP** — auto-generate a real-road trip animation from photos.
2. **Story Director** — on top of the MVP: automatic moment-selection, narrative,
   hero photos, chapters/elision, variable pacing, light edit controls, video
   beads, licensed music + beat-sync. *Kamome is ultimately not full playback of
   all trip data — it is a director that dares to select and omit.* Not now.

Concrete changes (spec bumped to v1.7):
- **Phase 3.5 renamed "Recap Visual System" → "Replay MVP,"** and **photo-EXIF
  import is pulled forward into it** from the old Phase 4. Sequence:
  photo-EXIF import (schema v2 `trip.source`) → MapLibre souvenir-map substrate →
  Modern Minimal (the ONE MVP theme; multiple themes are not an MVP condition) →
  vehicle follow-cam (primary dynamic, **not** an unchallengeable "always
  centred" dogma — Story Director makes it one shot among many) → basic photo
  deck (deterministic 3–8 @ 0.8 s; explicitly *basic*, not final) →
  **three-real-trip dogfood** → TestFlight.
- **The P3.5 gate becomes a product release gate,** not a static-visual gate.
  The MapLibre-vs-Apple side-by-side survives as a **design review** only; it
  does not replace the full-video judgment. Hard conditions: three real trips of
  different character each go photos → import → recap → MP4 → share **entirely
  in-app** (no DB edits, no external tools); routes honest (no gross
  sea/mountain/wrong-road; low confidence shown as inferred); all three worth
  keeping and sharing; **≥ 1 published publicly**; limited-photo path passes on
  device; stable on-device export (no crash / acceptable memory); per-trip export
  time recorded and *product-acceptable* (the single < 90 s number is retired as
  pass/fail). "Three trips" is hard — never downgraded to one.
- **MP4 is the launch format; GIF is demoted to non-blocking.**
- **Phase 3's device items are redistributed (nothing faked passed):** export /
  S5-UX / limited-photo / per-trip-render-time → into the Replay MVP gate; the
  2 h drive + region-resume re-validation → **Capture Beta**. Checklists in
  `Docs/device-test-P3.md` are preserved and re-tagged, not deleted.
- **Phase 5 "Passive Capture Tier" renamed → "Capture Beta"** and moved *after*
  the video product. It inherits the moved tracking/battery gates (2 h drive,
  region-resume, long-duration background, process-death recovery, passive
  capture, ≥ 3-day battery) and is the **only** place "Arm once, forget it" is
  validated and usable in copy. The old §10 "passive-capture v1" success criteria
  move here.
- **Phase 4 "Import & Map Matching" renamed → "Story Director."** Its EXIF half
  moved into the MVP; matching already landed; **no importer remains** — the
  Google Timeline importer is **dropped as redundant** (owner add-on 2026-07-20:
  photo-EXIF import covers past trips, in-app capture covers new ones, so a
  drift-prone Timeline parser adds maintenance for little unique value; the
  `imported_timeline` enum value is kept only for forward-compat).
- **Story Director is deterministic — no AI/LLM tokens** (owner constraint
  2026-07-20). It is a scoring-and-selection engine over structured trip data
  (moment salience = weighted photo-count / `is_highlight` / dwell / geo-novelty
  / day-boundary; top-N with non-maximum-suppression spacing; omit + speed-warp
  the gaps; per-photo hold scales with salience). Hero-photo pick uses
  **on-device Vision** (saliency / faces — free, local, no tokens, no network,
  not an LLM; owner-confirmed 2026-07-20), cached for determinism, with
  `is_highlight` → dwell-midpoint → chronological fallback; Vision stays in its
  own boundary file. No network, no per-call cost, and **determinism keeps
  golden-frame CI stable**. The manual "replace / remove" controls are the taste
  escape hatch.
- **Capture Beta must justify itself vs. photo reconstruction (open question,
  owner-raised 2026-07-20; decide from MVP feedback).** Since photo-EXIF import
  already reconstructs most photo-rich trips, live capture earns its
  background/battery build only via the three things photos structurally cannot
  give: a **truth-path** (actual road vs. an OSRM guess between sparse photos),
  **no-photo stops/scenes**, and **not-even-photos zero effort**. Recorded as a
  question, not an assumption.
- **Plans (Phase 6) benefits from captured road-detail; community sharing is the
  virality engine** (owner note 2026-07-20, discuss later). A shared route from
  *recorded* driving beats one reconstructed from a stranger's photos — links
  Capture Beta → Plans value; sequencing deferred.
- **Plans & Fork (Phase 6) and Backend (Phase 7) unchanged and further
  deferred** — plan/fork must never block or delay the video product; start only
  after the Replay MVP *and* Story Director show real sharing.
- **Honest provenance (product rule, not cosmetic).** `trip.source` separates
  what Kamome **recorded** from what was **reconstructed from photos**; the UI
  must surface it (S1 badge, S3 note); GPS/EXIF are not tamper-proof and must
  never be presented as proof or as a "Verified Trip". Spec §3/§6.
- **Positioning de-overclaimed:** MVP copy may not claim 12-day zero-touch
  capture or imperceptible battery; those are Capture-Beta-validated promises.

**Docs touched:** spec (header/positioning, §1.1/§1.3/§1.5/§1.8, §2.1–§2.3, §3,
§4.4/§4.5/§4.7, §5, §6, §7 full phase map, §9, §10, §11), `handoff-P3.5.md`
(rewritten as the Replay MVP work order, Photo EXIF Import first),
`kamome-animation-vision.md` (two-layer note), `device-test-P3.md` (Capture-Beta
re-tagging), `CLAUDE.md` (current phase + gate), plus secondary phase-ref
reconciliation in `osrm-setup.md` / `icebox.md` / `vector-tile-pipeline.md`.

**Rejected:** shipping passive-capture as the first release (over-promises
battery/background integrity that need hardware Chiu can't always run, and buries
a validated photo-recap product behind it); marking P3's device items passed to
"unblock" release (violates §0 rule 1 — they are moved, not passed); deleting the
tracking checklists (they are real Capture-Beta work); keeping GIF as a launch
gate (MP4 is the share format, GIF is a nice-to-have); a Google Timeline importer
(drift-prone maintenance, redundant given EXIF import + in-app capture); using
AI/LLM tokens for Story Director (per-call cost + network + breaks golden-frame
determinism — hand-tuned heuristics fit the structured-data problem); a
single-video gate (three trips of different character is the honest bar for
"worth publishing");
letting the map-vs-Apple side-by-side stand in for the product judgment (pretty
map ≠ shareable film); building Story Director / multiple themes / plans now
(scope; the architecture keeps them open without building them — spec §0 rule 6,
boundary discipline).

## 2026-07-21 — Replay MVP §2: MapLibre substrate landed (provider in app target, pmtiles ingestion, MapKit kept alive)

**Context.** Replay MVP work order §2 (`Docs/handoff-P3.5.md`;
`Docs/vector-tile-pipeline.md`): build the MapLibre souvenir-map substrate that
lets the recap be a 紀念品地圖 instead of Apple/Google cartography (spec §0 rule
6). The renderer boundary already exists — `RecapSnapshotProviding`
(`Core/ExportEngine/RecapSnapshot.swift`); this ADR records the concrete
integration choices made building the second implementation behind it.

**Decisions.**

1. **MapLibre pinned exactly at `6.27.0`** (SPM,
   `maplibre/maplibre-gl-native-distribution`, product `MapLibre`, added to the
   **app target** in `project.yml`). Exact-version, not a range: golden-frame CI
   and a reproducible substrate must not float under a map SDK. v6 line ⇒ `MLN*`
   API. Resolution verified (`xcodebuild -resolvePackageDependencies`).

2. **Provider lives in the app target, not `Core/ExportEngine`.**
   `Docs/vector-tile-pipeline.md` §7 had penciled
   `Core/ExportEngine/MapLibreSnapshotProvider.swift`, but that path is inside
   the `KamomeExportEngine` **SwiftPM** target, which must stay a pure,
   deterministic, SDK-free core (`swift test`, golden frames). A third-party
   binary map framework there would poison every package test. So
   `App/Services/MapLibreSnapshotProvider.swift` — same home as the other SDK
   boundary adapters (`PhotoLibraryImportSource` = PhotoKit,
   `RouteMatchService`). `MapKitSnapshotProvider` stays in the package only
   because MapKit is a system framework the package can `#if canImport` without a
   dependency; MapLibre cannot. The protocol is still the boundary; the file is
   `#if canImport(MapLibre)`-guarded exactly like `MapKitSnapshotProvider` is
   `#if canImport(MapKit)`-guarded. **Confinement is now CI-enforced** (grep gate
   in `.github/workflows/ci.yml`: `import MapLibre` may appear in exactly one
   file).

3. **Tile ingestion path = native `pmtiles://`**, declared in the theme JSON's
   source, with the on-disk path injected by a pure, SDK-free resolver
   (`RecapMapStyle`, unit-tested). Chosen over the MBTiles / localhost fallbacks
   (`Docs/vector-tile-pipeline.md` §5) because it keeps a single artifact and no
   runtime server. **The scheme lives in config (theme JSON), not code**, so the
   MBTiles fallback is a one-line theme edit if a device shows native pmtiles://
   unsupported in this MapLibre build. *Flagged: the actual tile render is Metal
   and is **not** in CI — it is on the sim/device manual list (§6 gate); the
   pmtiles://-vs-mbtiles:// confirmation happens there.*

4. **Camera = center + span → MapLibre zoom** (Web Mercator, 512 px tiles,
   `scale = 1` so point==pixel like the MapKit provider's `displayScale 1`).
   Pitch/bearing stay out of the snapshot request until the follow-cam (§4) needs
   them — additive extension, deferred gap 1 (ADR 2026-07-19), not pre-built.

5. **First theme is `functional-base.json` — unstyled, subtractive** (land +
   water + a quiet road skeleton; no POI, no labels). It only proves frames
   render. **Modern Minimal (§3) is separate and needs Chiu's side-by-side
   sign-off** — deliberately not self-certified here. `MapKitSnapshotProvider`
   and production wiring (`RecapModel` still constructs `MapKitSnapshotProvider`)
   are **untouched**: MapKit stays the shipping base map until Modern Minimal
   clears the design review, then it is retired in that same PR.

6. **OSM attribution** (`© OpenStreetMap contributors`, ODbL) is set on the theme
   source now. Surfacing it on the end card / about screen is **bound to the §3
   switch-over PR** — the point at which OSM tiles are actually shown to users
   (MapKit renders production output through §2). Recorded here so it cannot be
   forgotten.

**What is verified vs. flagged.** Verified in-repo: SPM resolves; the app builds
and **links** MapLibre (compile-checks the `MLN*` API usage); the confinement
grep holds; `RecapMapStyle` resolution + zoom math are unit-tested; golden-frame
CI stays bit-stable on `FlatSnapshotProvider`. **Flagged (needs sim/device, not
faked):** the actual MapLibre pixel output — tiles loading via `pmtiles://`, the
subtractive style rendering, zh-Hant labels (a §3 concern) — folds into the §6
three-trip gate and the §3 design review.

**Rejected:** provider in the SwiftPM core (poisons deterministic package tests
with a binary SDK); a generic multi-renderer `MapProvider` abstraction (premature
— the protocol already is the boundary, ADR 2026-07-19); a floating MapLibre
version (non-reproducible substrate); bundling full-region tiles in git (only the
small cropped fixture is committed); adding a live-tile MapLibre golden test
(non-deterministic Metal render — violates golden-frame discipline); building
Modern Minimal / pitch-bearing / RecapTheme tokens now (§3/§4 scope with owner
sign-off, no consumer yet).

## 2026-07-21 — §3 Modern Minimal: kicked off as a DRAFT (visual sign-off is Chiu's, on a real render)

**Context.** §3's acceptance is a **side-by-side design review that Chiu signs
off** on real MapLibre stills (vector-tile-pipeline §1). MapLibre rendering is
Metal — not producible in agent CI — and the judgment is a human's. So an agent
can lay the **buildable, verifiable groundwork** but cannot close §3.

**Decision.** Land the groundwork only, explicitly un-self-certified:
`Config/RecapThemes/modern-minimal.json` as a **DRAFT** base style (refined
subtractive cartography from `Docs/kamome-animation-vision.md`, marked DRAFT in
metadata, bundled), plus the review harness
(`Docs/demos/phase3_5/modern-minimal/README.md`). **MapKit stays the shipping
base map** — `RecapModel` is untouched. The label/glyph pipeline, the overlay
`RecapStyle.modernMinimal` preset, the `RecapModel`→MapLibre switch (which retires
`MapKitSnapshotProvider`), and OSM end-card attribution are **all gated on the
sign-off** and land in that one switch-over PR — driven by what the review reveals
(theme tokens come from real needs, ADR 2026-07-19), not guessed ahead of it.

**Rejected:** self-certifying the look or switching production to MapLibre without
Chiu (violates handoff §3 + spec §0 rule 1); authoring labels/glyphs and the
overlay preset blind before the review (unverifiable, likely reworked — the review
should drive them); lowering the quality bar if the draft disappoints (reopen the
substrate ADR instead, decisions.md 2026-07-19).

## 2026-07-22 — pmtiles ingestion CONFIRMED in-sim: `pmtiles://file://`, MapLibre renders in the simulator

**Context.** §2 landed the substrate with the actual MapLibre pixel render flagged
device/sim-only (decisions.md 2026-07-21). Building the §3 review harness
(`Tests/AppTests/ModernMinimalRenderTests.swift`, env-gated, writes PNG stills)
exercised the real `MLNMapSnapshotter` in the iOS simulator and resolved two of
those flags.

**Findings.**
1. **MapLibre renders in the simulator** (Metal). No device needed to eyeball the
   base map; the golden-frame discipline (no MapLibre in CI) is unchanged — the
   render test is env-gated and asserts only non-blank, never pixels.
2. **Ingestion path = `pmtiles://file:///abs/path.pmtiles`.** MapLibre 6.27.0's
   pmtiles handler recognises the scheme but rejects a bare `pmtiles:///path`
   with `MLNErrorDomain Code=6 "unsupported URL"`; it needs a full URL after the
   scheme. `RecapMapStyle` now injects `tilesURL.absoluteString` (the `file://`
   URL) rather than `.path`. This retires the pmtiles-vs-mbtiles fallback question
   for local files (vector-tile-pipeline §5) — native pmtiles works.
3. **The functional-base and modern-minimal styles both render** subtractively
   (coast, water, quiet roads; no POI/labels) over the committed fixture. First-
   look stills committed under `Docs/demos/phase3_5/modern-minimal/`.

**New §3 sign-off item.** The snapshotter bakes MapLibre's own wordmark + a
`© OpenMapTiles © OpenStreetMap contributors` line into every image. The
attribution satisfies ODbL, but the wordmark is unwanted in the final recap —
decide at sign-off whether the compositor covers the corners or the ornaments are
suppressed, and place attribution deliberately (end card).

**Still flagged (unchanged):** the *aesthetic* is not self-certified — Chiu signs
off the look (§3); render-loop threading of `MLNMapSnapshotter` under the full
export and the on-device render/budget are the §6 gate.

## 2026-07-22 — §3 visual direction corrected: dark atmospheric souvenir map (not pale "Modern Minimal")

**Context.** Chiu rejected the §3 draft v1 (`modern-minimal.json`) as "essentially a
desaturated OSM base map — an engineering map with the contrast reduced, not a
designed map." The target is the **illustrated, editorial souvenir map** validated
in the prototype + WIP demo (`Docs/prototype/recap_engine.html`, artifact "Kamome
Recap 冰島環島"): dark-navy sea, dark-slate land silhouette, a **glowing coastline**,
pale ice/glacier, warm-orange glowing route.

**Finding — NOT a substrate problem.** The demo's own build note prescribes exactly
our stack: real MapLibre vector-tile geometry + a Kamome-authored style sheet that
"decides what to show and what colours" (底圖幾何要真，視覺樣式要我們自己寫). The v1
failure was the *style's design language* (pale nav-map, full road grid, flat fills,
no graphic treatment) and the fact that **most of the crafted feeling lives in the
compositor** (vignette, route glow, grade), which §3 had not touched. So MapLibre
stays; the style + compositor change.

**Decision (owner-approved approach, 2026-07-22).** Minimum-viable path, no new data,
same OMT tiles:
1. **Base style rewritten** to the dark souvenir language (draft v2): dark sea,
   slate land, glowing coastline via stacked `line-blur` layers on the water
   boundary, pale `ice`, drop roads/POI/labels (faint major-road whisper only).
   Rendered in-sim; first-look stills in `Docs/demos/phase3_5/modern-minimal/`.
2. **Next: compositor atmosphere** (vignette, route/marker glow, vertical grade) as
   `RecapTheme` tokens in `RecapFrameCompositor` — where the rest of the craft lives.
3. **Deferred (not required for reference parity):** hillshade/terrain relief (new
   DEM source — the reference has none), paper/grain fill-textures, hand-illustrated
   per-landmark art (that is Style 1 / the custom renderer the ADR deferred; the
   demo is vector-styled, so it is not this).

Verification stays honest: render stills in-sim and get Chiu's read **before** any
compositor build or production switch. MapKit remains the shipping base map.

## 2026-07-22 — §3 signed off as the substrate; recap-output redesign moved to its own session

**Decision (Chiu, 2026-07-22).** After the draft v2 dark souvenir base map, Chiu:
"still not what I want, but this is not the MapLibre issue… we could sign off §3
MapLibre for now, and do the compositor atmosphere later. The output video format
does not meet my expectation — we need to discuss and update it, in another session."

**What this means.**
- **§3 substrate is signed off** — MapLibre + the dark-souvenir base-style *direction*
  are accepted; stop iterating the base style. It is **not** a substrate problem.
- **The real gap is the overall recap OUTPUT / video format**, not the base map. That
  redesign (aspect/size/duration, container/delivery, in-frame template/chrome, the
  follow-cam animation) is a **separate future session** — "revisit all the difference."
  No output-format decisions were made here.
- **Deferred, bundled with that redesign:** the compositor atmosphere (vignette,
  route/marker glow, grade — `RecapTheme` tokens), labels/glyphs, the overlay
  `RecapStyle.modernMinimal` preset, and the `RecapModel`→MapLibre production switch
  that retires `MapKitSnapshotProvider` + surfaces OSM attribution.
- **MapKit stays the shipping base map.** The production switch is **not** done now —
  flipping mid-redesign would ship an un-atmosphered look while the whole output is
  being reconsidered. Hold it for the switch-over PR after the redesign.

**Rejected:** flipping production to MapLibre on this sign-off (premature — output is
under redesign); continuing to tune the base-map palette (Chiu: not the issue).

## 2026-07-23 — Follow-cam camera core: wide-to-close framing, camera ≠ vehicle

**Context.** The recap OUTPUT redesign's first piece. The prototype's one unmet item
was the TravelBoast follow-cam; diagnosis (this session) was that the shipping camera
used a single fixed `camera_span_m` (1500 m) start-to-finish — no establishing shot,
no close follow — so it read as "the route sliding," not "the car driving."

**Decision (implemented, commit `3eac0ab` on `phase-3-recap`, CI green).**
- **Split camera from vehicle.** `CameraPath` emits `Position` (the vehicle subject —
  lat/lon + `heading`, the route tangent) and a new `CameraFrame` (the snapshot —
  center/span/`bearing`). In wide shots the camera centers the *trip* while the vehicle
  sits small in its real place; in the body the camera locks onto the vehicle. Two
  outputs, not one — that separation is what a wide→close film needs.
- **Wide establishing/closing, close body.** Title/end windows frame the whole-trip
  bounding box (`wide_span_padding`); the body eases to `camera_span_m` (reused as the
  close span). Wide↔close eases over `zoom_transition_s` (renders as a quick cross-fade
  dolly; adaptive keyframe interval for a smoother dolly is a deferred refinement).
- **`bearing` on the snapshot boundary.** `RecapSnapshotProviding` gained `bearing`
  (the "additive extension" the ADR 2026-07-19 anticipated). `MapLibreSnapshotProvider`
  honors it (`MLNMapCamera.heading`); `FlatSnapshotProvider` rotates its projection so
  golden-frame CI stays deterministic; `MapKitSnapshotProvider` accepts-and-ignores it
  (the retiring north-up path).
- **`follow_heading_up` defaults false** = north-up map + a marker that rotates to
  heading (the validated prototype behavior). Heading-up *map* rotation is a
  MapLibre-era opt-in (MapKit can't rotate; the marker's screen rotation is then
  `heading − bearing`). Kept the close-span default at 1500 — tuned on a device render,
  not guessed.

**Not in this decision (next):** the vehicle marker sprite and the photo deck (with
Chiu's 2026-07-23 zoom-in/rotate/zoom-back revision) — the visual `RecapFrameCompositor`
half, on branch `feature/vehicle-marker-photo-deck`.

**Not merged.** Reaffirmed the documented hold (handoff §6): PR #11 keeps `phase-3-recap`
off `main` until the three-trip dogfood gate — the redesign is mid-flight and MapKit is
still the shipping base map, so merging now would land a half-finished redesign in main.

**Rejected:** heading-up on by default (inconsistent on the still-shipping MapKit path,
which can't rotate); a generic multi-camera abstraction (boundary discipline — extend
`CameraFrame`/`RecapSnapshotProviding` additively when a consumer needs it); guessing a
new close-span value in code (it's a device-tuned feel, left at the prior default).

## 2026-07-31 — Stop presentation ported from the prototype's CSS, and the stop group flips as one cluster

**Context:** The stop scene was the last part of the recap still reading as UI
rather than as a film: a photo card that looked like a thumbnail, the place name
on a rounded plate, and no metadata over the picture. The target was never a
screenshot to eyeball — the 2026-07-20 validation prototype
(`Docs/prototype/recap_engine.html`) is a working implementation with exact
values, and the 2026-07-30 screenshots beside it are its output, not its spec.

**Decision — the prototype's CSS is the source of truth for the stop's look.**
Every token in `RecapStyle`'s deck/label block now cites the declaration it came
from (`.card { border-radius: 14px; border: 3px solid #fff; box-shadow: 0 20px
44px -16px rgba(0,0,0,.85) }`, `.clabel`, `.dots`, `.hud .badge`), converted at
the prototype's ~413 px stage → 1080 reference ratio (×2.62). Three layers, drawn
back to front and enforced by draw order: **map** (pin, trail — never covered by
a scrim), **photo** (two static peek cards behind a portrait hero), **typography**
(metadata pill on the photo; name + accent strap + progress dots under it).

- **No pill behind the stop's name.** The prototype sets it as free type with
  `text-shadow: 0 2px 12px rgba(0,0,0,.6)`. A rounded plate reads as chrome at any
  size; the shadow is what makes big type sit *in* the film. Both beats of the
  stop draw the same identity block, so beat 1 → beat 2 still cross-fades in place.
- **Day + place + distance moved onto the photo** as `.hud`'s pill + right-aligned
  km readout; the strap under the name carries day + the stop's secondary detail.
  The figure appears once, not in two places.
- **The stop group is one cluster and mirrors as one** (`RecapStopLayout`). It used
  to flip only the *card* below the pin when a stop sat high in frame, stranding
  that card's own caption at the other end of the composition — visible immediately
  in the first render of this pass. The name is the photograph's caption, so the
  cluster now hangs pin → name → card above the pin, or pin → card → name below it.
  The pin still sits exactly on the stop; only which side the cluster hangs on
  changes. New regression test: photo and caption are always one gap apart, swept
  over every anchor in frame.
- **The frame-edge clamp is given the cluster's width**, hero plus peek overhang, so
  a stop near the border keeps both peeks instead of losing one off-screen.

**Alternative rejected:** the prototype's **fanned card stack** — still deferred
(handoff §"Photo deck → fan/stack carousel"). It changes what `RecapPhotoDeck` has
to express (per-card transforms driven by a moving front index, not one focused
photo) and needs its own scoping pass, not a styling round. Also rejected: clamping
the whole cluster into frame *without* mirroring, which would drift the pin off the
stop it marks — the one thing the 2026-07-26 layout rule exists to prevent.

**Not 1:1 with CSS:** `backdrop-filter: blur(8px)` on the metadata pill has no
CoreGraphics equivalent that does not mean reading the frame buffer back per frame,
so the pill is a flat fill with its alpha raised .55 → .72 to buy back the contrast
the blur was providing.

**Unchanged, checked:** film pacing (iceland: total 90.00 s, opening ends 5.90 s,
first stop 5.93 s, car 11.37 s, longest still 2.97 s), the camera, the route glow,
the 380 px car sprite and the modern-minimal map style.

## 2026-07-31 — Day and distance become persistent HUD, not stop chrome

**Context:** The day and the running distance were drawn by the photo card, so
they appeared for a few seconds at each stop and vanished on the road in between.
Two problems, one visible and one conceptual: pause the film mid-leg and it told
you nothing about where you were in the trip, and a distance rendered *by a stop*
reads as a property of that stop rather than of the journey.

**Decision:** a new `OverlayContent.hud(dayLabel:place:travelledM:)`, emitted by
`LinearTimeline` on **every frame of the body** and drawn in the frame's top
corners (the prototype's `.hud`) — day (plus the place, while parked at one) on
the left, running total on the right. `RecapPhotoDeck` and `.stopLabel` lost
`dayLabel`/`travelledM` outright rather than keeping them unused; the strap under
a stop's name is now its `detail` alone, and absent when it has none.

- **The day on a leg is the day of the stop just left**, held until the next is
  reached. A leg belongs to no stop and must inherit from one; inheriting
  backwards is the honest direction, because you drive on the day you set out and
  the counter should turn over on arrival, not somewhere out on the road.
- **Suppressed under the title and end cards.** They are full-bleed and own their
  seconds; chrome across a centred title stack is clutter, and the readout there
  is "0 km". This follows the prototype, which also drops the HUD for both cards.

**Rejected:** keeping a copy on the card as well (the prototype does exactly that
— its badge and its strap both read "Day 10 · Fjaðrárgljúfur"). Saying it twice in
one frame and then taking one copy away is worse than saying it once, everywhere.
Also rejected: deriving the day from elapsed film time, which would drift against
the trip's real dates.

---

## 2026-08-06 · Stop presentation is budget-constrained — derive the count, never assume one

**Status:** accepted. Implemented as `StopPhotoAllocator.keptStopCount` /
`presentationCostS`; supersedes the hand-tuned `tier_skip_share`.

**Context.** The same law has now been re-derived three times, from three
different directions, each time as if it were new:

1. *The 90 s vs 180 s duration study* (2026-08-04). Doubling the film did not
   double the photographs. Iceland's 65 stops showed **one photograph each at
   30, 60, 90, 180 and 195 s** — every length tried.
2. *The "10 stops per 30 s" ratio test* (2026-08-05). The proposed ratio was
   ~3× too aggressive; the data supported roughly 10 s of *film* per presented
   stop, and above ~20 presented stops no watchable length worked at all.
3. *The Variant B skip share* (2026-08-06). A fixed share needed hand-tuning per
   trip — 0.82 for Iceland's 65 stops, 0.5 for New Zealand's 20 — because a share
   scales with the trip while the budget does not.

**Decision.** How many stops a film may present is **derived from its duration**,
never configured as a count and never as a share of the trip:

```
keptStops = (duration − opening − endCard) × maxHoldFraction ÷ presentationCost
presentationCost = labelLead + 2·deckZoom + 2·subjectPark + standardPhotos × photoMinHold
```

Both terms are computed from existing tunables, so no second constant can drift
away from them. At the shipped values a stop costs **5.4 s of dwell**, and a 120 s
film keeps **11 stops** — for Iceland (65 stops) and New Zealand (20) alike, with
no per-trip input.

**Consequences.**

- *A trip's size stops mattering.* A 20-stop and a 65-stop trip both fill a 120 s
  film to the same density. Trip size decides what is left out, not the pacing.
- *Dwell seconds and film seconds are different denominators, and confusing them
  costs a factor of two.* Dwell is only `max_hold_fraction` of the body, so 5.4 s
  of dwell ≈ 9–10 s of film. The first implementation divided the dwell budget by
  the film-seconds figure and returned 6 stops where the measurements said 12.
  Any future work on this must say which one it means.
- *Ranking is deterministic* — score descending, original trip order for ties — so
  re-exporting a trip keeps the same stops. A film that reshuffled between renders
  could be re-rolled but not evaluated.
- *The failure mode is silent.* Overrun does not error; it scales every dwell down
  until `deck_photo_min_hold_s` truncates the decks, and the film simply shows one
  photograph per stop. `RecapDeckBudgetTests` exists to make that audible.

**Rejected:** a fixed stop count (breaks the moment duration changes); a fixed
share of the trip (needs per-trip tuning, which is what prompted this); and a
hand-set `stop_presentation_s` constant (a fourth number to keep in sync with the
three it is computed from).

## 2026-08-08 — MVP substrate is OSRM + MapLibre, behind swappable boundaries

**Context:** The recap pipeline has two substrate dependencies — routing (road
snapping) and rendering (the base map). Both are implemented and validated
against real trips. Apple Maps + MKDirections is a plausible future alternative,
and the question of which ships was reopened while triaging a camera bug.

**Decision (owner, canonical text):**

> "The MVP rendering and routing substrate is OSRM + MapLibre because it is
> already implemented and validated against real trips. The application must keep
> routing and rendering behind stable boundaries so future releases may
> substitute MKDirections + Apple Maps without changing the story model or replay
> pipeline."
>
> "Pixel Art remains a post-MVP visual differentiation path enabled by retaining
> MapLibre."

**Rationale, recorded alongside — not as separate decisions:**

- MapLibre is retained specifically because it is the only substrate that keeps
  the Pixel Art / custom-map visual-identity path viable post-MVP. Apple Maps
  forecloses that option permanently. **A deliberate strategic trade-off, not an
  oversight.**
- Apple Maps + MKDirections evaluation happens **after** MVP validation, and will
  be decided by **rendered A/B comparison, not theoretical reasoning** about
  story-model independence. Do not assume route geometry, label density, or map
  visual hierarchy are equivalent across substrates.
- Map labels on MapLibre remain deferred/icebox, blocked on the glyph/fontstack
  problem. **That Apple Maps solves this for free is NOT a reason to revisit the
  substrate decision** — it is out of scope.

**Deferred by decision, not by technical blocker** — do not pick these up
opportunistically: MKDirections integration; the Apple Maps substrate
(MKMapSnapshotter/MKDirections or any Apple-Maps-specific rendering path); Pixel
Art theme implementation (spike branch stays parked); an Apple-Maps label
workaround as a MapLibre glyph substitute.

**Rejected:** shipping Apple Maps as the app substrate with MapLibre kept only
for the owner's own films. That was briefly recorded on 2026-08-08 and is
**superseded by this entry** — it would have foreclosed Pixel Art permanently,
which is the differentiation path the custom substrate exists to enable.

**Consequence for the code:** `establishing` currently carries two meanings
through one parameter — story pacing and the tile-coverage span cap. On the
committed substrate that is a core-path defect, not an Apple-Maps prerequisite.
See HANDOFF.md.

## 2026-08-09 — The recap camera: a configured zoom, and a wider establishing shot

**Context:** Iceland's recap opened flat — establishing beat and body span were
the same number, so the "closing zoom" had no zoom in it. Three rounds of renders
narrowed the cause and the fix.

**Decisions (owner, from rendered output rather than reasoning):**

1. **The opening establishes on the whole trip, then zooms in to the body.**
   Iceland 736.8 km → 294.7 km. This supersedes the 2026-08-02 "wide baseline",
   where the body framed the whole trip and the film therefore opened flat.
2. **The zoom is configured directly** — `target_zoom_ratio` (2.5, acceptable
   range 2.25–2.75), applied per trip against *its own* established span. It
   replaced `body_span_padding`, a fraction of the trip's bounding box that had
   been reverse-derived from Iceland and did not generalise: New Zealand, which
   establishes on a wider country beat, came out at 4.14× from the same constant.
3. **Where a region offers genuinely wider context, take it — even at the cost of
   a longer opening.** New Zealand's country beat survives because its region is
   the whole country while the trip is the South Island, giving a 9.00 s opening
   against Iceland's 5.50 s. Cutting the region to collapse that beat was the
   alternative and was rejected: the establishing shot exists to show where the
   journey sits, and that is worth the seconds.

**Consequences:**

- Tile regions need **establishing headroom**, not just coverage:
  `containedSpan(region) >= wide_span_padding × fittingSpan(trip)`. Documented with
  its derivation in `Deploy/regions.json` `_establishing_headroom`;
  `Tools/tile-headroom.sh` reports it and `build-tiles.sh` runs it after every
  build. Iceland's region was rebuilt (158.7 → 159.5 MB, the margin being open sea).
- `camera_pan_window_fraction_per_s` returns to **0.35** and becomes a genuine
  floor rather than a soft target the ceiling always overrode. Without it the
  ratio alone broke camera continuity on 128 assertions.
- Pacing no longer reads the map: `RecapPacing.contentDerived | .fixed` replaced a
  nil-`establishing` check that conflated "no tiles installed" with "short
  deterministic film".

**Rejected:** re-tuning `body_span_padding` per trip. A second hand-picked
constant would have fitted New Zealand the way the first fitted Iceland, and told
us nothing about the third trip.

## 2026-08-13 — The Replay MVP gate splits: §6a the film (desk, Variant A), §6b the product (phone, Variant B)

**Context.** `RecapMode` gave the recap two shapes — `.highlight` (a
budget-derived number of stops, bounded length) and `.full` (every stop, no
duration ceiling). Chiu decided on 2026-08-11 that **Variant A (`.full`) is the
MVP release** — the films he publishes himself — while **Variant B (`.highlight`)
is what the app ships**. `.full` is reachable only through the render harness
(`KAMOME_RECAP_MODE`); no app code writes `recapMode`.

That made the single §6 gate incoherent. Its clause *"all three complete entirely
in-app — no repo-external tools"* was written before the two variants existed, and
taken literally it judges Chiu's own desk renders — the release artifact — as gate
violations. Meanwhile the clause it was protecting (can the product do this by
itself?) is a real question that nothing else asked.

The three desk renders settled the practical half. All three completed in Variant
A with every stop showing photographs and every stop named:

| | Miyakojima | New Zealand | Iceland |
|---|---:|---:|---:|
| presented stops | 10 | 20 | 65 |
| photographs shown | 23 | 45 | 144 |
| film length | 103.7 s | 193.7 s | **598.7 s** |
| frames / render time | 3,110 / 149 s | 5,810 / 600 s | 17,960 / 1,782 s |

Iceland is a ten-minute film taking half an hour to render on a Mac. On-device
render time has never been measured, and `HANDOFF.md` has carried uncapped-mode
device rendering as the single biggest viability risk since 2026-08-05. Variant B
on the same trip is bounded by `total_duration_max_s`.

**Decisions (owner):**

1. **§6 splits into two gates over two variants.** §6a runs at the desk in
   Variant A and asks *is this worth publishing*; §6b runs on a real iPhone in
   Variant B and asks *does the app do this by itself*. Item-by-item split in
   `Docs/handoff-P3.5.md` §6.
2. **Neither gate is downgraded below three trips**, and neither substitutes for
   the other. The pre-split rule that "three trips is hard, never one" now binds
   twice.
3. **Variant A is not required to run on device, and Variant B is not required to
   be the published film.** Each gate tests the variant that variant is for.

**Consequences:**

- **Uncapped rendering leaves the app's critical path.** Whether a 65-stop,
  18,000-frame film can be exported on a phone is no longer an MVP question. It
  becomes a Phase 2 question if Variant A is ever shipped in-app.
- **Variant A is validated only at the desk** — there is no second gate behind it,
  so `~/kamome-renders` is release output rather than scratch.
- **§6b inherits the device items** that were always device-shaped: limited photo
  library, S5 UX, export stability and memory, per-trip export time. It also
  inherits a named crash to watch for — the intermittent
  `KamomeCore_KamomeExportEngine` bundle fatal error, which reaches a `fatalError`
  through `Bundle.module` in `RecapCarSprite.swift` on the shipped export path and
  therefore cannot degrade gracefully.
- **The merge to `main` now hangs off §6b**, not §6a — it is the app that merges.
  §6a comes first in time because it decides whether the device sitting is worth
  spending.
- The same three trips now exist as two edits each, which is a free A/B on which
  edit people actually want to share. That is a product experiment the split
  enables; **it is not a gate item.**

**Rejected: keeping one gate and reading "entirely in-app" loosely.** The clause
would then mean whatever the reader needed it to mean, which is how a hard gate
becomes a soft one. Splitting keeps both halves literal.

**What this does NOT decide.** Whether Variant A ever becomes reachable inside the
app; how travel is paced within a Variant A film (an open experiment — see
`HANDOFF.md`, "Pending experiment — travel pacing"); and whether Iceland stays a
Variant A trip. None of those are settled, and none should be read out of this
entry.

## 2026-08-15 — Phase 3.5 closes: §6a passed, §6b did not, and the phase map catches up

**Context.** Phase 3.5 (Replay MVP) ran from 2026-07-20. §1–§5 landed the
machinery — photo-EXIF import, the MapLibre substrate, the Modern Minimal theme,
the camera and stop presentation, the photo deck. §6 split into §6a (desk, Variant
A, "is the film worth publishing") and §6b (device, Variant B, "does the app do
this by itself") on 2026-08-13.

**Decisions (owner, 2026-08-15):**

1. **Phase 3.5 closes with §6a passed and §6b explicitly NOT passed.** Chiu's
   framing: the phase's question has an answer — a journey can be reconstructed
   from photographs into a film worth sharing, and a community liked it — while
   the six unmet items are release conditions rather than direction-validation
   conditions, and there is no plan to ship to the App Store yet.
2. **§6b's unmet items move to Phase 2 (App Store release)**, which already
   existed as the home for exactly this class of work. They are carried, not
   waived: only two of three trips ran on device; Limited Photo Library, the S5
   UX pass, per-trip export time, memory behaviour and crash-free export across
   three trips were never done. **And the souvenir map has never rendered on a
   phone** — both device films fell back to Apple Maps.
3. **The phase map is not rewritten; it is corrected.** Phase 3.5 quietly
   delivered the front of P4 Story Director — `StopPhotoAllocator`'s scoring and
   selection, `earnedStopCount`, and duration that follows content are precisely
   the "deterministic scoring/selection over trip data" P4 was defined as. P4's
   own precondition — "only after the MVP proves films get shared" — was met when
   Chiu published and the feedback came back good.
4. **Phase 4 is scoped around the artefact, not the product.** Chiu chose this
   explicitly over productisation: *"方便的產品都沒有這是足夠好的作品更吸引人."*
   Measurement and export survivability, vehicle sprites, map labels (still
   locked), cross-region journeys. Story Director's remaining content — hero
   photographs, chapters, music, video beads — stays deferred.

**Consequences:**

- **PR #11 merges on this decision**, not on §6b. The branch had run for over a
  hundred commits and a clean base for Phase 4 was the stated motivation.
- **Export performance is now a first-class problem with numbers behind it.**
  Export time is snapshot-bound (≈1.0–1.9 s per snapshot, one snapshot per
  `keyframe_interval_frames`), both measured films ran on Apple Maps, and an
  export dies if the app is backgrounded. The duration rule of 2026-08-13 made
  this materially worse — Iceland went from 2,700 frames to 6,345 — which was a
  cost visible only as arithmetic when it was approved.
- **Tile provisioning is reopened as a performance question**, not only a visual
  one, and stays undecided pending a device measurement of MapLibre.
- **MapLibre labels stay iceboxed** (owner, explicitly), to be reconsidered only
  after that measurement, because the same measurement decides both whether tiles
  are worth their download and whether per-frame overlay labels are affordable.

**What this does NOT decide.** Whether the app ships Apple Maps or the souvenir
map; whether tiles are distributed from a server; whether labels are ever built;
and whether Variant A becomes reachable in the app. Chiu's remark that Apple Maps
is acceptable *because it shows place names* is recorded as evidence for that
future discussion — the substrate ADR of 2026-08-08 is untouched and was not
reopened.

**Worth stating plainly, because a later reader will otherwise assume otherwise:**
the films published to Chiu's community were rendered on **Apple Maps**, not on the
souvenir map the v1.5 pivot was about. Nothing published so far demonstrates the
MapLibre substrate.

## 2026-08-15 — MapLibre is parked, Apple Maps is what ships, and routing moves behind an API

**Amends the 2026-08-08 substrate ADR.** Reopened and closed by Chiu on the same
day, on measured evidence and the first outside user feedback the product has had.
The 2026-08-08 entry stands as the record of why MapLibre was chosen; this is why
it is being parked rather than pursued.

**The evidence.** Export time is snapshot-bound, and four device runs put a number
on each substrate:

| trip shape | substrate | s per snapshot |
|---|---|---:|
| city (Tokyo) | Apple | **0.72** |
| small island (Miyakojima) | Apple | 1.00 |
| long road trip (New Zealand) | Apple | **1.55** |
| long road trip (New Zealand) | MapLibre | **0.84** |

Apple's cost tracks how much unseen ground a film covers — a city trip revisits
the same tiles, a road trip fetches new ones every snapshot. MapLibre reads local
`.pmtiles`, so it should be flat; it has **one** sample. On the road-trip shape
Kamome is named for, MapLibre was roughly twice as fast; on a city trip Apple beat
it outright.

**Neither substrate solves the export problem**, which is the finding that
mattered. At 0.72–1.55 s a snapshot, every film costs minutes either way. The
lever is snapshot count (`keyframe_interval_frames`, 15 today = one snapshot per
half-second), not where the tiles come from.

**The user evidence.** Chiu published films and gathered community feedback.
**Nobody raised the map style. The most common request was to change the vehicle.**
His own reading, recorded because it is the honest one: *"可能也做得不好"* — the
souvenir map may simply not be good enough yet to be noticed.

**Decisions (Chiu 2026-08-15):**

1. **MapLibre is parked, not removed.** The code, the themes, the tile pipeline
   and `Deploy/regions.json` all stay. In practice the app renders Apple Maps,
   because `RecapModel.snapshotProvider(for:)` already falls back whenever no
   `.pmtiles` region covers the trip, and no region will be installed.
2. **Tile provisioning and map labels leave the roadmap.** Labels stay iceboxed
   with no unlock condition pending; the 640 MB-per-region download problem and
   the whole P7 tile-server question are moot while nothing needs tiles.
3. **Routing stays OSRM, and moves behind an API** rather than a machine on
   Chiu's LAN. ⚠️ *Which* API is not decided — see below.
4. **Phase 4 reorders around what people asked for:** vehicle sprites →
   cross-region flight display → export reliability. Map work is not in it.

**Consequences:**

- **Structurally free, which is the point of the boundary.** `establishing == nil`
  is a supported path: `cappedToRegion` returns the asked-for span uncapped, the
  country beat drops out, and the opening frames from the trip's own bounds. The
  souvenir map's absence breaks nothing — `RecapSnapshotProviding` and the
  one-file confinement of each renderer are what made parking it a decision rather
  than a project.
- **Dormant, not wrong:** `Docs/vector-tile-pipeline.md`, `Tools/tile-headroom.sh`,
  the region headroom rule and the Planetiler builds. They stay accurate for
  whenever this reopens.
- **Pixel Art loses its near-term justification.** MapLibre was retained
  *specifically* to keep that identity path viable; parking one parks the other.

**Recorded honestly, because it is the weakness of this decision:** the souvenir
map was judged **without place names and without Pixel Art** — the two things that
would have made it distinctive, neither of which was ever built. This parks an
unfinished path on the evidence that its unfinished state did not impress anyone.
That is a legitimate call and it is not the same as concluding the path failed.
Chiu's condition for reopening, in his words: *"之後有新的需求或是我很想不同地圖再
展開."*

**Unchanged:** the v1.5 rejection of the GPS-visualiser framing, the story/render
separation, and every renderer-independent part of the pipeline — camera,
overlays, subject, chrome — which work over either substrate and always did.

## 2026-08-15 — Routing is bounded, cancellable, and says which of four things went wrong

**The trigger was the P0**, not a design review. The first person outside this
project to install Kamome could not use it: with a large photo library the app
went unresponsive. The mechanism, traced through the code rather than guessed:
`ImportService.importTrip` awaited `matchTrip` **after** the trip was already
saved; `matchTrip` walked the legs sequentially at `matching.timeout_s` each,
with failures swallowed by `try?`; and `ImportSheet` disabled its Close button
and `interactiveDismissDisabled` for the whole thing. More photographs meant more
stops, more legs, and more back-to-back timeouts behind a UI with nothing to
press. A build carrying a LAN `base_url` makes every one of those legs time out.

**Decisions:**

1. **Import returns when the trip is saved.** Routing is a separate concern with
   a separate lifetime — the trip is complete, viewable and exportable without
   it, and an unrouted leg draws dashed rather than claiming a road (PD-2).
   The import sheet's exit is enabled again, always.
2. **Two bounds, borrowed from the render** — `RecapExporter`'s `shouldContinue`
   + progress pair, which already solved this exact problem for export.
   `matchTrip` checks cancellation before every leg, and
   **`matching.trip_budget_s` (60 s)** bounds the whole trip. `timeout_s` bounded
   a request; nothing bounded the trip. Past the budget the remaining legs stay
   raw and are reported as *skipped* — never as "no road here".
3. **`RouteMatchCoordinator` owns one run per trip.** A second caller joins the
   run in flight instead of starting another.
4. **A failure taxonomy at the boundary**, built now rather than after the
   provider migration, because it is what makes that migration safe.
   `RouteProviderFailure` (unreachable / rateLimited / refused) is thrown by the
   providers; a nil outcome keeps its old meaning — the provider answered, and
   the answer was "no road route". `RouteMatchReport` aggregates them and S5
   shows the user which, beside the existing photo-shortfall row.

**On concurrency, checked rather than assumed** (this was the review's gate on
landing any of it). Detaching matching means a user who imports and immediately
taps the film button runs `matchTrip` twice over one trip. That is **not a data
race**: `AppDatabase` is a GRDB `DatabaseQueue`, which serialises every read and
write; `setMatchedPolyline` is a one-row, one-column UPDATE that does not read
the row first; and `matchTrip` never writes nil, so no run can un-match what
another matched. Two runs can only do the same work twice and agree.

It is still prevented, for reasons that are about the product rather than the
database: a *per-run* budget is not the per-trip budget `trip_budget_s` promises,
and two runs produce two verdicts for one trip when the screen can show one.
Hence single-flight ownership, **not a lock** — nothing here needed one.

**Consequences:** `ImportService` no longer takes a matcher, and the two desk
harnesses that relied on `importTrip` routing now ask for it explicitly — a
dependency they always had and never stated. `RouteMatchService` takes the
`matching` block instead of the whole config, because that is all it reads.

**Not decided here:** which hosted provider. §0 still governs that — routing
sends real trip coordinates off the device (PO.md, Routing).

## 2026-08-15 — Export variation enters as a seed, never as randomness

**Written before the feature, deliberately.** "Different photos each export" is
wanted and deferred; this records the one constraint it must be built under, so
the obvious implementation — a `random()` inside the selector — is not the one
that gets written.

**Decision.** Variation enters the pipeline **only** as an explicit seed:

- **Chosen at the composition boundary** (`RecapModel`), which is where a film
  becomes a specific film. Never generated inside `ExportEngine`.
- **Persisted with the export.** A seed that is not stored is not a seed, it is
  a coin toss with extra steps.
- **Re-rendering an export reproduces it**, byte for byte. "Shuffle" is the
  gesture that mints a *new* seed; export alone never does.

**Why.** The golden-frame gates and the two continuity gates
(`RecapCameraContinuityTests`) are the reason the recap pipeline can be changed
at all — they compare renders. Anything non-deterministic inside `ExportEngine`
makes a failing gate unreproducible and therefore useless, and this is already
recorded once: video clips in recap were iceboxed in 2026-07-17 on exactly this
ground ("deterministic excerpts only — random breaks golden-frame CI").

It also matters to the user, not only to CI. A film worth keeping is one you can
get back. If re-exporting silently produced a different edit, the good version
would be gone the moment anyone tried to render it at a higher bitrate.

**Rejected:** randomness inside the selector (unreproducible gates, and a film
the user cannot recover); a seed derived from the trip id alone (stable, but then
"shuffle" has nothing to change); a seed derived from the clock at export time
(reproducible only by accident, and never after the fact).

**Deferred:** the feature itself. This is the constraint, not a plan.

## 2026-08-16 — Routing moves to a commercial API's free tier, and real coordinates leave the device

**Decision (Chiu).** Routing moves off the developer's LAN to a **third-party
hosted routing API, on a free tier**. The specific provider is **not yet chosen**.

**Why not self-hosting**, which is cheaper in money. A self-hosted OSRM only
routes the regions it preloaded, and that failed in practice on 2026-08-15: a
friend's Tokyo trip had **no routable legs at all**, because `Deploy/regions.json`
carries Kyushu for Miyakojima and Tokyo is not in it. Loading the planet is a
machine costing hundreds a month, so the €5–10 VPS buys coverage of four countries
and dashes everything else — and "every leg a straight line" is what §6a's honesty
item exists to prevent. The saving is paid for in the product's core promise.

**Volume makes a free tier genuinely sufficient**, which is the fact that decides
this: one film is one request per drive leg — 9 on Miyakojima, 17 on New Zealand,
58 on Iceland — and a person makes a handful of films. Any free tier absorbs that.

**§0 — this is the cost, and it is accepted deliberately.** Routing sends **real
trip coordinates off the device to a third party**. Until now they went only to a
machine in Chiu's flat. §0 says a feature that needs real coordinates to leave the
device is a product decision for him, not an implementation detail; **this is that
decision, made.** It does not weaken §0's other guarantees — nothing is logged,
synced, or sent to analytics, and the trip itself still lives only on the device —
but a third party now sees where a leg started and ended.

**Consequences:**

- **The provider choice is still open**, and it is not only a price comparison:
  current terms for commercial use, attribution requirements, caching rules, and
  whether the response shape is OSRM-compatible all have to be read rather than
  assumed. The boundary survives either way — OSRM's wire format lives only in the
  two provider files and downstream consumes a domain-level `RouteMatchOutcome` —
  so a differently-shaped provider is one new file.
- **The detour-ratio plausibility gate must be lifted out of `OSRMRouteProvider`
  in the migration PR**, and not before. It is Kamome's honest-provenance policy
  rather than an OSRM fact, and a new provider file would silently drop it.
- **`matching.trip_budget_s` (60 s) was chosen, not measured**, against a healthy
  server at roughly one second per leg on the largest trip. A free tier's rate
  limits may bind well inside it; re-measure once a provider exists.
- **A disclosure surface does not exist.** Every import will silently contact a
  third party. Whether that needs saying to the user, and where, is an open
  product question — the failure taxonomy shipped 2026-08-15 tells them when
  routing *fails*, not that it happens at all.
- Self-hosted OSRM stays viable behind the same boundary if this is ever reversed;
  `Deploy/` and `regions.json` remain accurate and are not deleted.

## 2026-08-20 — Geoapify is the provider, and **two** policies must survive the migration

**Decision (Chiu).** Routing is **Geoapify**, closing the 2026-08-16 "hosted free
tier, provider not chosen" ADR and `Docs/routing-provider-selection.md`. Decided on
a survey run against a live free-plan key on 2026-08-19 (Iceland Ring Road /
Golden Circle geometry, derived publicly — **no Kamome fixture, nothing from
`Tests/Fixtures/trips/local/`**, §0 respected).

**What the survey settled, measured:**

| checklist item | result |
|---|---|
| route quality, 5 Iceland pairs | 200 on all; detour ratio **1.15–1.49**; 193 pts over 11 km — dense enough to draw as road |
| a photo 300 m off-road | snaps, **exactly** — P5 returned an identical distance and identical 363-point geometry |
| map-matching capacity | 1000 points enforced cleanly, 100% matched, single sub-trace; 1500 rejected explicitly |
| rate limit | **28.7 req/s sustained, zero 429s, no rate-limit headers on any response** |
| failure classes | `400 No suitable edges` / `400 No path could be found` / `401` / malformed — all distinguishable |

**Decision (Chiu): the one deficiency is accepted.** There is no 429 and no
`Retry-After`; overload arrives as TCP reset, indistinguishable from unreachable.
His reasoning, recorded because it is the product judgement and not a technical
one: Kamome starts as a free product, and this much fault tolerance is acceptable
rather than worth choosing a worse router over.

---

### 🔴 The consequence that is not in the survey: **two** policies live in `OSRMRouteProvider`, and only one was on record

The 2026-08-16 ADR names the detour-ratio gate as the thing a new provider file
would silently drop. **There is a second, and it is the one the survey's own
numbers make dangerous.**

`OSRMRouteProvider.requestURL` sends **`radiuses=` per waypoint**, floored at
`matching.route_waypoint_radius_m` (**500 m**), with the reason written beside it:
*photos sit beside roads, not on them.* Under OSRM a waypoint further than that
from a road returns `NoSegment` → nil → **the leg draws dashed**. That is PD-2
behaving correctly: refuse rather than invent.

Geoapify's `/v1/routing` takes a different URL shape entirely
(`?waypoints=lat,lon|lat,lon&mode=drive`), and **whether it accepts any snap-radius
parameter was not tested.** If the new provider file simply does not send one, the
survey says what happens — and it is a regression from honest to fabricated:

| photo position | today (OSRM, `radiuses=500`) | Geoapify with no radius (measured) |
|---|---|---|
| 300 m off-road | routes, correct road | routes, **identical** geometry — good |
| 500 m off-road | dashed (`NoSegment`) | `400 No path could be found` — dashed |
| **1000 m off-road** | **dashed** | **200 · 20.33 km for an 11.29 km leg · ratio 2.247** |
| **2000 m off-road** | **dashed** | **200 · 18.49 km · ratio 2.007** |

`matching.route_max_detour_ratio` is **2.5**. Both wrong-road routes **pass the
gate** (9.05 km straight × 2.5 = 22.6 km allowed, 20.33 km returned), are stored
by `setMatchedPolyline`, and are drawn as **solid road the traveller never took**.
PD-3 exists to stop exactly this and its threshold sits just above it.

**Do not fix this by tightening the ratio.** The survey's legitimate routes measure
1.15–1.49 and its wrong-road routes 2.0–2.25, which looks like a clean gap — but a
fjord or peninsula drive is *legitimately* 2–4× its straight line, and Iceland is
made of them. The ratio cannot tell a wrong road from an indirect one. **The snap
radius can**, because it acts before a route exists.

**So the migration PR carries three things, not one:**

1. Lift the detour-ratio gate out of `OSRMRouteProvider` (already on record).
2. **Carry `route_waypoint_radius_m` across, or establish that it cannot be.**
   If Geoapify has no radius parameter, that is a product decision — a photo 1 km
   from a road either draws dashed or draws a road it did not take — and it comes
   back to Chiu rather than being settled by whichever is easier to write.
3. Keep `RouteProviderFailure.rateLimited` and its two strings. On Geoapify the
   case is unreachable code, but the **pre-launch Cloudflare Worker can emit a real
   429 with `Retry-After`** — it is the natural place to throttle — so the
   distinction is recoverable in a component already planned. Deleting the case now
   means rebuilding it then (Arch.md §7.2/§7.3 discipline).

### Corrections to what the survey concluded

- **The 1500 m map-matching ceiling does not bind photo import.** EXIF legs go
  through `RouteReconstructing.route` (`/v1/routing`); only `.gpsHifi` /
  `.gpsPassive` reach `/v1/mapmatching` (`RouteMatchService.route`). Sparse photo
  points never touch that limit. Where it *will* bite is **Capture Beta**, and
  specifically the known region-resume hole (2026-07-19: 32 min / 13 km lost) — a
  gap that size returns **200 with points silently unmatched**. Recorded against
  Capture Beta, not against today.
- **`matching.timeout_s` (10 s) vs a measured 9.6 s for a 1000-point match** — the
  same Capture Beta concern, 0.4 s of headroom. Not today's problem.

### Open, and deliberately not guessed

- **`matching.trip_budget_s` (60 s).** Task 1 measured 0.48–2.53 s a leg (cold),
  Task 2 measured 440–840 ms back-to-back (keep-alive, which `URLSession.shared`
  gives us). Iceland is 58 legs, so the sequential trip lands somewhere between
  **≈35 s and ≈88 s — derived arithmetic, not a measurement** — and 60 s sits
  inside that band. **Do not pick a new number.** The first real import against
  Geoapify *is* the measurement: `matchTrip` already logs `STOPPED after N legs —
  trip_budget_s exhausted`. Read that line, then set it.
- **`chunk_size` (100 waypoints) against a GET-only endpoint.** `POST /v1/routing`
  returns 404 — the endpoint is GET-only — so 100 waypoints become ~2 KB of query
  string, and Geoapify's own waypoint cap for `/routing` was never probed. Cheap to
  test on the same script; untested is not the same as fine.

### §0 — GET-only changes the shape of the exposure, not the decision

The 2026-08-16 ADR accepted that a third party sees where a leg started and ended.
GET-only means **the coordinates travel in the URL query string, beside the API
key** — and a URL is the most-logged part of an HTTP request. The survey saw
`cf-ray` headers, so Cloudflare fronts Geoapify and edge logs record URLs by
default.

This does **not** reopen the decision, which is Chiu's and stands. It does two
things: it raises the value of the pre-launch Cloudflare Worker from "the key must
leave the binary" to "the only hop Kamome controls the shape of", and it makes the
Worker's **no-log requirement** load-bearing rather than tidy.

### What this does NOT decide

Whether the user is told that importing contacts a third party (still open, still
§0, still Chiu's). Whether the Worker lands before or after Phase 4. Whether
Geoapify's place-name quality reopens "place names as narrative rhythm" — the
survey's Task 4 is **strong evidence** (`type=amenity` returned Skógafoss, Gullfoss,
Strokkur, Hallgrímskirkja, Seljalandsfoss, Diamond Beach on 8 of 9 coordinates,
against `type=street`'s Suðurlandsvegur) but that feature is iceboxed and stays
iceboxed until Chiu names it.

## 2026-08-20 (b) — Geoapify's terms, read; and what Kamome now commits to on privacy

**Written after the empirical survey**, which measured behaviour and never touched
terms. `Docs/routing-provider-selection.md` named two questions that could
disqualify outright; the survey answered one (map-matching exists, 1000 points,
enforced cleanly). This is the other one, read from the documents.

### What the terms actually say

| question | answer | source |
|---|---|---|
| may returned routes be **stored permanently**? | **The T&C does not address it at all** — no clause permitting it, none forbidding it. Geoapify's own FAQ says results may be cached and reused, but the wording found is **Places-API specific**. | Terms & Conditions; Places-API comparison page |
| free tier, commercial use | Commercial use of Free is allowed in development and, **"with some limitations"**, in production. The limitations are **not defined**; the terms say to contact them. Pricing calls it "Limited Commercial Use". | T&C *Plans and usage limits*; Pricing |
| a **publicly distributed mobile app** on Free | **Not addressed anywhere.** | — |
| free-tier limits | **3,000 credits/day, up to 5 requests/second.** Note *credits*, not requests — whether a routing call costs one credit is unverified. | Pricing |
| attribution | OSM attribution **always**; Geoapify attribution **mandatory on Free**; format `Powered by Geoapify` with a link. **Where it must appear is not specified**, which leaves Chiu's 2026-08-17 in-app decision intact. | T&C *Attribution*; Pricing |
| what they log | **Request body, headers, IP address and timestamp**, used for access control / usage counting and for detecting issues and optimising the APIs. | Privacy Policy *Services and API Requests* |
| retention | **No longer than 24 hours** — stated for *successful* requests. | Privacy Policy *Data Retention Period* |

### Verdict: **not disqualifying, and the provider decision stands.** Two things to close.

1. 🟠 **Get the storage answer in writing, for routing specifically.** The practical
   risk is low — the data is OSM-derived and Geoapify markets storage as its
   advantage over Google — but `matched_polyline` is kept forever and re-exported
   offline months later, which *is* the product. Silence in a contract is not
   permission. **One email, before submission, not before Phase 4.**
2. 🟠 **"Limited commercial use" has to be defined before the App Store**, because a
   publicly distributed app is exactly the unaddressed case. Volume is not the
   problem — 3,000 credits/day against 58 requests per Iceland film is ~50 films a
   day. This is a submission blocker, not a Phase 4 one (`Docs/pre-launch.md`).

### ⚠️ The retention clause has an edge that matters to Kamome specifically

24 hours is a **good** answer, and better than §0 feared. But the sentence covers
**successful** requests, and Kamome's interesting cases are the failures — an
unroutable leg, a rate-limited burst, a request that times out. Nothing states how
long a *failed* request is held, and a failed request still carried the coordinates.

Combined with **GET-only** (2026-08-20 ADR), the honest §0 statement is: *for up to
24 hours, a third party holds the start and end coordinates of each routed leg,
in a URL, tied to the device's IP address and a timestamp.*

---

## Chiu's decisions, 2026-08-20

1. **Journeys are multi-modal by design; car ships first.** The spec was wrong to
   read as car-only. → spec **v1.8**, new §4.4.1.
2. **Walks route on a walking profile and draw solid.** Real footpaths, not
   fabricated roads, and not pervasive dashing.
3. **The §0 line moves — and it moves by source, not by mode.**
   - **Recorded trips are the user's own and stay that way.**
   - **Photo-imported trips need a path computed, so their coordinates go to the
     provider — and a walk is treated exactly like a drive.** Chiu's reasoning,
     recorded because it is the product judgement: the user is choosing which
     photographs make the trip, and a city stroll reconstructed from photos is not
     a confidential matter. **This must still be declared honestly** in a privacy
     policy, and the PO session is asked to keep watch on it.
4. **A crossing always shows a path.** Sea → ship. Land → whatever mode can be
   determined. Undetermined → **the seagull**. The seagull carries the same claim as
   a dashed line — *this path is estimated* — while being a better experience than
   nothing: the traveller still sees a plausible route.

### 🔴 Item 3 needs one clarification before anything is built

**"Recorded trips stay on the device" is not true of the code today.**
`RouteMatchService.route` sends `.gpsHifi` / `.gpsPassive` traces to
`matcher.match(trace)` — the **dense recorded trace**, which is far more revealing
than a handful of photo positions, and is the main input for Capture Beta.

Two readings of the decision, and they need different work:
- *"We do not **log** it"* — already true; §0's other guarantees hold, but the
  provider still sees recorded traces.
- *"We do not **send** it"* — a real change: recorded legs would stop being
  map-matched, and Capture Beta loses road-snapping entirely.

**Not resolved here.** Flagged for Chiu.

### 🔴 The justification for item 3 describes a product that does not exist yet

The reasoning is *"they can choose the photographs"*. **Today they cannot.** Import
takes a **date range over the whole library**; choosing an album or selecting
photographs is `Docs/cross-region-journeys.md` requirement 1, **unbuilt**.

So either the album/selection path lands before walk routing does, or the
disclosure says plainly that a date range decides what is sent. **A privacy notice
resting on a control the user does not have is the failure mode §0 exists to
prevent.** Flagged for Chiu; not a blocker on car routing, which is unaffected.

## 2026-08-20 (c) — The terms risk is accepted; traces are sent; the notice must say what is actually sent

**Chiu, closing the three questions left open by 2026-08-20 (b).**

### 1. The two terms questions: accepted, do not ask

**Decision:** do not write to Geoapify. Proceed, and if either becomes a problem,
upgrade the plan or stop. **Concurred, and the reasoning holds for both** — but for
different reasons worth keeping apart:

- **"Limited commercial use"** — the worst case is being told to pay, at a volume
  where paying is trivial. Nobody is harmed, and it reverses in an afternoon.
- **Permanent storage of routing results** — the T&C's **silence is in Kamome's
  favour**: there is no clause to breach. The data is OSM-derived, and Geoapify
  markets storage as its advantage over Google.

**What bounds the risk, and why "forgiveness" is defensible here rather than
generally:** if storage were ever disallowed, the fallback is **known and already
built** — route at export time instead of reading `matched_polyline`, using the
coordinator and budget that already exist. Offline re-export degrades; nothing
breaks. A risk with a working fallback is a risk worth taking.

**The record is the mitigation.** 2026-08-20 (b) carries the URLs, the date, and
what each document said. If terms change later, "on 2026-08-20 the terms were silent
and the vendor's own FAQ said results may be cached" is the whole defence, and it
costs nothing to have written it down.

### 2. Recorded GPS traces are sent — this is decided

**Decision (Chiu):** they must be. Without sending the trace there is no route data,
and Capture Beta's road snapping depends on it. §0's answer is **honest declaration,
not withholding.**

### 3. ⚠️ The approved wording understates what is sent — corrected here

The sentence Chiu approved — *"the start and end coordinates of each leg, in a URL,
tied to IP and timestamp"* — is accurate for **neither** path once checked against
the code. There are two paths and they differ in both content and shape:

| | photo-imported leg | recorded leg |
|---|---|---|
| endpoint | `/v1/routing` | `/v1/mapmatching` |
| method | **GET — coordinates in the URL** | **POST — coordinates in the body** |
| what is sent | the leg's waypoints: stop centroids **plus photo positions**, thinned to ≥ `route_waypoint_min_spacing_m` (250 m), capped at `chunk_size` (100) | **the full recorded trace**, in chunks of up to 100 points |

Verified in `OSRMRouteProvider.requestURL` and `OSRMMatchProvider` (today both GET;
Geoapify's mapmatching is POST, so recorded traces move out of the URL on migration).

**So the notice must say two things, not one:** that an imported trip sends the
photo positions a leg is built from, and that a recorded trip sends **the recorded
path itself**. Retention is Geoapify's stated ≤24 h for successful requests, with
IP and timestamp. Saying "start and end coordinates" while sending a full trace
would make the honest declaration a false one — which is worse than not declaring.

### 4. The album path is now load-bearing for the privacy story

**Decision (Chiu):** the notice states plainly that a **date range** decides what is
sent, *and* that the user can control which places are given by choosing an album.

**Consequence, recorded because it changes a priority:** album selection
(`Docs/cross-region-journeys.md` requirement 1, the cheap half — "a list and a
fetch") stops being a cross-region convenience and becomes **the control the privacy
notice describes.** A notice may not promise a control the app does not offer, so
**the album path ships with the notice, or the notice does not mention it.**
Free-form photo selection stays a later design pass.

## 2026-08-20 (d) — The snap radius was the wrong mechanism, and it was never guarding what I said

**This corrects the 2026-08-20 ADR, `HANDOFF.md` item 1 and `CLAUDE.md`, all
written by the PO session.** The engineering session measured the mechanism those
documents assumed and found it does not hold. The measurement wins.

### What was claimed

> The snap radius can tell a wrong road from an indirect one, because it acts
> before a route exists. Under OSRM a photo 1 km from a road returns `NoSegment`
> and draws **dashed**; Geoapify without a radius returns a 20.33 km route for an
> 11.29 km leg, which passes the 2.5 detour gate and draws as solid road.

### What was measured (Geoapify, live key, public landmark coordinates only, §0 respected)

`/v1/routing` **accepts no snap-radius parameter** — established behaviourally, not
from a status code: a nonsense parameter returns byte-identical output, so unknown
parameters are silently ignored. The response also never reports where a waypoint
snapped; `properties.waypoints[].location` echoes the input verbatim in all 24
probes. Per-point `match_distance` exists only on `/v1/mapmatching`, which sparse
photo legs cannot use.

Then the endpoint was offset 1 km and 2 km at every 30° bearing, measuring the
distance from the requested waypoint to the road that came back:

| case | routed | ratio | waypoint → returned road |
|---|---:|---:|---:|
| 1000 m @ 150° | 19.96 km | 2.14 | **123 m** |
| 1000 m @ 180° | 20.45 km | 2.31 | **132 m** |
| 2000 m @ 90° | 21.08 km | 1.92 | **125 m** |
| 2000 m @ 150° | 18.87 km | 1.93 | **44 m** |
| benign 2000 m @ 0° | 12.16 km | 1.27 | 477 m |
| benign 1000 m @ 270° | 9.55 km | 1.19 | 465 m |

**Snap distance and route wrongness are anti-correlated.** The wrong routes snap to
roads **44–132 m** away; the benign ones snap **465–477 m** away. A 500 m radius
admits every dangerous case. A radius tight enough to reject them would reject the
good routes first. The 20 km detour is not "snapped to a distant road" — it is
"snapped to a **near** road on the far side of the Hvítá canyon".

### The correction, and it goes further than the engineering session claimed

**`radiuses=500` was not protecting Kamome from this band on OSRM either.** OSRM
snaps to the nearest road within the radius; a wrong road 123 m away is well inside
500 m, so OSRM would have taken it too and drawn the same wrong solid line. The
claimed regression from *honest dashed* to *fabricated solid* **did not exist**.

What the radius **did** guard is a different and real class: a waypoint with **no
road anywhere near it** — a lagoon surface, a beach, a glacier, open sea. The
survey's own Jökulsárlón point (≈3.5 km from any road) is exactly that.

**And Geoapify guards that class natively**, without any parameter: it returns
`400 No suitable edges near location`, which the provider already maps to a
keep-raw verdict and a dashed leg.

**So nothing is lost in the migration.** The parameter's absence costs Kamome
nothing it actually had.

### Decision: the detour gate stays at 2.5, nothing new is built in this PR

1. **This is not a regression the migration created**, so the migration is not the
   place to solve it. It is a pre-existing limitation that has now been measured
   for the first time.
2. **The detour gate keeps the job it was built for** — PD-3 outlier protection,
   the 300 km route from one bad EXIF fix. It was never a wrong-road detector and
   is not being asked to become one.
3. **Do not tighten the ratio.** Unchanged reasoning, now with numbers on both
   sides: benign offsets measured 1.19–1.27 and wrong ones 1.92–2.31 **on one leg
   in one landscape**, while a fjord or peninsula drive is legitimately 2–4×. One
   leg is not a distribution.
4. **The Iceland film is the test.** 58 legs of real photo positions, judged by
   looking — against a synthetic 24-bearing probe of deliberately displaced points.
   If wrong roads appear in it, a guard gets designed against that evidence.

**Partially self-dissolving, worth knowing:** many photos taken ≥1 km from the
driven road were taken **on foot**. Once walks route on a walking profile
(spec v1.8 §4.4.1), those legs route on the footpath actually taken instead of
being forced onto the car network.

### Two items closed for free by the same probe

- **`chunk_size: 100` is safe** — 100 waypoints is 2,485 chars of GET query and
  returns 200; 150 works too. (`HANDOFF.md` item 5.)
- **`/v1/mapmatching` POST works**, returning `match_type` and `match_distance`
  per point. (`HANDOFF.md` item 6's endpoint.)

### Addendum (Chiu, 2026-08-20) — recorded trips: the lean, parked

Deferred to **Capture Beta**, not decided now. **Chiu's current thinking, recorded
so it is not re-derived:** a journey the user actually walked or drove and recorded
**does not need to leave the device at all.** The trace is already the route data and
already draws solid; only snapping polish is lost.

This does not reverse 2026-08-20 (c) — photo-imported trips still send coordinates,
walks included. It narrows the *recorded* half, and it is cheaper to act on than it
looked when (c) was written, because that decision rested on the premise that
withholding the trace would leave no route data. For recorded trips that premise was
wrong.

**Nothing to build now.** The MVP path is photo import. Revisit when Capture Beta
opens.

---

## 2026-08-21 — The Iceland film passed: the Geoapify migration is accepted

**Closes item 4 of 2026-08-20 (d)**, which named the film as the test and reserved
the verdict for Chiu.

**Decision (Chiu, 2026-08-21, owner report).** The routes are correct. None of the
49 solid legs is a wrong road. The Geoapify migration is accepted on that evidence
and PR #16 has no product blocker left.

**What was judged.** `~/Kamome-films/2026-08-21-iceland-geoapify.mp4` — Iceland,
the real 2,300-photo dump, 21 stops, 64 legs, 211.5 s, rendered 2026-08-21 through
a locally-run Cloudflare Worker to Geoapify. Kept outside the repository
deliberately: it is a render of a real trip (§0).

    matchTrip: 58/64 legs routable, budget 60s
    matchTrip: 49/58 legs reconstructed; 8 have no road route, 1 unreachable,
               0 rate-limited, 0 never asked

The nine that did not draw as road are each a mechanism working, not a failure:
five `No suitable edges` (the class the absent snap radius would have guarded,
refused natively by the provider — (d) again), two `No path could be found`, one
detour-gate rejection at 3.5× (61.6 km routed against 17.5 km straight — PD-3
firing on real data), and one timeout, correctly reported as retryable rather than
as geography.

**Classification.** VERIFIED as a product judgement by the owner from rendered
output — which is the only thing that could have settled it. It is **not** a
measurement that no wrong road can ever appear: it is one trip, judged by looking.
A wrong road found later is new evidence against which a guard gets designed, not
a reversal of this entry.

**Still open, and not closed by this** — the keyed path has never been observed
working through the app's own configuration. This film was rendered through a
locally-run Worker because the key then in `Config/Secrets.xcconfig` returned 401.
Chiu fixed the key on 2026-08-21 and reports it fine, but **no run log exists**;
`Docs/eng-session-P4-visual.md` item 3 folds that confirmation into its next
render rather than spending a session on it.

## 2026-08-27 — The film follows the device's system appearance, and light gets a warm trail

**Decision (Chiu, 2026-08-27).** The recap film **follows the device's system
appearance**. On a light base the trail is **orange** instead of the blue-cyan one.

**Why the trail cannot simply carry over.** Measured, not preference. On Apple
Maps' light base the trail's cyan `(0.42, 0.87, 0.98)` is in the same colour
family as the ocean, lakes, rivers and fjords it crosses: in the 2026-08-27
comparison still the north-coast leg between Sauðárkrókur and Húsavík is not
distinguishable from a fjord, and the south-coast leg past Hvannadalshnúkur runs
along the shoreline and disappears into the sea beside it. On the dark base, same
frame and same subject size, the trail is unmistakably the hero of the frame.
This is why the preset was tuned dark in the first place (2026-07-22), and the
2026-08-15 substrate ADR invalidated that tuning without anyone re-tuning it.

**What this constrains, and it is more than a colour** (`Docs/decisions.md`
2026-08-15, "Export variation enters as a seed, never as randomness"). Appearance
is ambient device state, so it is bound the way that ADR binds a seed:

- **Captured at the composition boundary** — `RecapView` reads
  `@Environment(\.colorScheme)` at the tap and hands it to
  `RecapModel.startExport(appearance:)`. Never read inside the render loop, which
  is detached and would otherwise let a mid-render dark-mode toggle change a film.
- **Constant for the render**, and it selects **both** the base map's trait and the
  overlay palette from one domain value (`RecapAppearance`). A substrate that
  cannot honour it says so (`MapRendererCapabilities.fixedAppearance`; the MapLibre
  souvenir map is dark and has no light variant) and wins.
- **Every gate pins it explicitly.** `RecapStyle.modernMinimal` is now a function
  of the appearance and `MapKitSnapshotProvider(appearance:)` has no default, so a
  test cannot inherit the simulator's setting.
- ⚠️ **NOT persisted.** The ADR also requires the value to be stored with the
  export; there is no export record in the schema, and the seed feature that would
  create one is deferred by that same ADR. Until then the resolved appearance is
  written into the film's log line only, and **re-exporting under a changed system
  appearance yields a different film**. Recorded as a known gap
  (`Docs/eng-session-appearance.md` §4.1), not as satisfied.

**Rejected:** an `export.appearance` config key (it is ambient device state, not a
tunable, and a committed key would ship an answer to the manual-picker question
Chiu deferred); reading `UITraitCollection.current` inside the provider (an
environment read inside the render loop — precisely what 2026-08-15 forbids).

**Deferred, explicitly:** a **manual appearance override** in the UI. Chiu wants
system-follow now and a user picker later; that is a separate feature with its own
UI decisions.

**✅ Both open values closed by Chiu on 2026-08-29**, from the renders in
`~/Kamome-films/2026-08-28-appearance/`:

1. **The orange is `RecapStyle.routeAccent` `#FF8A5B`** — candidate **B** of three
   swept on one frame (t=114.3 s, the frame that settled the subject size) with
   their derived dashed variants, against `chromeAccentColor` `(0.95, 0.55, 0.32)`
   and a deeper `(0.96, 0.42, 0.15)`. It is the validated prototype's own
   `--route`, already the film's progress dot and strap line, so the film keeps
   one warm accent rather than gaining a fourth.
2. **The glow stays off on dark**, at α0. The question was not inherited: `a58942d`
   retired the pass *because the base was light*, so the acceptance of "the halo is
   gone" did not carry to a dark base. Rendered as an α0 / α0.32 pair; on dark the
   pass works exactly as designed (measured: it lifts the terrain beside the trail
   by `(8,29,29)`, compositing *lighter* than the ground) and he chose the trail
   without it regardless. The mechanism stays, guarded on alpha.

**A correction to this entry's own lineage** (Chiu, 2026-08-29): a parallel draft of
this decision quoted the trail's blue as `(0.13, 0.45, 0.95)`. That is `RecapStyle`'s
**neutral default**, which nothing renders; the shipped `modernMinimal` preset's
trail was the cyan `(0.42, 0.87, 0.98)` measured here. It is the same trap the glow
brief fell into, from the same source, twice — reading a value off the struct's
defaults rather than off the preset the app actually selects.

**Not decided by this entry:** whether the grade, vignette and chrome should also
differ by appearance. They are shared today, reported rather than pre-empted.

---

## 2026-08-27 (b) — The subject shrinks 30%, and the mark's fraction is spent doing it

*A different subject from the same day as the appearance entry above, not an
amendment to it.*

**Decision (Chiu, from stills).** `export.subject_length_px` **225 → 157.5**, and
the seagull mark's `length_fraction` **0.7 → 1.0** so the mark stays the size it
already was. Landed in PR #18.

**Why not a per-vehicle override.** `length_fraction` on a directional subject is
forbidden by `VehicleCatalogTests.testEveryDirectionalSubjectTakesTheConfiguredSize`,
and correctly: `center-sprites.py` equalises apparent size across sets, so an
override would be fighting the tool. car-toy did not look big *as car-toy* — the
subject looked big. The 2026-08-22 car-toy film was **the first film anyone had
watched with a vehicle in it**; every earlier judged film used the seagull, so 225
had never actually been seen in motion.

**Method, deliberately the one that set 225.** Stills at 225 / 180 / 157.5 on one
frame, not a film. 225 was itself Chiu's call from stills at 200/220/250 after a
hard-coded 300 was reported too big (`ConfigLoaderTests` carries that history).

⚠️ **INFERRED, and corrected here before it hardened:** an earlier draft of this
entry asserted that the 2026-08-22 car-toy film was *the first film anyone had
watched with a vehicle in it*. That is not established. What is established is
narrower — the 2026-08-21 reference film's subject was the seagull, and vehicle
sprites predate the subject catalogue (`4c2a9a7`, 2026-08-17), so what the §6a
films of 2026-08-13/14 drew is **UNKNOWN** from this repository. The cheapest
thing that would settle it is the subject named in those films' own log lines, if
they were kept.

### ⚠️ What this spends

`cb14ae8` gave the mark a *fraction* so its size would stay **relative** to the
vehicle: move the vehicle, and the mark follows in proportion. Pinning the fraction
at **1.0 spends that guarantee.** The mark is now simply the same length as a
vehicle.

Today's sizes are unchanged only because the base fell by the reciprocal:

    before   225   × 0.7 = 157.5 px
    after    157.5 × 1.0 = 157.5 px

**So the next time `subject_length_px` moves, the mark moves with it at full rate
and its size becomes a fresh judgement rather than a maintained relation.** That was
the right trade — letting the mark follow this change would have put it at 110.25 px,
**2.25 px below the 112.5 px rejected on 2026-08-18 as too small** — but it is a
guarantee traded away, not a value changed, and it would otherwise have survived
only in a commit message.

`testAnOmniMarkMayDeclareItsOwnProportion` would have gone vacuous at 1.0, so per
`Arch.md` §7.3 its documentation now names the test that still drives the mechanism
with a non-unit fraction. **The mechanism is not deleted — only this subject stopped
using it.**

### The same week went the other way for the other gull, and both were right

PR #22 (2026-08-29) **re-established** exactly the relation this entry spends: the
*fallback* marker's size stopped being an absolute `170` and became
`fallbackMarkerLengthFraction` — a fraction of the subject it stands in for.

The trigger was this entry's own change. With `subject_length_px` at 225 an absolute
170 was 0.756 of the vehicle; when it fell to 157.5 **the stand-in silently became
larger than the thing it replaced**, because nothing tied the two numbers together.

So the codebase now holds **two seagulls sized by opposite mechanisms** — the
choosable sprite pinned at `length_fraction` 1.0, and the vector fallback derived
from the subject. Both are correct for their case: the sprite is *the* subject and
takes the configured size, while the fallback is a stand-in and must never outgrow
what it stands in for. But the pair is a trip hazard, and this is the one place the
two decisions meet, so it is recorded here rather than left to be rediscovered.

⚠️ **Open, and small:** the fallback's fraction is `1` and nothing states *why* 1
rather than the 0.756 that shipped, nor pins it. This repository's own precedent
says a mark's proportion should be both asserted and explained
(`testAnOmniMarkMayDeclareItsOwnProportion`: *"asserted rather than merely allowed,
so changing it is a deliberate edit to this test and not a silent drift"*). Raised
against PR #22 after it merged; a sentence and one assertion close it.

## 2026-08-29 — The fallback marker becomes a badge, and it is one badge for both appearances

*Recorded 2026-08-30, after the fact. It should have been written on the day; see
the note at the end of this entry, which is the process half of the decision.*

**Context.** On 2026-08-28 a render silently drew the vector seagull instead of
the car sprite, and the still survived review because a **white gull on a light
Apple Maps base** is close to invisible (`HANDOFF.md` 2026-08-28 finding 10). The
token's job therefore now includes *being noticed*. A navy sweep followed; Chiu's
verdict on it was that none of the candidates read as blue.

**Decision (Chiu, 2026-08-29), three parts.**

1. **A badge, not a recoloured bird** — a blue disc, a white ring, the gull in
   white. It replaced the colour question rather than answering it.
2. **One badge for both appearances.** The disc and the on-disc colour live on
   `RecapStyle` and neither preset touches them.
3. **The blue is `#1D6FE0`**, and the size is **`fallbackMarkerLengthFraction`
   0.60** of the subject — 94.5 px today.

**Why a pair of colours beats any single one — MEASURED, not argued.** The
badge's own internal contrast is **identical to a decimal across three sizes and
both appearances** (127.9–128.3 in 0–255 units) while the terrain under it moves
183.9 → 81.6. On dark the disc alone is nearly invisible against the ground
(gap 7.5) and the ring carries it (135.8); on light the roles swap (94.8 / 33.5).
**Neither colour suffices alone; the pair does, on both bases.** That is what no
single ink could do, and it is why every navy that cleared the old 0.35 luminance
ceiling was too dark for its hue to register — the target could not be hit.

**The room around `#1D6FE0`, stated as a boundary rather than a value.** Ring and
gull are white, so straddling mid-grey needs the disc below **0.50** luminance;
today's 0.399 has **0.101 of headroom**. Deeper and more saturated is free;
markedly lighter is not. A genuinely light blue is reachable **only by inverting
the pair** (light disc, dark ring) — verified by running the guard, not built.
Recorded so the next person wanting a lighter blue finds the exit rather than a
failing test.

**Why this also closed a structural collision.** `Docs/cross-region-journeys.md`
requirement 4 wants a seagull as the **narrator of an unmodelled crossing** —
"cheap and good-looking rather than a failure state". The fault marker was being
styled in the opposite direction, and a viewer could not tell the two birds
apart. **A badge reads as a marker; a bare bird reads as a bird**, so the
narrator keeps the plain gull and nothing has to be decided about which reading
wins. This is what unblocked the crossing beat's default sprite.

⚠️ **Three gull objects now exist and they are not interchangeable:**
`VehicleMarker.seagull` (the bare vector — **also the end-card brand mark**),
`VehicleMarker.seagullBadge` (the fault marker, never the narrator), and the
`seagull` folder in `vehicles.json` (a choosable omni sprite). Restyling the
first in place would have silently turned the wordmark's bird into a blue disc,
and **no test asserts the brand mark's shape** — that near-miss was caught by a
human reading the call graph.

**The related change that went the other way, deliberately.** PR #22
re-established the relation ADR 2026-08-27 (b) spent: the fallback marker's size
stopped being an absolute `170` and became a **fraction of the subject it stands
in for**. With `subject_length_px` at 157.5 the absolute had made *the stand-in
larger than the thing it replaces*. So the codebase now holds two seagulls sized
by opposite mechanisms, and both are correct for their case — the sprite *is* the
subject and takes the configured size; the fallback is a stand-in and must never
outgrow it.

**Open, and only this:** the **0.60 size**, which Chiu explicitly reserved the
right to revisit **from a film** rather than a still. Marked in
`RecapStyle.fallbackMarkerLengthFraction`'s own comment, where it will be read.
It belongs to the next film review, not to a session of its own.

**Two known limits this decision does not close, both named rather than hidden:**
the guard asserts **token** luminance while the viewer sees the frame **after the
grade** (the disc is 0.399 as a token, 0.349 on screen — the rule survives, but
nothing checks that it keeps surviving); and nothing anywhere asserts the end
card's brand mark. Same class as the golden-frame gates being unable to see
`MapKitSnapshotProvider`.

### ⚠️ Why this entry is dated 2026-08-29 and was written on 2026-08-30

**The decision lived only in `HANDOFF.md` for a day.** That file is by its own
definition "only what is current" and is trimmed regularly — it went from 1,961
to ~915 lines on 2026-08-29 — so these three decisions were one trim away from
being archived out of the ledger the staleness protocol actually reads.

The gap has a specific cause worth keeping. On 2026-08-29 the PO session correctly
resolved that **it must not write an ADR for a decision an engineering session is
actively implementing** (two entries for one decision in an append-only ledger is
worse than none). That rule is right and stands. **It was only half a rule**:
nobody was named to write it afterwards, so nobody did. The other half is now in
`PO.md` — *the session that implements a decision writes its ADR before its PR
merges; a PO session writing one afterwards dates it to the day of the decision
and says why it is late.*

## 2026-08-30 — The second round of outside feedback: shake is a P0, the film gets a frame, and the trip gets a name

**Context.** The second batch of feedback from people other than Chiu, on films
they were given. The first batch (2026-08-15) reordered Phase 4 around the vehicle
request and parked MapLibre. This one is about the film's **motion** and its
**frame** — nobody mentioned colour, which is worth recording on its own, given
that colour is what the previous nine days of merged work was about.

### 1. 🔴 Camera shake / ghosting is a **P0 that blocks submission** (Chiu)

Chiu's words: *"影片晃動感太明顯 不夠流暢 會有殘影 這是上架前最重要一定要解決的問題."*
**This is the highest-priority defect in the project.** It is added to
`Docs/pre-launch.md` item 3 (*export survives*), which until now meant only
lifecycle and performance.

**A mechanism is VERIFIED in code** and the effect is INFERRED from it — nobody
has yet rendered the falsification pair. It is not a new defect but an old
parameter whose premise expired: `keyframe_interval_frames` (15) was sized for the
**static** camera of 2026-07-25, and `FollowCamera` made the camera move on
2026-08-01 without the interval being revisited. Between two snapshots the loop
**alpha-blends two pictures of the same map at different positions**. Full working
and the falsification test are `HANDOFF.md` 2026-08-30 finding 1 — read it before
proposing any fix, because **the obvious fix is wrong**: fine-sampling the whole
body multiplies the snapshot count by ~15, and a 3.5-minute film already costs six
minutes to export.

**Sequencing (Chiu, 2026-08-30): the shake rides with the crossing beat**, rather
than becoming a fourth parallel line. `Docs/eng-session-cross-region.md` step 5
already extends fine sampling for arc windows and therefore already touches this
mechanism. The **real** fix — reprojecting instead of cross-fading — is
camera-arc Pass 1's crop-scaling (`Docs/camera-arcs.md` §7), which follows.

### 2. The film gains an opening and an ending, and the trip gains a name (Chiu)

Four things, decided as a set because they are one impression:

- **Opening zooms in; ending zooms out and ends.** The arc shape this implies is
  already the decided design — `Docs/camera-arcs.md`'s contained arc opens out to
  an apex, translates, and closes in — so a crossing is *zoom out → cross → zoom
  in*, and the opening/ending are the same move at the film's two edges. No new
  camera concept is being introduced here.
- **The user can name the trip, and the name appears at the opening as a
  pop-in title.**
- **The end card carries a trip summary.**
- ⚠️ **The summary is computed statistics, never generated prose.** Not a new
  call — an AI prose diary is already iceboxed (this ledger, 2026-07-20 §; the
  icebox entry stands).

**INFERRED, and it makes this much smaller than it looks:** *the data model
already carries the name.* `Trip.title` is a stored column
(`Core/Persistence/Records.swift`), it already flows to the title card
(`LinearTimeline`: `title = trip.title`), and album imports already use the
album's own name while date-range imports generate one from the dates
(`ImportFlowModel`). **What is missing is an edit surface, not a schema change.**
Verified by reading; no UI work has been attempted.

**Open and genuinely Chiu's**, not to be defaulted by an implementer: whether the
name can be edited *after* import, and what the generated default should be when
there is no album to borrow from.

### 3. 🟠 The opening never establishes *where in the world* — and it is a MapLibre-parking casualty

Reported from a film of a friend's East Australia trip: *"因為可能地圖太大 所以開頭
畫面看不到整個澳洲 就是我之前說的會不知道在哪裡."*

**VERIFIED from code, and it is not a tuning problem.** The opening's country beat
frames `establishing`, which is *only* ever an installed `.pmtiles` region's
extent (`RecapModel:204`). MapLibre was parked on 2026-08-15 and no region is ever
installed, so `establishing` is permanently nil and the country beat has **always**
fallen back to the trip's own bounds × `country_view_padding` (2.2)
(`CameraPathPrologue:70–75`). The film has therefore never shown a country to
anybody; it shows the trip, slightly wider.

**This is the fourth instance of one pattern** — a behaviour tuned for the
MapLibre substrate that silently degraded when Apple Maps became what ships. The
other three: the route glow inverting on a light base, the cyan trail
disappearing into water, and the dashed leg becoming indistinguishable from the
solid one. **The pattern is now named, and a sweep for the rest is owed** — it is
cheaper to look for these deliberately than to keep meeting them one film at a
time.

**Not designed here.** Worth an implementer knowing: Apple Maps is a *global* base
map with no extent limit, and the app already geocodes every stop, so a
country-level frame is **more** reachable after parking MapLibre than before, not
less. `country_view_padding` is a config key and is **not** frozen.

### 4. Recording ships, behind a beta marker (Chiu)

Passive capture is no longer the main line and will be completed in a later phase,
but it stays **usable**, marked as beta so its status is honest in the UI rather
than only in a document.

**This resolves a standing tension rather than creating one.** The spec has always
forbidden MVP copy from claiming 12-day zero-touch capture or imperceptible
battery — those are Capture-Beta-validated promises (spec §1/§7/§10). A beta
marker is that rule made visible. It is also consistent with **honest provenance**,
the same principle that forbids "Verified Trip".

**Focus, stated explicitly (Chiu):** the photo-import path is the subject now;
recording is discussed later. A recorded-trip log exists and is deliberately not
being worked yet.

### 5. Device evidence, from two other people's phones (Chiu, owner report)

- ✅ **"A crash-free export across three trips" — PASSED.** One of the two §6b
  items `Docs/pre-launch.md` calls the ones that actually bite. Closed by owner
  report; no log was kept, and none is reconstructed.
- ❌ **Per-trip export time was not recorded.** It stays open, and it is not
  bookkeeping: it is the **input to pre-launch item 5** (the export-time
  estimate). Capture it in the next device session.
- The other §6b items — Limited Photo Library on hardware, S5 UX pass, memory at
  full frame count — remain unrun.

### What this entry does **not** decide

The **shake's fix** (only its priority and its owner). The **camera-arc Pass 1**
schedule beyond "after the crossing". The **badge's 0.60 size**, still reserved
for a judgement from a film (ADR 2026-08-29). Whether the **grade, vignette and
chrome** should differ by appearance (ADR 2026-08-27 left it open and it stays
open). Nothing here reopens a locked decision.

## 2026-08-31 — The opening cuts out of a title card, and the frame it cuts out of is the country

**Context.** The opening had never once shown a country. `establishing` is only
ever an installed `.pmtiles` region's extent, MapLibre was parked on 2026-08-15,
and nothing has installed one since — so the "country" beat had always been *this
trip's own bounds × `country_view_padding` (2.2)*, which on a compact trip inside
a large country says nothing. That is the reported *"看不到整個澳洲… 不知道在哪裡"*.

**And the opening was worse than merely mis-framed — MEASURED 2026-08-31.** The
"country" beat and the "region" beat are **the same picture at two paddings, on
every trip**: 685.0 → 467.1 km on `ishigaki-crossing` is a ratio of **1.4667×**,
which is exactly `country_view_padding / wide_span_padding` = 2.2 / 1.5, and
Miyakojima reproduces the identical figure (69.5 → 47.4 km). The film spent
**2.5 seconds and 148 moving frames easing between two frames a viewer cannot
tell apart.**

**The structural fault underneath both faces.** `RecapDurationPlan.bodySpanM`
divides the span of the opening's **first** beat. One number was doing two
incompatible jobs — the "where in the world is this" establishing shot *and* the
divisor that sets how tightly the destination is framed — chained by
`target_zoom_ratio`. **You could not widen the country without smudging the
destination.** The destination smudge and the missing country were one defect
seen from two ends.

### Decision (Chiu, 2026-08-31)

1. **Beat 1 is a title card over a HELD country frame**, carrying the country
   name and the place name as **text**, and it **cuts** to beat 2. A cut costs no
   continuity here because the viewer reads a title card as *chrome*, not as
   camera — the film convention, in Chiu's words: *"就像電影一樣不會有沒有連續的
   問題."*
2. ⚠️ **The cut lands as the title leaves.** Title on screen = chrome, and a cut
   reads as convention. Title gone, then a jump a moment later = a bug.
3. **Beat 2 onward is the film proper and obeys continuity in full** —
   continuous zoom, no cuts, no gate exemptions.
4. **Beat 2's frame is never a label.** The recognisable name was spent on the
   title card.
5. **The frame is the COUNTRY, not the smallest containing named unit.** The PO
   session recommended the latter (Iceland → Iceland, Miyakojima → the island,
   a Sydney trip → New South Wales) and **Chiu overruled it on recognisability**:
   *"我不認為使用者或他的觀眾會認得出來 New South Wales 是哪裡."* The correction
   is right and the PO recommendation had conflated two things — **what to frame**
   and **what to call it**. Splitting them gives both: the country is recognisable
   as a *name*, and beat 2 supplies the scale as a *picture*.
6. **The same change applies to purely local trips**, because the 1.4667×
   non-move is provable on every trip, so the ease was buying nothing anywhere.

**This is why the cut is a fix and not a preference:** once beat 1 is cut out of,
its span no longer has to be continuous with anything, so `bodySpanM` divides
**beat 2's** span instead. That breaks the chain above. The product decision and
the measurement arrived at the same place independently.

### The country's extent comes from a built-in table — and §0 is the reason

**Chiu chose a table over asking MapKit or `CLGeocoder`**, on a point the design
had not foreseen and the implementing session raised:

> A geocoded country lookup would send **a real coordinate off-device in order to
> draw a wider opening** — a new §0 exception beyond routing and one share, and
> therefore a product decision rather than an implementation detail.

He declined to open one for framing. The table also happens to be the only option
that satisfies *"a film must render with no network"* on its own; every Apple API
that returns a country extent is a round trip. `Core/ExportEngine/CountryExtent.swift`
is `import Foundation` only, the lookup is point-in-box against a constant, and
`Locale.localizedString(forRegionCode:)` supplies the name in the viewer's
language offline. **No persistence change was needed after all.**

⚠️ **A country whose single bounding box would be a lie is left out, not
approximated** — one box for the United States spans Alaska to Florida. That is
honest provenance (spec §0) applied to geography: a frame Kamome cannot draw
truthfully it does not draw.

### Measured result

`ishigaki-crossing`, shipped path: opening **9.0 → 6.5 s**; beat 1
**685 km (trip × 2.2) → 285.6 km (Taiwan)**; beat 2 467.1 → 50.1 km; body span
**274.0 → 20.0 km**, 13.7× tighter. The opening's moving frames **148 → 74** —
exactly the ease that went. The two beats are now 5.7× apart on this trip and 44×
on Miyakojima; the 1.4667× non-move is gone.

**The continuity gate stays honest about the cut without an exemption.** It
asserts the card beat is a *still frame* — ground overlap 1.0 to 1e-9 for every
frame before the cut — and then scans everything after it with nothing forgiven.
If the card beat ever moves, the gate **fails rather than skips**, which is the
whole difference between this and an excused window. 0 violations, 0 excused, all
seven fixtures.

### Deferred, and one deviation recorded rather than overruled

- **`CameraPath.openingRoute` frames the local journey the body camera *starts
  in*, not the destination** — a deviation from Chiu's literal instruction,
  reported under `Arch.md`'s deviation rule and **left standing on his ruling.**
  Measured: framing the destination puts beat 2 275 km from where the body
  starts, so the closing zoom would travel **273 km across a 33.3 km frame** —
  8.2 frame-widths, 69 gate violations, and a film that shows the destination,
  jumps back to the origin, drives, then flies to the destination it already
  showed. The implementing session's reading is the correct one: *"the premise is
  true of the film you want and not of the film that exists."* It **self-resolves**
  — the 2026-09-01 type-2 form drops the origin's drive, and beat 2 then *is* the
  destination.
- **The title card still shows trip title + dates, not the country name.** The
  name is available offline; wiring it in is composer plus chrome layout, and is
  a DESIGNER question.

## 2026-08-31 (b) — The P0 is closed: the loop reprojects one snapshot instead of cross-fading two

*Closes the P0 opened by ADR 2026-08-30. A different subject from the opening
entry above, on the same day.*

**The fix is not a smaller interval — it is not cross-fading.** `RecapRenderLoop`
no longer blends two snapshots taken at different positions. `RecapSnapshotStations`
plans **stations** — one snapshot per run of frames — and every frame is produced
by *reprojecting* that station onto its own camera. A reprojected frame is
geometrically exact, so there is no mismatch to bound and nothing to fine-sample
against.

**Judged, not calculated.** Chiu watched the interval-15 / interval-1 pair and
chose interval 1, which made *"the body must look like interval 1 and must not
cost interval 1"* the acceptance bar rather than a theory. Measured against an
interval-1 reference, `miyakojima` body 20–30 s:

| | travelling | **frame-to-frame swing** | snapshots |
|---|---:|---:|---:|
| shipped cross-fade | 2.005 | **1.402** | 191 |
| crop-scaling, `magnification` 1.10 + hold splits | 1.061 | **0.747** | 55 |

**The swing is the column that answers 晃動** — shake is a *change* frame to
frame, and reprojection error has no temporal structure.

**Stop beats are pixel-exact again, for +10 snapshots.** Stations split at each
hold's boundaries and at the frame the dolly settles inside it, so a parked camera
gets its own station at magnification ~1.0 (0.585 → 0.046). Threshold-free: the
holds are a fact the story layer already states.

**Accepted as it stands (Chiu, adopting the PO recommendation): the residual
0.747 is left alone.** It is half the cross-fade's figure, it is a sharpness
*step* rather than a double image, and it is localised at exactly the two hold
boundaries where a pixel-exact parked station abuts a magnified travelling one.
`Docs/camera-arcs.md` §7's remedy — cross-fading *at a station boundary* — costs
no extra fetches and can be added if anyone notices it in a film. **Not built.**

**`snapshot_station_max_magnification` is 1.1, not §7's reasoned 1.5.** §7 priced
it for an arc, a large zoom, and had never priced it against a body camera that
pans; the value was chosen from a rendered cost/sharpness curve.

### What the whole round cost, honestly

| | shipped | + crop-scaling | + the opening |
|---|---:|---:|---:|
| `ishigaki-crossing` snapshots | 367 | 51 | **178** |
| wall clock | 1216 s | — | **219 s** |

⚠️ **The intermediate 51 was cheap because the destination was still a smudge** —
a 274 km body span barely moves relative to its own window, so stations lasted.
Framing the destination properly costs snapshots and no rendering cleverness
changes that. Net against what ships: **2.1× fewer snapshots and 5.6× less wall
clock**, with the ghosting gone, stop beats exact, a real country shot and a 13.7×
tighter destination.

### The process finding worth more than the fix

The session first reported that a 70-second render was killed on this machine and
that a control run on `main` reproduced it, concluding the fault was pre-existing.
**Chiu rejected that from direct experience** — he has watched 3-, 5- and
10-minute films rendered here — and the claim collapsed: all six failures fell
inside one five-minute window in which **six `xcodebuild` processes were competing
for one simulator.** In the session's own words:

> It wasn't a control — it was confounded in precisely the same way. **A control
> that shares the confound manufactures confidence instead of removing it**, which
> is worse than having none.

Two things follow, and both are cheap to remember: **run one render at a time**,
and **a control run must be shown not to share the suspected confound** before it
is allowed to close a question.

## 2026-09-01 — Kamome's films are three types, and the film ends where the trip does

**Context.** Chiu watched whole films of the crossing work and separated what had
been one undifferentiated "cross-region" problem into three shapes.

### Decision (Chiu, 2026-09-01)

**Three types. Build 1 and 2; defer 3.**

1. **Local only** — one region, no crossing. Ships today.
2. **Home → one destination abroad** — fly out, then the trip at the destination.
   *"假設這樣的行程只會有出發機場照片，從機場出發後到當地，再銜接到當地行程."*
3. **Multi-region / multi-country** — several crossings. **Deferred to a later
   phase.**

**Why the deferral costs nothing.** Type 3 is a *loop over* type 2, not a new
mechanism — `Docs/cross-region-journeys.md`'s own reframing is "N local journeys
joined by discontinuities", so type 1 is N=1, type 2 is N=2, and type 3 is N>2.
Building 2 properly is what makes 3 cheap. ⚠️ **`ishigaki-crossing` renders a
type 3 today** (it contains the Taipei drive *and* the crossing *and* Ishigaki);
Chiu keeps it deliberately as the type-3 reference film.

**The film ends at the destination. There is no return flight.** The import
carries the homeward leg and its photographs; the film does not. The trip's last
stop at the destination is the ending, and the end card closes it. Reasoning
adopted from the PO session: the film is about the journey, not the logistics,
and flying home after the memories is an anticlimax.

### How a film knows its type — the rule, and the two holes it avoids

**Count distinct local journeys, folding a return to a region already visited.**
Not crossings, and not countries. Both obvious signals have a real
counter-example in this project's own material:

| signal | breaks on |
|---|---|
| counting **crossings** | Taiwan → Japan → Taiwan is **two** crossings and **one** destination |
| counting **countries** | Tokyo → Miyakojima is **one** country and is still a type 2 — *Chiu's own trip* |

`SegmentRoutability.noRoad` already partitions a trip into local journeys, so the
rule is nearly free. The verdict belongs with the **trip**, not the renderer —
the same category as `stop.kind` and `segment.routability`, with the same
discipline: stored, forward-only, and "unknown" meaning something explicit rather
than defaulting to a type. `CountryExtent` may help *name* a region; **the country
is not the identity**, per the Miyakojima row above.

### ⏳ OPEN — does a type-2 film draw the flight? Gated on a measurement

Chiu's two candidates, **not yet chosen**:

- **Option 1 — the flight is not drawn.** The title card sits over a frozen frame
  of the destination country with the trip title and dates, and cuts straight
  into the local trip.
- **Option 2 — the flight is drawn** over a frame containing **both** places, and
  the film then arrives at the destination.

Within option 2 the PO recommendation is to **hold the camera still and move the
plane**, rather than following the plane with the camera: after crop-scaling a
static camera costs **one snapshot at any span**, it passes both continuity gates
trivially, and it is the universal airline-route-map language — whereas a camera
translating ~10,000 km is either a very long shot or the 2026-08-02 strobing
defect rebuilt. The arrival is then the contained arc's closing half, which
already exists.

⚠️ **The choice is blocked on a fact nobody has: can MapKit render a long-haul
frame at all?** Every option-2 variant needs one frame holding two places, at
spans up to ~9,800 km, where Mercator distorts badly between distant latitudes. A
probe at four spans (Taipei → Ishigaki / Tokyo / Sydney / Paris) is the cheapest
thing that settles it, and **the answer may be scale-dependent** — a near pair
legible and pleasant, a far pair ten seconds of a plane crossing empty ocean. If
so the boundary becomes a config threshold with the frozen card past it, and
**Chiu picks the number.**

**Not decided by this entry:** the flight question above; the title card's text
(it still shows trip title + dates, not the country name); the badge's 0.60 size,
still reserved for a judgement from a film (ADR 2026-08-29).
