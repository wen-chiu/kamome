# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.2). Read it before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device.

## Current phase: 2 merged (PR #4, 2026-07-15) — two manual gate items open

Phase 2 gate: unit tests ✅ (photo→stop incl. conflict cases), S3 screenshot ✅
(`Docs/demos/phase2/`), **limited-photo-access manual check ⬜ (Chiu, on
device: choose "Selected Photos" and confirm matching + placeholders work)**.

**Phase 1 device test also still open** — 2 h drive per
`Docs/device-test-P1.md`, Chiu signs off. Both manual items are hard
preconditions for Phase 3 (`Docs/decisions.md`, 2026-07-12).

Phase 3 (recap video, spec §4.5/§7) starts only after both boxes are ticked.

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
