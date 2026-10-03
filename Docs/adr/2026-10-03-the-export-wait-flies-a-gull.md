# While a film renders, the brand gull flies the bar's own progress

**Status:** Decided (Chiu, 2026-10-03)
**Supersedes:** nothing. Fills the space S5 review 2026-09-25 item 2 cleared (the settings fold away while rendering)

## Context

Chiu, 2026-10-03: *「在export影片的時候 中間有空白 我們可以設計一個可愛海鷗在飛行的動畫填滿
讓除了下面的progress bar還可以知道系統在還跑 這樣會增加程式負擔跟輸出時間嗎？」* (#216).

- VERIFIED (`RecapView.exportForm`): while rendering, the form above the docked bar is empty unless a notice shows.
- VERIFIED (`RecapExportJob+Render.swift`, `runDetached`): the frame loop runs in a detached task and sends
  progress to the main actor at most ~10 times a second. **But the main queue is not free:** VERIFIED
  (`MapLibreSnapshotProvider.swift`), the snapshotter is run-loop bound and driven from the main queue. A
  SwiftUI animation, evaluated on the main actor every display frame, would compete with it.
- A looping animation proves the *app* is alive, not the *render*: it keeps flying through a stuck snapshot.
  Before the first frame (roads, iCloud photos, #162) the bar sits at 0 for the longest stretch.

## Decision

Chiu, on the proposal: *「海鷗由你來畫」*, *「綁真實進度 好」*.

1. **The bird is the brand's.** The double-arc gull of the app icon and `VehicleMarker.seagull`, over the icon's
   dotted route and three stops — a copy of the path in `UI/Recap/ExportGullView.swift`, so the film's marker is
   never restyled by it (`HANDOFF.md`).
2. **Two signals, kept apart.** The wings always beat (the app is alive). The gull's *position* is the bar's frame
   progress and nothing else: it waits over the first stop until frames start, and never runs ahead of the bar.
3. **No app code per display frame.** The flap is a Core Animation keyframe animation on a `CAShapeLayer`
   (the render server interpolates it); the gull and route move only when progress does, without easing.
4. **Decorative.** Hidden from VoiceOver (the bar carries the number). Reduce Motion holds the brand pose.

## Rejected

- **Lottie, a GIF or a video loop:** a dependency, or a decoder competing with `AVAssetWriter`.
- **A SwiftUI animation (an animatable `Shape`, `TimelineView`, `keyframeAnimator`):** built first; it
  rebuilds the path on the main actor every display frame, beside the map snapshotter.
- **Spreading the position over roads and photos too:** those stages have no fraction, so the gull would move
  on a guess, and jump when photos are skipped.
- **Perching the gull when progress stalls:** the screen cannot tell slow from stuck; a stuck snapshot already
  fails loudly at its deadline (`SnapshotDeadline`).

## Consequences

- `UI/Recap/` only, plus `RecapModel.drawingFraction`. Nothing in `ExportEngine`, the coordinator or the
  render loop changes (VERIFIED, diff).
- Export cost, desk A/B (iPhone 17 Pro simulator, demo trip, 1800 frames, alternating, while other sessions
  held the Mac at load 190–350): app CPU 261 / 223 s with the gull, 240 / 247 s without; render server
  17.2 / 9.0 s against 9.7 / 8.4 s. INFERRED: no cost above the noise, which is ±20 s of CPU and larger in
  wall time (60–230 s for the same film).
- UNKNOWN: the cost on a phone, where the GPU is shared with the map snapshots. Settled by the same A/B on the
  phone (#112).
