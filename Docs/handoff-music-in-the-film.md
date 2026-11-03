# Handoff — music in the film: how the export carries it (2026-11-03)

**A proposal, not a decision.** Chiu asked (2026-11-03): 「我正在製作音樂可以搭配影片一起輸出
… 我要輸出的時候直接配上音樂 … 透過使用者旅行國家跟照片風格自行判斷加給他 … 在code上也可以判斷
beats 景點出現或照片出現可以加強音樂 … 先產生如何實作的方式跟詳細內容」.

This is the *app* half. Where the music comes from (ACE-Step 1.5 / Stable Audio 3 generated at the
desk, five styles × three moods, beatmap measured once) is `Docs/handoff-music-rethink.md` and is
not repeated here. **Music left Deferred on 2026-11-03, free films included**
(ADR 2026-11-03-music-leaves-deferred-and-every-film-has-it); §7 says what is still open.
Nothing here changes the app yet.

Labels follow `CLAUDE.md` rule 4. Each unmeasured claim names what would settle it.

**Status, 2026-11-03: PR A is built** (§8). The cue sheet, manifest, arrangement, renderer, muxer,
the §3.3 rule, the beatmap tool and the desk harness exist; nothing a user sees changed. Where the
build departs from the text below, the text was updated: the manifest gained five fields (§2.2), a
crossing is two cues (`crossing`, `landing`), and the departure's photographs over a frozen card
are cues like a stop's. **After Chiu's listen the music plays straight through**
(ADR 2026-11-03-the-music-plays-straight-through): §2.5 items 5–6 were built, heard and removed.
The stop dip sounded broken, and the return and the photo lift went unnoticed. #361 is closed.

---

## 1. The shape, in one picture

Music is **a second renderer of the same story.** The map renderer reads `cameraFrame(atTime:)`;
the soundtrack reads the film's *moments* (when a stop arrives, when a photo changes, when the
car sets off). The story never learns that music exists — the same rule as `CHARTER.md` §3 for
the map.

    RecapComposer ──► RecapTrip ──► LinearTimeline ──► RecapRenderLoop ──► RecapVideoEncoder ──► silent.mp4
         │                               │                                                         │
         │ SoundtrackContext             │ FilmCueSheet (pure)                                     │
         ▼                               ▼                                                         ▼
    SoundtrackPicker (pure) ──► track ──► SoundtrackArrangement (pure) ──► SoundtrackRenderer ──► mux ──► film.mp4
                                          (cut, dips, accents, fades)        (AVFoundation)        (passthrough)

Three properties carry the whole design:

1. **The audio is planned and rendered after the timeline exists, never inside the frame loop.**
   The timeline is fully known before frame 0 (VERIFIED: `LinearTimeline` is built once in
   `RecapExportJob.plan`), so the soundtrack can render *in parallel* with the minutes of map
   drawing and add only the mux to the wall time.
2. **Mux after encode, with video passthrough.** `RecapVideoEncoder` stays video-only. Adding an
   audio input to the same `AVAssetWriter` was rejected: with `expectsMediaDataInRealTime = false`
   the writer interleaves inputs and can hold video back until audio catches up, and the video
   loop's `isReadyForMoreMediaData` wait would then spin (INFERRED from AVAssetWriter's documented
   interleaving; *settle:* not worth settling — the mux route avoids the question).
3. **Changing the music never redraws the map.** A new soundtrack takes the video track out of the
   existing `film.mp4` and muxes new audio beside it — seconds, not the 4–30 minutes of a render
   (`Docs/handoff-export-performance.md`). This is what makes "we choose, you change it after you
   have seen the film" affordable, and it answers Chiu's own worry: the person cannot judge music
   before the film exists, so the default must be automatic and the change must be cheap.

---

## 2. The story side (pure Swift, `KamomeExportEngine`, no AVFoundation)

### 2.1 `FilmCueSheet` — the film's moments, read off the timeline

An extension on `LinearTimeline` returning `[FilmCue]`, sorted by time:

