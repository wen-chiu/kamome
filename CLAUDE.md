# Kamome — boot file for Claude Code sessions

Kamome (卡摸咩) is a **memory engine for road trips**: import or capture a
journey once, then turn it into a cinematic recap film (MP4) worth keeping and
sharing. Product reference: `Docs/kamome-poc-spec.md` (v1.8 — what Kamome *is*,
not a status report; later ADRs in `Docs/decisions.md` override its stale
status text).

**Current phase: 4 — films worth keeping** (vehicle sprites → cross-region
crossing → export that survives). Phase 3.5 (Replay MVP) **CLOSED 2026-08-15**:
§6a passed, §6b's unmet items moved to Phase 2 (App Store release,
`Docs/pre-launch.md`). Later: P5 Capture Beta, P6 Plans, P7 backend.

## Session-start reading order

1. **`Docs/current-state.md`** — the snapshot: phase, boundaries, locked
   decisions, active work, deferred items. **Staleness check first:** its
   "Last synced" line must name the newest ADR in `Docs/decisions.md`; if it
   does not, the file is stale, `decisions.md` wins, and you report the
   staleness before proceeding.
2. Your charter: `Arch.md` (engineering session) or `PO.md` (product-owner /
   governance session).
3. `HANDOFF.md` — live findings, open experiments, known bugs. Current only.
4. The task doc your work names (pointer map in `Docs/current-state.md`).

**Do not treat historical documents as current state.** `Docs/decisions.md` is
append-only — the newest entry on a subject wins over any older entry, any
handoff, and this file. Closed HANDOFF/CLAUDE history lives in
`Docs/_archive/handoff-2026-08.md` and is never a work instruction.

## Critical standing rules

- **§0 — Location data never leaves the device by default** (Chiu 2026-08-03).
  A user's real trip, route or location history is never logged off-device,
  synced, sent to analytics or crash reporting, or **committed to this repo**
  (real dumps live only in gitignored `Tests/Fixtures/trips/local/`;
  `KamomeLog` may name *which* stop failed, never its coordinates). If a
  feature needs real coordinates to leave the device, that is a product
  decision for Chiu, never an implementation detail.
  **Decided exceptions** (explicit owner decisions — `Docs/decisions.md`
  2026-08-16 and 2026-08-20 (b)/(c)): routing sends real trip leg coordinates
  to Geoapify (photo-imported trips, walks included; recorded traces for
  map-matching), and one user-initiated share of one trip. Honest disclosure
  is the decided posture (`Docs/pre-launch.md` item 7).
- **Rules of Engagement** (spec §0): phase gates are hard gates; **no magic
  numbers** — all tunables in `Config/TrackingConfig.json`; boring tech; demo
  artifact per phase; flag anything needing the physical device; **honest
  provenance** (never "Verified Trip"; recorded vs reconstructed-from-photos
  is a product rule; a wrong road is never drawn as fact).
- **Never write an assumption as though established** — mark VERIFIED /
  INFERRED / UNKNOWN beside claims in documents, and name the cheapest thing
  that would settle each (PO.md, Chiu 2026-08-20).
- Do not reopen locked decisions (register in `Docs/current-state.md`; the
  reopening rule is `PO.md` §"Reopening a Locked Decision").

## Verification commands (run from repo root)

```bash
xcodegen generate
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
swiftlint
```

(Local Xcode is 26.6 → destination iPhone 17 Pro; CI auto-picks its simulator.
swiftlint locally needs `XCODE_DEFAULT_TOOLCHAIN_OVERRIDE=/Library/Developer/CommandLineTools`
— Rosetta swiftlint can't load Xcode 26's arm64-only SourceKit.)

The `.xcodeproj` is generated — never hand-edit it; change `project.yml` and
re-run `xcodegen generate`.

## Desk harnesses — `TEST_RUNNER_` env (fixed 2026-08-15)

```bash
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:KamomeTests/RecapTimelineReportTests TEST_RUNNER_KAMOME_TIMELINE_REPORT=miyakojima
```

On this toolchain, xcodebuild turns `TEST_RUNNER_FOO=bar` into a **build
setting**, and scheme environment values expand build settings — so
`project.yml` declares each harness variable as `$(TEST_RUNNER_<VAR>)`. Two
consequences: an unset variable arrives as a defined **empty string** (harnesses
must read it through `HarnessEnv.value`, which collapses empty to nil), and
adding a harness variable means adding a line to `project.yml`, or it can never
be set.
