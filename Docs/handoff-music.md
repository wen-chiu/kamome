# Handoff — film music, desk loops (Chiu 2026-10-29; round 4 2026-10-30)

**State, 2026-10-30.** A desk tool composes loop sets for road-trip films, and an arranger fits one
to a film's events. **Nothing in the app plays music**: music in the film is still deferred
(`Docs/current-state.md`), and this is the material for that decision, not the decision. Chiu
asked for it: free-licence music only, looping, with different beats at the film's turns.

## How it got here

| round | what Chiu heard | what changed |
|---|---|---|
| 1 | melodies 60–70%; East Asia's guitar unnatural; Nordic monotonous; the percussion did not sit | — |
| 2 | (Chiu chose recorded CC0 sounds over synthesis, an upright piano and vibraphone over the guitar) | VCSL recordings; a new Nordic tune |
| 3 | "still a strange disharmony — subtract" + a Polarsteps film's music to match | triads only, ≤ 4 layers, five moods |
| 4 | consonant but mechanical, repetitive, no emotional depth (written brief) | Tropical and Pop recomposed, A and B arrangements each |

**Round 4's brief (Chiu, 2026-10-30), in short:** colour chords, inversions, two-bar chords and a
moving bass, without stacking extensions; 2-bar motifs grown into 4- and 8-bar phrases; up to six
layers, each with one role, a subtle pad allowed; a different groove per genre; development from
intro to peak; a cleaner mix. Test on Tropical and Pop first, as A (restrained) and B
(expressive), against Round 3. The other three styles stay Round 3.

**What Round 4 is.** One 16-bar composition per style, heard at five levels — `intro`, `build`,
`main`, `peak`, `stop` — with the same chords and tune in the same place in each, so the film's
events move it up and down a ladder: each `go` climbs a rung, a crossing goes to the top, a long
drive climbs at the next 8-bar line, a stop drops to `stop` and keeps the rung. The melody rule
(`check_tune`) allows a chord's colour tone and an anticipation in the bar's last beat. The mix
has per-instrument EQ, a pad and bass that duck under the kick, and an EQ'd reverb return.

| style | key, tempo | progression (bars) | tune / chords / groove |
|---|---|---|---|
| `tropical-a/-b` | D, 100 | Bm(2) Gmaj7(2) Dadd9(2) Asus4 A · Bm(2) Gmaj7(2) D D/F# G A | piano tune and chords; bass walks D-F#-G-A; soft kick, claps, shaker; B: marimba answers, congas |
| `pop-a/-b` | E, 120 | Eadd9(2) B/D#(2) C#m C#m/B Amaj7 Bsus4 · then twice as fast | sung synth line; bass falls E-D#-C#-B-A; four-on-the-floor; B: echo, pluck answers, tambourine |

## Evidence

- **VERIFIED — licence:** VCSL's `LICENSE` is CC0 1.0 Universal; `fetch` and `render` refuse a
  checkout without it. Kick, bass, pad, synth line and pluck are synthesised in the file.
- **VERIFIED — melody rules:** every tune passes its check; a planted breach exits 2. Round 4's
  voicings score zero semitone grinds (a close maj7's 7th against its root is avoided by the
  pianist's open voicing).
- **VERIFIED — Round 3 unchanged:** re-rendered `pop` is byte-identical to the Round 3 render.
- **MEASURED against Chiu's reference, one 60 s drive** (band energy relative to the mix, dB):

  | | 60–250 Hz | 500–1000 Hz | 2–8 kHz | bars repeating an earlier bar | loudness, first → last drive bar |
  |---|---|---|---|---|---|
  | Round 3 tropical / pop | −10 / −5 | +8 / +7 | −2 / −5 | 17 of 26 / 21 of 30 | flat, −22 |
  | Round 4 tropical A/B | −3 / −4 | +7 | −2 to −4 | 0–1 of 25 | −27 → −21 |
  | Round 4 pop A/B | −3 | +6 | −1 to −4 | 6–7 of 30 | −23 → −20 |

  Proxies, not a verdict: a spectrum close to a mastered pop track is not the goal in itself.
- **VERIFIED, desk:** 20 of 20 Round 4 loop seams clean; arranged peaks ≤ 0.92.
- **UNKNOWN — the six questions of the brief** (memorable melody, natural chords, instruments that
  belong together, natural rhythm, atmosphere, completeness). Settle: Chiu listens to the four
  `round4-*` comparison videos (Round 3 → A → B on one timeline).
- **UNKNOWN — phone speaker.** Settle: one play on the phone.

## What exists

| Piece | Where |
|---|---|
| Composer, sampler, arranger (pure stdlib) | `Tools/kamome-music.py` |
| VCSL recordings, pinned commit, never committed here | `~/Kamome-music/vcsl/` — `fetch` |
| Output (never committed; regenerate) | `~/Kamome-music/<style>/` — loops, one-shots, `beatmap.json` |

    python3 Tools/kamome-music.py fetch                        # once; needs git
    python3 Tools/kamome-music.py render --style tropical-a --style tropical-b --style pop-a --style pop-b
    python3 Tools/kamome-music.py arrange --style tropical-b --example

Round 3 styles, still current for the other moods: `acoustic` (NZ AU), `cinematic` (IS NO),
`lofi` (JP TW KR), plus Round 3's `pop` and `tropical` (VN TH) kept for comparison.

## Not decided — Chiu

1. A or B per style, or neither — then whether Round 4's approach goes to the other three moods.
2. Whether the film gets music at all, and in which tier (ADR 2026-07-20 recorded free = silent
   export, premium = an in-app track).
3. What a country outside the eight gets — `pop` is the candidate — and which style a
   two-country trip takes.
4. Whether the export moves events onto the beat (≤ half a beat). That touches measured
   durations, e.g. `crossing_beat_s` 4.0.

## If it is wired in

Events from `LinearTimeline`: `journeyStartS` → `go`; each hold's start → `stop`, end → `go`;
`crossingBeatWindowsS` → `crossing`; the end card → `end`. The ladder logic is `arrange`'s. Mix
after `RecapVideoEncoder` (video untouched, muxed with passthrough — INFERRED). Fades, recipes and
the snap go to `Config/TrackingConfig.json`. Ship rendered loops as AAC, not VCSL: a Round 4 style
is five 16-bar loops, ~3 min of audio, ~3 MB at 128 kbps (INFERRED).
