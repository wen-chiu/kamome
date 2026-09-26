# Export performance — what it costs, and what that is made of

**Opened 2026-09-22.** Chiu's trigger: an Italy film with a Middle East transit
rendered in **1,859 s** (31 minutes) on device, 3.5 minutes of film.

The rule this document exists to keep: **the export bill is a number, not an
adjective.** Every claim below says how it was measured, and the unmeasured ones
say what would settle them.

## 1. The instrumentation (landed 2026-09-22)

Two log lines, durations and counts only — nothing here names a place (§0).

    render plan: <n> stations for <m> frames        ← before a frame is drawn
    render cost: <total>s total · <frames> frames · <stations> stations /
      <fetches> fetches · snapshots <s>s (mean <x>s, wait <w>s) ·
      composite <c>s · encode <e>s · finish <f>s

How to read it:

- `snapshots` is the **substrate's** bill, summed across concurrent fetches, so
  it may exceed the total. `wait` is what the loop actually **stalled** for.
- `snapshots − wait` is what prefetching already hid. A `wait` near the total
  means the render is starved on the provider and **concurrency** is the lever;
  a large `composite` means it is not.
- `render plan` prints in milliseconds, before the cost is paid: a film that
  will take half an hour says so at second one.

`RecapRenderLoop.RenderStats` carries the same numbers in-process, so a harness
can assert on them instead of reading a log.

## 2. The snapshot budget, measured (VERIFIED 2026-09-22)

`RecapSnapshotBudgetTests`, offline, shipped config:

| fixture | film | frames | stations | of which crossing arc |
|---|---:|---:|---:|---:|
| `nz-real` | 88.0 s | 2,640 | 73 | 0 |
| `iceland` | 69.0 s | 2,070 | 55 | 0 |
| `auckland-crossing` | 60.0 s | 1,800 | **102** | **54** |

**A crossing arc is the most expensive beat in the film by a wide margin.** On
`auckland-crossing` the arc is ~4 s of screen time and **53% of the snapshot
budget** — roughly one station per 2 frames, against one per 36 in the body. The
arc zooms, and a station's length is budgeted in zoom
(`Docs/camera-arcs.md` §7), so an arc expires its station almost every frame.

A trip with a transit stop in another region buys one arc per crossing. It also
widens the film's extent, and a wider extent is a more expensive *picture* as
well as more of them (INFERRED — see §4).

## 3. The one dial that halves it (VERIFIED 2026-09-22)

`snapshot_station_max_magnification`, 1.10 → 1.25, same fixtures:

| fixture | @1.10 | @1.25 |
|---|---:|---:|
| `nz-real` | 73 | **35** (2.1×) |
| `auckland-crossing` | 102 (arc 54) | **43** (arc 21, 2.4×) |

It buys that with **sharpness** — `Docs/handoff-crop-scaling.md` §1 prices 1.20
at mean error 0.905 against 1.10's 0.658, and 1.25 is past the measured table.
**A look decision, Chiu's, judged against two renders — never a config edit.**

## 4. What is still unknown, and the cheapest way to settle it

- **What a MapLibre snapshot costs on device, and how it scales with span.**
  The 0.72–1.55 s per snapshot figure everything is estimated from is
  `MKMapSnapshotter` (decisions.md 2026-08-15) and the production substrate is
  not MapKit any more. `testMapKitSnapshotLatency` still prices the old one.
  → Settled by one device export with §1's log line.
- **Whether the 31-minute film was ~300 snapshots at ~6 s or ~900 at ~2 s.**
  Opposite problems, opposite fixes. → Same single run.
- **Whether raising prefetch depth buys anything**, i.e. whether
  `MLNMapSnapshotter` renders concurrently at all. → `wait` versus `snapshots`
  in the same line.

## 5. Per-frame cost (Mac only — ratios, not device figures)

Measured 2026-09-22 on the dev Mac, 1080×1920, a detailed source image:

| operation | ms/frame |
|---|---:|
| background draw, magnified 1.02–1.10 **or** any fractional offset | **11–12** |
| background draw, **integer offset, 1:1** | **0.96** |
| oversized station, integer crop | 1.10 |
| encoder's RGBA → 32ARGB pixel-buffer copy | 0.59 |

Two consequences. **Any** departure from a 1:1 integer blit costs ~11×, because
it forces a resample — that is what the current reprojection pays on every
frame. And the encoder copy that looks wasteful is not: 0.59 ms is not where the
minutes are, and 32BGRA measured the same.

