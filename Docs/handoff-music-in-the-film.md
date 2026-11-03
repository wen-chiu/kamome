# Handoff — music in the film: how the export carries it (2026-11-03)

**A proposal, not a decision.** Chiu asked (2026-11-03): 「我正在製作音樂可以搭配影片一起輸出
… 我要輸出的時候直接配上音樂 … 透過使用者旅行國家跟照片風格自行判斷加給他 … 在code上也可以判斷
beats 景點出現或照片出現可以加強音樂 … 先產生如何實作的方式跟詳細內容」.

This is the *app* half. Where the music comes from (ACE-Step 1.5 / Stable Audio 3 generated at the
desk, five styles × three moods, beatmap measured once) is `Docs/handoff-music-rethink.md` and is
not repeated here. Music in the film is still **deferred** (`Docs/current-state.md`, "Deferred");
§7 lists what Chiu must decide before any of this is built. Nothing here changes the app.

Labels follow `CLAUDE.md` rule 4. Each unmeasured claim names what would settle it.

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
  overlay already uses (`deckWindow`, the photo-slot math), so a pacing change moves the music
  with the picture. A second copy of the slot math is the bug to prevent; a test pins that every
  `photoChanges` cue equals the frame where `overlayContents` shows a new photo.
- **No coordinate, name or country in a cue** — kind, time, stop index. §0 by construction.
- Open PRs that move these times — wen-chiu/kamome#355 (stops play in trip order) and
  wen-chiu/kamome#343 (the film ends on a souvenir map) — change *values*, not the cue kinds. If
  #343 lands, `endReveal`/`endCard` read whatever it defines; the cue sheet has no opinion.

### 2.2 `SoundtrackManifest` — the beatmap as Codable

One JSON per track, written at the desk by the beatmap tool (§5), never computed on the phone:

```json
{
  "id": "tropical-depart-2",
  "style": "tropical", "mood": "depart",
  "file": "tropical-depart-2.m4a",
  "bpm": 100.0, "beats_per_bar": 4, "first_downbeat_s": 0.412,
  "sections": [
    { "name": "intro",  "start_bar": 0,  "bars": 8,  "energy": 1, "role": "intro" },
    { "name": "verse",  "start_bar": 8,  "bars": 16, "energy": 2, "role": "body", "repeatable": true },
    { "name": "lift",   "start_bar": 24, "bars": 8,  "energy": 3, "role": "lift" },
    { "name": "chorus", "start_bar": 32, "bars": 16, "energy": 4, "role": "peak", "repeatable": true },
    { "name": "ending", "start_bar": 48, "bars": 6,  "energy": 2, "role": "outro" }
  ],
  "final_hit_bar": 52, "tail_s": 3.1,
  "integrated_lufs": -14.1,
  "provenance": { "engine": "acestep-1.5", "commit": "ca1e85f", "seed": 123456789 }
}
```

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
   `repeatable` section at its phrase lines. If the manifest has none, the picker must not
   choose that track for that film (a filter, not a runtime surprise).
5. **Moments the music answers** — Chiu's 「景點出現或照片出現可以加強音樂」:

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
6. **The music answers the picture, not the other way round (v1).** An accent snaps to the
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
`AVAudioUnitEQ` (one low-pass band) and the main mixer. The render loop pulls 1,024-frame chunks
and sets gain and cutoff from the plan's curves before each chunk — the curves are pure, so
the "what" is unit-tested and this file only does the "how". Output: AAC 48 kHz stereo,
`soundtrack.audio_bitrate_kbps` (192 proposed).

Rejected: `AVMutableComposition` + `AVAudioMix`. Simpler, but `AVAudioMix` has volume ramps only —
no low-pass — and the stop dip without a filter is just "quieter", which reads as a mistake
(INFERRED; *settle:* render one film both ways at the desk and let Chiu listen).

### 3.2 `RecapFilmMuxer.swift` — `silent.mp4` + `soundtrack.m4a` → `film.mp4`

`AVMutableComposition` with the video track and the audio track, exported with
`AVAssetExportPresetPassthrough` to `.mp4`. Video bytes are copied, not re-encoded.
**INFERRED:** passthrough accepts an AAC track into an MP4 container and takes seconds for a
90 s film. *Settle:* one desk harness run on the simulator, timed.

"Change the music" reuses this file: it takes the video track out of the stored `film.mp4`
instead of `silent.mp4`. No silent master is kept, so storage does not double.

### 3.3 The confinement rule this needs

`Config/architecture.json` confines AVFoundation to `Core/ExportEngine/RecapVideoEncoder.swift`.
This design needs two more files. Proposal: confine it to those three files by name, and add
`AVFAudio` (where `AVAudioEngine` actually lives; it can be imported without AVFoundation) as its
own confined SDK, or the rule has a hole. **Architecture change → Chiu confirms first** (rule 2).

