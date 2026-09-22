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
  1. **Parallel compositing** (`RecapRenderLoop.renderStation`) — a station's
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
