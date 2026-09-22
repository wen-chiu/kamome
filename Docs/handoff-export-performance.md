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

- **No-look-change optimisation** — parallel compositing, provider concurrency,
  memoised trail projection, progress throttling. Handed to its own session
  2026-09-22; the prompt is the handoff (Chiu 2026-09-05).
- **Product dials that would cut the bill** and are Chiu's alone: §3's
  magnification, `earned_stops_cap` (film length is bought by stops), and
  whether a transit stop in another region belongs in the film at all.
- **Structural, needs an ADR**: stations that serve frames by integer crop at
  1:1 instead of by magnification — §5 says it is ~10× cheaper per frame *and*
  sharper, and it changes what a longer station costs from picture quality to
  snapshot pixels. Not started.
