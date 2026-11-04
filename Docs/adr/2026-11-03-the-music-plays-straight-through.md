# The music plays straight through the film: no dip at a stop, no lift on a photograph

**Status:** Decided (Chiu, 2026-11-03)
**Supersedes:** nothing decided. It replaces the proposal in `Docs/handoff-music-in-the-film.md` §2.5 items 5–6 (stop dip, return on the downbeat, photo lift, crossing lift, cut onto the end reveal), which was never an ADR.

## Context
- PR A (wen-chiu/kamome#364) built the proposal and rendered a 90 s and a 180 s desk film with a real ACE-Step take. At each stop the music dipped −6 dB with a low-pass to 1.2 kHz; it came back on the downbeat after the car set off; each photograph change opened the filter a step.
- Chiu listened, 2026-11-03:
  - the final hit on the end card: 「可以」;
  - the stop dip: 「不行 像壞掉 照正常就好」;
  - the return on the downbeat, and the photo lift: neither noticed;
  - the cuts and the repeat: 「應該聽不出來」.
- On syncing the music to the photographs: 「看起來要讓你在照片出來的時候抓著旋律beats有點難 就先這樣吧」.

## Decision
1. **The music plays at one level for the whole film.** Its loudness is normalised to `target_lufs` under the true-peak ceiling. It has no dip, filter, lift or accent at any moment of the film.
2. **The film's moments decide only the arrangement:**
   - the final hit lands on the end card;
   - cuts fall on phrase lines;
   - the remainder is absorbed inside the intro;
   - a long film replays a stretch;
   - the peak is placed nearest the strongest moment.
3. **Not pursued for now:** a section change at a crossing, the cut onto the end reveal, and moving photographs onto the beat (handoff §6). wen-chiu/kamome#361 is closed with this.

## Rejected
- **Keeping the dip machinery switched off in config.** Ten keys and a filter would control nothing, which is the dead-config trap `Scripts/check-dead-config.sh` exists for. The code stays in git history (#364's first commits) if a later listen wants it back.
- **A gentler dip (−2 or −3 dB, no filter).** Chiu asked for 「照正常就好」, not for less of it.

## Consequences
- **Removed:** `SoundtrackAutomation.swift`, the `AVAudioUnitEQ` in `RecapSoundtrackRenderer`, and ten `soundtrack` keys (`stop_dip_db` … `photo_accent_decay_beats`). `SoundtrackPlan` now carries one `gain`.
- **Pinned:** `testAStopDoesNotDuckTheMusic` renders through a stop and finds the clicks unchanged. Against the dip version it fails: 0.12 against 0.41.
- **Unchanged:** the cue sheet stays as the arrangement's input and PR B's.
- **PR B's runbook loses one row:** "does the stop dip read on the phone speaker".
