# Phase 3.5 demos

## Removed artifact

The following file was removed 2026-09-12 because it published Apple Map Data
(MKMapSnapshotter imagery) in a public repository, in violation of Apple's
Developer Program License Agreement Attachment 6 §§2.3, 2.5 (ADR 2026-09-12).

| file | what it was | what it proved | rendered |
|---|---|---|---|
| `kamome-recap-NZ-disaster.MP4` | A device-recorded recap film of Chiu's New Zealand trip, rendered via MKMapSnapshotter (no .pmtiles region installed, so RecapExportJob's provider fell back to MapKit) | A real-trip film exported on a device — and the "disaster" that motivated the Phase 3.5 visual pivot | circa 2026-07-19 |

The frame was VERIFIED by extraction: Apple Maps satellite/hybrid cartography
with " 地圖" (Apple Maps) at bottom-left.

This was also one of two committed films of Chiu's real trips (§0 owner
question since 2026-08-30, HANDOFF.md "⏳ Awaiting Chiu"). The other is the
Phase 3 demo (`Docs/demos/phase3/kamome-p3-recap.mp4`, also removed in this
PR). Both are now removed, and current practice writes films to
`~/Kamome-films/` outside the repository. The §0 owner question is closed by
this PR.

The tombstone is the record of what was measured. A re-render on the new
substrate (OpenFreeMap + MapLibre, ADR 2026-09-09) is optional rather than
owed (ADR 2026-09-12).

## Remaining contents

- `import/` — import-flow screenshots (Kamome UI with MapKit live view; Apple
  notices legible)
- `matching/` — §4.4 map matching before/after (files removed, tombstones in
  its README)
- `modern-minimal/` — MapLibre renders of OSM data (not Apple Map Data)
- `substrate/` — export substrate evaluation renders
