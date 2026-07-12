# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.2). Read it before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device.

## Current phase: 0 — Skeleton (in progress)

Gate criteria (spec §7 Phase 0, verbatim):

> **Gate:** `xcodebuild -scheme Kamome test` green; `swiftlint` clean; schema
> round-trip test (insert/read 50k trackpoints < 2 s in-memory).

## Verification commands (run from repo root)

```bash
xcodegen generate
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 16'
swiftlint
```

The `.xcodeproj` is generated — never hand-edit it; change `project.yml` and
re-run `xcodegen generate`.