| cue | time source (all exist today, VERIFIED by reading) | weight |
|---|---|---|
| `opening` | 0 | — |
| `titleCut` | `titleCutS` | strong |
| `go` (car sets off) | `journeyStartS`, then each `hold.endS` | strong |
| `stopArrives` | each `hold.startS` with photos (`activeScene`) | medium |
| `quietStop` | each hold without photos (`quietStop`) | light |
| `photoChanges` | inside `deckWindow(hold)`, each photo slot's start | light |
| `crossing` | `path.crossingBeatWindowsS` lower/upper bound | strong |
| `endReveal` | `CameraPath.endRevealStartS` (needs a public read) | strong |
| `endCard` | `durationS − endCardS` | final |

Rules for this file:
- **Derived, never stored, never re-computed by a copy.** Each time comes from the function the
  overlay already uses, so a pacing change moves the music with the picture. A second copy of the
  slot math is the bug to prevent; a test pins that every `photoChanges` cue equals the frame where
  `overlayContents` shows a new photo.
- **One refactor this needs (VERIFIED by reading, 2026-11-03):** the photo-change times are not
  exposed today. They are computed inline inside `focusIndex(atTime:deck:count:)`
  (`LinearTimelineStopScene.swift`: `rotateStart + k · slot`, with `count` from
  `affordablePhotoCount`). PR A extracts that into one `photoSlotStartsS(deck:count:)` that
  `focusIndex` and the cue sheet both call. `CameraPath.endRevealStartS` is `private`; it widens
  to internal, as `LegRange` did on 2026-09-02.
- **No coordinate, name or country in a cue** — kind, time, stop index. §0 by construction.
- Open PRs that move these times — wen-chiu/kamome#355 (stops play in trip order) and
  wen-chiu/kamome#343 (the film ends on a souvenir map) — change *values*, not the cue kinds. If
  #343 lands, `endReveal`/`endCard` read whatever it defines; the cue sheet has no opinion.

### 2.2 `SoundtrackManifest` — the beatmap as Codable

One JSON per track, written at the desk by the beatmap tool (§5), never computed on the phone:

```json
{
  "schema_version": 1,
  "id": "tropical-depart-2",
  "style": "tropical", "mood": "depart",
  "file": "tropical-depart-2.m4a", "duration_s": 152.3,
  "bpm": 100.0, "beats_per_bar": 4, "first_downbeat_s": 0.412, "tempo_drift_bpm": 0.2,
  "sections": [
    { "name": "intro",  "start_bar": 0,  "bars": 8,  "energy": 1, "role": "intro" },
    { "name": "verse",  "start_bar": 8,  "bars": 16, "energy": 2, "role": "body", "repeatable": true },
    { "name": "lift",   "start_bar": 24, "bars": 8,  "energy": 3, "role": "lift" },
    { "name": "chorus", "start_bar": 32, "bars": 16, "energy": 4, "role": "peak", "repeatable": true },
    { "name": "ending", "start_bar": 48, "bars": 6,  "energy": 2, "role": "outro" }
  ],
  "sections_confirmed": false,
  "final_hit_bar": 52, "tail_s": 3.1,
  "integrated_lufs": -14.1, "true_peak_dbtp": -1.2,
  "provenance": { "engine": "acestep-1.5", "commit": "ca1e85f", "seed": 123456789 }
}
```

**As built (PR A):** `Core/ExportEngine/SoundtrackManifest.swift` is the one schema. The five added
fields are what validation needs: `duration_s` (sections must fit the file), `tempo_drift_bpm` and
`true_peak_dbtp` (the desk's refusals, re-checked), `sections_confirmed` (false until Chiu has
listened), `schema_version`. `Tools/kamome_soundtrack_manifest.py` refuses exactly what the Swift
validator refuses, with the same codes; `Tests/Fixtures/soundtracks/invalid/` holds one file per
code and both sides are tested against it.

`sections` are what `handoff-music-rethink.md` A4 said the old `beatmap.json` lacked. **Whole
tracks, not loops or stems** (rethink B1, INFERRED there): a produced track already has an intro,
a lift and an ending, and Chiu's four rounds showed that what we assemble ourselves sounds
assembled.

### 2.3 `SoundtrackPicker` — "which music", decided by us

Input is a neutral `SoundtrackContext` built in the app (ExportEngine never sees Persistence —
`Config/architecture.json`):

