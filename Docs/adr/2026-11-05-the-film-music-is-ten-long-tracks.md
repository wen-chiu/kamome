# The film music is a library of ten long tracks: regional styles for their regions, a mood choice for everyone else

**Status:** Decided (Chiu, 2026-11-05)
**Supersedes:** the five STYLES × three MOODS briefs as the source of bundled tracks (`Tools/kamome_music_briefs.py`, rethink Part D); the briefs stay as a desk tool. Nothing in ADR 2026-11-03-the-music-plays-straight-through changes.

## Context
- Chiu listened on 2026-11-05 to 28 Stable Audio 3 takes from a second set of prompts: long descriptive briefs, 180 s each. His verdict: 「新的風格比較好聽 可能因為prompt的關係」. He kept ten of them: 「十個 就先用他們吧」.
- He also gave the rule for length: one track per film, and 「影片最多可能可以到五分鐘 程式上我們要針對影片長度去做音樂修剪」. Standard films reach 300 s (`standard_duration_max_s`).
- **Measured on 2026-11-05** (VERIFIED), on one 320 s take of `indiepop` (seed 505387708):
  - `Tools/kamome-beatmap.py`, after a two-pass `loudnorm` master: 111.999 BPM against the brief's 112; drift 0.079 BPM; −13.0 LUFS, −1.4 dBTP; final hit at 312.9 s.
  - `SoundtrackArrangement.plan`, run on that manifest for every film length from 60 s to 300 s in 1 s steps: every length fitted; no repeat was needed; the final hit landed on the end card.
- **INFERRED:** the other 19 takes behave the same way. *Settle:* run the same probe on each before it is bundled.

## Decision
1. **The library is ten briefs** (`LIBRARY` in `Tools/kamome_music_briefs.py`). The prompts are Chiu's, word for word, except S1 and S2. Those two were written for this file in the same style, for regions that had none. Each brief has a fixed BPM and key. Stable Audio 3 medium generates them, two seeds each.
2. **Every track is 320 s**, longer than any film. A film only ever cuts music; it never stretches it and does not need to repeat a section.
3. **The picker's mapping** (Chiu's choice, 2026-11-05):

   | country | brief | style / mood in the manifest |
   |---|---|---|
   | JP TW KR | S1 Cinematic City Pop | citypop / depart |
   | IS NO | S2 Nordic Cinematic Post-Rock | nordic / epic |
   | VN TH | 07 Tropical Acoustic | tropical / cruise |
   | Europe, NZ, AU | 08 European Folk | folk / cruise |
   | everyone else, depart | 04 Feel Good Indie Pop, 01 Cinematic Indie Pop | anthem / depart |
   | everyone else, cruise | 12 Chill Downtempo, 11 Organic Electronic | anthem / cruise |
   | everyone else, epic | 02 Epic Cinematic, 06 Adventure Pop Rock | anthem / epic |

   **A regional style plays whatever the photographs' mood.** This needs no picker change: `SoundtrackPicker.rank` ranks the moods, and the only takes in the style's pool are its own.

## Rejected
- **Mood for every country, regardless of where the trip is:** a Japan trip could get Nordic post-rock.
- **A separate folk brief for NZ and AU:** Chiu shares 08 with Europe.
- **Keeping the 120–180 s takes and repeating a section for long films:** a 300 s film would replay up to two minutes.

## Consequences
- **This PR (Tools only):**
  - `kamome_music_briefs.LIBRARY`;
  - `kamome-stableaudio.py library`;
  - `kamome-beatmap.py --brief`.
- **Owed by the PR that bundles music, as an issue:**
  - the `country_styles` table gains the European countries under `folk`;
  - the catalog tool reads the library's flat `<brief>-s<seed>.wav` names through `--brief`;
  - the bundle is replaced by the library;
  - each take is probed for 60–300 s.
- **UNKNOWN:** which ISO codes count as "Europe" (for example, Turkey, Cyprus, the Caucasus). `IS` and `NO` stay `nordic`. *Settle:* Chiu names the list.
- **Size:** 20 takes × 320 s at 128 kbps is about 100 MB, against 66 MB for #367's 29 takes. Shipping one seed per brief halves it. Chiu's call.
