# Handoff — Phase 3.5 = **Replay MVP** work order (rewritten 2026-07-20)

Written for the next Claude session picking up `phase-3-recap`. Everything here
assumes you have read `CLAUDE.md` and `Docs/kamome-poc-spec.md` (v1.7) first.

**Phase 3.5 was renamed "Recap Visual System" → "Replay MVP" (recap from
photos)** by the 2026-07-20 owner decision (`decisions.md` 2026-07-20 Replay MVP
repositioning; spec §7). This file is the work order for that release, in
**mandatory sequence**. The old sequence started at MapLibre — **do not follow
that; the new first item is Photo EXIF Import.** Prioritise product order over
the historical order (spec §0; owner instruction 2026-07-20).

When in doubt, prefer doing less: every tunable goes in
`Config/TrackingConfig.json`, every renderer SDK stays confined to one provider
file, no gate item is ever marked passed without the artifact that proves it,
and no abstraction is built before its consumer exists.

## What the Replay MVP is

The first shippable product: **pick a past trip's photos → reconstruct the trip
from EXIF place + time → snap the route to real roads → generate a souvenir-map
recap → export MP4 → share.** It ships nothing about passive/background capture
— that is Capture Beta (Phase 5). The gate is a **product release gate**: three
real past trips become films Chiu wants to publish (full gate at the end of this
doc and spec §7 / §10).

## State at handoff

- Branch `phase-3-recap`, all committed, full suite green
  (`xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`),
  swiftlint clean. PR #7 (phantom guard) is the base; this branch stacks on it.
- **P3 is engineering-complete but NOT self-certified on device.** Its device
  items were **redistributed 2026-07-20** (spec §7 Phase 3; `Docs/device-test-P3.md`):
  export/photo items fold into the Replay MVP gate below; the 2 h drive +
  region-resume items **moved to Capture Beta**. Nothing was marked passed.
- §4.4 matching **app side is landed and validated end-to-end** (recorded
  `/match` CI replay, road-matched perth fixture, before/after artifact in
  `Docs/demos/phase3_5/matching/`; `decisions.md` 2026-07-19). `matching.base_url`
  ships `""` = disabled until region auto-selection exists. **Do not redo this.**
- OSRM local setup is documented and proven (`Docs/osrm-setup.md`): WA extract
  on :5001 for the perth fixture, TW on :5002. Servers live in `~/kamome-osrm`.

---

## 1. Photo EXIF Import  ← START HERE (spec §4.7, schema v2 §3)

The Replay MVP's core loop and the way Chiu dogfoods recap quality on **past**
trips. The throwaway web prototype (`Docs/prototype/recap_data_pipeline.py`) is
the executable spec — it already did EXIF → stops → route → snap → recap on a
real 13-day, 170-photo trip. Port that pipeline into the app; do not reinvent it.

Shape (all tunables → `TrackingConfig.json`, typed mirror + `ConfigLoaderTests`):

1. **Schema v2 migration** (spec §3): one forward migration adding
   `trip.source` (`recorded | imported_timeline | imported_photos`, default
   `recorded`), `segment.source` (`gps_hifi | gps_passive | timeline | exif`),
   `photo_ref.order_idx`. Migration test round-trips old→new. Only `exif` /
   `imported_photos` are *written* this phase; `gps_passive` is for passive
   capture (Capture Beta); `imported_timeline` / `timeline` stay reserved for
   forward-compat only — the Google Timeline importer was **dropped** as
   redundant (owner 2026-07-20; spec §4.7).
2. **`Core/ImportKit/` photo-EXIF importer.** Input: a user-selected album or
   date range (PhotoKit, limited-access compatible). Read EXIF GPS + timestamp;
   cluster into stops (time-gap + distance heuristics — `import.*` tunables);
   build a time-ordered coarse route; write a `trip` (`source='imported_photos'`),
   `segment`s (`source='exif'`), `stop`s, `photo_ref`s attached to their stop by
   construction. No PhotoKit type leaks past the importer boundary; pure
   clustering logic is unit-tested against a fixture EXIF set (deterministic).
3. **Road reconstruction** via the existing `RouteMatchService` / `OSRMMatchProvider`
   (§4.4) — sparse geotags look wrong unsnapped. Low confidence must render as
   **inferred** (dashed), never invented (the gate rejects sea/mountain/wrong-road).
