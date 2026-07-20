# Handoff — Phase 3.5 continuation (written 2026-07-19)

Written for the next Claude session picking up `phase-3-recap`. Everything
here assumes you have read `CLAUDE.md` first. Work through the numbered
sections **in order** — the sequence is a spec rule (§7 / decisions.md
2026-07-19), not a suggestion. When in doubt, prefer doing less: every
tunable goes in `Config/TrackingConfig.json`, every renderer SDK stays
confined to one provider file, and no gate item is ever marked passed
without the artifact that proves it.

## State at handoff

- Branch `phase-3-recap`, all committed, full suite green
  (`xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`),
  swiftlint clean. PR #7 (phantom guard) is the base; this branch stacks on it.
- **P3 is NOT closed.** Its four remaining gate items need Chiu's physical
  iPhone (`Docs/device-test-P3.md` items F–H plus the 2 h drive and
  limited-photo re-check; item C region-resume re-validation rides the same
  drive). Owner decision (decisions.md 2026-07-19): P3.5 fixture work
  proceeds in parallel; the device items get executed when hardware is
  available and **must** be done before the P3.5 gate is judged. Do not
  mark them done. Do not "simulate" them.
- §4.4 matching **app side** is landed and dormant (decisions.md 2026-07-19
  matching entry): `Core/RouteMatching/`, `RouteMatchService`,
  `RecapComposer` snapped-geometry preference, `matching` config block with
  `base_url: ""` = disabled. Nothing runs until a server exists.

## 1. Stand up OSRM and validate matching end-to-end  ✅ DONE 2026-07-19

Kept for the record — matching validated end-to-end (road-matched perth
fixture, recorded `/match` CI replay, before/after artifact in
`Docs/demos/phase3_5/matching/`; `decisions.md` 2026-07-19 matching).
`matching.base_url` reverted to `""` as required. Original checklist below.

Follow `Docs/osrm-setup.md` literally. Definition of done:

1. `docker compose up -d` serving Taiwan (:5000) and Australia (:5001).
2. The curl smoke check in that doc returns `"code": "Ok"`.
3. Set `matching.base_url` to `http://127.0.0.1:5001` (perth fixture =
   Australia), run the app in the simulator, export a recap of the perth
   fixture trip, and visually confirm the replay follows road curves where
   `Docs/demos/phase3/` cuts corners. Save a before/after frame pair into
   `Docs/demos/phase3_5/matching/`.
4. Capture one real `/match` response for a perth-fixture segment into
   `Tests/Fixtures/osrm/` (name it after the segment), and add a CI test
   that replays it through `OSRMMatchProvider`'s injectable `transport`
   asserting the decoded geometry stays within a small tolerance of the
   recorded polyline. Pattern: `Tests/CoreTests/RouteMatchingTests.swift`.
5. Revert `base_url` to `""` before committing — the shipped default stays
   disabled until region auto-selection exists (P4). The dev value belongs
   in your local working copy only.

Gotchas: chunk cap is OSRM's default 100 — don't raise `matching.chunk_size`.
Do not lower `matching.confidence_min` to force sparse traces to match.
If Docker isn't available on the machine, say so in the session summary and
skip to section 2 — MapLibre work doesn't depend on a live OSRM.

## 2. MapLibre substrate (§7 step 2, ~1–2 sessions)

Read `Docs/vector-tile-pipeline.md` first — it is the implementer guide and
contains the quality bar. Summary of the shape:

1. Tile build: Planetiler → PMTiles from the same Geofabrik extracts
   (commands in the pipeline doc). Check a small fixture-area PMTiles
   extract into `Tests/Fixtures/tiles/` for deterministic golden frames;
   full-region files stay out of git.
2. Add MapLibre Native iOS via SPM in `project.yml` (app target) — the
   `.xcodeproj` is generated, never hand-edit it; run `xcodegen generate`.
3. `MapLibreSnapshotProvider` conforming to the existing
   `RecapSnapshotProviding` (see `Core/ExportEngine/RecapSnapshot.swift` and
   `MapKitSnapshotProvider.swift` for the contract — projection must travel
   with the snapshot). **All MapLibre imports live in that one file.** No
   multi-renderer abstraction layers — the protocol already is the boundary.
4. A first functional (not styled) Kamome style JSON so frames render; wire
   provider selection so `FlatSnapshotProvider` still backs golden-frame CI.
   `MapKitSnapshotProvider` stays until the theme clears the quality bar,
   then dies in the same PR that passes it.
5. Deferred gaps stay deferred until their consumer exists: pitch/bearing in
   the snapshot request arrives only with the isometric camera work;
   `RecapTheme` overlay tokens only with Modern Minimal.

