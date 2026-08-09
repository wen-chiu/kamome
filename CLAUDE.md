# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.7, 2026-07-20 **Replay
MVP repositioning** — see below; the first release ships a **photo-import
recap**, not passive capture). Phase map: **P3.5 = Replay MVP (current
release target)**, P4 = Story Director, P5 = Capture Beta, P6 = Plans, P7 =
backend. Earlier: v1.5 recap visual pivot, v1.4 fork = mechanism (user-facing
copy says Save / Get this route, never "fork"), v1.3 battery-moat. Read it
before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device, honest provenance (never
"Verified Trip" — recorded vs reconstructed-from-photos is a product rule).

## §0 · Location data never leaves the device by default (Chiu 2026-08-03)

**A standing principle, not a checklist item.** Kamome's subject matter *is* a
record of where someone was and when. That is among the most sensitive data a
phone holds, and the product's whole claim is that it is safe to keep here.

A user's real trip, route or location history is **never** logged off-device,
transmitted, synced, sent to analytics or crash reporting, or committed to this
repository. The single exception is an explicit, user-initiated share of one
trip that the user actively chooses — never a default, never bundled into
another action, never opt-out.

This governs work that does not exist yet, which is the point of writing it
here: any P7 backend sync, any analytics or crash reporter, any telemetry, any
"help us improve" toggle is designed against this rule rather than measured
against it afterwards. If a feature needs real coordinates to leave the device,
that is a product decision for Chiu, not an implementation detail.

Concretely, today:
- `Tools/exif-to-fixture.sh` writes to `Tests/Fixtures/trips/local/`, which is
  gitignored as a whole directory. The render harnesses prefer a dump there over
  the committed synthetic fixture of the same name, so real trips drive desk
  review while CI keeps deterministic placeholders.
- Committed fixtures are hand-written plausible coordinates only.
- `KamomeLog` may name *which* stop failed to geocode; it may not log the
  coordinates.

It was broken once, on 2026-08-02: a real 160-photo dump of an actual trip was
committed. Caught before any push and rewritten out of history the same day.

## Replay MVP repositioning (spec v1.7, 2026-07-20, Chiu) — READ FIRST

Long-term vision unchanged (Kamome auto-remembers a journey and directs it
into a film worth rewatching). But the **first release is smaller and
verifiable — the Replay MVP:** pick a past trip's photos → reconstruct from
EXIF place+time → snap to real roads (OSRM, already landed) → souvenir-map
recap → **MP4** → share. Two-layer evolution: (1) Replay MVP, (2) Story
Director (auto-select/narrative/hero/music) — build the MVP without blocking
layer 2. `decisions.md` 2026-07-20. Consequences:

- **Phase 3.5 renamed → Replay MVP**; **photo-EXIF import pulled forward**
  into it (was old P4). Work order = `Docs/handoff-P3.5.md`, resequenced:
  **Photo EXIF Import first** → MapLibre souvenir map → Modern Minimal (the
  ONE MVP theme) → vehicle follow-cam (primary dynamic, NOT "always-centred"
  dogma) → basic photo deck (0.8 s, explicitly *basic*) → **three-real-trip
  dogfood** → TestFlight.
- **P3.5 gate is now a product release gate** (three real trips → shareable
  films, in-app only, no DB edits / no CapCut; ≥1 published; limited-photo on
  device; stable MP4 export; per-trip time *product-acceptable*, the single
  <90 s number retired). Map-vs-Apple side-by-side = design review, NOT the
  gate. "Worth publishing," not "prettier map." Three trips is hard, never one.
- **MP4 is the launch format; GIF demoted to non-blocking.**
- **P3 device items redistributed (none faked passed):** export/S5-UX/
  limited-photo → Replay MVP gate; 2 h drive + region-resume → Capture Beta
  (`Docs/device-test-P3.md` re-tagged).
- **P5 Passive Capture Tier renamed → Capture Beta**, moved *after* the video
  product; inherits the tracking/battery device gates; only place "Arm once,
  forget it" is validated. **P4 Import & Matching renamed → Story Director**
  (EXIF half moved to MVP; Story Director is **deterministic — no AI/LLM
  tokens** (scoring/selection over trip data); Google Timeline importer
  **dropped** as redundant — EXIF import + in-app capture cover it).
- **Honest provenance:** schema v2 `trip.source` (recorded | imported_photos |
  imported_timeline) lands with the MVP; UI labels imported trips
  "reconstructed from photos"; low-confidence legs render inferred.

## Recap visual pivot (spec v1.5, 2026-07-19, Chiu)