```swift
public struct SoundtrackContext {
    public let countryShare: [String: Double]   // ISO code → share of film time, from stops' country_code
    public let photoMood: PhotoMood              // aggregate over the photos the film will show
    public let filmType: RecapFilmType           // a crossing / flight film leans epic
    public let durationS: Double
    public let appearance: RecapAppearance       // a dark film leans cruise
    public let seed: UInt64                      // from the trip's id: same trip, same music
}
```

**Two questions, answered separately — this is the main design choice:**

1. **Style ← country** (Chiu's table, rethink A1): the country with the largest share of film
   time picks one of `citypop · nordic · tropical · folk · anthem`. Ties and a flight film go to the
   *destination* (the home end of a type-2 film is not the trip). Unlisted countries → `anthem`
   (still Chiu's call, rethink D4 item 4). The table lives in `Config/TrackingConfig.json`, not in
   code (rule 7).
2. **Mood ← photographs + film shape**: `depart` (bright, hopeful) · `cruise` (calm) · `epic`
   (grand). A weighted score, each weight a tunable:

   | signal | where it comes from | pushes toward |
   |---|---|---|
   | landscape share (mountain, coast, sky, snow, waterfall) | Vision scene labels | epic |
   | mean saturation and brightness | pixel statistics on the 512 px image the analyser already loads | depart (high) / cruise (low) |
   | night share | brightness + `night` label | cruise |
   | people / food / city share | Vision labels | depart |
   | crossing or flight film; long standard film | `filmType`, `durationS` | epic |
   | dark appearance | `appearance` | cruise |

   Highest score wins; within the winning brief, the take (2–3 kept per brief) is chosen by
   `seed`, so two trips to Japan do not get the same track but one trip always gets the same one.

**Why country is only half:** a country decides *colour* (instruments), photographs decide
*feeling*. Country alone would play the same city-pop to a Tokyo night trip and a Hokkaidō snow
drive; and most of Kamome's users are Taiwanese travelling in East Asia, so a country-only rule
would give almost every film one style (INFERRED from the product's market, spec §1; *settle:*
count `country_code` over the local fixtures in `Tests/Fixtures/trips/local/`).

**No ML, no network** — a deterministic score over structured data, as the Story Director was
always meant to be (spec §7: "deterministic — no AI/LLM tokens").

### 2.4 `PhotoMood` — what the photo analyser adds

`App/Services/PhotoAnalyzer.swift` already loads every photograph at `photo_analysis.target_px`
and runs two Vision requests (VERIFIED). Add, in the same pass and on the same pixels:
- `VNClassifyImageRequest` → keep only the top labels in a fixed whitelist (≈ 15 labels:
  mountain, beach, sea, snow, sky, forest, waterfall, city, night, food, people …), as a bitmask.
- Mean luminance, mean saturation, warm/cool balance from a 32×32 downsample — no Vision needed.

Bump `PhotoAnalysisVersion.current` to 2; rows at version 1 keep working (the picker treats a
missing mood as neutral and falls back to the film-shape signals). Labels and colour statistics
are personal data but not location data; they stay in the local database like the feature print.
**UNKNOWN:** the added cost per photo. *Settle:* the analyser already times itself
(`featurePrintMs`, `aestheticsMs`) — add `classifyMs` and read one import on a phone.

### 2.5 `SoundtrackArrangement` — fitting a 2–3 minute track to a 60–300 s film

Pure function `(manifest, cues, durationS, config) → SoundtrackPlan`, where the plan is a list of
`Clip(sourceStartS, sourceEndS, filmStartS)` plus automation curves `gain(t)` and `cutoffHz(t)`.

1. **Anchor the ending.** The track's `final_hit_bar` must land on `endCard` (the last chord
   arrives with the end card). So `outroFilmStart = endCard − (finalHit − outroStart)`.
2. **Cut the middle on a phrase line.** Play from the intro, and cross-fade (equal power, one beat,
   tunable) from a phrase boundary *c* in the body into the ending's start. Choose *c* so the
   peak section plays nearest the film's strongest cue (a crossing, or the last stops before the
   end reveal).
3. **Absorb the remainder without stretching time.** The gap between "film time to the ending"
   and "whole phrases of music" is less than a phrase. Start the track that much *into* its
   intro (audio offset *s* > 0) and fade in over the title card. No time-stretch, no pitch
   change, ever: a stretched track is the "something is wrong" sound Chiu hears at once.
