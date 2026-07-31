# §6 Replay MVP gate — owner runbook

Consolidated 2026-07-31, after the visual/pacing work closed. The gate items
themselves live in `Docs/handoff-P3.5.md` §6 and are unchanged; this is the
**order to do them in**, and it is written for Chiu rather than for an
implementer. Everything here needs a human, a phone, or real photos — there is no
remaining dev work in front of it.

The ordering principle: **every judgment you can make at the desk, make at the
desk.** A film that isn't worth publishing is a design problem, and finding that
out on the phone costs a side-load, an import and an export per attempt. Stages 0
and 1 are cheap and repeatable; stage 2 is not.

---

## Stage 0 — real data (desk, ~30 min, do this first)

**The four trip fixtures are placeholders.** Every one of them is hand-written
plausible coordinates, not a photo dump:

| fixture | photos | span | what it is |
|---|---|---|---|
| iceland | 16 | 9.8 h | Golden Circle, invented timestamps |
| new-zealand | 13 | 9.2 h | SH1/SH8/SH80, invented |
| finland | 11 | 8.8 h | Helsinki → Porvoo, invented |
| miyakojima | 13 | 9.8 h | Hirara → Higashi-Hennazaki, invented |

Real trips differ in the ways that matter most: photo counts per stop (which
drives dwell and therefore the whole duration plan), how far off-road the EXIF
fixes land (PD-3's detour gate), and whether a region's tiles actually contain
the trip.

- [ ] **Dump each real trip.** `./Tools/exif-to-fixture.sh ~/Pictures/<trip> <name> "<title>"`
      — reads place + time only, copies no image data, overwrites the placeholder.
- [ ] **Check coverage** with the `pmtiles-bounds.sh` line the script prints. A
      trip that escapes its region renders as Apple Maps, not as a broken map, so
      this fails quietly if you skip it.
- [ ] **Pick the three gate trips** from the four candidates — "different
      character" is the requirement: a long drive, a dense walk-heavy day, and
      something with an inferred leg in it.

## Stage 1 — judge each trip at the desk (~5 min per trip)

Run all three in ascending cost. Any of these can send you back to stage 0 with a
different trip.

- [ ] **Measure the pacing** (no render):
      ```
      TEST_RUNNER_KAMOME_TIMELINE_REPORT=<name> …
      ```
      Watch for: total duration inside 60–90 s, a longest-still that is not
      absurd, and the leg list — `drive/inferred` and `walk/inferred` are the legs
      that will draw dashed.
- [ ] **One stop still** (`RecapStopStillTests`) — is the busiest stop's
      composition right on this trip's real photographs?
- [ ] **32 s pilot** (`RecapPilotFilmTests`) — the opening and the first two stops
      at real pacing.
- [ ] **Decide, per trip: is this worth publishing?** This is the gate's real
      question and you can answer most of it here.

**Terrain is handled now** (2026-07-31). It lives behind its own
`KAMOME_TERRAIN_PATH`, which nobody was setting, so every render before that date
silently had no hillshade. `RecapReviewScene` now defaults it from the tiles path
and **prints the DEM it resolved**, so a flat render says so:

```
KAMOME_REVIEW region iceland-2026-07-29.pmtiles · terrain iceland-terrain.pmtiles
```

If that line ever says `terrain NONE — the map will be flat`, stop and fix it
before judging the film.

```
TEST_RUNNER_KAMOME_TILES_PATH=$HOME/kamome-osrm/tiles \
TEST_RUNNER_KAMOME_OSRM_BASE_URL=http://127.0.0.1:5100 \
TEST_RUNNER_KAMOME_STOP_PHOTOS=<folder of the trip's real jpegs> \
TEST_RUNNER_KAMOME_RENDER_OUT=<out> …
```

## Stage 2 — the iPhone (one sitting, the expensive part)

Pre-flight, or the first three items will fail confusingly:

- [ ] `matching.base_url` = the **Mac's LAN address** (not `127.0.0.1`), phone and
      Mac on the same Wi-Fi, OSRM reachable from the phone's browser.
- [ ] Side-load the three regions' `.pmtiles` over Finder (Files → Kamome),
      **and each region's `<name>-terrain.pmtiles` beside it** — the DEM carries
      the hillshade. Both may sit loose at the top level; the lookup tells them
      apart by the `-terrain` suffix (fixed 2026-07-31, was `terrain/`-only).

Then, per trip:

- [ ] **Import from the real photo library** → first time PD-3's outlier gate
      meets real EXIF.
- [ ] **Open the trip detail screen and let the stop names land** before
      exporting. Geocoding runs from S3 only (`TripDetailModel` → `StopNamer`), so
      a film exported without visiting S3 is full of "Unnamed stop". This is the
      most likely way to waste an export.
- [ ] **Export MP4**, note the render-time readout (device-test-P3 item F).
- [ ] **Share sheet** → plays in Photos/Messages.

Once, not per trip:

- [ ] **Limited Photo Library path** (Selected Photos) — device-test-P3 item H,
      never exercised on hardware.
- [ ] **S5 UX pass** — device-test-P3 item G, the full list.
- [ ] Memory pressure / no crash across all three exports.

## Stage 3 — sign-off

- [ ] **Honesty review**: look at a published film with a dashed leg in it and
      agree it reads as *"Kamome is guessing here"*. Pixel tests prove the two
      strokes differ; only you can say the difference communicates. (PD-1/PD-2)
- [ ] **≥ 1 published publicly**, no external editing.
- [ ] **All three are films you want to keep.** "A travel-path animation worth
      publishing" — not "the map beats Apple Maps".

---

## Not on this list, on purpose

- **OSRM, not ORS.** There is no OpenRouteService integration anywhere in the
  repo and none is planned in the handoff — routing is self-hosted OSRM
  (`Deploy/`), merged across all four regions, serving on `:5100`. If ORS is
  something you are considering, it is a new decision, not a status check.
- **VPS shared-token auth** — deferred by owner call 2026-07-29, still flagged in
  `handoff-P3.5.md` §"VPS migration". Not a gate item: on home Wi-Fi there is
  nothing to authenticate against.
- **Photo-deck polish and the fan/stack carousel** — agreed post-wrap.
- **"Unnamed stop" in the demo fixtures** — a harness artifact (the render
  harnesses never open S3, so nothing geocodes). Real device runs name their
  stops; see the stage-2 note.