*(Phase/gate framing here is superseded by the Replay MVP section above — kept
for the substrate ADR + boundary-discipline detail, which still hold.)*

Chiu rejected the P3 demo's Apple-tile look — Kamome is a **travel
storytelling engine**, not a GPS visualizer (now spec §0 rule 6: every
motion/visual decision must serve the journey's narrative; a replay must be
recognizably Kamome without branding). Vision:
`Docs/kamome-animation-vision.md`. Consequences:

- **P3 scope frozen as the pipeline milestone** — its machinery (CameraPath,
  OverlayTimeline, compositor, encoders, S5) all survives. Gate items
  unchanged (device: 2 h drive, limited-photo re-check, < 90 s budget, S5
  UX); the "Chiu posts one recap" share-worthiness item moved to P3.5.
- **New Phase 3.5 — Recap Visual System** (spec §7), strictly sequenced:
  OSRM matching §4.4 (pulled forward; route must never be straight lines
  between GPS points) → MapLibre substrate → Modern Minimal theme.
- **Substrate ADR** (decisions.md 2026-07-19): MapLibre Native +
  self-hosted vector tiles (Planetiler → PMTiles, same extracts as OSRM),
  Kamome-authored style JSON per theme. Implementer guide:
  `Docs/vector-tile-pipeline.md` — includes the **quality bar** (must be
  clearly better-designed than Apple Maps for replay, judged side-by-side
  vs. the P3 artifact, Chiu signs off; unreachable bar ⇒ reopen the ADR).
- **Boundary discipline, not premature abstraction** (Chiu): no generic
  multi-renderer interface. `RecapSnapshotProviding` already is the
  boundary (`import MapKit` lives only in `MapKitSnapshotProvider.swift`;
  MapLibre types get the same one-file confinement). Deferred gaps, built
  only when their consumer exists: pitch/bearing in the snapshot request
  (isometric camera), `RecapTheme` overlay tokens (defined during Modern
  Minimal). Engine ↔ theme fully decoupled; Modern Minimal is the first
  theme, never a structural assumption.

**Prototype validation (2026-07-20, `Docs/prototype/`, decisions.md
2026-07-20).** Direction de-risked in a throwaway web prototype on Chiu's
real 170-photo Iceland trip; owner sign-off "收斂回 app". Locked constraints
for §4.5/§7 (no architecture change — they constrain existing components):
(a) base map = **real geometry + subtractive style** = 紀念品地圖 (reaffirms
substrate ADR; abstract map rejected); (b) stop photos = **rotating deck at
the place**, hero cross-fades 3–8 photos at **0.8 s each** (OverlayTimeline);
(c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle
is the subject, close heading-up zoom) — the prototype's one unmet item;
top-down car default, seagull/scooter/bike swappable. Positioning restated →
spec header v1.6 ("stories you can relive and share"). Forward directions
recorded: photo-EXIF import first (prototype IS that importer, §4.7), video
"beads" (auto-trim 2–3 s, muted), beat-synced royalty-free music.

## Current phase: 3.5 = **Replay MVP** (spec §7) — current item: **§6 three-trip gate; camera/legibility work CLOSED 2026-08-02**

**Read `Docs/handoff-P3.5.md` before doing anything** — the Replay MVP work
order. §1 Photo EXIF Import ✅, §2 MapLibre substrate ✅, §3 base-map substrate ✅,
§4/§5 camera + stop presentation ✅ (2026-08-02). **§6 is the remaining item**, and
`Docs/gate-P3.5-checklist.md` is the runbook.

### ⚠️ Two blockers stand in front of §6 (diagnosed 2026-08-01, NOT fixed)

Both are invisible on the committed fixtures and only appear on real data, so the
desk stages pass with them present. **Fix before spending an iPhone sitting** —
details and suggested shapes in the checklist's "Blocking dev work" section.

1. **Multi-day trips type every inter-day leg `.walk`** — `ImportService.mode`
   divides distance by wall-clock gap, so an overnight gap implies walking pace;
   walks are never routed, so the leg stays a dashed straight line. 7 of 9 legs
   on the real NZ trip. Fails the gate's "no mountain-crossing straight line".
2. **iCloud-optimised photos resolve to empty grey cards** —
   `PhotoLibraryPhotoResolver` sets `isNetworkAccessAllowed = false`. EXIF import
   still works (metadata needs no download), so this survives every desk stage.

### Camera architecture (rebuilt 2026-08-01 → 2026-08-02, Chiu)