4. **A film longer than the track** (standard films reach 300 s, rethink B1) repeats a
   `repeatable` section at its phrase lines. *As built:* it replays the longest **stretch** that
   begins and ends on a repeatable section, because a 180 s desk film that replayed one 8-bar
   section five times in a row (16 s, five times) was a loop. If the manifest has none, the picker must not
   choose that track for that film (a filter, not a runtime surprise).
5. ~~**Moments the music answers**~~ — **removed after Chiu's listen, 2026-11-03** (ADR
   2026-11-03-the-music-plays-straight-through): 「不行 像壞掉 照正常就好」. Kept below as the record of
   what was tried. Chiu's original request, 「景點出現或照片出現可以加強音樂」:

   | cue | what the music does | why this and not more |
   |---|---|---|
   | `go` | the next downbeat after it returns to full level (and full band, if stems ship) | "the beat drops when the car moves" is the strongest sync a viewer feels |
   | `stopArrives` | dip: −6 dB and a low-pass sweep to ~1.2 kHz over one beat, held through the deck, released at `go` | the photographs become the subject; the music steps back instead of competing |
   | `photoChanges` | a small lift: low-pass opens by a step on the nearest beat within tolerance | the photo "breathes" with the music without a sound effect on every card |
   | `crossing` | a section change to the next higher-energy section at the next phrase line | the leap of a flight deserves the track's own lift, not an added riser |
   | `endReveal` | the cut into the ending lands here when the phrase grid allows | the map reveal and the outro arrive together |

   Every number is a tunable in a new `soundtrack` block of `Config/TrackingConfig.json`
   (`stop_dip_db`, `stop_cutoff_hz`, `accent_snap_tolerance_s`, `crossfade_beats`, `fade_in_s`,
   `fade_out_s`, `photo_accent_enabled`, …). **No added one-shot sound effects in v1** —
   Chiu's round-2 lesson (「太多東西你沒辦完整控制協調就會變得畫蛇添足」): a sting in the wrong key
   is the fastest way to make a good track sound cheap.
6. ~~**The music answers the picture, not the other way round (v1).**~~ Removed with item 5. An accent snaps to the
   nearest beat only within `accent_snap_tolerance_s`; outside it, the dip/lift ramps on the cue
   itself, unsynced. Human audio–video tolerance is roughly 45 ms audio-early to 125 ms
   audio-late (ITU-R BT.1359, INFERRED as applicable to music accents; *settle:* Chiu watches one
   film with tolerance 0 and one with 0.1 s and says which is "on the beat"). Moving the
   *picture* onto the beat is §6, and is a separate decision.

---

## 3. The rendering side (AVFoundation, one file each)

### 3.1 `RecapSoundtrackRenderer.swift` — plan → `soundtrack.m4a`

`AVAudioEngine` in **offline manual rendering mode** (`enableManualRenderingMode(.offline, …)`):
one `AVAudioPlayerNode` per clip (so a cross-fade is two nodes overlapping), into an
`AVAudioUnitEQ` (one low-pass band) and the main mixer. *As built after the ADR above:* no
`AVAudioUnitEQ`, just the players into the main mixer, with one gain on the rendered samples. The render loop pulls 1,024-frame chunks
and sets gain and cutoff from the plan's curves before each chunk — the curves are pure, so
the "what" is unit-tested and this file only does the "how". Output: AAC 48 kHz stereo,
`soundtrack.audio_bitrate_kbps` (192 proposed).

Rejected: `AVMutableComposition` + `AVAudioMix`. Simpler, but `AVAudioMix` has volume ramps only —
no low-pass — and the stop dip without a filter is just "quieter", which reads as a mistake
(INFERRED; *settle:* render one film both ways at the desk and let Chiu listen).

### 3.2 `RecapFilmMuxer.swift` — `silent.mp4` + `soundtrack.m4a` → `film.mp4`

