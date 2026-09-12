# Phase 3 demo — recap video (§4.5)

## Removed artifacts

The following files were removed 2026-09-12 because they published Apple Map
Data (MKMapSnapshotter imagery) in a public repository, in violation of Apple's
Developer Program License Agreement Attachment 6 §§2.3, 2.5 (ADR 2026-09-12).

| file | what it was | what it proved | rendered |
|---|---|---|---|
| `kamome-p3-recap.mp4` | 30 s recap film of the perth\_margaret\_river\_day1 fixture, 1080×1920@30 H.264 @ 5 Mbps, rendered end-to-end through CameraPath → RecapRenderLoop → MKMapSnapshotter → RecapFrameCompositor → RecapVideoEncoder | The Phase 3 gate: the pipeline produces a watchable film from a fixture | 2026-07-19 |
| `still-title-card.png` | Title card frame from the P3 film | Title card layout and chrome | 2026-07-19 |
| `still-stop-card.png` | Mandurah stop card frame (day badge) | Stop card layout, day badge, and photo deck | 2026-07-19 |
| `still-end-card.png` | End card frame (stats + "Get this route" QR) | End card layout and stats display | 2026-07-19 |

The tombstone is the record of what was measured. A re-render on the new
substrate (OpenFreeMap + MapLibre, ADR 2026-09-09) is optional rather than
owed (ADR 2026-09-12).

## Historical context (preserved from the original README)

The film was rendered 2026-07-19 on the iPhone 17 Pro simulator in **34.6 s**
(real map tiles, snapshot prefetch on).

Known visual limitation (expected): the route cut across Geographe Bay and
clipped shorelines — sparse fixture sampling + straight-line interpolation.
OSRM map matching (§4.4, P4 core) snaps it to roads; do not tune sampling
for this (decisions.md 2026-07-16).

Post-scriptum (P3.5 §1, 2026-07-19): the bay crossing turned out to be the
*fixture's own* straight-line geometry, kilometers off-road — §4.4 matching
correctly refuses to invent a route for it (confidence gate). The fixture
has since been regenerated with road-matched drive legs
(`generate_fixtures.py route_leg`); this artifact predates that and was kept
frozen as the P3 baseline / the "before" of
`Docs/demos/phase3_5/matching/`.