The recap camera was rebuilt after the NZ device film. `CameraPathActs` framed
each act to its own bounds while timing came from a separate clock, so motion
came from **data shape** rather than spatial continuity — acts collapsed onto the
`camera_span_m` floor and the camera crossed 110 km between them. What replaced
it, all of which is load-bearing:

- **`FollowCamera`** — a dead-zone dolly, pre-simulated once at build time so
  `cameraFrame(atTime:)` stays pure and random-access. Inertia is simulation
  state, never a post-process. A world-bounds clamp keeps the frame inside the
  route's extent, and **yields to the subject** when the two disagree.
- **One span per trip**, from `RecapDurationPlan.bodySpanM`. Never adaptive —
  recomputing mid-film is what produced a 97× zoom-out before the end card.
- **Wide baseline (2026-08-02) SUPERSEDED 2026-08-08** (Chiu, from renders). It
  framed the *body* to the whole trip via `wide_span_padding` 1.5 — but the
  opening's regional beat used the same expression, so establishing and body were
  the same number and the film opened flat. `body_span_padding` (0.6) now sizes
  the body separately: the establishing shot frames the whole trip, the body
  follows the vehicle inside it. Iceland 737 km → 295 km = a 2.5× zoom.
  `camera_pan_window_fraction_per_s` stays 0.05.
- **`CameraPathActs` keeps only discontinuity detection** — a ferry is a fact
  about the journey; framing was a decision about the camera, and conflating them
  is what made acts visible to the audience.
- **The opening** is country → region → body, the country beat framed to fit
  *inside* the tile extent (never shows past the data), dropped entirely when the
  region is no wider than the trip. Held beats are capped at ~1 s **after the
  title card**; the title beat itself holds `title_card_s`. The closing zoom is
  skipped when the body frame already matches the regional beat.
- **The ending** pulls back past the body (`end_reveal_padding` 1.9) so the last
  frame is the complete journey; `end_card_style` selects `.full` (free) or
  `.minimal` (held for a paid tier).

**Two gates guard all of it** (`RecapCameraContinuityTests`, offline, every
fixture, `base_url=""` for worst-case inferred legs):
- consecutive frames share ≥50% of their ground (measured ≥97%);
- the subject never passes 80% of the half-frame (measured 43–54%).
Do not relax either — they exist because a still frame is trivially correct and a
strobing one is only wrong *between* frames.

**Deferred, scoped, wanted:** map reference labels — handoff §"Map reference
labels". Blocked on a missing `glyphs` fontstack (MapLibre cannot draw Latin
labels without one); tile data already carries the names. Related but separate:
landmark title cards as narrative rhythm (`icebox.md`).

**Still not merged to main:** PR #11 holds until §6 passes (owner call).

## Phase 3 history (recap pipeline, spec §4.5/§7) — started 2026-07-16

Gate restructure (decisions.md 2026-07-16, Chiu): the 2 h drive
(`Docs/device-test-P1.md`) and the limited-photo-access re-check moved from
Phase 3 *preconditions* to Phase 3 *gate items* — P3 dev is fixture-driven,
but **P3 cannot close without both**. *(Superseded 2026-07-20: the 2 h drive
moved to Capture Beta; the limited-photo re-check stays as a Replay MVP gate
item.)* The 2026-07-16 smoke drive surfaced:

- Road deviation in the polyline is expected (sparse drive sampling + ε=15 m
  display simplification); fix is OSRM matching (§4.4, P3 stretch / P4 core),
  raw points are retained — do NOT tighten sampling config for this.