`KAMOME_RENDER_BENCH=1 swift test --filter testRenderBudgetFullResolutionFlatProvider`
renders 900 frames with no provider cost at all: 10.8 s, i.e. ~12 ms/frame for
composite + encode + GIF on the Mac.

## 6. Open work

- **No-look-change optimisation — landed 2026-09-22, desk-measured, device
  unmeasured.** All five items:
  1. **Parallel compositing** (`RecapRenderLoop.renderFrames`; per station until §7) — a station's
     frames now composite on a bounded pool (`compositeConcurrency = 4`,
     ~8 MB/frame named the same way `prefetchDepth` already was) and deliver
     to the encoder strictly in order regardless of completion order.
     **Verified safe to call concurrently**: `FrameCompositor`,
     `VehicleSubjectRenderer`, `RecapOverlayRenderer` and `LinearTimeline` hold
     no mutable state (read by inspection — every stored property is `let`),
     each `compositor.render` call allocates its own fresh `CGContext`, and
     `PhotoLibraryPhotoResolver`'s cache is already `NSLock`-guarded.
     **NOT verified**: whether `MLNMapSnapshot.point(for:)` is safe to call
     from two threads at once — MapLibre Native's public surface does not say,
     and its Objective-C++ layer (read from source) is a bare call into a
     captured `std::function` with no visible synchronisation. Rather than
     assume, `MapSnapshot`'s per-station projection cache (below) holds its
     lock **across** that call too, so parallel compositing never actually
     runs two `point(for:)` calls at once — the parallelism this item buys is
     in `CGContext` drawing, not in the provider's own projection.
  2. **Provider concurrency** — `prefetchDepth` 4 → 8. Code-complete only:
     whether `MLNMapSnapshotter` renders more than one snapshot at a time
     (the `wait` vs `snapshots` reading this doc's §1 names) needs a real
     MapLibre export, which this session had no device or simulator network
     path to run. **Unmeasured — say so rather than infer it.**
  3. **Memoised trail projection** — `MapSnapshot.point` now caches per
     `(lat, lon)`, scoped to one station's lifetime (freed with it), guarded
     by the same lock that serialises item 1's concurrent callers. Memoising a
     pure function is bit-identical by construction; nothing about *what* is
     drawn changed. The desk benchmark (flat provider, cheap math already) is
     the wrong place to see this pay off — its target is the ~one Obj-C call
     per trail vertex per frame this doc's own comments named, which only a
     MapLibre-backed export exercises.
  4. **Progress throttling** — `RecapExportJob+Render.runDetached` caps the
     main-actor hop to ~10/s and always forwards the final 1.0.
     `RecapExporter.export` itself still calls its `progress` argument every
     frame unthrottled, so `RecapEncoderTests`' per-frame cadence assertion
     needed no change.
  5. **Hoisted `CGColorSpace` / vignette `CGGradient`** — built once in
     `FrameCompositor.init` instead of once per frame.

  **Desk, before/after** (`KAMOME_RENDER_BENCH=1 swift test --filter
  testRenderBudgetFullResolutionFlatProvider`, same Mac): **10.9 s → 6.4 s**
  for 900 frames — items 1 and 5 are what this benchmark can see, since its
  `FlatSnapshotProvider` has no provider latency and cheap-already projection
  math (items 2 and 3 are provider-bound and don't move a flat-provider
  number). **Device, before/after**: not run — no physical device in this
  session, so no `render cost` log line to quote. Whatever runs D1–D5 next is
  the first real reading of items 2 and 3.

  One test needed a fix, not a weakening: `RecapMapCreditTests`'
  `RecordingOverlay` recorded overlay calls into one shared buffer closed by
  an external "frame ended" signal, which assumed calls never interleave — a
  station's frames now composite in parallel, so two frames' calls could land
  in the same bucket (crashed once outright, from concurrent unguarded
  `Array.append`s, before being made thread-safe at all). Fixed by keying the
  recorder off each call's own `CGContext` — one per `compositor.render` call
  by construction — retained by the key so its identity can't be handed back
  out by the allocator mid-run (a first attempt that didn't retain silently
  merged 120 frames into 8 buckets). No assertion in that file changed.
- **Product dials that would cut the bill** and are Chiu's alone: §3's
  magnification, `earned_stops_cap` (film length is bought by stops), and
  whether a transit stop in another region belongs in the film at all.
- **Structural, needs an ADR**: stations that serve frames by integer crop at
  1:1 instead of by magnification — §5 says it is ~10× cheaper per frame *and*
  sharper, and it changes what a longer station costs from picture quality to
  snapshot pixels. Not started.

## 7. Second pass, 2026-09-23 — where the next minutes are (desk reading, no device)

- **Every snapshot rebuilds MapLibre from scratch (VERIFIED from source).**
  `MLNMapSnapshotter.mm` at `ios-v6.27.0`, `-startWithCompletionHandler:` →
  `configureWithOptions:` does `std::make_unique<mbgl::MapSnapshotter>(…)` and
  `setStyleURL(…)` on **every** start. So each station pays a new renderer
  backend, a style parse, sprite/glyph load and a re-decode of every tile from
  the ambient cache — reusing the Objective-C object would not avoid it. The
  lever is a **persistent renderer** (a pool of offscreen `MLNMapView`s that
  keep style and parsed tiles, camera moved per station). How much of a
  snapshot's cost is setup: **UNKNOWN** — settle with one device export that
  also times `mapSnapshotter:didFinishLoadingStyle:` against completion.
- **Ambient tile cache is never sized (VERIFIED: no `MLNOfflineStorage` call in
  the app).** MapLibre's default is 50 MB (INFERRED from its docs); whether a
  multi-region film evicts and refetches mid-export is UNKNOWN — same device
  run, Network instrument.
- **A GIF export rendered and encoded the full 30 fps MP4 and threw it away.**
  `RecapGIFEncoder` keeps one frame in `fps / gif_fps` (stride **2** at the
  shipped 30/12, so half the frames). **Landed 2026-09-23:**
  `RecapExporter.exportGIF` + `RecapRenderLoop.renderFrames(only:)` composite
  only the kept frames, write no MP4, and never fetch a station none of whose
  frames is kept. The plan is still made over every frame, so kept frames are
  byte-identical (`RecapEncoderTests.testGIFOnlyExportMatchesTheTwoEncoderGIF`,
  `RecapRenderPipelineTests`). `Output.videoURL` is now optional.
- **Compositing parallelism stopped at every station boundary** (the old
  `renderStation` drained its task group per station; crossing arcs run ~2
  frames per station). **Landed 2026-09-23:** one worker pool for the whole
  film, frames submitted in film order across boundaries, the next station's
  snapshot awaited while the previous station's frames still composite,
  delivery still strictly in order. Device gain UNKNOWN — read `composite` and
  `wait` in the `render cost` line on a crossing film.
- **Stations are snapshotted at frame pixel size while covering a wider span
  (VERIFIED, `renderFrames` passes `frameWidthPx/HeightPx`).** A pure pan is
  paid as magnification. Snapshotting at `frame × station/tightest span` pixels
  would make pans cost pixels instead of stations *and* be sharper — this is §6's
  structural item, a look change, Chiu's ADR.

## 8. Third pass, 2026-09-25 — why a snapshot costs what it does (Iceland, 859 s)

Chiu's trigger: the Iceland film (4+ min of film, 14 days, 26 stops) rendered
in **859.3 s** on device. `render cost` says *how long* the snapshots took.
It cannot say why. Three log lines now say it, on **every** exit, including
cancel and failure (`RecapExportJob+Diagnostics`, counts and fixed words only):

    render device: thermal <state> · low power on|off · background GPU supported|not supported|n/a (iOS < 26)
    map cache: <n> MB ambient
    render thermal: <start> → <end> · worst <state> · <s>s at serious or above
    render substrate: <n> snapshots (<f> failed) · mean <x>s, style <y>s|n/a ·
      peak in flight <p> · requests <r> / <d> distinct · <v> revalidated · <t> refetched

How to read them, and what each reading decides:

| reading | means | lever |
|---|---|---|
| `style` a small share of `mean` | setup is cheap, tiles are the cost | **not** a persistent renderer (§7) |
| `refetched` well above 0 | the cache dropped tiles mid-film | raise `map_cache_mb` |
| `revalidated` ≈ `requests − distinct` | expired tiles re-checked, one round trip each | tile prefetch / freshness, not cache size |
| `peak in flight` 1 | snapshots never overlapped | `prefetch_depth` buys nothing |
| worst `serious`, many seconds hot | the phone throttled | the figure measures heat as well as code |
| `background GPU` not supported | iOS 26 continued processing cannot keep MapLibre running | pause/resume, not background render |

**Landed, no pixel changes:** `export.pipeline.map_cache_mb` (256, INFERRED)
sizes MapLibre's ambient cache before the first snapshot. The default is
**50 MB** (VERIFIED, `MLNOfflineStorage.h`). **Not done:** a bounding-box tile
pre-download. Iceland's box at z14 is ~130,000 tiles (INFERRED from tile
geometry at 64°N), and the film needs only the ones along its camera path, which
is what the render fetches anyway. Revisit only if `revalidated` says round
trips are the cost.

