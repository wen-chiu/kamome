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

## Current phase: 3.5 = **Replay MVP** (spec §7) — current item: **§3 Modern Minimal — DRAFT landed, awaiting Chiu's device render + sign-off**

**Read `Docs/handoff-P3.5.md` before doing anything — it is the Replay MVP
work order, in mandatory sequence.** §1 Photo EXIF Import ✅ (2026-07-21) and
§2 **MapLibre souvenir-map substrate** ✅ (2026-07-21) are landed. **§3 Modern
Minimal is IN PROGRESS**: a DRAFT base style (`Config/RecapThemes/modern-minimal.json`)
+ the review harness (`Docs/demos/phase3_5/modern-minimal/README.md`) landed
2026-07-21, but the visual is **NOT self-certified** — §3 closes only when Chiu
signs off on a side-by-side of real MapLibre stills vs. the P3 artifact (Metal
render, needs sim/device; not producible in CI). **MapKit is still the shipping
base map** (`RecapModel` untouched) until that sign-off, which also carries the
labels/glyphs, the overlay `RecapStyle.modernMinimal` preset, the MapLibre
production switch (retiring `MapKitSnapshotProvider`), and OSM end-card
attribution (handoff §3 Status; decisions.md 2026-07-21). Do NOT self-certify the
look or switch production without Chiu. P3 is
engineering-complete; its device items are redistributed (export/photo → Replay
MVP gate; 2 h drive + region-resume → Capture Beta), none faked passed
(`Docs/device-test-P3.md`). State at handoff:

- **§2 MapLibre substrate landed 2026-07-21** (`handoff-P3.5.md` §2 Status;
  decisions.md 2026-07-21). MapLibre `6.27.0` (SPM, exact, app target) confined
  to `App/Services/MapLibreSnapshotProvider.swift` (**not** the SwiftPM core —
  keeps package tests SDK-free; CI grep gate enforces `import MapLibre` in that
  one file). Conforms to the existing `RecapSnapshotProviding`; projection travels
  with the snapshot (`MLNMapSnapshot.point(for:)`); span→zoom via Web Mercator,
  `scale = 1`. Pure `RecapMapStyle` resolver injects the on-disk tiles path into
  the theme's `pmtiles://__KAMOME_TILES__` sentinel (unit-tested, no Metal).
  First theme = `Config/RecapThemes/functional-base.json` (subtractive: land/
  water/road skeleton, **no POI/labels** — NOT Modern Minimal). Fixture tiles via
  `Tests/Fixtures/tiles/generate_tiles.sh` (Planetiler/Docker). **MapKit is still
  the shipping base map** — `RecapModel` unchanged until §3 clears the design
  review, then MapKit dies in that PR. Golden-frame CI unchanged
  (`FlatSnapshotProvider`, bit-stable). **Device/sim-only, flagged NOT passed:**
  actual MapLibre pixel render + `pmtiles://`-vs-`mbtiles://` confirmation (Metal,
  not in CI) → §3 review + §6 gate. Ingestion scheme is theme-JSON-declared, so a
  fallback is a one-line edit.

- **§1 Photo EXIF Import landed 2026-07-21** (`handoff-P3.5.md` §1 Status).
  Engine (schema v2 provenance, `Core/ImportKit/`,
  `TripRepository.saveImportedTrip`, `ImportService`, `PhotoLibraryImportSource`)
  shipped earlier; this pass added the **S1 UI + provenance labels**:
  `Import from photos` hero on S1 (`HomeView`; live capture demoted to a
  secondary section), `ImportSheet` (date-range → import → progress/errors →
  push S3; `ImportFlowModel`), S1 `From photos` badge + S3
  "reconstructed from photos" note (never "verified"), all copy zh-Hant-first
  in the catalog (`LocalizationTests` guards it, incl. that the note omits
  "verified"). New tunable `import.default_range_days` (picker default;
  ConfigLoaderTests). Demo: `Docs/demos/phase3_5/import/`. **Device-only,
  flagged NOT passed:** live PhotoKit date-range fetch + Limited-Library path
  (`presentLimitedLibraryPicker`) — folds into the §6 three-trip gate.
  Device-test follow-ups landed 2026-07-21: import date pickers made friendlier
  (tap-to-expand rows that collapse on pick; end date snaps to the start's
  month), and **stop names now surface progressively** — `StopNamer` gained an
  `onNamed` callback and `TripDetailModel` reloads as each name lands, fixing
  many-stop imported trips that the old one-shot `t+3 s` reload left unnamed
  (shared path; recorded trips benefit too).

- §4.4 matching app side landed on `phase-3-recap` (decisions.md 2026-07-19
  matching): `Core/RouteMatching/` (`EncodedPolyline`, `RouteMatchProviding`
  boundary, `OSRMMatchProvider` — OSRM types confined to that one file,
  injectable transport for recorded-response CI), `RouteMatchService`
  (drive/scooter only; fire-and-forget at End Trip, idempotent at export),
  `RecapComposer` prefers snapped geometry at `matching.display_epsilon_m`.
  `matching.base_url` ships "" = disabled — no server exists yet.
- Handoff §1 (matching end-to-end) done 2026-07-19: local OSRM live (WA
  extract :5001 for perth, TW :5002; servers in `~/kamome-osrm`), matched
  recap export proven in-sim via env-gated `RecapMatchingE2ETests` (real
  RecapModel pipeline; all four drive segments snapped, worst chunk
  confidence ≈ 0.98), before/after artifact + notes in
  `Docs/demos/phase3_5/matching/`, recorded `/match` response replayed in
  CI (`OSRMRecordedFixtureTests` + `Tests/Fixtures/osrm/`). **Perth
  fixture regenerated with road-matched drive legs** (`route_leg` in
  `generate_fixtures.py`, needs the local server to regenerate): §1
  exposed that the old straight-line legs sat kilometers off-road (the
  Geographe Bay crossing was the fixture's own geometry) and the §4.4
  confidence gate correctly refused to invent a route — the gate was NOT
  loosened. Stops/walks/timing structure unchanged; full suite green.
  Fixture-regen decision + artifact pair still need Chiu's eyes.
- Next (Replay MVP order, `handoff-P3.5.md`): §1 Photo EXIF Import ✅ (2026-07-21)
  → §2 MapLibre souvenir map ✅ (2026-07-21) → **§3 Modern Minimal 🚧 (draft +
  review harness landed 2026-07-21; awaiting Chiu's device render + sign-off)**
  → §4 follow-cam → §5 photo deck → §6 three-real-trip dogfood = the Replay
  MVP release gate.

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
