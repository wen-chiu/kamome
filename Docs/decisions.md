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

## 2026-07-12 — Config loader module is `Core/ConfigLoader`, not `App/`

**Context:** Spec §8 lists "config loader" under `App/`. A loader inside the
app target cannot be unit-tested without booting the app, and Phase 1+ core
modules will need typed config without importing the app.
**Decision:** Types + parsing live in `KamomeConfig` (`Core/ConfigLoader/`);
`App/` keeps only the startup wiring (`AppConfig.loadOrDie()`), which is where
"fail loudly at launch" happens.
**Rejected:** loader entirely in `App/` per the letter of §8.