4. **Honest provenance (spec §3/§6):** imported trips are labeled
   *reconstructed from photos*, never "Verified Trip". S1 card gets a source
   badge; S3 gets a provenance note. This is a product rule, not decoration.
5. **Feed the existing pipeline unchanged:** the imported trip must flow through
   Trip Detail (S3), `RecapComposer`, and `ExportEngine` with **no special
   casing** — an imported trip and a recorded trip are the same downstream.
6. **S1 entry point:** `Import from photos` is the MVP hero action (spec §5 S1).

Definition of done: a fixture photo set imports to a trip with the expected
stop count + total distance (CI, deterministic); the imported trip renders in S3
and exports a recap in the simulator; provenance is visible; no DB hand-editing
anywhere in the flow. Artifact: a sim screen recording + the fixture in
`Docs/demos/phase3_5/import/`.

### Status — §1 landed 2026-07-21 (engine + S1 UI + provenance)

Engine (schema v2, `Core/ImportKit/`, `TripRepository.saveImportedTrip`,
`ImportService`, `PhotoLibraryImportSource`) shipped earlier and is CI-green.
This session added the **S1 UI + honest-provenance labels**, closing the DoD
except the device-only steps:

- [x] **Schema v2** — `trip.source` / `segment.source` / `photo_ref.order_idx`,
      `TripSource` / `SegmentSource` (`Core/Persistence/Provenance.swift`). Only
      `imported_photos` / `exif` are written this phase. Round-trip test:
      `TripRepositoryTests.testImportedTripRoundTripsWithHonestProvenance`,
      `SchemaTests`.
- [x] **`Core/ImportKit/` importer** — `PhotoImportClusterer.plan` +
      `PhotoDeckSelector`; pure, no PhotoKit. `import.*` tunables in
      `TrackingConfig.json` (`+ default_range_days` for the S1 picker default,
      2026-07-21). Deterministic unit + E2E tests.
- [x] **Road reconstruction** — `ImportService` calls `RouteMatchService`
      best-effort; `matching.base_url` ships `""` so it is a no-op until a
      server exists. Low-confidence → inferred is inherited from §4.4 (unchanged).
- [x] **Honest provenance (S1 badge + S3 note)** — S1 card shows a `From photos`
      badge, S3 shows "reconstructed from your photos… not a recorded track",
      never "verified" (`HomeView`, `TripDetailView`). All copy zh-Hant-first in
      the String Catalog; `LocalizationTests.testProvenanceStringsResolve`
      asserts the note never contains "verified".
- [x] **Feeds the pipeline unchanged** — proven by
      `ImportPipelineE2ETests.testImportedTripFlowsThroughRecapComposer`; the
      demo S3 shot renders the same map/stats/timeline/recap-button as a
      recorded trip.
- [x] **Stop naming surfaces for imported trips** (device-test follow-up
      2026-07-21). Naming was already wired (`StopNamer`, shared with recorded
      trips) but a one-shot `t+3 s` reload never surfaced names for a
      photo-dense trip whose stops geocode over ~30 s (`geocode.min_interval_s`
      throttle). Fix: `StopNamer.nameUnnamedStops` gained an `onNamed` callback;
      `TripDetailModel` reloads (coalesced) as each name lands. Verified in-sim
      — an imported trip with unnamed stops fills in progressively. No
      import-specific code; recorded trips benefit too.
- [x] **S1 entry point** — `Import from photos` hero action (`HomeView`); live
      capture (vehicle picker + Start Journey) demoted to a secondary section
      per §5 S1. Wired: hero → `ImportSheet` (date range) →
      `PhotoLibraryImportSource` → `ImportService.importTrip` → dismiss + push S3.
      Progress + friendly `notEnoughGeotaggedPhotos` / denied-access errors are
      wired (`ImportFlowModel`). Demo: `Docs/demos/phase3_5/import/`.
- [ ] **Device-only (flagged, NOT marked passed):** live PhotoKit date-range
      fetch from real geotagged photos, and the **Limited Photo Library** path
      (`ImportSheet` "Select More Photos" → `presentLimitedLibraryPicker`) —
      simctl can't answer the iOS 26 photo prompt or seed EXIF assets. Folds
      into the §6 three-trip release gate. See the demo README.

