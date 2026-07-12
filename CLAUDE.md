# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.2). Read it before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device.

## Current phase: 2 — Stops, Photos, Trip Detail

Phase 0 + 1 merged (unit gates in CI). **Phase 1 device test is deferred, not
done** — 2 h drive per `Docs/device-test-P1.md`, Chiu signs off, hard
precondition for Phase 3 (`Docs/decisions.md`, 2026-07-12).

Gate criteria (spec §7 Phase 2, verbatim):

> **Gate:** unit tests for photo→stop assignment (timestamp-only, GPS,
> conflict cases); a seeded demo trip renders S3 with photos on correct pins
> (screenshot in demo folder); limited-photo-access path manually verified.

## Verification commands (run from repo root)

```bash
xcodegen generate
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 15'
swiftlint
```

(Local Xcode is 15.4 → destination iPhone 15; CI uses iPhone 16 on Xcode 16.)

The `.xcodeproj` is generated — never hand-edit it; change `project.yml` and
re-run `xcodegen generate`.
