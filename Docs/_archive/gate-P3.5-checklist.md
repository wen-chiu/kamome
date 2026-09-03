# §6 Replay MVP gate — owner runbook

Consolidated 2026-07-31; revised 2026-08-02 after the camera/legibility work
closed; **revised 2026-08-13 for the §6a / §6b split**. The gate items themselves
live in `Docs/handoff-P3.5.md` §6 and stay authoritative; this is the **order to
do them in**, written for Chiu rather than for an implementer.

## The split, and how these stages map onto it

§6 became two gates on 2026-08-13 (Chiu; ADR in `Docs/decisions.md`), over
**different variants**, because that is what actually ships:

| stage here | gate | where | variant |
|---|---|---|---|
| Stage 0 + Stage 1 | **§6a — the film** | the desk | **A** (`recap_mode: full`, harness-only) |
| Stage 2 | **§6b — the product** | a real iPhone | **B** (`highlight`, the shipped default) |
| Stage 3 | spans both | — | — |

**Variant A is not what ships.** It is the edit Chiu publishes from — every
clustered stop presented, no duration cap, `allocation_zero_share` forced to 0 so
no stop shows a pin without a photograph. Both overrides are harness environment
variables; `Config/TrackingConfig.json` is **never** edited between runs. Stage 2
passes no variant flag at all, which is what makes it the shipped default.

## Status — the phase is CLOSED (2026-08-15); this file is now the runbook for a future device sitting

- **§6a — CLOSED by owner, 2026-08-14.** All three Variant A films judged
  (Iceland one he wants to keep, the other two 很好); the publish item was
  closed on a **private share to friends**, recorded as a deviation from the
  literal "≥ 1 published publicly" wording (`Docs/_archive/handoff-2026-08.md`,
  "§6a — CLOSED by owner").
- **§6b — explicitly NOT passed.** Phase 3.5 closed on 2026-08-15 with §6b's
  six unmet items moved to Phase 2 (App Store release) — they are listed in
  `Docs/pre-launch.md`, which is now their home. ADR: `Docs/decisions.md`
  2026-08-15. **Do not reopen 3.5 to finish §6b.**
- The Stage 2 procedure below stays as the runbook for whenever the Phase-2
  device sitting happens.

The ordering principle, which the split preserves: **every judgment you can make
at the desk, make at the desk.** A film that isn't worth publishing is a design
problem, and finding that out on the phone costs a side-load, an import and an
export per attempt. Stages 0 and 1 are cheap and repeatable; stage 2 is not.

---

## Known defects — #1 fixed, #2 mitigated, neither blocking now

Both were found on 2026-08-01 while diagnosing the NZ device film. **Neither is
visible on the committed fixtures**, so the desk stages pass with them present
and stage 2 is where they bite. **#1 is fixed** (2026-08-02, and the fix is
visible in the §6a renders: the real multi-day trips reconstruct their inter-day
legs as roads). **#2 is mitigated, not solved** — the film still shows blank
cards, it now says why. Read #2 before Stage 2; it is the one that can still cost
a sitting.

Nothing here blocks the §6b sitting. This section was titled "Blocking dev work"
while #1 was open, and is kept for the diagnosis, which is still the record.

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

### 2. iCloud-optimised photos resolve to empty cards ⚠️ NAMED, not solved

`PhotoLibraryPhotoResolver.loadAsset` sets `isNetworkAccessAllowed = false`, so
an asset whose full-size data lives in iCloud rather than on the device returns
nil and the deck blooms an **empty grey matte**. EXIF import still works, because
place and time are metadata that need no download — which is exactly why this
survives the desk stages and only appears on the phone.

Real trips from previous years are the most likely to be optimised away. Every
stop card silently blank is a direct fail of *"films Chiu wants to keep."*

**What landed 2026-08-02 (option C, owner call):** nothing is downloaded — the
resolver still refuses network access — but warming now *reports* what it could
not load, and the recap screen says so before the film finishes: *"38 of 47
photos couldn't be loaded, so those stops show blank cards. Open them in Photos
to download them first."* The route is stated as unaffected, because it is.

So on the gate sitting a blank-card film **tells you why** instead of looking
like a rendering bug. That is the whole value; the photos are still blank.

**What is still owed (option B, deferred):** actually fetching the originals,
which needs its own phase — progress, cancel, and copy — because `warm` loops
every deck photo sequentially and an unbounded download behind a progress bar
that reports *render* progress would turn a visible bug into an invisible hang.
When B is built, that is also the moment for the copy-catalog pass
(zh-Hant-first, per Chiu 2026-08-02).