`AVMutableComposition` with the video track and the audio track, exported with
`AVAssetExportPresetPassthrough` to `.mp4`. Video bytes are copied, not re-encoded.
**VERIFIED (desk, 2026-11-03):** passthrough accepts the AAC track into an MP4 container
(`RecapSoundtrackRendererTests`); the time it takes is §4.1a. **One thing it does that was not
expected:** AAC carries 2,112 samples of encoder priming. Decoded by AVFoundation, the muxed film's
final hit lands on the end card's sample (`testTheMuxedFilmKeepsTheFinalHitOnTheEndCard`); decoded
by ffmpeg, the same file plays it **2,112 samples (44 ms) late**. The standalone `.m4a` states its
priming in an `iTunSMPB` tag that ffmpeg honours, but the muxed `.mp4`'s audio edit list starts at
media time 0. Apple applies the priming trim implicitly and ffmpeg does not, and AVFoundation then reads the muxed
track up to 44 ms short at its tail, inside the end card's fade-out. Writing the AAC with
`AVAssetWriter` instead changed nothing (measured). 44 ms of late audio is inside the ~125 ms a
viewer tolerates (ITU-R BT.1359, INFERRED as applicable). **UNKNOWN:** what LINE's and Instagram's
re-encoders do with it. *Settle:* the PR B runbook row "a film shared to LINE and Instagram keeps
its sound", checked for sync on the end card's chord.

"Change the music" reuses this file: it takes the video track out of the stored `film.mp4`
instead of `silent.mp4`. No silent master is kept, so storage does not double.

### 3.3 The confinement rule this needs (Chiu confirmed 2026-11-03)

`Config/architecture.json` confines AVFoundation to `Core/ExportEngine/RecapVideoEncoder.swift`,
and `Scripts/check-architecture.sh` enforces it (VERIFIED by reading both). The change:

```json
"confined": {
  "MapLibre":     "App/Services/MapLibreSnapshotProvider.swift",
  "GRDB":         "Core/Persistence/",
  "AVFoundation": ["Core/ExportEngine/RecapVideoEncoder.swift",
                   "Core/ExportEngine/RecapSoundtrackRenderer.swift",
                   "Core/ExportEngine/RecapFilmMuxer.swift"],
  "AVFAudio":     ["Core/ExportEngine/RecapSoundtrackRenderer.swift"]
}
```

**Landed in PR A (2026-11-03)**, with the list form, the missing-path check and the type check below,
each shown failing on a planted violation. **It lands in PR A, with the two files, not before.** Two facts of the checker decide that
(VERIFIED by reading `check-architecture.sh`):
- A confined value is **one** path, matched as a prefix. Three named files need the checker to
  accept a list. A prefix such as `Core/ExportEngine/Recap` would admit every `Recap*` file and
  void the rule.
- The checker **fails a rule that nothing imports** ("the confinement rule is dead"). An
  `AVFAudio` rule written today fails `./check.sh` until the renderer exists.
- So PR A also teaches the checker to fail a listed path that does not exist, so that the rule
  never grants a permission to a file nobody wrote.

**Why `AVFAudio` needs its own line:** `AVAudioEngine` lives in AVFAudio, which a file can import
without importing AVFoundation, and the checker matches the literal `import` line.