**Measured on the simulator, 2026-09-26** (`MapSubstrateMeterTests`, opt-in
`TEST_RUNNER_KAMOME_LIVE_TILES=1`, one 256 px frame of Tokyo, **not a device
figure**): style load **0.02 s** of a **2.2 s** cold snapshot. An identical second
snapshot cost **0.08 s**, sent 2 requests, both **revalidations**, and refetched
nothing. So the §7 hypothesis that setup is the bill is **weakened**. The cost
looks like tile fetching and decoding. Settled by the device line above.

**VERIFIED:** MapLibre 6.27 never calls `MLNNetworkConfigurationDelegate`'s
`didReceiveResponse:`, neither on success nor on DNS failure. Status codes and
bytes cannot be measured that way. The request side (`willSendRequest:` with
its conditional headers) is what the meter counts.

## 9. The device reading, and the fix it pointed at (2026-09-26)

**Device (VERIFIED, iPhone16,2, iOS 26.4.2, Iceland, 338 s film, 699 stations):**

    render cost: 942.5s total · snapshots 6420.4s (mean 9.25s, wait 611.7s) · composite 1240.3s · encode 84.2s
    render thermal: nominal → serious · 639s at serious or above
    render substrate: 694 snapshots · mean 9.22s, style 0.03s · peak in flight 9 ·
      requests 17216 / 1908 distinct · 8449 revalidated · 6859 refetched
    background GPU not supported

