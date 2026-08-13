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
- [x] **In-sim render CONFIRMED 2026-07-22** (`ModernMinimalRenderTests`,
      env-gated, writes stills). MapLibre 6.27.0 loads the pmtiles and renders the
      subtractive style in the simulator; ingestion path resolved to
      `pmtiles://file:///…` (`RecapMapStyle` injects the file URL — decisions.md
      2026-07-22 / pipeline §5). First-look stills in
      `Docs/demos/phase3_5/modern-minimal/`.
- [ ] **Still device-only / §6 gate (NOT passed):** `MLNMapSnapshotter` threading
      under the *full* export render loop, and the on-device render/budget. Metal
      stays out of CI (§8). Aesthetic sign-off is §3 (Chiu). New §3 item surfaced:
      MapLibre bakes its own wordmark + attribution into snapshots — cover or
      suppress at the switch-over.

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

### Status — §3 substrate SIGNED OFF for now (Chiu, 2026-07-22); remainder deferred

Chiu's call 2026-07-22: **the MapLibre substrate + base-style direction is accepted
("this is not the MapLibre issue") — stop iterating the base style.** The real
dissatisfaction is the **overall recap output / video format**, to be redesigned in
a **separate session** ("revisit all the difference"). So §3 is signed off *as the
substrate*, and the visual-polish + switch-over items are deliberately deferred.

- [x] **MapLibre substrate accepted** — `MapLibreSnapshotProvider` + tiles render
      correctly in-sim (decisions.md 2026-07-22). Not a substrate problem.
- [x] **Base style direction settled** — dark atmospheric **souvenir map** (draft
      v2, `Config/RecapThemes/modern-minimal.json`): dark sea, slate land, glowing
      coastline, pale ice, no roads/POI/labels. v1 (pale desaturated OSM) rejected.
      Stills in `Docs/demos/phase3_5/modern-minimal/`. **Not pixel-final** — polish
      folds into the redesign below.
- [ ] **DEFERRED to the recap-output redesign session (NOT done):**
      - **Compositor atmosphere** — vignette, route/marker glow, vertical grade as
        `RecapTheme` tokens in `RecapFrameCompositor` (where most of the crafted
        feeling lives; the base style alone reads flat).
      - **Output video format** — Chiu wants the overall recap output revisited
        (aspect/size/duration, container/delivery, in-frame template/chrome,
        follow-cam animation §4/§5). Open discussion; no decisions yet.
      - **The switch-over PR** — sparse labels + glyph pipeline (zh-Hant via
        `localIdeographFontFamily`), overlay `RecapStyle.modernMinimal` preset,
        `RecapModel`→MapLibre switch that **retires `MapKitSnapshotProvider`**, OSM
        end-card attribution. **Held** until the atmosphere + output format land —
        **MapKit stays the shipping base map** until then (do not flip early).

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

### Status — §4 and §5 COMPLETE 2026-07-25 (`ce28db6` + `2917008`, `phase-3-recap`; NOT merged)

The framing half landed 2026-07-23 (`3eac0ab`, detail below). The **visual half**
— vehicle subject and photo deck — landed 2026-07-25 together with the Layer 3
render wiring, and Chiu signed it off. **See `Docs/handoff-recap-visuals.md`**;
it also lists what remains before PR #11. Headlines, because they reverse
decisions recorded further down this file:

- The camera is **static**: one fixed frame per act, re-framed only across a
  >25 km jump. No follow-cam, no stop dolly. The map is **north-up and never
  rotates** (heading-up was tried and abandoned);
  the vehicle carries the heading as an **8-direction sprite set**, nearest-bucket
  selected, never rotated at runtime. `FollowCamMode` was removed.
- The photo deck is a **zoom-in reveal** (0.30 → 0.50 frame width) on its own
  envelope, deliberately a different curve from the camera dolly.
- The stop plays **two beats**: pin + name floating clear above the vehicle, then
  cross-fading out as the photo card takes over the stop's identity beneath it.