**A hole that already exists (VERIFIED 2026-11-03, not this design's):** `import AVKit`
re-exports AVFoundation. `UI/TripDetail/FilmPlayerSheet.swift` and `UI/Recap/RecapFinishedView.swift`
use `AVPlayer` with only `import AVKit`. Any of the four AVKit files could build an
`AVAssetWriter` and pass the check. Playback in the UI is legitimate, so PR A should not ban
AVKit; it should add a type check that `AVAssetWriter`, `AVAssetExportSession`,
`AVMutableComposition` and `AVAudioEngine` appear only in the three files. Recorded as a trap
in `HANDOFF.md`.

**Rejected:** everything in `RecapVideoEncoder.swift` (three jobs in one file, and past the size
it can be read at); confining to `Core/ExportEngine/` (the rule would then guard nothing).

---

## 4. The app side

### 4.1 Export flow (`RecapExportJob`)

    roads ─► compose ─► plan (timeline) ─► pick soundtrack ─► photos ─┬─► draw + encode video (minutes) ─┬─► mux ─► store
                                                                       └─► arrange + render audio ───────┘
                                                                           (seconds, in parallel)

- **The picker runs after `plan` and before `drawing`** (VERIFIED order in
  `RecapExportJob.runStages`: roads → compose → plan → photos → drawing). It needs the timeline's
  `durationS` and `filmType`, and the plan's `appearance`, which exist only after `plan`. If §6 is
  ever chosen, the picker must move before the timeline and read
  `LinearTimelinePacing.plannedDurationS` instead. That is a §6 cost, not a v1 one.
- **Streamed, not held.** 180 s of 48 kHz stereo float is ~69 MB if held whole; the renderer writes
  each 1,024-frame chunk to the file as it goes, under the memory budget D2 prices.
- **Cancel and leaving the app.** The audio task reads the same `shouldContinue` as the render
  loop. Whether `AVAssetExportSession` survives the app going to the background mid-mux is
  UNKNOWN. *Settle:* one device export left during the last seconds (runbook row, PR B).
- `ExportLogHistory` gains two stages, `music` and `mux`, so their cost is measured, not modelled.
- A soundtrack failure **fails loudly but does not lose the film**: the silent film is kept and
  the sheet says the music could not be added, with 「再試一次」 that re-runs only §3.1–3.2.
  Not a silent fallback (`CHARTER.md` §4): the person is told.

### 4.1a What the music costs in export time (Chiu asked 2026-11-03)

**VERIFIED (simulator), 2026-11-03**, PR A's desk harness (`RecapSoundtrackFilmTests`): the
`margaret-river` fixture at `KAMOME_FORCE_DURATION_S` 90 and 180, iPhone 17 Pro simulator (iOS 26.5)
on an M2 Mac with 16 GB, real 120 s ACE-Step take, 192 kbps AAC, shipped `video_bitrate_mbps` 5.
**The Mac was heavily loaded throughout** (load average 260–510: another session generating music
with ACE-Step, which swaps, plus another session's encode; disk 97% full). So these are an upper
range, not a typical cost. Every run is listed, and none is dropped.

| run | film | drawing + encode | music, alongside drawing | mux | music, alone | mux (replace) |
|---|---|---|---|---|---|---|
| 1 | 90 s | 404 s | 4.7 s | 0.68 s | 6.3 s | 0.85 s |
| 2 | 90 s | 627 s | 14.0 s | 0.66 s | 6.4 s | 1.73 s |
| 1 | 180 s | 1,003 s | 27.4 s | 1.58 s | 5.8 s | 0.32 s |
| 2 | 180 s | 685 s | 16.9 s | **66.1 s** | 9.8 s | **94.2 s** |
| 3 ¹ | 180 s | 250 s | 11.5 s | 2.35 s | 4.2 s | 1.96 s |

¹ After the repeat fix (§2.5 item 4 now replays a stretch). Arranging took under 3 ms in every run.

What this settles, and what it does not:
- **The music adds nothing to the wait while the map draws** (VERIFIED, 5 of 5 runs): even under
  this load it finished in 4.7–27 s, against 250–1,003 s of drawing. It is slower than the 50×
  real time the old table assumed (alone, 4–10 s: 18–43× real time), which does not matter while it
  runs in parallel.
- **The mux is the only added wall time.** It took 0.3–2.4 s in 8 of 10 measurements and 66 s / 94 s
  in one run (180 s, run 2). That run was the peak of the external load. The cause is **UNKNOWN**:
  contention for the disk (97% full, swapping) is INFERRED, not shown. *Settle:* the phone's `mux`
  stage in `ExportLogHistory` (PR B, runbook row), and one more simulator run on an idle Mac.
- **「換音樂」 costs the music render plus the mux**: 4–10 s plus 0.3–2 s here, with no redrawing.
- **Device numbers are still owed** (PR B, runbook row: `music` and `mux` stages).

For scale: a 338 s film took 942 s on an iPhone before the tile fix (VERIFIED,
`Docs/handoff-export-performance.md` §9).

### 4.2 Screens

- **Film sheet (`RecapView`)** — one new row in the settings card: 「音樂」, value 「自動」, a menu
  with 自動 / 無音樂. Nothing more before the film exists; this follows Chiu's reasoning that a
  person cannot choose music for a film they have not seen.
- **Player (`FilmPlayerSheet`)** — 「換音樂」 opens a short list: the current choice, the next
  two by the picker's score (labelled by mood in plain words, e.g. 「輕快」「悠閒」「壯闊」 — never
  by country, see §4.4), and 無音樂. Selecting one renders that audio and muxes it to a
  temporary file (the same ~2–7 s as §4.1a), which the existing `AVPlayer` plays. 「使用這首」
  moves it into place; closing throws it away. The UI never builds a composition itself, so no UI
  file needs AVFoundation beyond the playback it already does through AVKit.
- zh-Hant: **音樂** is a new word for the glossary (ADR 2026-10-26-zh-hant-uses-one-word-for-each-thing);
  pick it once (音樂, not 配樂/BGM) and add it to `ZhHantGlossaryTests`.
- **The silent switch — VERIFIED that nothing sets it today:** no file in `App/` or `UI/` sets an
  `AVAudioSession` category, so the players run under the default (`.soloAmbient`), which the
  silent switch mutes. With music, a phone on silent plays the film without sound unless a
  category is set. Video apps usually set `.playback`. A product call (§7, defaults), and a device
  check.

### 4.3 Storage

- `FilmRecord` gains `soundtrack_id` (nullable — null = silent) and `soundtrack_plan_version`.
  A schema migration in `Core/Persistence` (GRDB stays there).
- Tracks ship in the app bundle: `App/Resources/Soundtracks/` with one catalog JSON plus each
  track's `.m4a` and manifest. 15 tracks × ~2.5 min at 128 kbps ≈ **36 MB** (rethink B1's
  estimate, INFERRED). Bundle vs. On-Demand Resources is Chiu's call (rethink D4 item 5).

