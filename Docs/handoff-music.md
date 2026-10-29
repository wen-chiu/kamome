# Handoff — film music, desk loops (Chiu 2026-10-29)

**State, 2026-10-29.** A desk tool composes and synthesises four regional loop sets, and an
arranger fits one to a film's events. **Nothing in the app plays music**: music in the film is
still deferred (`Docs/current-state.md`), and this is the material for that decision, not the
decision. Chiu asked for it: free-licence music only, by region, looping, with different beats at
the film's turns.

## What exists

| Piece | Where |
|---|---|
| Composer, synthesiser, arranger (pure stdlib) | `Tools/kamome-music.py` |
| Output (never committed; regenerate) | `~/Kamome-music/<style>/` — 4 loops, 4 one-shots, `beatmap.json` |

    python3 Tools/kamome-music.py render                       # ~2.5 min, 4 cores
    python3 Tools/kamome-music.py arrange --style nordic --example
    python3 Tools/kamome-music.py style --country IS

| style | countries (Chiu's table) | tempo | key, progression |
|---|---|---|---|
| `east-asia` | JP TW KR | 90, swung | F: Bbmaj9 · A9 · Dm9 · Cm9 F9 |
| `nordic` | IS NO | 80 | D: Dadd9 · A/C# · Bm7 · Gmaj7#11 |
| `southeast-asia` | VN TH | 100 | A: A · F#m7 · Dmaj7 · Esus4 E |
| `oceania` | NZ AU | 98 | G: G · Em7 · Cadd9 · Dsus4 D |

**How the turns work.** Loops: `intro` (title card), `travel_a`/`travel_b` (driving, alternating
after each stop), `stop` (photos — no kick, no snare). Events: `go` → riser + `hit_big`, next
travel loop; `stop` → `hit_soft`, the old loop fades over 0.9 s; `crossing` → riser + `hit_big`,
`travel_b`; `end` → riser + `outro`. Every loop in a style plays the same 4-bar progression in the
film's phase, so a switch on **any beat** stays in harmony. Events snap to the nearest beat; the
film is not moved, and the arranger prints how far each event is off the beat.

## Evidence

- **VERIFIED, by construction:** no sample, sound font or recording is read; every sound is
  synthesised from sine waves and noise in the file. The beat map is exact (tempos are whole
  samples per beat), not detected.
- **VERIFIED, desk measurement:** pitch within ±6 cents for every pitched instrument (the KS
  guitars within ±0.1); every loop's seam step is below its own 99.9th-percentile sample step;
  the four example soundtracks average −21 to −22 dBFS, peaks ≤ −1.2 dBFS.
- **VERIFIED on the illustrative timeline only:** the largest event-to-beat offset is 350 ms
  (half a beat at 80 BPM). Not measured on a real film's events.
- **UNKNOWN — whether it sounds good.** Nobody has listened. Settle: Chiu listens to the four demo
  MP4s (session of 2026-10-29) or runs `arrange --example` and plays the WAVs.
- **UNKNOWN — phone speaker.** Basses carry harmonics so the line survives a phone speaker
  (INFERRED from design). Settle: one play on the phone.
- **INFERRED — licence:** synthesised output carries no third-party rights. Whether it is
  *copyrightable* is uncertain; that limits stopping others copying it, not using it.
- **INFERRED, from Suno's own announcement via search — not read at suno.com:** Suno free-plan
  songs are personal, non-commercial use only, and upgrading later does not make them commercial;
  songs downloaded on a paid plan may be used commercially. Settle: Suno's current terms.

## Not decided — Chiu

1. Whether the film gets music at all, and in which tier (ADR 2026-07-20 recorded free = silent
   export, premium = an in-app track).
2. Synth quality versus a paid source (a paid Suno month, a composer). The arranger is
   source-agnostic only if loops meet its format: whole-bar loops sharing one progression, a
   constant tempo. Suno tracks do not, without manual cutting.
3. What a country outside the eight gets (`style` refuses), and which style a two-country trip
   takes.
4. Whether the export moves events onto the beat (≤ half a beat). That touches measured
   durations, e.g. `crossing_beat_s` 4.0.

## If it is wired in

Events from `LinearTimeline`: `journeyStartS` → `go`; each hold's start → `stop`, end → `go`;
`crossingBeatWindowsS` → `crossing`; the end card → `end`. Mix after `RecapVideoEncoder` (video
untouched, muxed with passthrough — INFERRED). Fades, recipes and the snap go to
`Config/TrackingConfig.json`. Assets as AAC: 88–100 s of audio per style (measured from the
renders), so ~6 MB for four at 128 kbps (INFERRED).