## 2. MapLibre souvenir-map substrate (spec §4.5, `Docs/vector-tile-pipeline.md`)

Read `Docs/vector-tile-pipeline.md` first — implementer guide + the design
quality bar (a **design review**, not the release gate — spec §4.5 revised).

1. Tile build: Planetiler → PMTiles from the same Geofabrik extracts as OSRM.
   Check a small fixture-area PMTiles extract into `Tests/Fixtures/tiles/` for
   deterministic golden frames; full-region files stay out of git.
2. Add MapLibre Native iOS via SPM in `project.yml` (app target). The
   `.xcodeproj` is generated — never hand-edit; run `xcodegen generate`.
3. `MapLibreSnapshotProvider` conforming to the existing `RecapSnapshotProviding`
   (`Core/ExportEngine/RecapSnapshot.swift`, `MapKitSnapshotProvider.swift` for
   the contract — projection must travel with the snapshot). **All MapLibre
   imports live in that one file.** No multi-renderer abstraction — the protocol
   already is the boundary.
4. A first functional (not yet styled) Kamome style JSON so frames render;
   `FlatSnapshotProvider` still backs golden-frame CI. `MapKitSnapshotProvider`
   stays until the theme clears the design review, then dies in that same PR.
5. Real geometry + **subtractive** style (coastline / water / terrain only; no
   POI, no road labels) — this is the "紀念品地圖" the prototype validated. Not a
   generic navigation map.
6. Deferred gaps stay deferred until a consumer exists: pitch/bearing in the
   snapshot request arrives with the follow-cam (§4); `RecapTheme` overlay
   tokens arrive with Modern Minimal (§3).

### Status — §2 substrate landed 2026-07-21 (functional, MapKit still shipping)

Machinery for the substrate is in on `phase-3-recap`; the shipping base map is
**still MapKit** until §3 clears Chiu's design review (then MapKit dies in that
PR). Decisions + rationale: `decisions.md` 2026-07-21.

- [x] **Tile build** — `Tests/Fixtures/tiles/generate_tiles.sh` (Planetiler via
      Docker; local Java is 11, the image bundles Java 21) → small Perth-corridor
      `perth-2026-07-19.pmtiles` checked in. Full-region tiles stay out of git.
- [x] **MapLibre SPM `6.27.0`** (exact) in `project.yml`, app target. Resolves +
      links; the build **compile-checks** the `MLN*` API usage.
- [x] **`MapLibreSnapshotProvider`** (`App/Services/`, **not** the SwiftPM core —
      keeps package tests SDK-free; decisions.md 2026-07-21) conforming to the
      existing `RecapSnapshotProviding`. `import MapLibre` in that one file only,
      **CI grep gate** enforces it. Projection travels with the snapshot
      (`MLNMapSnapshot.point(for:)`); span→zoom via Web Mercator, `scale = 1`.
- [x] **Pure style resolver** `RecapMapStyle` (no SDK) injects the on-disk tiles
      path into the theme's `pmtiles://__KAMOME_TILES__` sentinel — unit-tested
      (`Tests/AppTests/MapLibreSubstrateTests.swift`), so the tile wiring is
      verified without a Metal render.
- [x] **Functional subtractive theme** `Config/RecapThemes/functional-base.json`
      (land/water/road skeleton, no POI/labels) + `README.md` Maputnik workflow.
      **Not** Modern Minimal.
- [x] **Golden-frame CI unchanged** — still `FlatSnapshotProvider`, bit-stable,
      no live tiles/Metal/network.
- [ ] **Device/sim-only (flagged, NOT passed):** the actual MapLibre pixel
      output — `pmtiles://` tiles loading, the subtractive style rendering,
      threading of `MLNMapSnapshotter` off the render loop — plus the
      pmtiles://-vs-mbtiles:// ingestion confirmation. Metal is not in CI (§8);
      this folds into the §3 design review + the §6 three-trip gate. Ingestion
      scheme is theme-JSON-declared, so a fallback is a one-line edit.

## 3. Modern Minimal theme — the ONE MVP theme (spec §4.5, Chiu in the loop)