### 4.4 §0 — where location could leak, and the guard

The picker reads `country_code`, which is derived from location. It runs on the device only, and:
- **The chosen style is location data in disguise** (`citypop` says JP/TW/KR). It never goes into
  a `.public` log string, `ExportLogHistory`, or the film's metadata. Logs may say
  `music: picked in 4 ms · plan 31 cues`; the track id is logged `privacy: .private`.
- The player labels tracks by mood, not by region, for the same reason (a screenshot is shared).
- `Scripts/check-location-data.sh` should learn the style names as forbidden public-log words.

---

## 5. The desk side (Python, Chiu's own tools)

`Tools/kamome-beatmap.py` turns a kept, mastered track into its manifest and refuses a bad one:
- **Tempo and grid:** the brief already sets BPM (`Tools/kamome_music_briefs.py`); the tool
  measures it (librosa beat tracking) and fails if drift > 1 BPM or the measured BPM is off the
  brief's (rethink B2 item 4). It finds `first_downbeat_s`.
- **Sections:** proposed from a self-similarity matrix on 8-bar chunks, then **confirmed by
  Chiu's ear** in the compare page — the tool writes them, a human signs them.
- **Loudness:** −14 LUFS integrated, true peak ≤ −1 dBTP, measured with `ffmpeg -af ebur128=peak=true`, or refuse. ffmpeg is already a desk tool (`Scripts/encode-sample-film.sh`), so this adds no dependency.
- **A gate in `./check.sh --static`:** every catalog track has a manifest, every manifest's
  sections fit inside the file's duration, no section crosses another, at least one `repeatable`
  body section exists. Stdlib-only for the gate; librosa only in the desk tool.

**librosa is a desk-only dependency, confirmed by Chiu 2026-11-03** (「librosa 可以用」), as ACE-Step was
(rethink D3a). It is never an app dependency and never runs in `./check.sh`. pyloudnorm is not
needed: ffmpeg measures loudness.

Reusable from PR wen-chiu/kamome#340 (rethink A4, VERIFIED there by reading): the event model and
`plan()`'s snap-to-beat with shift reporting. Port the *idea* to Swift (§2.5); do not ship Python
logic as the app's truth.

---

## 6. Later, and only if Chiu chooses: the picture moves onto the beat