The rest of this section is the 2026-07-23 camera-core record, still accurate:

- `CameraPath` now emits **two** outputs: `Position` (the vehicle — lat/lon +
  `heading`, the route tangent) and a new `CameraFrame` (the snapshot —
  center/span/`bearing`). Title/end windows frame the whole trip (wide); the body
  eases to a close span locked on the vehicle over `zoom_transition_s`. Camera ≠
  vehicle: in wide shots the camera centers the trip while the vehicle sits small
  in place — that separation is what makes "establishing shot → dive into the drive."
- `RecapSnapshotProviding` gained `bearing` (heading-up): `MapLibreSnapshotProvider`
  honors it (`MLNMapCamera.heading`), `FlatSnapshotProvider` rotates its projection
  for CI determinism, `MapKitSnapshotProvider` accepts-and-ignores (retiring
  north-up path). `RecapRenderLoop` drives snapshots from `cameraFrame`.
- New tunables `wide_span_padding` / `zoom_transition_s` / `follow_heading_up`
  (**default false** = north-up map + rotating marker, the validated prototype
  behavior; heading-up map rotation is a MapLibre-era opt-in). The close span
  reuses `camera_span_m` (default kept 1500) — **tune on a device render**, not guessed.
- 6 new framing tests (wide/close spans, tiny-trip floor, monotonic zoom-in,
  heading direction, bearing gated on `follow_heading_up`).

**Remaining for §4 — the visual half (`RecapFrameCompositor`):** replace the red
head dot with a **top-down car marker** rotated to `Position.heading` (screen
rotation = `heading − bearing`; swappable via theme), plus the §5 photo deck. Judge
the follow-cam *feel* on device (§6) over the MapLibre substrate at close zoom —
`FlatSnapshotProvider` stills can pre-check the *layout* (car size, photo framing)
deterministically first.

## 5. Basic photo deck @ ~0.8 s (OverlayTimeline; prototype §2.2)

Reference: `Docs/prototype/README.md` §2.2, `decisions.md` 2026-07-20. At each
stop the camera eases to the place and a **photo deck** blooms — a 3-card fan
(peek-left / hero / peek-right) with the **hero cross-fading through that stop's
3–8 photos**, progress dots, dwell scaling with photo count.

- Per-photo hold = **0.8 s** (Chiu revised down from 1.0 s). This + max photos
  per stop → `TrackingConfig.json`.
- Photos come from `photo_ref` rows matched to the stop (§4.3); `is_highlight`
  leads the deck. Deterministic (fixed order + timing) → golden-frame safe.
- **Revised 2026-07-23 (Chiu):** the deck should **zoom the photo IN — enlarge it
  to a clear, prominent size — then zoom back out to the map** once the stop's
  photos finish. So the deck carries a **scale envelope over the dwell** (grow →
  hold & rotate 0.8 s/photo → shrink back), not a constant small bead. This
  *revises* the earlier "bead floating on the map, not a takeover" note below:
  bigger and clearer at peak, but it still returns to the map (not a hard
  full-screen cut). Deterministic scale keyframes → golden-frame safe.
- (Superseded) Owner had said **not** a full-screen takeover — "bead floating on
  the map"; the 2026-07-23 revision keeps the "returns to the map" spirit but
  wants the photo enlarged for clarity at peak, not bead-sized throughout.
- **Explicitly the MVP's *basic* photo presentation, not Story Director.** Do
  not bake in a long-term assumption that every stop carries equal narrative
  weight — Story Director will vary pacing and select/omit stops (spec §7 P4).

## 6. Three-trip dogfood + Replay MVP release gate (needs Chiu + iPhone + real photos)

**Split into §6a and §6b on 2026-08-13** (Chiu; ADR in `Docs/decisions.md`). The
single gate below conflated two different questions — *is the film worth
publishing* and *does the product work end to end* — and its "entirely in-app"
clause would have judged Chiu's own desk renders as gate violations. They are now
separate gates over **different variants**, because that is what actually ships:

