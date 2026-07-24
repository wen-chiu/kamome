# Phase 3.5 §1 — map matching before/after (handoff §1 item 3)

**before-p3-artifact.png** — frame from the frozen P3 demo
(`Docs/demos/phase3/kamome-p3-recap.mp4`): the camera is in the middle of
Geographe Bay, route line crossing open water between Bunbury and
Busselton.

**after-matched.png** — the same journey (same anchors, stops, schedule)
exported through the real app pipeline with §4.4 matching active against
the local OSRM WA server: the replay rides Bussell Hwy, takes the
roundabout, and curves onto Causeway Rd into Busselton — no open-water
crossing; every drive segment carries a `matched_polyline` (worst chunk
confidence ≈ 0.98, gate `confidence_min` 0.5 untouched).

Two things changed between the frames, deliberately:

1. **The perth fixture was regenerated with road-matched drive legs**
   (`generate_fixtures.py route_leg`, this commit). §1 validation exposed
   that the old fixture's straight anchor-to-anchor legs sat kilometers
   off-road — the bay crossing was the fixture's own geometry, and the
   §4.4 confidence gate *correctly* refused to invent a route for it
   (fallback to raw is the designed behavior for implausible traces; the
   gate was not loosened). Matching can only be validated end-to-end on a
   trace that plausibly came from a road trip.
2. **`matching.base_url` pointed at the local OSRM** (dev-only, shipped
   default stays `""`).

How the "after" was produced (matching disabled exports the raw-geometry
"before" twin of the same trip):

```bash
TEST_RUNNER_KAMOME_MATCHING_E2E=1 TEST_RUNNER_KAMOME_E2E_OUT=/tmp \
xcodebuild -scheme Kamome test \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:KamomeTests/RecapMatchingE2ETests
```

(The `-demo-seed` trip is intentionally not used: its thinned 11-point
route sits below `matching.confidence_min` and falls back to raw geometry
by design.)

Frames extracted with zero-tolerance `AVAssetImageGenerator`.