The strongest "cut on the beat" feeling comes from photo changes landing on beats, which means
the *timeline* bends to the music: `LinearTimelinePacing` rounds each photo slot to whole beats
of the chosen track (e.g. `deck_photo_hold_s` 2.5 s → 4 beats at 96 BPM is exactly 2.5 s; at
104 BPM it would become 2.31 s). Costs, all real:
- It changes measured pacing and the duration plan (rethink D4 item 6) — a product change.
- The story would depend on the music. To keep `CHARTER.md` §3, pass only a neutral
  `RecapPulse(periodS:)` into pacing, never a track.
- Changing the music after the film then breaks the sync unless the new track has the same tempo
  — so 「換音樂」 would offer only same-tempo tracks, or redraw the film.

Recommendation: **ship v1 without it**, listen, and decide with a film in hand.

---

## 7. What Chiu decides before any code (rule 2, rule 6)

| # | question | status |
|---|---|---|
| 1 | Music leaves "Deferred" | **Decided 2026-11-03**: yes (ADR 2026-11-03-music-leaves-deferred-and-every-film-has-it) |
| 2 | Tier (2026-07-20: free = silent) | **Decided 2026-11-03**: the free film has music too |
| 3 | The architecture change in §3.3: two more files allowed AVFoundation, AVFAudio confined | **Confirmed 2026-11-03**; the JSON and checker change land in PR A with the files |
| 4 | Tracks in the repository | **settled**: the repository is private (Chiu, 2026-11-03). Still never register the tracks with a Content ID service, or a user's shared film would be claimed against them |
| 5 | Defaults: the `anthem` style for unlisted countries, 自動 on by default, the silent switch | **later**: after the music is made (Chiu, 2026-11-03) |
| 6 | Bundle size (~36 MB) vs. download | open |
| 7 | librosa as a desk-only tool (§5) | **Confirmed 2026-11-03**. Loudness uses ffmpeg, already a desk tool; no pyloudnorm |

## 8. Build order — two PRs (Chiu, 2026-11-03: 「應該一起整體處理的地方就應該一起分析實作」)

The first plan had six PRs. Four of them were one system cut at its seams: PR 1 alone would have
published a public API (`cueSheet()`) with no consumer, and PR 2's manifest schema would have been
written on one side of a contract (Python) before the other side (Swift) existed. The cut that
remains follows what each half risks and how each half is judged.

| PR | what | behaviour change? | judged by | was |
|---|---|---|---|---|
| **A — music works end to end at the desk** | §2.1 cue sheet (with the `focusIndex` refactor), §2.2 manifest, §2.5 arrangement, `soundtrack` config, §3 renderer + muxer + the §3.3 rule, §5 `Tools/kamome-beatmap.py` writing the manifest the Swift side decodes (one schema, one cross-check test), desk harness `TEST_RUNNER_KAMOME_SOUNDTRACK=<fixture>`, the §4.1a timings measured | none | **Chiu's ear**: one fixture film with one real track, in `~/Kamome-films/` | old PRs 1–4 |
| **B — the app ships music** | §2.3 picker, §2.4 `PhotoMood` (analyser v2), §4.1 export wiring, `FilmRecord` + `PhotoAnalysisRecord` migrations in one schema bump, §4.2 sheet row and player 「換音樂」, copy and glossary, runbook rows | **yes** | **Chiu's eyes and a phone**: screenshots, the device runbook | old PRs 5–6 |

**Why not one PR:** A is the gate for B. Four rounds of music were rejected by ear
(`Docs/handoff-music-rethink.md` A2); if the dips or cuts are rejected too, nothing in B should
have been built on them. A changes nothing a user sees; B changes the product. They also need
different evidence, a listen against screens and a phone. **Why B stays one:** the picker is
untestable as a product without the export and the screen, and two migrations in two PRs would
be two schema bumps for one feature.

**If B grows too large,** `PhotoMood` is the piece to defer, never split: the picker then reads
country and film shape only, and the mood signal arrives in a later PR with its own schema bump.

Older references in this document and in ADR 2026-11-03 to "PR 1–4" mean PR A, and to "PR 5–6"
mean PR B.

New `Docs/device-runbook.md` rows, owed by PR B: added wall time (`music`, `mux` stages); audio
on the phone speaker; the silent switch; a film
shared to LINE and Instagram keeps its sound; an export left in the background still muxes.

**A visual change owes a render; this one owes a listen.** `./check.sh` cannot hear the film.
Both PRs ship a rendered film with music for Chiu.