| | §6a — the film | §6b — the product |
|---|---|---|
| where | the desk (Mac, render harness) | a real iPhone |
| variant | **A** (`recap_mode: full`, harness-only) | **B** (`highlight`, the shipped default) |
| question | is this worth publishing? | does the app do this by itself? |
| trips | three, hard | three, hard |

Neither is downgraded to fewer than three trips, and neither substitutes for the
other. **Chiu signs off on both.** Demo artifacts in `Docs/demos/phase3_5/`.

**Running the gate: `Docs/gate-P3.5-checklist.md`** — the owner runbook, in the
order to do it in. Its stages map onto the split: **Stage 0 + Stage 1 → §6a**,
**Stage 2 → §6b**, Stage 3 spans both. The items below are the gate itself and
stay authoritative; the checklist sequences them and carries the pre-flight traps.
*(The checklist's own prose still describes the pre-split gate — a doc pass owed,
not a contradiction in the items.)*

This replaces the old "combined device day." The Replay MVP does **not** need a
drive — it needs **three of Chiu's real past trips of different character**.

### §6a — the film gate (desk, Variant A)

- [ ] Three real trips of different character all **reconstruct from photo EXIF**
      (`Tools/exif-to-fixture.sh` → the render harness).
- [ ] Routes are honest: **no obvious sea-crossing / mountain-crossing straight
      line, no gross wrong-road**; low confidence shown as inferred (§4.4).
      Judged once here — route reconstruction is the same pipeline in both gates.
- [ ] All three films are ones **Chiu genuinely wants to keep and share**.
- [ ] **≥ 1 published publicly** without external-editing rescue.
- [ ] **No external editing of the film itself** — no CapCut, no DB edits, no
      prototype-script data-patching. The render harness is the sanctioned path
      here; hand-repairing its output is not.
- [ ] Final judgment: **"a travel-path animation worth publishing," not "the map
      looks prettier than Apple Maps."** (MapLibre-vs-Apple side-by-side is a
      design review only — §3.)

**The desk renders are the deliverable.** With this split, Variant A is validated
nowhere else — there is no second gate behind it. `~/kamome-renders` is release
output, not scratch. (Learned the hard way: the first Miyakojima film was written
to `/tmp` and swept before it could be reviewed.)

### §6b — the product gate (real iPhone, Variant B)

- [ ] Three real trips **import successfully from the real photo library**.
- [ ] All three complete **entirely in-app**: import → route reconstruction →
      recap → MP4 → share — **no DB edits, no repo-external tools** to fix results.
- [ ] **Limited Photo Library path passes on a real device.**
- [ ] All three export **stably on a real iPhone** — no crash, no unacceptable
      memory pressure. **Watch specifically for the intermittent
      `KamomeCore_KamomeExportEngine` bundle fatal error** — see `HANDOFF.md`;
      `Bundle.module` in `RecapCarSprite.swift` is on this path and traps rather
      than degrading.
- [ ] **Per-trip export time recorded** (S5 readout) and judged *product-acceptable*
      — the retired single < 90 s number is not the criterion.
- [ ] **S5 UX pass** — `Docs/device-test-P3.md` item G.

### What the split buys, beyond honesty

The same three trips now exist as **two edits each**, which is a free A/B on the
question the MVP is actually asking: *which one do people want to share?* That is
a product experiment enabled by the split, **not a gate item** — nothing here
passes or fails on it.

**Merge point:** hold the merge to `main` until **§6b** passes — it is the app
that merges, and §6b is the app's gate. §6a gates whether the device sitting is
worth spending at all, so it comes first in time. *(This resolves an ambiguity the
split created; the pre-split rule said "until §6 passes." Flagged for Chiu.)*
§1–§5 land the machinery; the whole Replay MVP lands on `main` as one PR (or a
tight stack).

