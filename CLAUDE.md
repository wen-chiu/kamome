# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.2). Read it before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device.

## Current phase: 1 — Tracking Engine (unit gates pass; device gate pending)

Phase 0 gate passed locally + CI 2026-07-12 (`Docs/demos/phase0/gate-output.md`);
PR #1 awaiting review/merge.

Gate criteria (spec §7 Phase 1, verbatim):

> - Replaying `perth_margaret_river_day1.gpx` yields exactly 4 stops (±0),
>   ≥ 2 drive segments, ≥ 2 walk segments; assert in unit test.
> - `city_walk_flapping.gpx` produces ≤ 1 spurious segment.
> - Physical device test (manual, checklist in `Docs/device-test-P1.md`):
>   2 h real drive, battery drain measured, route visually continuous.
>   **Chiu signs off on this gate.**

## Verification commands (run from repo root)

```bash
xcodegen generate
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 15'
swiftlint
```

(Local Xcode is 15.4 → destination iPhone 15; CI uses iPhone 16 on Xcode 16.)

The `.xcodeproj` is generated — never hand-edit it; change `project.yml` and
re-run `xcodegen generate`.
