# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.5, 2026-07-19 recap
visual pivot — see below; v1.4 fork demoted to mechanism — user-facing copy
says Save / Get this route, never "fork"; v1.3 battery-moat pivot — phases
renumbered: P4 Import & Matching, P5 Passive Tier = v1/TestFlight, P6 Plans
& Fork, P7 backend). Read it before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device.

## Recap visual pivot (spec v1.5, 2026-07-19, Chiu)

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

## Current phase: 3 (recap pipeline, spec §4.5/§7) — started 2026-07-16

Gate restructure (decisions.md 2026-07-16, Chiu): the 2 h drive
(`Docs/device-test-P1.md`) and the limited-photo-access re-check moved from
Phase 3 *preconditions* to Phase 3 *gate items* — P3 dev is fixture-driven,
but **P3 cannot close without both**. The 2026-07-16 smoke drive surfaced:

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