Confidence in the diagnosis: high but **device-only, never reproduced** — the
simulator has no iCloud library. The first real import confirms or refutes it,
and the new notice is what will tell you which.

---

## Stage 0 — real data (desk, ~30 min, do this first) — §6a ✅ DONE

**Done for the three gate trips** (2026-08-09). Real dumps now sit in
`Tests/Fixtures/trips/local/` for Miyakojima, New Zealand and Iceland, and the
render harnesses prefer them over the committed fixture of the same name — so
`iceland` means Chiu's trip at the desk and the placeholder below in CI. Those
dumps are gitignored per §0 and never leave this Mac. Kept below as the procedure
for a **fourth** trip.

**The four committed trip fixtures are placeholders.** Every one of them is
hand-written plausible coordinates, not a photo dump:

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
- [ ] **Check region headroom, not just coverage.** A region that merely contains
      the trip caps the establishing shot down to the body span and the film opens
      flat: `./Tools/tile-headroom.sh <region>.pmtiles`. This has caught 2 of 3
      trips (Iceland, Miyakojima) at this step.
      *(Multi-day trips are fine now — defect #1 was fixed 2026-08-02. The old
      "prefer single-day trips" advice is withdrawn.)*
- [ ] **Pick the three gate trips** from the four candidates — "different
      character" is the requirement: a long drive, a dense walk-heavy day, and
      something with an inferred leg in it.

## Stage 1 — judge each trip at the desk — §6a ✅ DONE, kept as the procedure

**Done and judged for all three trips** (2026-08-13, verdicts at the top). Kept
because a fourth trip, or a re-render after any camera change, runs exactly this.

Run all three in ascending cost — Miyakojima, then New Zealand, then Iceland.
Any of these can send you back to stage 0 with a different trip.

⚠️ **Budget the render honestly.** "~5 min per trip" was written when Stage 1 was
a 32 s pilot. A whole film in Variant A costs, measured 2026-08-12:
Miyakojima 3,110 frames / 149 s · New Zealand 5,810 / 600 s · **Iceland 17,960 /
1,782 s (~30 min)**. Run them in the background, and never in a shell that can
time out mid-write — see "reading the log" below for why a finished-looking MP4
is not a finished film.

- [ ] **Measure the pacing** (no render):
      ```
      TEST_RUNNER_KAMOME_TIMELINE_REPORT=<name> …
      ```
      Watch for: a longest-still that is not absurd, the established → body spans
      and their ratio, the dashed-leg list, and — in Variant A — a duration that
      is *product-acceptable*. **There is no 60–90 s window any more**; that
      number was retired with the repositioning, and the accepted §6a films run
      103.7 s, 193.7 s and 598.7 s.
      `drive/inferred` and `walk/inferred` are the legs that will draw dashed;
      walks dash by design. **A multi-day trip showing mostly `walk/inferred`
      would be defect #1, which is fixed — if you see it again, it is a
      regression.**
- [ ] **One stop still** (`RecapStopStillTests`) — is the busiest stop's
      composition right on this trip's real photographs?
- [ ] **The whole film** (`RecapPilotFilmTests`, `KAMOME_PILOT_SECONDS=9999` —
      that means the entire film, not a pilot).
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

The Stage 1 render, in full. **Variant A is the two `RECAP_MODE` /
`ALLOCATION_ZERO_SHARE` lines** — drop them and you have rendered Variant B,
which is Stage 2's edit, not this gate's:

```
TEST_RUNNER_KAMOME_PILOT_FILM=<name> \
TEST_RUNNER_KAMOME_PILOT_SECONDS=9999 \
TEST_RUNNER_KAMOME_RECAP_MODE=full \
TEST_RUNNER_KAMOME_GEOCODE_STOPS=1 \
TEST_RUNNER_KAMOME_OSRM_BASE_URL=http://127.0.0.1:5100 \
TEST_RUNNER_KAMOME_TILES_PATH=$HOME/kamome-osrm/tiles \
TEST_RUNNER_KAMOME_TERRAIN_PATH=$HOME/kamome-osrm/terrain \
TEST_RUNNER_KAMOME_STOP_PHOTOS=<folder of the trip's real jpegs> \
TEST_RUNNER_KAMOME_RENDER_OUT=$HOME/kamome-renders \
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:KamomeTests/RecapPilotFilmTests
```

⚠️ **`KAMOME_GEOCODE_STOPS=1` is not optional for a film you intend to judge.**
Without it every card reads "Unnamed stop", which has twice been reported as a
regression and once cost a re-render. It is off by default so CI stays hermetic
and offline for the golden-frame gates — the default is right, the command was
wrong. Names are cached per trip in `Tests/Fixtures/trips/local/<name>-names.json`
(gitignored, §0), so only the first run per trip pays the ~2 s per stop.

