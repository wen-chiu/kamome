# Handoff — film music, desk loops (Chiu 2026-10-29, round 3 2026-10-30)

**State, 2026-10-30.** A desk tool composes five loop sets for road-trip films, and an arranger
fits one to a film's events. **Nothing in the app plays music**: music in the film is still
deferred (`Docs/current-state.md`), and this is the material for that decision, not the decision.
Chiu asked for it: free-licence music only, looping, with different beats at the film's turns.

## How it got here

| round | what Chiu heard | what changed |
|---|---|---|
| 1 | melodies 60–70%; East Asia's guitar unnatural; Nordic monotonous; the percussion did not sit | — |
| 2 | (Chiu chose recorded CC0 sounds over synthesis, an upright piano and vibraphone over the guitar) | VCSL recordings; a new Nordic tune |
| 3 | "still a strange disharmony — too much harmony I can't control; subtract" + a Polarsteps film's music to match | rebuilt by subtraction, five moods |

**Diagnosis behind round 3 (INFERRED from the measurements, not from listening):** rounds 1–2
voiced jazz chords (maj9, #11, add9 clusters) on two or three harmony instruments at once, and
synthesised imitations of acoustic instruments (flute, whistle, guitar). Chiu's reference,
**MEASURED** from its audio: 118 BPM; E major, tuned to A440 (+0.2 cents); only triads I, iii, vi,
IV, V; a four-on-the-floor kick under a 3-3-2 bass; a one-bar hook repeated, inside G#4–F#5. Its
melody was not copied — only those numbers.

**The rules now, in the module docstring.** Triads from the key, one chord a bar, in stock pop
progressions; at most four layers; recorded instruments or honestly electronic sounds; no swing,
crackle or pads. `check_melody` refuses to render a tune with a non-chord tone on beat 1 or 3, or
held a beat or more.

## What exists

| Piece | Where |
|---|---|
| Composer, sampler, arranger (pure stdlib) | `Tools/kamome-music.py` |
| VCSL recordings, pinned commit, never committed here | `~/Kamome-music/vcsl/` — `fetch`, 226 files, 432 MB |
| Output (never committed; regenerate) | `~/Kamome-music/<style>/` — 4 loops, 4 one-shots, `beatmap.json` |

    python3 Tools/kamome-music.py fetch                        # once; needs git
    python3 Tools/kamome-music.py render                       # ~2 min, 4 cores
    python3 Tools/kamome-music.py arrange --style cinematic --example
    python3 Tools/kamome-music.py style --country IS

| style | countries | tempo, key | progression | chords / tune / drums |
|---|---|---|---|---|
| `pop` | none yet | 120, E | I–V–vi–IV | grand piano / electronic pluck / kick, claps, hats |
| `acoustic` | NZ AU | 100, G | I–IV–vi–V | upright piano / glockenspiel / cajón, claps, tambourine |
| `cinematic` | IS NO | 80, D | I–V–vi–IV | one grand piano: left hand chords, right hand tune / bass drum, snare |
| `lofi` | JP TW KR | 84, C | IV–V–iii–vi | upright piano / vibraphone / kick, cross-stick, hats |
| `tropical` | VN TH | 105, C | vi–IV–I–V | grand piano off-beats / marimba / kick, claps, shaker |

Sections: `intro` chords only; `travel_a` drums, bass, chords, the 4-bar hook; `travel_b` the hook
and its answer, fuller drums; `stop` chords and the tune, softly. Turns: a recorded cymbal swells
into `go`, `crossing` and `end`; a hit lands on `go` and `crossing`; wind chimes open a `stop`.

## Evidence

- **VERIFIED — licence:** VCSL's `LICENSE` is CC0 1.0 Universal; `fetch` and `render` refuse a
  checkout without it. The kick, bass and pluck are synthesised in the file.
- **VERIFIED — the rule:** all five tunes pass `check_melody`; a planted breach exits 2.
- **MEASURED — VCSL:** note names put middle C at C3; glockenspiel and pianos are re-pitched from a
  measurement of each recording (round 2), within ±6 cents.
- **VERIFIED, desk measurement:** 20 of 20 loop seams below their own 99.9th-percentile sample
  step; the five example soundtracks average −21.1 to −23.5 dBFS after AAC, peaks ≤ −1.1 dBFS;
  largest event-to-beat offset 350 ms, on an illustrative timeline only.
- **UNKNOWN — whether round 3 sounds right.** Settle: Chiu listens to the five `v3` demo MP4s.
- **UNKNOWN — phone speaker.** Settle: one play on the phone.

## Not decided — Chiu

1. Whether the film gets music at all, and in which tier (ADR 2026-07-20 recorded free = silent
   export, premium = an in-app track).
2. What a country outside the eight gets — `pop` is the candidate — and which style a
   two-country trip takes.
3. Whether the export moves events onto the beat (≤ half a beat). That touches measured
   durations, e.g. `crossing_beat_s` 4.0.

## If it is wired in

Events from `LinearTimeline`: `journeyStartS` → `go`; each hold's start → `stop`, end → `go`;
`crossingBeatWindowsS` → `crossing`; the end card → `end`. Mix after `RecapVideoEncoder` (video
untouched, muxed with passthrough — INFERRED). Fades, recipes and the snap go to
`Config/TrackingConfig.json`. Ship the rendered loops as AAC, not VCSL: 70–100 s of audio a style,
~1.1–1.6 MB at 128 kbps (INFERRED).