---

## 4. The app side

### 4.1 Export flow (`RecapExportJob`)

    compose ─► pick soundtrack ─► plan timeline ─┬─► render video (minutes) ─┬─► mux ─► store
                                                 └─► arrange + render audio ─┘
                                                     (seconds, in parallel)

- The picker runs before `plan`, because §6 (if ever chosen) needs the track before the timeline.
- `ExportLogHistory` gains two stages, `music` and `mux`, so their cost is measured, not modelled.
- A soundtrack failure **fails loudly but does not lose the film**: the silent film is kept and
  the sheet says the music could not be added, with 「再試一次」 that re-runs only §3.1–3.2.
  Not a silent fallback (`CHARTER.md` §4): the person is told.

### 4.2 Screens

- **Film sheet (`RecapView`)** — one new row in the settings card: 「音樂」, value 「自動」, a menu
  with 自動 / 無音樂. Nothing more before the film exists; this follows Chiu's reasoning that a
  person cannot choose music for a film they have not seen.
- **Player (`FilmPlayerSheet`)** — 「換音樂」 opens a short list: the current choice, the next
  two by the picker's score (labelled by mood in plain words, e.g. 「輕快」「悠閒」「壯闊」 — never
  by country, see §4.4), and 無音樂. Selecting one previews at once (the player plays the stored
  video with the candidate's freshly rendered audio) and 「使用這首」 re-muxes.
- zh-Hant: **音樂** is a new word for the glossary (ADR 2026-10-26-zh-hant-uses-one-word-for-each-thing);
  pick it once (音樂, not 配樂/BGM) and add it to `ZhHantGlossaryTests`.
- **UNKNOWN — the silent switch.** Should the player play sound when the phone is on silent?
  Video apps usually do (`AVAudioSession.Category.playback`). A device check, and a product call.

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
- **Loudness:** −14 LUFS integrated, true peak ≤ −1 dBTP (`pyloudnorm`), or refuse.
- **A gate in `./check.sh --static`:** every catalog track has a manifest, every manifest's
  sections fit inside the file's duration, no section crosses another, at least one `repeatable`
  body section exists. Stdlib-only for the gate; librosa only in the desk tool.

librosa and pyloudnorm are **desk-only dependencies — Chiu confirms them** (rule 2), as he did
for ACE-Step (rethink D3a).

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

1. **Music leaves "Deferred"** and an ADR says so (scope: v1 = §1–§5, not §6).
2. **Tier.** ADR 2026-07-20 says *free = silent export, premium = in-app track* (`Docs/decisions.md`
   line 593). Does it still stand? No paywall exists, so "premium" has nowhere to live yet.
3. **The architecture change** in §3.3 (two files allowed AVFoundation, AVFAudio confined).
4. **Public repository.** Tracks committed here are public to anyone. Alternatives: Git LFS in a
   private store fetched at build time, or accept it (AI output may carry no copyright anyway,
   rethink C3). **And never register the tracks with a Content ID service** — a user's shared
   film would be claimed against them.
5. **Defaults:** the `anthem` style for unlisted countries; 自動 on by default; whether the
   silent switch silences the player.
6. **Bundle size** (~36 MB) vs. download.

## 8. Build order — one PR each, each `./check.sh` green

| # | PR | behaviour change? | device? |
|---|---|---|---|
| 0 | ADR: music opens, scope v1, answers to §7 | — | — |
| 1 | `FilmCueSheet` + tests (cues equal overlay frames) | none | no |
| 2 | `kamome-beatmap.py` + manifest schema + static gate + one real track | none | no |
| 3 | `SoundtrackArrangement` + tests (ending on end card ±1 sample, total = film duration, no stretch, accents within tolerance or unsynced, repeat for long films) | none | no |
| 4 | Renderer + muxer + architecture rule + desk harness `TEST_RUNNER_KAMOME_SOUNDTRACK=<fixture>` writing a film with music to `~/Kamome-films/` | none (harness only) | no |
| 5 | `PhotoMood` (analyser v2) + `SoundtrackPicker` + context + tests (deterministic, §0 log words) | none | timing on a phone |
| 6 | Export wiring + `FilmRecord` migration + sheet row + player 「換音樂」 + copy | **yes** | yes — runbook rows below |

New `Docs/device-runbook.md` rows for PR 6: added wall time (`music`, `mux` stages); audio on the
phone speaker (does the stop dip read, or does it sound broken); the silent switch; a film shared
to LINE and Instagram keeps its sound; an export left in the background still muxes.

**A visual change owes a render; this one owes a listen.** `./check.sh` cannot hear the film —
every PR from 3 on ships one rendered film with music for Chiu.