### Local routing + map regions for this gate (Chiu 2026-07-29)

The gate runs against a **local** OSRM on home Wi-Fi, not a VPS. Everything is
declared in `Deploy/` — `regions.json` is the single source for both halves of
the stack, and the same `docker-compose.yml` runs locally and on a VPS later
(`--profile public` adds Caddy). Setup: `Docs/dogfood-infrastructure.md`.

Four regions, chosen because Chiu has real photos from each: **Iceland, New
Zealand, Finland, Miyakojima**. Routing merges them into one dataset (the app has
one `matching.base_url`); tiles stay one `.pmtiles` per region, side-loaded over
Finder.

### VPS migration — deferred security work ⚠️

Tracked here so it is not silently skipped when the migration happens (Chiu
2026-07-29 — explicitly deferred, explicitly not dropped).

- [ ] **Shared-token auth on OSRM, server *and* app in the same change.**
      `Deploy/Caddyfile` carries the server half commented out. The app half does
      **not exist**: `OSRMMatchProvider.swift` and `OSRMRouteProvider.swift` both
      build a bare `URLRequest` with no headers. Enabling the Caddy block alone
      makes every route and match request 403, and because both providers treat a
      failure as "keep raw geometry" (PD-2), **every leg would silently render
      dashed** — indistinguishable from a routing failure, with nothing in the UI
      saying why. Ship both halves together or neither.
- [ ] Token in `Deploy/.env` (git-ignored), never in `TrackingConfig.json` —
      that file is bundled into the app and readable from any IPA.
- [ ] Re-check the endpoint allow-list in `Deploy/Caddyfile` still matches what
      the providers call (`/route`, `/match`, `/nearest`).

Not blocking the §6 gate: on home Wi-Fi the service is not reachable from the
internet, so there is nothing to authenticate against.

### Trips that span two map regions — OPEN, first hit 2026-08-01 🔴

Found on the first real-device import: a six-day Miyakojima trip whose **day 1
starts at a Taiwan airport**. Diagnosed, deliberately not fixed (owner call —
see how single-region trips behave first).

**One cause, three symptoms.** `RecapMapTiles.tilesURL` requires *containment*,
not overlap, so a trip that leaves its region matches nothing:

```
trip bbox        W 121.230  S 24.790  E 125.470  N 25.100
miyakojima       W 125.100  S 24.600  E 125.550  N 25.000   → does not contain
```

`RecapMapRegionResolver.resolve` therefore returns nil, and `RecapModel` turns
that one nil into three separate degradations at once:

1. **Apple's map** instead of the souvenir map (`snapshotProvider(for:)`).
2. **No prologue** — `establishing` is nil, so `LinearTimeline.pacing` returns no
   duration plan and `openingS` is 0. This is the "opening zoom broke" symptom.
3. **30 s flat** — with no plan the film falls back to the retired
   `export.target_duration_s`. A six-day trip came out at 30 seconds.

Symptoms 2 and 3 are **not really about tiles at all** — they are a coupling bug.
Pacing is a story fact (how many stops, how many photos); which tiles are
installed is a rendering fact. The `guard establishing != nil` in
`LinearTimeline.pacing` is the whole of it, and removing it is one line — plus
re-basing the test harnesses that pass a nil extent to mean "short deterministic
film" (~8 suites assume no prologue and a 30 s duration; the clean migration is to
express that in their `TrackingConfig.Export` — `opening_*_s: 0` and
`total_duration_min/max_s == target_duration_s` — rather than through a nil
extent). Attempted and reverted 2026-08-01: correct, but its only beneficiary
today is the multi-region case, so it ships with this.

Symptom 1 is the real multi-region question, and it has several possible shapes —
none chosen: merge the covering regions into one PMTiles; render per-act with a
different region each; accept Apple's map for the crossing act only; or build a
region per trip. **Decide after seeing single-region trips (Iceland/NZ/Finland)
render end to end.**