Vision: `Docs/kamome-animation-vision.md`. The **one** publishable theme.
**Multiple themes are explicitly not an MVP success condition** — theme swap
stays feasible through the boundary, but do not spend product time proving
abstraction. Theme tokens land in `RecapTheme` during this step, not before.
Engine ↔ theme stay decoupled; Modern Minimal is the first theme, never a
structural assumption. Design review: side-by-side stills vs. the P3 artifact at
matched camera positions, **Chiu signs off** — post the comparison and stop; do
not self-certify. (This review keeps the substrate honest; it does **not**
replace the three-trip release gate — spec §4.5 revised.)

### Status — §3 kicked off 2026-07-21 (DRAFT theme + review harness; awaiting Chiu)

Blocked on a human sign-off + a real Metal render (neither is available to an
agent in CI), so only the **buildable, verifiable groundwork** landed; the visual
is **not** self-certified and **MapKit is still the shipping base map**
(`RecapModel` untouched).

- [x] **Draft base style** `Config/RecapThemes/modern-minimal.json` — refined
      subtractive cartography from the vision doc (restrained desaturated palette,
      water/land contrast, landcover tint, road hierarchy with subtle casing).
      **Marked DRAFT in its metadata; unrendered/unverified here.** Bundled as an
      app resource so it can be rendered on sim/device.
- [x] **Design-review harness** `Docs/demos/phase3_5/modern-minimal/README.md` —
      the matched-camera procedure vs. `Docs/demos/phase3/still-*.png`, the
      quality-bar checklist Chiu applies, and the sign-off-gated follow-ups.
- [ ] **Needs Chiu + a real render (NOT done):** render Modern Minimal stills on
      sim/device, side-by-side vs. the P3 artifact, **Chiu signs off**. Only then:
      sparse place labels + glyph pipeline (zh-Hant via `localIdeographFontFamily`),
      the overlay `RecapStyle.modernMinimal` preset, the `RecapModel`→MapLibre
      **switch that retires `MapKitSnapshotProvider`**, and OSM end-card
      attribution — all in that one switch-over PR. If the bar proves unreachable
      after honest iteration, **reopen the substrate ADR** (do not lower it).

## 4. Vehicle-focused follow-cam (spec §4.5 step 1; prototype §2.3)

Reference: `Docs/prototype/README.md` §2.3, `decisions.md` 2026-07-20. The one
thing the prototype did not achieve — Chiu's verdict: "只有路線移動而已沒有帶入車子."

Requirement: `CameraPath` emits a **vehicle-locked follow trajectory** (per-frame
position + heading + zoom) where the **vehicle is the subject** — large, roughly
centred, close **heading-up** zoom, map + route translating underneath so it
reads as *driving forward through terrain*. Wide establishing shots become
explicit keyframes reserved for title / end / day-transitions.

- **Not dogma (spec §4.5, 2026-07-20):** "vehicle centred for the whole film" is
  an MVP simplification. Story Director (Phase 4) will make the follow-cam **one
  narrative shot among many**. So emit the follow trajectory *and* wide keyframes;
  never hardwire "centred vehicle" as the only camera mode.
- Sequenced after §2/§3: the close shot needs the near-terrain detail the
  MapLibre substrate gives at zoom (sparse geometry made the prototype feel empty).
- Marker: **top-down car is the default**; seagull (brand mascot) / scooter /
  bike swappable — a `RecapTheme` / overlay-asset concern, seagull no longer
  forced as the moving marker.
- Tunables → `TrackingConfig.json` (follow zoom, heading-up on/off, wide-shot
  keyframe rules). No magic numbers. Golden-frame CI stays deterministic
  (`FlatSnapshotProvider`); the *feel* is judged on device in §6.

## 5. Basic photo deck @ ~0.8 s (OverlayTimeline; prototype §2.2)

Reference: `Docs/prototype/README.md` §2.2, `decisions.md` 2026-07-20. At each
stop the camera eases to the place and a **photo deck** blooms — a 3-card fan
(peek-left / hero / peek-right) with the **hero cross-fading through that stop's
3–8 photos**, progress dots, dwell scaling with photo count.