- Phantom-trip guard landed (PR #7, CI green): `trip.min_duration_s` /
  `trip.min_distance_m` in `TrackingConfig.json`; `TrackingSession.end()`
  discards sub-minimum recordings (`TripGuard`, Core/TripComposer). PR #7
  also fixed the local smoke's stale missing-key expectation.
- P3 milestone branch `phase-3-recap` (stacked on PR #7): `KamomeExportEngine`
  target started with `CameraPath` (§4.5 step 1 — speed-warp to
  `export.target_duration_s`, per-stop holds pinned on-route, smoothstep
  easing, new `export.max_hold_fraction` tunable caps holds on stop-dense
  trips).
- §4.5 steps 2, 4, 5 landed 2026-07-18 (three commits on `phase-3-recap`):
  frame renderer (`RecapFrameCompositor` + `RecapRenderLoop`, keyframe
  snapshots cross-faded per `export.keyframe_interval_frames`, projection
  travels with `MapSnapshot` so MKMapSnapshotter's `point(for:)` stays
  authoritative; `FlatSnapshotProvider` keeps golden-frame gates
  deterministic), title/end cards as new OverlayEvent kinds (photos toggle
  gates stop cards only — decisions.md 2026-07-18 recap-chrome, **confirmed
  by Chiu**; chrome-free export = separate future option, never this
  toggle), `RecapQRCode`, and `RecapExporter` → H.264 MP4 +
  decimated GIF with progress/cancel. New export tunables: frame size,
  camera_span_m, keyframe_interval_frames, title_card_s, end_card_s.
  S5 landed 2026-07-19: `RecapComposer` (trip DB → cards; recap geometry
  goes through Douglas-Peucker at simplify.epsilon_m), `RecapModel`/
  `RecapView` (photos toggle labeled "停留照片卡" + always-on chrome note,
  MP4/GIF picker, progress/cancel, share sheet, render-time readout), film
  button on S3. Render-loop snapshot prefetch + `video_bitrate_mbps` (5)
  landed after 2026-07-19 benchmarks (sim: pipeline 22.8 s, snapshots
  0.67 s each, demo end-to-end 34.6 s). Demo artifact:
  `Docs/demos/phase3/` (perth fixture, real tiles). QR payload =
  `kamome://route/<id>` placeholder until P6/P7.
  Remaining for P3 (all need the physical device, `Docs/device-test-P3.md`
  F–H): render budget < 90 s via S5 readout, S5 UX pass, 2 h drive,
  limited-photo re-check.
- Recap product decisions (decisions.md 2026-07-17, Chiu): overlay moments
  (stop cards, and later route-attached photo fly-bys) are **timeline events**
  built alongside CameraPath in step 2 — don't hardwire rendering to
  `holdingStopIndex`. S5 gets a photos on/off toggle (route-only animation =
  overlay events off) — P3 scope. Route-photo fly-bys = P3 stretch after the
  render budget is proven; video clips in recap = icebox (deterministic
  excerpts only — random breaks golden-frame CI).
- Photo fixes landed 2026-07-16: route-attached photos (stop_id NULL) get an
  S3 strip; Selected-Photos access shows a banner + limited-library picker;
  re-match preserves highlights. Limited-access box stays unticked until Chiu
  re-checks on device.
- Evening dwell_pause without dwell_resume was benign (parked until End
  Trip). Region-resume got its first hardware proof on the 2026-07-19 drive
  and **failed half-open**: resume fired, iOS suspended the app ~10 s after
  the region-exit wake, 32 min / 13 km lost (straight line in the recap,
  second stop unrecordable). Fix landed on `phase-3-recap` (decisions.md
  2026-07-19 region-resume): background-flag re-assert on resume, trip-long
  significant-location-change safety net, `sampling.recovery_gap_s` (60)
  silent-death watchdog, engine-side resume now also restarts GPS
  (`resumeActiveTracking`). New CSV events `region_exit` / `gps_recover`.
  Re-validation = device-test-P3 item C (needs the physical device).
- Stop detection redesigned after the 2026-07-18 17:04 drive missed both real
  stops (ADR 2026-07-18): DwellDetector is streak-based (age-based span check
  never fired on sparse real sampling); engine never dwell-pauses mid-walk;
  `StopDeriver` (TripComposer) adds silence-gap + walk-visit (loop-closure)
  stops at trip end. Trip stop semantics = live ∪ derived; new dwell tunables
  gap_min_s / visit_min_s / visit_return_radius_m.
- `stop.kind` wired (ADR 2026-07-18 stop-kind): `dwell` | `walk_visit` via
  `StopKind`; silence-derived = dwell (detection ≠ kind); pre-existing rows
  say "auto" — readers treat unknown as dwell. Compositor renders walk visits
  with walking duration/trace (recovered via time overlap with the walk
  segment — no Place/Visit abstraction, owner decision). Next-drive
  validation items tracked in `Docs/device-test-P3.md` (A–E). POI naming
  (MKLocalSearch → geocode fallback) = next standalone PR after the first
  end-to-end replay; do not block compositor on it.

## Verification commands (run from repo root)

```bash
xcodegen generate
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
swiftlint
```

(Local Xcode is 26.6 → destination iPhone 17 Pro; CI auto-picks its simulator.
swiftlint locally needs `XCODE_DEFAULT_TOOLCHAIN_OVERRIDE=/Library/Developer/CommandLineTools`
— Rosetta swiftlint can't load Xcode 26's arm64-only SourceKit.)

The `.xcodeproj` is generated — never hand-edit it; change `project.yml` and
re-run `xcodegen generate`.