Now loud, at least: `RecapModel` logs `no installed map region covers this trip`
with the three consequences named, and every film logs its duration, prologue,
stop count and dashed-leg count (`KamomeLog.recap`).

Related, also deferred: the airport-departure animation (a flight leg is a genuine
discontinuity — `act_split_km` already cuts a new act there, but nothing tells the
story of the hop).

### Map reference labels — scoped, wanted, not urgent 📌

**Status: a real implementation pass, deliberately deferred** (Chiu 2026-08-02).
Not a maybe — revisit it properly rather than bolting labels on later.

**The problem it solves.** At body zoom the souvenir map is landform and water
with no names, so a viewer cannot anchor "where am I". Chiu, on the 11-day NZ
film: *once zoomed in I lose all sense of geographic orientation.* A travel
memory film has to let someone recognise where they were, not just watch a line
move. The **wide baseline** (2026-08-02: `wide_span_padding` 1.5,
`camera_pan_window_fraction_per_s` 0.05, so the span ceiling binds and the whole
trip is framed) solves most of it by showing a recognisable country silhouette.
Labels are what is left: *which* lake, *which* pass.

**PD-6 is reopened by this.** The label-less map was a deliberate decision
(2026-07-19, subtractive style = souvenir map). Anything built here must not
drift back toward the Apple-tiles look that decision rejected — the bar is
place and water names at low density, never POIs.

**⚠️ The blocker, found 2026-08-02.** `Config/RecapThemes/modern-minimal.json`
has **no `glyphs` URL**, and there are no glyph PBFs on any dev machine.
MapLibre Native cannot render Latin labels without a fontstack; its local-font
path (`MLNIdeographicFontFamilyName`) covers CJK ideographs only. So this is
**not** a style-JSON-only change, contrary to a first estimate — a symbol layer
added today renders nothing. Two unblock paths, neither yet taken because both
pull third-party code:

1. **Prebuilt pack** — `openmaptiles/fonts` (Noto Sans). Fastest; adds a binary
   font asset to ship or side-load, and a licence to check.
2. **Generate SDF PBFs** from a system TTF with `fontnik` (Node is present on
   the dev Mac). No third-party binaries, but it is a native npm build and adds
   a generation step to the tile pipeline (`Deploy/bin/`).

**Data is not a blocker.** The regions are standard Planetiler builds and
already carry `place`, `water_name` and `mountain_peak`; the current style
simply omits those layers. No re-tiling needed.

**Scope when it is picked up.**
- Style: `glyphs` URL + symbol layers for `place` (city/town/village) and
  `water_name` only. Low density, tuned per zoom.
- **The real work is collision with Kamome's own overlays.** MapLibre places
  labels knowing nothing about the photo deck, the stop cluster or the vehicle,
  so a town name can land under a card or across the trail. Either feed
  exclusion zones into the style per frame (MapLibre cannot do this cleanly from
  a static style) or draw labels in `RecapOverlayRenderer` — the second is a
  subsystem: sourcing, placement, priority, collision.
- Validate the same way the camera was: render NZ and one island trip, judge
  side by side, and consider a gate on labels never overlapping the deck rect.

**Related but separate:** landmark title cards as narrative rhythm
(`icebox.md`, 2026-08-02). That is narration with its own timing; this is
annotation the map carries continuously. Do not conflate them.

### Vatnajökull grey cross — diagnosed, mitigation NOT applied 📌

**A tile seam, not the DEM and not the source data** (2026-08-03). A pale cross
lies across Vatnajökull in every Iceland render, at every display zoom.

Ruled out by experiment:
- **Not terrain.** Rendered with the DEM disabled — the cross is still there.
- **Not overlapping ice/glacier classes.** The style filter matches both; filtered
  to `glacier` alone every Icelandic icecap disappears, so Planetiler emits them
  all as `class: ice` and there is no cross-class double-draw.