- Per-photo hold = **0.8 s** (Chiu revised down from 1.0 s). This + max photos
  per stop → `TrackingConfig.json`.
- Photos come from `photo_ref` rows matched to the stop (§4.3); `is_highlight`
  leads the deck. Deterministic (fixed order + timing) → golden-frame safe.
- Owner-confirmed **not** a full-screen takeover — "bead floating on the map."
- **Explicitly the MVP's *basic* photo presentation, not Story Director.** Do
  not bake in a long-term assumption that every stop carries equal narrative
  weight — Story Director will vary pacing and select/omit stops (spec §7 P4).

## 6. Three-trip dogfood + Replay MVP release gate (needs Chiu + iPhone + real photos)

This replaces the old "combined device day." The Replay MVP does **not** need a
drive — it needs **three of Chiu's real past trips of different character**, each
run fully in-app: **photos import → matching → recap → MP4 → share.**

**Replay MVP hard gate (spec §7 / §10 — a product release gate):**
- [ ] Three real trips of different character all **import successfully from photos**.
- [ ] All three complete **entirely in-app**: import → route reconstruction →
      recap → MP4 → share — **no DB edits, no repo-external tools** (no CapCut,
      no prototype-script data-patching) to fix results.
- [ ] Routes are honest: **no obvious sea-crossing / mountain-crossing straight
      line, no gross wrong-road**; low confidence shown as inferred (§4.4).
- [ ] All three films are ones **Chiu genuinely wants to keep and share**.
- [ ] **≥ 1 published publicly** without external-editing rescue.
- [ ] **Limited Photo Library path passes on a real device.**
- [ ] All three export **stably on a real iPhone** — no crash, no unacceptable
      memory pressure.
- [ ] **Per-trip export time recorded** (S5 readout) and judged *product-acceptable*
      — the retired single < 90 s number is not the criterion.
- [ ] Final judgment: **"a travel-path animation worth publishing," not "the map
      looks prettier than Apple Maps."** (MapLibre-vs-Apple side-by-side is a
      design review only — §3.)

"Three trips" is **hard** — never downgraded to one video. **Chiu signs off.**
Demo artifacts in `Docs/demos/phase3_5/`. This gate = Replay MVP release candidate.

**Merge point (owner call 2026-07-20):** hold the merge to `main` until §6
passes. §1–§5 land the machinery; §6 validates it on three real trips; the whole
Replay MVP lands on `main` as one PR (or a tight stack).

## Not in the Replay MVP (do not build here)

- Passive / background capture, region-resume, ≥ 3-day battery, "arm once" —
  **Capture Beta (Phase 5)**; its device checklist is preserved, not passed
  (`Docs/device-test-P3.md`, `-P1.md`, `-P5.md`).
- Auto moment-selection, hero photos, chapters/elision, variable pacing, edit
  controls, video beads, licensed music/beat-sync — **Story Director (Phase 4)**,
  only after the MVP proves films get shared. (Deterministic scoring, **no AI/LLM
  tokens** — owner constraint 2026-07-20; spec §7 Phase 4. Google Timeline
  importer dropped as redundant.)
- Plans / Get this route — **Phase 6**, further deferred.

## Standing rules (unchanged, restated because they get violated under pressure)

- Phase gates are hard gates. This work order reorders around a product
  decision; it waives nothing. No gate item marked passed without its artifact.
- No magic numbers — new tunables go in `TrackingConfig.json` + typed mirror +
  `ConfigLoaderTests` assertions (every key required; a missing key is a startup
  error, and `AppConfigTests` guards the bundled copy).
- Verification before every commit: `xcodegen generate`, full xcodebuild test
  run, `swiftlint` (toolchain override note in CLAUDE.md).
- Golden-frame CI stays bit-stable: no live tiles, no randomness, no network in
  tests. Recorded fixtures only.
- Renderer/SDK confinement: MapLibre, MapKit, OSRM, PhotoKit types each stay in
  their one boundary file.
- The `.xcodeproj` is generated — change `project.yml`, re-run `xcodegen`.
- User-facing copy: zh-Hant first (`String(localized:)` + xcstrings), never the
  word "fork", never "Verified Trip"; log timestamps in local time with offset.
- Flag anything needing the physical device in the session summary instead of
  attempting it.
