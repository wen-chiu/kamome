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