## 3. Modern Minimal theme (§7 step 3, ~1–2 sessions, Chiu in the loop)

Vision: `Docs/kamome-animation-vision.md`. The gate is subjective by design:
side-by-side stills vs. the P3 artifact at matched camera positions, **Chiu
signs off** — post the comparison and stop; do not self-certify. Quality bar
specifics are in spec §4.5 (v1.5 block). Theme tokens land in `RecapTheme`
during this step, not before. Engine ↔ theme stay decoupled: Modern Minimal
is the first theme, never a structural assumption.

## 4. CameraPath → vehicle-locked follow-cam (§4.5 step 1 rework, prototype-derived)

Reference: `Docs/prototype/README.md` §2.3, `decisions.md` 2026-07-20 — the ONE
thing the web prototype did not achieve, so it is the app's headline acceptance
test. Chiu's verdict on the wide route-draw: "只有路線移動而已沒有帶入車子."

Requirement: `CameraPath` must emit a **vehicle-locked follow trajectory**
(per-frame position + heading + zoom) where the **vehicle is the subject** —
large, roughly centred, at a close **heading-up** zoom with the map + route
translating (and preferably rotating) underneath, so it reads as *driving
forward through terrain*. Today it interpolates along the full polyline at a
fixed wide frame — that is exactly what reads as "only the route moves." Wide
establishing shots become explicit keyframes reserved for title / end /
day-transitions.

- Sequenced after §2/§3 on purpose: the close shot needs the near-terrain
  detail the MapLibre substrate gives at zoom (sparse geometry made the
  prototype's follow feel empty).
- Marker: **top-down car is the default**; seagull (brand mascot) / scooter /
  bike swappable — a `RecapTheme`/overlay-asset concern, the seagull is no
  longer forced as the moving marker.
- Tunables → `TrackingConfig.json` (follow zoom, heading-up on/off, wide-shot
  keyframe rules). No magic numbers.
- Golden-frame CI stays deterministic (`FlatSnapshotProvider`); camera math is
  testable frame-by-frame. The *feel* is judged on device in §6.

## 5. Stop photo deck @ 0.8 s (OverlayTimeline enrichment, prototype-derived)

Reference: `Docs/prototype/README.md` §2.2, `decisions.md` 2026-07-20. Richer
than today's single stop-card: at each stop the camera eases to the place and a
**photo deck** blooms — a 3-card fan (peek-left / hero / peek-right) with the
**hero cross-fading through all of that stop's 3–8 photos**, progress dots,
dwell length scaling with the photo count.

- Per-photo hold = **0.8 s** (Chiu revised down from 1.0 s). This and
  max-photos-per-stop → `TrackingConfig.json`.
- Photos come from `photo_ref` rows already matched to the stop (§4.3);
  `is_highlight` leads the deck.
- Owner-confirmed **not** a full-screen takeover — "bead floating on the map."
- Deterministic (fixed photo order + timing) → golden-frame safe.

## 6. Then: the combined device day (needs Chiu + iPhone)

One drive covers P3 items (2 h drive, region-resume item C, limited-photo
re-check, < 90 s budget via S5 readout, S5 UX pass) and the P3.5 judgments on
the MapLibre substrate: budget re-proof, the §4 follow-cam reading as the
vehicle *driving* (not just the route moving), and the §5 photo deck feeling
right at 0.8 s. Only after that: P3 closes, P3.5 gate judged (including "Chiu
posts one recap somewhere real"), demo artifact in `Docs/demos/phase3_5/`.

**Merge point (owner call 2026-07-20):** hold the merge to `main` until here.
P3.5 finishes §2–§5 first, then this one device day validates P3 + P3.5
together, and the whole recap-visual-system lands on `main` as one PR.

## Standing rules (unchanged, restated because they get violated under pressure)

- Phase gates are hard gates. This handoff reorders work around a hardware
  constraint; it waives nothing.
- No magic numbers — new tunables go in `TrackingConfig.json` + typed mirror
  + `ConfigLoaderTests` assertions (every key is required; a missing key is
  a startup error, and `AppConfigTests` guards the bundled copy).
- Verification before every commit: `xcodegen generate`, full xcodebuild
  test run, `swiftlint` (toolchain override note in CLAUDE.md).
- Golden-frame CI must stay bit-stable: no live tiles, no randomness, no
  network in tests. Recorded fixtures only.
- User-facing copy: zh-Hant first (`String(localized:)` + xcstrings), never
  the word "fork", log timestamps in local time with offset.
- Flag anything needing the physical device in the session summary instead
  of attempting it.
