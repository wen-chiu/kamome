# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.2). Read it before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device.

## Current phase: 0 — Skeleton (gate passed locally 2026-07-12; PR + CI pending)

Gate criteria (spec §7 Phase 0, verbatim):

> **Gate:** `xcodebuild -scheme Kamome test` green; `swiftlint` clean; schema
> round-trip test (insert/read 50k trackpoints < 2 s in-memory).

Gate output: `Docs/demos/phase0/gate-output.md`.

## Verification commands (run from repo root)

```bash
xcodegen generate
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 15'
swiftlint
```

(Local Xcode is 15.4 → destination iPhone 15; CI uses iPhone 16 on Xcode 16.)

The `.xcodeproj` is generated — never hand-edit it; change `project.yml` and
re-run `xcodegen generate`.
