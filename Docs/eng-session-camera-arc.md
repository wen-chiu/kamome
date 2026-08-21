# Engineering session — the contained arc, Pass 1 (rendering only)

**Status: NOT YET RUN (as of 2026-08-21).** Ready to paste; Pass 2 is gated on
Chiu judging Pass 1's render.

**Paste the block below as the first message of a fresh Claude Code session.**

Scope is **one pass of one task**. This session does **not** build the crossing
beat, does not change the film, and does not touch `Docs/cross-region-journeys.md`
work. Pass 2 is a separate session and is gated on Chiu judging Pass 1's render.

Slots into `Docs/pre-launch.md` **item 2** (cross-region) as its prerequisite, and
it moves items **3** and **5** (export survives / export-time estimate) because it
changes the snapshot count by roughly 4×.

---

```
You are the engineering session for Kamome, operating under `Arch.md`. Read it
first — §7/§8 (verification is mandatory, three levels), §9 (fixture and baseline
discipline), §11 (plan deviation) and §12 (communicate before implementing) are
the parts I will hold you to. §14: never say "done".

Read in this order before proposing anything:
- `CLAUDE.md` — current state, Phase 4, and §0 (location data never leaves the
  device). Phase 4 item 3 records that `keyframe_interval_frames` and the
  opening's every-frame interval are FROZEN for a design conversation. That
  conversation has happened; this task is its first half.
- `Docs/camera-arcs.md` — the design. §2 (the cost model), §4 Case A, §7 (the
  rendering rule), §8 (the gates) and §10 Pass 1 are your task. Everything else in
  that file is Pass 2 and is **not yours**.
- `HANDOFF.md`, "Findings — PO/Architecture session (2026-08-21)".

Where a `Docs/handoff-*.md` file contradicts an ADR, the ADR wins and the handoff
is stale. Say so rather than resolving it quietly.

⚠️ Other sessions are working in this tree (routing → Geoapify; the sprite
commit). Code facts in `Docs/camera-arcs.md` were read on 2026-08-21 and are named
by symbol, not by line number. **Re-verify each one you rely on** and say so if
one has moved. Stage explicit paths only — no `git add -A`, no `git reset --hard`,
no `git clean`: the tree has held uncommitted art with no other copy.

## The task

**Render the opening three ways so Chiu can judge one question: does a scaled zoom
read as a dolly, and how soft is too soft.**

The film does not change. Not its pacing, not its duration, not its beats, not its
spans, not the camera path. Only how the base map is produced during the opening.

Today's opening is already a *contained arc* — every frame of it is a
sub-rectangle of the country beat's footprint. `Docs/camera-arcs.md` §4 Case A
gives the geometry; verify it yourself on at least two fixtures before building
anything, because the whole task rests on it.

Deliver, on one fixture, the **first 9 seconds only** (~270 frames), three clips:

1. **as-is** — the shipped path, fine-sampled. The measured baseline is 151
   snapshots for the opening.
2. **coarse** — `keyframe_interval_frames` applied to the opening too,
   cross-faded. This is the janky baseline the freeze exists to avoid; render it
   so the comparison is honest rather than assumed.
3. **crop-scaled** — one snapshot per zoom station (~1.5× of zoom apart, so ~3
   for this arc), every intermediate frame produced by cropping into the nearest
   station, cross-fading only at a station boundary.

Report the snapshot count for each, measured through the shipped
`RecapRenderLoop`, not derived.

## Start with the throwaway

The cheapest version of (3) needs **no pipeline change at all**: one snapshot at
the country span, cropped in over 9 s, no overlays, in a scratch harness. Build
that first and look at it. If a scaled zoom does not read as a dolly, the design
is wrong and nothing else in this task is worth writing.

Only then decide whether the real implementation is worth proposing — and propose
it before writing it (§12).

## What is already decided — do not redesign these

- **No exemption to either continuity gate, and no threshold change.**
  `RecapCameraContinuityTests` divides overlap by the *smaller* footprint, so a
  contained move already scores 1.0. If your change needs a gate relaxed, the
  change is wrong. Tests are not yours to weaken (`Arch.md` §7).
- **Do not change `keyframe_interval_frames` in `Config/TrackingConfig.json`.**
  Variant (2) is a render-time override in the harness, not a config edit. The
  value stays frozen; the design makes it irrelevant to arcs rather than tuning
  it.
- **Do not change the camera path, the beats, `target_zoom_ratio`, the body span,
  or `RecapDurationPlan`.** All of that is Pass 2.
- **Overlays keep drawing per frame through `MapSnapshot.point`.** Only the base
  map is resampled. A cropped view should be expressible as a *derived*
  `MapSnapshot` — same `CGImage`, composed projection — so the Story layer and
  `LinearTimeline` are untouched (`PO.md`, Story vs Rendering).
- **Do not write to `Docs/decisions.md`.** Nothing here is settled until Chiu has
  judged the render.

## What counts as done

- Three clips of the same 9 seconds, from the same fixture, watchable side by
  side, handed to Chiu.
- A measured snapshot count for each, through the shipped loop.
- The full test suite green, including both continuity gates, with no test
  modified.
- One honest paragraph on the artifact in variant (3): where the map goes soft,
  and whether a station boundary is visible.
- A `HANDOFF.md` entry saying what you found, including anything that contradicts
  `Docs/camera-arcs.md`. A finding that only exists in your session has not been
  delivered.

If the throwaway kills the idea, **that is a successful session** — say so plainly
and stop. Do not build the real thing to have built something.
```