Confirmed by measurement. Rendering Vatnajökull at a fixed 100 km span and
shifting the centre, the cross tracks the ground exactly (74 px predicted,
75 px observed). Converting the intersection to tile coordinates:

```
observed cross   lat 64.1754  lon -16.8693
zoom 6           tile-x 29.0010   tile-y 16.9970   ← within 0.1% / 0.3% of a corner
```

It sits on a **z6 tile corner**. A z6 corner is also a corner at every higher
zoom, which is why power-of-two zoom comparisons could not tell it apart from
ground-fixed data — that test is confounded and the centre-shift plus this
arithmetic is what settles it.

**Mechanism.** The ice polygon extends into the tile buffer, both neighbouring
tiles draw the overlap, and at `fill-opacity: 0.26` the doubled region
composites to ~45% — a pale band along the seam. Vatnajökull is the only feature
large enough to straddle a z6 corner, hence exactly one cross rather than a grid.
The same latent flaw sits on every translucent fill (`landcover-scrub` 0.45,
`landcover-wood` 0.55, `park` 0.35); their polygons are too small and fragmented
to show it.

**Two fixes, and the cheap one has a cost:**
1. *Style, one line:* make the ice fill opaque and bake the blend into the colour
   (≈ `#4E5C64`). An opaque fill cannot double-blend. **But `hillshade` is layer
   1 and `ice` is layer 5, so an opaque glacier loses its terrain texture and
   goes flat.** That is a look tradeoff — **Chiu wants to see it before deciding,
   so it is deliberately not applied.**
2. *Tile build, correct:* reduce or clip the landcover polygon buffer in
   Planetiler so neighbouring tiles do not overlap, keeping translucency. Costs a
   rebuild of all four regions.

### Photo deck → fan/stack carousel (future, scoped separately) 📌

Explicitly **not** in the 2026-07-30 cinematic pass (Chiu). The deck today is a
single card that cross-fades between photos; the prototype opens a **fanned
stack**: the stop arrives, the stack fans out, the front card advances roughly
every second through 3-8 photos, with a dot-progress indicator, the photo as the
visual focus (larger than now — the map may shrink or recede behind it).

This is a visual redesign, not a sizing tweak — it changes what `RecapPhotoDeck`
has to express (a stack with per-card transforms, not one focused index), so it
needs its own scoping pass rather than being folded into a styling round. The
2026-07-30 pass raised the card to 0.42→0.58 frame width and gave it a settle
overshoot; that is the interim, not the destination.

### Stop presentation — CSS port landed 2026-07-31 ✅

The 2026-07-31 pass ported the stop's *look* from the prototype's actual CSS
(`Docs/prototype/recap_engine.html`) rather than from its screenshots — every
token in `RecapStyle`'s deck/label block now cites its source declaration.
Details + rationale: `decisions.md` 2026-07-31. Landed:

- Portrait 3:4 hero card, 14 px radius, 3 px white keyline, the prototype's heavy
  drop shadow; two **static** peek cards (`translateX(±52px) rotate(±8deg)
  scale(.9)`) behind it.
- `.hud` metadata pill on the photo (day + place, distance opposite it), and the
  `.clabel` identity block under it: **no plate**, big name over an uppercase
  letter-spaced accent strap, progress dots under that.
- `RecapStopLayout` now mirrors the **whole cluster** rather than flipping the card
  alone — the caption follows its photograph. Swept regression test.
- Pacing unchanged (iceland report identical); camera, route glow, sprite scale and
  map style untouched.
- New review harness `KamomeTests/RecapStopStillTests` — renders **one stop** of a
  real imported trip over live tiles, with real photographs from
  `KAMOME_STOP_PHOTOS`. Use it instead of an MP4 render for still-frame questions.

Still open here: the fan/stack carousel above; "Unnamed stop" geocoding in the
demo fixtures; the pin can touch the card's top edge when a stop sits high in
frame (the deferred overlap item).

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
