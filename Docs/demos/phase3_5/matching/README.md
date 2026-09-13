# Phase 3.5 §1 — map matching before/after (handoff §1 item 3)

## Removed artifacts

The following files were removed 2026-09-12 because they published Apple Map
Data (MKMapSnapshotter imagery) in a public repository, in violation of Apple's
Developer Program License Agreement Attachment 6 §§2.3, 2.5 (ADR 2026-09-12).

| file | what it was | what it proved | rendered |
|---|---|---|---|
| `before-p3-artifact.png` | Frame from the frozen P3 demo film: the camera in the middle of Geographe Bay, route line crossing open water between Bunbury and Busselton | The "before" of §4.4 matching — raw fixture geometry sat kilometers off-road | 2026-07-19 |
| `after-matched.png` | The same journey exported with §4.4 matching active against the local OSRM WA server: the replay rides Bussell Hwy, takes the roundabout, and curves onto Causeway Rd into Busselton (worst chunk confidence ≈ 0.98, gate `confidence_min` 0.5 untouched) | The "after" of §4.4 matching — no open-water crossing; every drive segment carries a `matched_polyline` | 2026-07-22 |

Both frames were Apple Maps cartography rendered via MKMapSnapshotter.
`after-matched.png` was VERIFIED by inspection: unmistakable Apple Maps styling
with " Maps" logo at bottom-left.

The tombstone is the record of what was measured. A re-render on the new
substrate (OpenFreeMap + MapLibre, ADR 2026-09-09) is optional rather than
owed (ADR 2026-09-12).

## Historical context (preserved from the original README)

Two things changed between the frames, deliberately:

1. **The perth fixture was regenerated with road-matched drive legs**
   (`generate_fixtures.py route_leg`). §1 validation exposed that the old
   fixture's straight anchor-to-anchor legs sat kilometers off-road — the bay
   crossing was the fixture's own geometry, and the §4.4 confidence gate
   *correctly* refused to invent a route for it (fallback to raw is the designed
   behavior for implausible traces; the gate was not loosened). Matching can only
   be validated end-to-end on a trace that plausibly came from a road trip.
2. **`matching.base_url` pointed at the local OSRM** (dev-only, shipped default
   stays `""`).
