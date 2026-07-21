# Kamome Animation Vision

**Status:** Product direction from Chiu, 2026-07-19, after reviewing the P3
demo artifact (`Docs/demos/phase3/kamome-p3-recap.mp4`), approved with
refinements the same day. Integrated into spec v1.5 (§0 rule 6, §4.5
quality bar, §7 Phase 3.5), `Docs/decisions.md` 2026-07-19 (gate decision
+ substrate ADR), and `Docs/vector-tile-pipeline.md` (implementer guide).
Pipeline mechanics of §4.5 (camera path, overlay timeline, encoding,
budgets) are unaffected.

**Scope note — Replay MVP repositioning (2026-07-20, `decisions.md`).** This
document is the *long-term* visual north star; it is not the MVP checklist.
Product evolution is two layers: **(1) Replay MVP** — auto-generate a real-road
trip animation from imported photos; **(2) Story Director** — add automatic
selection, narrative, hero photos, pacing, and music. Read every ambition below
through that lens:
- **Follow-cam is the MVP's primary dynamic, not the sole or final narrative.**
  The "vehicle is the subject / centred" framing is the MVP simplification;
  Story Director makes the follow-cam **one narrative shot among many** (chapter
  transitions, establishing shots, hero holds). Build `CameraPath` for both from
  the start (spec §4.5).
- **"Multiple art styles" is a long-term differentiator, not an MVP condition.**
  The MVP ships exactly **one** theme (Modern Minimal). Cute Illustration /
  Semi-Realistic are future; the engine ↔ theme decoupling keeps them open
  without building them.
- **"Accuracy is a core value" means faithful-to-roads, not proof.** Many MVP
  recaps are **reconstructed from photo locations**, not recorded; they must be
  labeled honestly (spec §3/§6 — `trip.source`, never "Verified Trip"). GPS/EXIF
  are not tamper-proof; low-confidence legs render as inferred, never invented.

---

Kamome is not a GPS visualization tool. It is a travel storytelling engine.
Every exported replay should feel beautiful enough that users want to share
it, even if the trip itself was ordinary.

## Inspiration and core difference

Closest inspiration: **TravelBoast**. Kamome should not become another
TravelBoast — it should be the next generation of travel replay: the
simplicity and charm of TravelBoast with real GPS accuracy and much higher
visual quality.

TravelBoast requires users to manually draw the route and place start/end
points. Kamome requires none of that: the animation is generated directly
from the recorded GPS track. The replay must faithfully follow the actual
road driven, including road geometry, curves, intersections, elevation
(future), and actual travel direction. It should feel like watching your
real journey instead of recreating it manually. **Accuracy is a core value
of Kamome.**

## MVP goal

An animation similar to TravelBoast's overall format is acceptable:

- fixed isometric camera
- animated vehicle moving along the route
- smooth route drawing
- lightweight rendering
- exportable video

But not TravelBoast's visual design — Kamome should already look noticeably
more modern and premium.

## Design direction

Aesthetic closer to Apple's design language: clean, minimal, refined,
elegant, premium. Avoid: overly saturated colors, childish UI,
cheap-looking icons, excessive decorations. Everything should feel
intentionally designed.

## Route rendering

The vehicle always moves on the actual road. **Never animate over straight
lines between GPS points.** The replay snaps naturally to road geometry
while preserving the recorded journey. Smooth interpolation is encouraged,
but geographical fidelity is never sacrificed.

## Visual quality vs. TravelBoast

Smoother animations, better easing, higher quality illustrations, more
beautiful road rendering, richer terrain colors, subtle shadows, polished
transitions, consistent visual hierarchy. Every frame should feel carefully
designed instead of generated mechanically.

## Multiple art styles

A key differentiator: the rendering engine should eventually support
interchangeable visual styles without changing the animation logic.

- **Style 1 — Cute Illustration.** Beautifully illustrated travel maps:
  hand-crafted illustrations, soft colors, playful but elegant, charming
  trees/mountains/landmarks, cozy atmosphere. A premium illustrated travel
  journal.
- **Style 2 — Modern Minimal.** Apple-inspired: simplified geometry,
  restrained palette, clean typography, subtle shadows, smooth gradients,
  premium product feel. Minimal without feeling empty.
- **Style 3 — Semi Realistic (future).** Cinematic: realistic terrain,
  natural lighting, detailed roads, atmospheric perspective — closer to a
  travel documentary, still stylized enough to remain beautiful.

## Camera

MVP: fixed isometric camera (TravelBoast-like) is acceptable. Future:
cinematic camera movements — fly-in, zoom, orbit, road follow, drone-like.
The animation engine should be designed so these can be added later without
major architectural changes.

## Binding principles (Chiu's 2026-07-19 refinements)

- **Recognizable visual identity.** A Kamome replay must never look like
  Apple/Google Maps with an animated route on top. The visual language
  must be distinctive enough to recognize a Kamome replay instantly, even
  without branding. (Spec §0 rule 6.)
- **Storytelling is the judgment criterion.** Kamome is a travel
  storytelling engine, not a vehicle animation engine. Every future
  camera movement, pause, transition, and visual effect must serve the
  narrative of the journey — not merely visualize GPS data. This is the
  test applied to all future motion decisions.
- **Engine ↔ theme decoupling.** The replay engine and rendering theme
  are fully decoupled. Modern Minimal is just the first theme
  implemented, not a structural assumption; nothing theme-specific may
  leak into the replay engine. (Boundary specifics: substrate ADR,
  `Docs/decisions.md` 2026-07-19.)

## Long-term vision & priorities

Kamome should become the most beautiful way to relive a road trip. Users
should immediately recognize a Kamome replay from its visual quality alone.
Implementation decisions prioritize, in order:

1. beauty
2. clarity
3. smooth animation
4. geographical accuracy
5. delightful details

over adding more features.
