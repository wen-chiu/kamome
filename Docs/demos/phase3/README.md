# Phase 3 demo — recap video (§4.5)

`kamome-p3-recap.mp4` — the perth_margaret_river_day1 fixture rendered
end-to-end through the shipping pipeline (CameraPath → RecapRenderLoop →
MKMapSnapshotter tiles → RecapFrameCompositor → RecapVideoEncoder): 30 s,
1080×1920@30, H.264 @ 5 Mbps. Stills: title card, Mandurah stop card
(day badge), end card (stats + "Get this route" QR — encodes
`kamome://route/demo`, the P3 placeholder payload until P6/P7).

Rendered 2026-07-19 on the iPhone 17 Pro simulator in **34.6 s** (real map
tiles, snapshot prefetch on). The GIF twin (22 MB) is not committed —
regenerate both with:

```bash
TEST_RUNNER_KAMOME_DEMO_RENDER=1 TEST_RUNNER_KAMOME_DEMO_OUT=/tmp \
xcodebuild -scheme Kamome test \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:KamomeCoreTests/RecapBudgetAndDemoTests/testRenderDemoArtifact
```

Known visual limitation (expected): the route cuts across Geographe Bay and
clips shorelines — sparse fixture sampling + straight-line interpolation.
OSRM map matching (§4.4, P4 core) snaps it to roads; do not tune sampling
for this (decisions.md 2026-07-16).
