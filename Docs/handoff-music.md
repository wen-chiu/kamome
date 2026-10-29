# Handoff — film music, desk loops (Chiu 2026-10-29)

**State, 2026-10-29.** A desk tool composes four regional loop sets, and an arranger fits one to a
film's events. **Nothing in the app plays music**: music in the film is still deferred
(`Docs/current-state.md`), and this is the material for that decision, not the decision. Chiu
asked for it: free-licence music only, by region, looping, with different beats at the film's
turns.

**Round 2, same day (Chiu's listen of round 1).** Melodies were "about 60–70%"; East Asia's
guitar sounded unnatural; Nordic's tune was monotonous; **the percussion did not sit with the
music**. Chiu then chose, when asked: **acoustic sounds from CC0 recordings** (VCSL) instead of
synthesis, and **an upright piano and a vibraphone instead of East Asia's guitar**. Nordic got a new
tune that moves; every `stop` loop now plays its style's own theme, sparser, so one tune runs
through the film.

## What exists

| Piece | Where |
|---|---|
| Composer, sampler, synthesiser, arranger (pure stdlib) | `Tools/kamome-music.py` |
| VCSL recordings, pinned commit, never committed here | `~/Kamome-music/vcsl/` — `fetch`, 403 files, 517 MB |
| Output (never committed; regenerate) | `~/Kamome-music/<style>/` — 4 loops, 4 one-shots, `beatmap.json` |

    python3 Tools/kamome-music.py fetch                        # once; needs git
    python3 Tools/kamome-music.py render                       # ~2.5 min, 4 cores
    python3 Tools/kamome-music.py arrange --style nordic --example
    python3 Tools/kamome-music.py style --country IS

| style | countries (Chiu's table) | tempo | key, progression | recorded / synthesised |
|---|---|---|---|---|
| `east-asia` | JP TW KR | 90, swung | F: Bbmaj9 · A9 · Dm9 · Cm9 F9 | upright, vibes, cross-stick, hats / EP, kick, bass, flute |
| `nordic` | IS NO | 80 | D: Dadd9 · A/C# · Bm7 · Gmaj7#11 | grand, glock, bass drum, snare, toms / pads, sub |
| `southeast-asia` | VN TH | 100 | A: A · F#m7 · Dmaj7 · Esus4 E | Đàn Tranh, marimba, cajón, congas / guitars, pan flute, kalimba |
| `oceania` | NZ AU | 98 | G: G · Em7 · Cadd9 · Dsus4 D | cajón, claps, tambourine, glock / guitars, whistle, bass |

Every style's turns use recorded cymbal swells, cymbal hits and wind chimes.

**How the turns work.** Loops: `intro` (title card), `travel_a`/`travel_b` (driving, alternating
after each stop), `stop` (photos — no kick, no snare). Events: `go` → riser + `hit_big`, next
travel loop; `stop` → `hit_soft`, the old loop fades over 0.9 s; `crossing` → riser + `hit_big`,
`travel_b`; `end` → riser + `outro`. Every loop in a style plays the same 4-bar progression in the
film's phase, so a switch on **any beat** stays in harmony. Events snap to the nearest beat; the
film is not moved, and the arranger prints how far each event is off the beat.

## Evidence

- **VERIFIED — licence:** VCSL's `LICENSE` is CC0 1.0 Universal and its README says commercial
  software, no credit; `fetch` and `render` refuse a checkout whose `LICENSE` is not. Everything
  not from VCSL is synthesised in the file.
- **VERIFIED — `fetch` from empty:** checks out commit `c1ea7bc`, 403 files, 517 MB.
- **MEASURED — VCSL's note names put middle C at C3.** Every instrument read 1200 cents above its
  name as scientific pitch; the tool reads them that way.
- **MEASURED — tuning.** The glockenspiel is 8–24 cents sharp, one Đàn Tranh string 38, the pianos'
  lower notes up to 10 flat; the Tanzanian kalimba is ±50 cents (its own scale), so the kalimba
  stays synthesised. Pianos, glock and Đàn Tranh are re-pitched from a measurement of each
  recording; rendered notes then read within ±6 cents. The grand's high notes read −8 cents in
  their first 0.2 s and 0 after: unison strings beating, not mistuning.
- **VERIFIED, desk measurement:** every loop's seam step is below its own 99.9th-percentile sample
  step (16 of 16); the four example soundtracks average −21.3 to −22.1 dBFS, peaks ≤ −0.5 dBFS
  after AAC.
- **VERIFIED on the illustrative timeline only:** the largest event-to-beat offset is 350 ms
  (half a beat at 80 BPM). Not measured on a real film's events.
- **UNKNOWN — whether round 2 sounds good.** Settle: Chiu listens to the four `v2` demo MP4s.
- **UNKNOWN — phone speaker.** Settle: one play on the phone.
- **INFERRED, from Suno's own announcement via search — not read at suno.com:** Suno free-plan
  songs are personal, non-commercial use only, and upgrading later does not make them commercial.
  Settle: Suno's current terms.

## Not decided — Chiu

1. Whether the film gets music at all, and in which tier (ADR 2026-07-20 recorded free = silent
   export, premium = an in-app track).
2. What a country outside the eight gets (`style` refuses), and which style a two-country trip
   takes.
3. Whether the export moves events onto the beat (≤ half a beat). That touches measured
   durations, e.g. `crossing_beat_s` 4.0.

## If it is wired in

Events from `LinearTimeline`: `journeyStartS` → `go`; each hold's start → `stop`, end → `go`;
`crossingBeatWindowsS` → `crossing`; the end card → `end`. Mix after `RecapVideoEncoder` (video
untouched, muxed with passthrough — INFERRED). Fades, recipes and the snap go to
`Config/TrackingConfig.json`. Ship the rendered loops as AAC, not VCSL: 88–100 s of audio per
style, ~6 MB for four at 128 kbps (INFERRED).