⚠️ **Pre-flight OSRM with `docker ps`, not `curl`.** The container must be up
(`kamome-osrm`, healthy). `curl` from a sandboxed shell fails as though the server
were down, and `RouteMatchService.swift:39` logs the *wrong* base URL when a
reconstructor is injected — it says `(none — matching disabled)` while routing
works fine — so neither the log nor a curl can answer this. Judge routing by the
`matchTrip … N/M legs reconstructed` tally instead.

## Stage 2 — the iPhone (one sitting, the expensive part) — §6b, NOT STARTED

**This stage is Variant B — the shipped default.** Pass no variant flag and edit
no config: `recap_mode: highlight` with `allocation_zero_share` at its shipped
0.4 is the product, and §6b asks whether *the app* does this by itself. The
Variant A films from Stage 1 do not substitute for it, and its three trips are
three, hard.

⚠️ **Watch for the intermittent `KamomeCore_KamomeExportEngine` bundle fatal
error** (`Bundle.module`, on the export path, traps rather than degrading). It hit
2 of 3 attempts on one desk trip and never appeared on the others; on the Mac a
retry cleared it. **On the phone there is no retry flag** — if it fires during the
sitting, record what preceded it rather than burning the sitting on a re-run.
Logged in `HANDOFF.md`; undiagnosed.

### Dev work that stands in front of the sitting

- [x] **The duration rule** (`b3093ad`). Confirmed by render, not only by tests:
      Iceland came out at **211.5 s · 21 of 65 stops · 6,345 frames · 63
      photographs**, matching every prediction, with no overrides in the log.
- [ ] **Album-based import.** The app imports a **date range from the whole photo
      library**; the desk fixtures were built from folders curated by hand. Every
      overseas trip therefore pulls its travel days in on device and did not at the
      desk — the first device import opened in the departure country and fell back
      to Apple's map. Narrowing the date range was rejected (it guts a short trip),
      so the sitting waits on this. Scope: `Docs/cross-region-journeys.md`
      § "Choosing the photographs".

**Cross-region framing — plane, ship, seagull — is explicitly NOT in front of this
sitting.** It is large, §6b does not depend on it, and the sitting's findings are
design inputs to it. Requirements are held in `Docs/cross-region-journeys.md`.

### Pre-flight, in this order

**Order matters: prove the app installs before spending an hour on data.**

- [ ] **Install and launch a bare build on the phone first.** Signing goes in
      `project.yml` under the app target's `settings: base:`
      (`DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE: Automatic`) — **never picked by hand
      in Xcode**, which `xcodegen generate` wipes. No app has ever been built for
      a device from this branch; find that out before downloading photographs.
- [ ] **`matching.base_url` = the Mac's LAN address** (not `127.0.0.1`), then
      rebuild. There is **no runtime override in the app** — `AppConfig.loadOrDie`
      reads the bundled JSON only. ⚠️ **Never commit this**, and note it is a
      different rule from the signing above, which *is* meant to be committed.
- [ ] **An album per trip in Photos**, once album import lands. The three §6b
      trips need to exist as albums on the phone, not only as folders on the Mac.
