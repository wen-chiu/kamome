# The end card glows softly behind its type, and its closing line is in the film's language

**Status:** Decided (Chiu, 2026-10-10)
**Supersedes:** ledger entry "2026-09-05" on the tagline being deliberately unlocalized; amends ADR 2026-09-05 (d) (the end card's ground)

## Context
The sample film's closing card, in zh-Hant and light appearance at 58.5 s, had two problems (VERIFIED from the exported MP4, #287):
- **A base-map name under the trip's name.** 「Taiwan 臺灣」 appeared twice, and one copy sat under 「範例・花蓮到台東」, so the two read as one jumble.
- **The closing line was English in a Chinese film.** 「Turn your journey into memory.」 was 30 px accent red over a dark map, the one line in the stack that barely read.

The Map labels lock keeps country names on the base map (CHARTER §6). A deeper full-frame dim and a card were both rejected for this card before (`RecapEndCardStyle`).

## Decision
Chiu, asked to choose, on 2026-10-10:
- **The type gets a local soft glow** (「文字後面加局部柔光」).
  - It is a feathered dark ellipse behind the stack only: full strength to 45 % of its radius, then fading to nothing.
  - The base map keeps every name; the one under the type steps back.
  - The strength is per appearance, beside the dim: 0.45 on light, 0.32 on dark (`RecapStylePresets`).
- **The closing line is localized** (「中文影片用中文，改白字」).
  - `recap_end_tagline` reaches the renderer as `RecapTrip.endCardTagline`, which defaults to the English brand line.
  - It is drawn in the stack's white, not the accent.
  - zh-Hant draft: 「把旅程留成回憶。」. The final wording is Chiu's, in the #118 batch.

## Rejected
- **Fading the base map's country names on the end card:** it reopens the Map labels lock. Offered, and not chosen.
- **A deeper full-frame dim, or a card:** both were rejected before (ADR 2026-09-05 (d)).
- **English everywhere and only white:** the line would still be foreign in a Chinese film.

## Consequences
- `RecapChromeTests.testTheStackGlowDarkensBehindTheTypeAndNowhereElse` keeps the glow local: darker at the stack, unchanged at the frame's edge.
- `LocalizationTests` restates the tagline rule: the English value equals the brand line, and no language promises a scan.
- **Rendered:** both sample films (zh-Hant and en, light, frame at 58.5 s), the ones now bundled (#285).
  - VERIFIED: the closing line is in the film's language and reads, in white.
  - VERIFIED: **the glow softens the collision and does not remove it.** 「Taiwan 臺」 still touches the left end of the trip's name; a dark name with a white halo stays legible under a glow this light.
  - Stronger is Chiu's call, judged from that frame: deepen the glow's core, which moves toward the rejected card, or fade country names on the end card only, which reopens Map labels.
- Dark appearance is UNKNOWN until one dark export is looked at.
