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

## 2026-07-12 — Config loader module is `Core/ConfigLoader`, not `App/`

**Context:** Spec §8 lists "config loader" under `App/`. A loader inside the
app target cannot be unit-tested without booting the app, and Phase 1+ core
modules will need typed config without importing the app.
**Decision:** Types + parsing live in `KamomeConfig` (`Core/ConfigLoader/`);
`App/` keeps only the startup wiring (`AppConfig.loadOrDie()`), which is where
"fail loudly at launch" happens.
**Rejected:** loader entirely in `App/` per the letter of §8.