- [ ] **Originals downloaded.** Check Settings → Photos first: if "Optimise iPhone
      Storage" is off, there is nothing to do. If it is on, download each trip's
      photographs to originals — the resolver refuses network access, so an
      iCloud-resident photograph blooms a grey card (defect #2 above). **This is
      the only failure with no on-the-day remedy**, and Iceland is thousands of
      photographs.
- [ ] **Side-load tiles.** Regions live in `~/kamome-osrm/tiles/`, DEMs in a
      **separate** `~/kamome-osrm/terrain/` — the two are not in one folder.
      Drag both into Finder → iPhone → Files → Kamome, **loose at the top level**;
      the lookup finds them there and tells them apart by the `-terrain` suffix
      (PD-7, 2026-07-31 — a file dragged in lands loose, and making a subfolder
      first is a step nobody guesses). Start with the smallest region alone
      (single-digit MB) and only push the rest once one trip has run end to end;
      the three together are close to a gigabyte.
- [ ] **Prove OSRM from the phone's Safari** before importing anything:
      `http://<address>:5100/route/v1/driving/…?overview=false` must return
      `"code":"Ok"`. **Do not skip this.** `importTrip` treats routing failure as
      "keep raw geometry" (PD-2), so a wrong address, the wrong Wi-Fi or the macOS
      firewall gives you a complete, plausible film with every leg dashed — not an
      error. ATS and the local-network prompt are already handled in the
      Info.plist; allow the prompt when it appears or every leg dashes.

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
      never exercised on hardware. Album enumeration behaves differently under
      `.limited`, so once album import lands these two meet here for the first
      time.
- [ ] **S5 UX pass** — device-test-P3 item G, the full list.
- [ ] Memory pressure / no crash across all three exports.

### What to record, and why each one

| record | why |
|---|---|
| **export time per trip** (S5 readout) | a gate item, and the only viability risk never measured. Iceland is **6,345 frames — 2.35× the 90 s cut** — so this is the figure to judge against |
| **every crash, and what preceded it** | the bundle fatal error above; there is no retry flag on the phone |
| **whether any stop shows 5 photographs** | `tier_top_photos` (5) needs a stop in the top `tier_top_share` **with a favourite**. Fixtures carry no favourites, so this path has **never executed** — the first real library import is its first run |
| **presented stops and film length per trip** | against the references below |
| memory, thermals | 6,345 frames has never run on a phone |

### Expect different, and know which differences are faults

**The device films will not match the desk films, and that is not a fault.** The
desk fixtures came from hand-curated folders; the phone imports an album or a date
range out of the real library. Different photo sets cluster into different stops,
so stop counts and lengths will differ.

References, for sanity rather than equality:

| trip | presented stops | length | rendered? |
|---|---:|---:|---|
| Iceland | 21 of 65 | 211.5 s | **yes**, shipped default |
| New Zealand | 15 of 20 | 154.5 s | predicted only |
| Miyakojima | 8 of 10 | 88.0 s | predicted only |

The differences that **are** faults:

- **Every leg dashed** ⇒ routing never answered. See the Safari check above.
- **Apple's map instead of the souvenir map** ⇒ no installed region *contains* the
  trip. Either the tiles are not side-loaded, or the trip escapes its region —
  which on device usually means travel-day photographs came in
  (`Docs/cross-region-journeys.md`).
- **A flat map with no hillshade** ⇒ the `-terrain` file was not side-loaded.
- **Blank grey photo cards** ⇒ iCloud-resident originals (defect #2). The recap
  screen names the shortfall; believe it.

## Stage 3 — sign-off (spans both gates)

- [x] **Honesty review**: look at a published film with a dashed leg in it and
      agree it reads as *"Kamome is guessing here"*. Pixel tests prove the two
      strokes differ; only you can say the difference communicates. (PD-1/PD-2)
      — **judged 2026-08-13 on Iceland's detour-gate leg: accepted.** ⚠️ That was
      a judgment on **one instance**, not a new rule; the §6a item still reads
      "no obvious sea-crossing straight line" and a future trip with several is a
      fresh question.
- [ ] **≥ 1 published publicly**, no external editing. **← the only §6a item
      still open.**
- [x] **All three are films you want to keep** (Variant A, 2026-08-13). "A
      travel-path animation worth publishing" — not "the map beats Apple Maps".
- [ ] The same judgment on **Variant B**, which is what §6b ships.

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

### At the desk: an MP4 on disk is not a finished film

The encoder writes continuously, so a render that was killed — or is still going —
leaves a file at a plausible size that was never finalized. One New Zealand render
sat at 113 MB looking complete and was unplayable garbage. **The only completion
evidence is the summary line:**

```
KAMOME_PILOT_FILM <path> — 5810/5810 frames · 193.7s of a 193.7s film · 123.9 MB · rendered in 600s
```

No line, no film — whatever `ls` says. Run renders in the background for the same
reason: a foreground shell that times out at ten minutes will SIGTERM Iceland
two-thirds of the way through a half-hour render.

## Not on this list, on purpose

- **OSRM, not ORS.** There is no OpenRouteService integration anywhere in the
  repo and none is planned in the handoff — routing is self-hosted OSRM
  (`Deploy/`), merged across all four regions, serving on `:5100`. If ORS is
  something you are considering, it is a new decision, not a status check.
- **VPS shared-token auth** — deferred by owner call 2026-07-29, still flagged in
  `handoff-P3.5.md` §"VPS migration". Not a gate item: on home Wi-Fi there is
  nothing to authenticate against.
- **Photo-deck polish and the fan/stack carousel** — agreed post-wrap.
- **"Unnamed stop" in a desk render** — a harness artifact, and a *solved* one
  since 2026-08-05: the harness composes straight out of `ImportService`, which
  cannot name a stop, so `RecapReviewGeocoder` runs the shipped `StopNamer` when
  `KAMOME_GEOCODE_STOPS=1` is set. Set it (Stage 1) and this does not happen.
  Real device runs name their stops on S3; see the stage-2 note.
