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
- [ ] **Let the stop names land before exporting.** Import pushes you to trip
      detail automatically, which is what starts geocoding (`TripDetailModel` →
      `StopNamer`), so nothing is skipped — but names arrive one every
      `geocode.min_interval_s` (2 s), so a nine-stop trip needs ~16 s on that
      screen. Tap the film button immediately and the early stops are named and
      the late ones say "Unnamed stop".
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

---

## Appendix — first device install (going straight to the phone)

For running the real app on real photos without the desk stages. Everything here
is one-time except step 2.

**1 · Signing.** The `.xcodeproj` is generated and git-ignored, so a team picked
by hand in Xcode is **lost on the next `xcodegen generate`**. Add it to
`project.yml` once instead, under the app target's `settings: base:`:

```yaml
        DEVELOPMENT_TEAM: <your 10-char team id>
        CODE_SIGN_STYLE: Automatic
```

Then `xcodegen generate`. Bundle id is `com.chiu.kamome.dev`; on a free Apple ID
the install expires after 7 days and needs a re-run.

**2 · Point the app at your Mac's OSRM.** `matching.base_url` ships `""` and there
is **no environment override in the app** — it is read from the bundled
`Config/TrackingConfig.json`, so this is an edit plus a rebuild:

```bash
ipconfig getifaddr en0        # e.g. 192.168.0.6
```

```json
"matching": { "base_url": "http://192.168.0.6:5100", ... }
```

The compose file already binds `0.0.0.0:5100`, so nothing to change server-side.
**Revert this before committing** — a LAN address in the shipped config is wrong
for everyone else.

**3 · Device prerequisites.** iOS 17+; Developer Mode on (Settings → Privacy &
Security → Developer Mode); phone and Mac on the same Wi-Fi. On a free account,
first launch also needs Settings → General → VPN & Device Management → trust.

**4 · Prove OSRM is reachable *from the phone*, in Safari, before importing:**

```
http://192.168.0.6:5100/route/v1/driving/-21.94,64.14;-21.13,64.25?overview=false
```

JSON with `"code":"Ok"` means good. Do not skip this: `importTrip` awaits
`matchTrip` but treats failure as "keep raw geometry" (PD-2), so a wrong address,
a different Wi-Fi, or the macOS firewall gives you a **complete, plausible trip
with every leg dashed** — not an error. If macOS prompts to allow incoming
connections, allow it.

**5 · Side-load tiles** for the regions you will import — `<region>.pmtiles` and
`<region>-terrain.pmtiles` — per §3 of `dogfood-infrastructure.md`. Without them
the film renders on Apple's map instead of the souvenir map; without the terrain
file it renders flat.

**6 · Use the app.** Home → **Import from photos** → the date range (defaults to
`import.default_range_days` = 7 days back) → Import.
- Photos permission: choose **Full Library** for the first run; Limited is a
  separate gate item and worth its own attempt afterwards.
- **Local Network** permission is prompted on the first routing call — allow it,
  or every leg draws dashed.
- Photos cluster into stops at `import.stop_radius_m` = 4 km, split by gaps over
  3 h. A dense city day may come out as one stop; that is the tuning to report.

**7 · Read the result on trip detail.** The route on S3's map is the tell: it
follows roads if OSRM answered, and runs in straight lines between stops if it did
not. Wait for the stop names (~2 s each), then film button → S5 → MP4 → share.

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
