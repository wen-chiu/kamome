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
