# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.4, 2026-07-18 fork demoted
to mechanism — user-facing copy says Save / Get this route, never "fork"; v1.3
battery-moat pivot — phases renumbered: P4 Import & Matching, P5 Passive Tier =
v1/TestFlight, P6 Plans & Fork, P7 backend). Read it before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device.

## Current phase: 3 (recap video, spec §4.5/§7) — started 2026-07-16

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
  Remaining for P3: S5 screen (wire RecapExporter + MapKitSnapshotProvider,
  photos toggle, stop-card photo/title/end content from the trip DB), render
  budget proof on device (§4.5 bar: 8-day trip < 90 s on iPhone 13-class),
  demo artifact, plus the two gate items below.
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
  Trip) — region-resume still unproven on hardware; the drive proves it.
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