What it settled: the loop waited on snapshots for 65% of the render. Style setup
is 0.3% of a snapshot, so **§7's persistent renderer is not the lever**. Each
distinct tile was requested ~9 times. This iPhone cannot render MapLibre in the
background (iOS 26 continued processing), so "keep going when locked" means
pause/resume, not background rendering.

**Cause (VERIFIED on the desk, `RecapTileRequestBenchTests`, `iceland` fixture):**
- **Terrain.** AWS answers terrain tiles with an ETag and **no** `Cache-Control`
  or `Expires` (curl, 2026-09-26). MapLibre revalidated one on every use: all
  the bench's revalidations were terrain.
- **Races.** OpenFreeMap's vector tiles carry `max-age=315360000` and were
  still downloaded ~4× each. With nine snapshotters in flight, MapLibre queues
  its requests, and a repeat leaves the queue after the first download has
  landed but before it serves from cache (median repeat gap 2–6 s).

**Fix, network only (`TileRequestCoalescer`, a `URLProtocol` behind MapLibre's
`sessionForNetworkConfiguration:`):**
1. Identical asks in flight share one download.
2. A terrain response without a lifetime is handed on with
   `max-age=terrain_max_age_s` (30 days, INFERRED; the DEM dates from 2017).
3. Bodies this export already downloaded answer later identical asks from
   memory (`tile_memory_mb`, 64).

Status, body and validators are the server's. Keys: `coalesce_tile_requests`
(kill switch), `terrain_max_age_s`, `tile_memory_mb`; all no-pixel.

**Measured, simulator, whole `iceland` film (183 stations), cold cache each run:**

| | before (2 runs) | after (2 runs) |
|---|---|---|
| wall | 219.0 s, 236.3 s | **64.2 s, 65.8 s** (3.1–3.7×) |
| snapshot mean | 9.65 s, 10.22 s | 2.74 s, 2.91 s |
| network downloads | ~5,100 requests | **638 = distinct** |

**Pixels (VERIFIED, PNG diff against a before-run reference):** MapLibre is
not byte-deterministic even unchanged: a second before run matched 106 of 182
snapshots byte-for-byte, with its largest difference **1/255** on 0.00010% of
pixels. After the fix: 90 of 182 byte-identical, largest difference **2/255** on
0.00014% of pixels. No pixel moved by more than 8/255 in either. That is
rendering noise, not a change in what is drawn.

**Not measured:** the device gain. The phone's round trip to AWS us-east from
Taiwan is longer than the Mac's, so it may be larger (INFERRED). Heat
(68% of the render at `serious`) is untouched. → The next device export's
`render network` line: `downloads` should equal `distinct`.
