# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.2). Read it before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device.

## Current phase: 1 merged on unit gates; device gate DEFERRED, due before Phase 3

Phase 0 gate passed 2026-07-12 (`Docs/demos/phase0/gate-output.md`, PR #1 merged).
Phase 1 unit gates passed in CI (PR #2); the physical device test (2 h drive,
battery, route continuity — `Docs/device-test-P1.md`) was deferred by owner
decision 2026-07-12 (see `Docs/decisions.md`) and **must pass, with Chiu's
sign-off, before any Phase 3 work starts**. Prerequisite for the drive:
Always-permission priming + background location flow.

## Verification commands (run from repo root)

```bash
xcodegen generate
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 15'
swiftlint
```

(Local Xcode is 15.4 → destination iPhone 15; CI uses iPhone 16 on Xcode 16.)

The `.xcodeproj` is generated — never hand-edit it; change `project.yml` and
re-run `xcodegen generate`.
