# §6 Replay MVP gate — owner runbook

Consolidated 2026-07-31; **revised 2026-08-02 after the camera/legibility work
closed** — see "Blocking dev work" below, which did not exist when this was
first written. The gate items
themselves live in `Docs/handoff-P3.5.md` §6 and are unchanged; this is the
**order to do them in**, and it is written for Chiu rather than for an
implementer. Everything here needs a human, a phone, or real photos — there is no
remaining dev work in front of it.

The ordering principle: **every judgment you can make at the desk, make at the
desk.** A film that isn't worth publishing is a design problem, and finding that
out on the phone costs a side-load, an import and an export per attempt. Stages 0
and 1 are cheap and repeatable; stage 2 is not.

---

## ⚠️ Blocking dev work — two known defects, diagnosed, NOT fixed

Both were found on 2026-08-01 while diagnosing the NZ device film. **Neither is
visible on the committed fixtures**, so the desk stages pass with them present
and stage 2 is where they bite. #1 is fixed; **#2 is still open** and is a
behaviour decision, not only a bug fix.

### 1. Multi-day trips type every inter-day leg as a walk ✅ FIXED 2026-08-02

`ImportService.mode(for:)` computes pace as distance ÷ **wall-clock gap**. On a
multi-day trip the gap between one day's last photo and the next day's first is
mostly sleeping, so a 60 km drive across 47 hours implies 1.3 km/h → `.walk` →
walks are deliberately never routed → the leg stays a straight line and draws
dashed.

Measured on the real 11-day NZ trip: **7 of 9 legs**. The gate item *"no obvious
sea-crossing / mountain-crossing straight line"* fails outright on any trip
longer than a day — the straight lines cross Lake Pukaki and the Southern Alps.

**Fixed** with a gap ceiling (`import.pace_unknowable_gap_s`, 4 h): past it the
elapsed time was not spent travelling, so pace carries no signal and the leg
falls back to the road-trip assumption already made for zero-elapsed legs.
Raising the walk threshold was rejected — an overnight gap is not slow travel.
On the NZ reconstruction: **7 walk-typed legs → 0**.

⚠️ **A different knob to watch at Stage 1.** OSRM is asked to snap each leg
endpoint within `matching.route_waypoint_radius_m` (500 m). A leg endpoint is a
*stop centroid* — the middle of a photo cluster — so a beach day, a lakeside
lookout or a summit can sit further from a drivable road than that, and the
whole leg then comes back `NoSegment` and stays dashed. Honest, but if real
trips show a lot of `drive/inferred`, check the log for `NoSegment` before
assuming the detour gate: they fail for different reasons and only one is a
tuning question.

### 2. iCloud-optimised photos resolve to empty cards 🔴

`PhotoLibraryPhotoResolver.loadAsset` sets `isNetworkAccessAllowed = false`, so
an asset whose full-size data lives in iCloud rather than on the device returns
nil and the deck blooms an **empty grey matte**. EXIF import still works, because
place and time are metadata that need no download — which is exactly why this
survives the desk stages and only appears on the phone.

Real trips from previous years are the most likely to be optimised away. Every
stop card silently blank is a direct fail of *"films Chiu wants to keep."*

Confidence: high but **device-only, never reproduced** — the simulator has no
iCloud library. Worth deciding the behaviour deliberately (allow the download
with progress, or detect and tell the user) rather than flipping the flag blind.

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
- [ ] **Prefer single-day trips until blocker 1 is fixed**, or accept that
      multi-day candidates will render their inter-day legs dashed and straight.
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
      that will draw dashed. **A multi-day trip showing mostly `walk/inferred` is
      the blocker above, not a property of the trip.**
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

---

## Appendix — reading the log when a film comes out wrong

Kamome degrades rather than failing: an unreachable routing server keeps raw
geometry and draws it dashed (PD-2), and a trip no installed region covers falls
back to Apple's map. Both produce a finished film that is quietly wrong. Since
2026-08-01 every one of those decisions says so in the unified log.

Attach the phone, open **Console.app**, select the device, and filter:

```
subsystem:com.chiu.kamome
```

Or afterwards, without Console: `log collect --device --last 30m`, then open the
archive in Console.

What to look for, in order:

| line | means |
|---|---|
| `matchTrip …: 0/4 legs routable against "(none — matching disabled)"` | the build has `matching.base_url` empty — you are running a config that never asks |
| `matchTrip …: 4/4 legs routable against "http://192.168.0.6:5100"` | it asked; read on for what came back |
| `route: TRANSPORT FAILED … ` | it could not reach the server at all — ATS, the local-network prompt, wrong Wi-Fi, firewall. **The message names which** |
| `route: OSRM said NoSegment` | reached the server; there is no road network there. Correct for a leg outside the merged extract, or across water |
| `route: REJECTED by the detour gate — 41.0 km routed vs 8.2 km straight` | PD-3 refused an implausible route (usually one bad EXIF fix) |
| `matchTrip …: 0/4 legs reconstructed` | the headline: how much of the film draws as road |
| `no installed map region covers this trip` | Apple's map, no prologue **and** the legacy 30 s duration, all at once |
| `film: 90.0s · 2700 frames · opening 5.9s · 9 stops · 0/5 legs dashed` | what was actually rendered |

The first two lines answer the question a finished film cannot: *did the app ask,
and what did it ask?*

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
