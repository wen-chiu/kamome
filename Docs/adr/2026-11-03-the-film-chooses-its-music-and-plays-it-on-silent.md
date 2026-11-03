# The film chooses its music, plays it on silent, and carries it in the app

**Status:** Decided (Chiu, 2026-11-03)
**Supersedes:** nothing. It settles `Docs/handoff-music-in-the-film.md` §7 items 5 and 6, which ADR 2026-11-03-music-leaves-deferred-and-every-film-has-it left for later ("預設值等音樂做好再來看").

## Context
- PR B of handoff §8 (the app ships music) needs four defaults before any code. Chiu answered them on 2026-11-03, at the start of the PR B session, choosing the recommended option each time.
- Only one take had a manifest (PR A's listen take). None was mastered; Chiu has not yet picked takes (`~/Kamome-music/RESULTS.md`).

## Decision
1. **A country not in the style table plays `anthem`.** The table is Chiu's (rethink A1): citypop JP TW KR · nordic IS NO · tropical VN TH · folk NZ AU.
2. **「音樂」 is 自動 by default** on the film sheet. 無音樂 is one choice away.
3. **The film plays with sound on the silent switch**: the players use `AVAudioSession` category `.playback`, as Photos and video apps do.
4. **The tracks are bundled in the app** (~36 MB proposed; measured once built). No On-Demand Resources, no download.
5. **The bundle carries both ACE-Step takes of every brief** (MIT), mastered to `target_lufs` under `true_peak_max_dbtp` and beatmapped at the desk by `Tools/kamome-soundtrack-catalog.py`. A take the beatmap tool refuses is left out and listed in the PR. `sections_confirmed` stays false until Chiu listens. The seed picks between the two takes of a brief.

## Rejected
- folk, or a mood-only pick across all styles, for unlisted countries.
- 無音樂 by default.
- `.ambient` or the default `.soloAmbient`: the silent switch would mute a film the person chose to play.
- On-Demand Resources and a download server: a download state, a failure path and an offline case in the export; a server is P7.
- One take per brief, only PR A's take, or the Stable Audio 3 takes (26 of 30 clip; tempo is a prompt request only).

## Consequences
- `Scripts/check-soundtrack-manifests.sh` stops refusing committed audio. It accepts audio only under `App/Resources/Soundtracks/`, and only with a manifest and a catalog entry each.
- AAC at 128 kbps CBR overshot a −2.3 dBTP master to −0.6 dBTP. Measured 2026-11-03 on anthem-depart-s1855554642. VBR held it at −1.2 dBTP, so the catalog tool encodes VBR.
- Device rows owed (`Docs/device-runbook.md`): the silent switch, audio on the phone speaker.
