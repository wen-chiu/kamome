# The film sheet says what it does, and the film player saves like the finished screen

**Status:** Decided (Chiu, 2026-10-26)
**Supersedes:** nothing. The 2026-07-18 rule stands: the photo-card switch must read as photo cards only. This changes how its note says so.

## Context
The first-time-user walk of 2026-10-10 (VERIFIED on screen, sample trip, zh-Hant) found that the film sheet (`RecapView`) read like iOS Settings (#291). Its leading button said 「完成」 but only closed the sheet. The switch's note said what the switch does *not* control, and named a 「取得這條路線」 card that appears nowhere else. Each stop showed 「2 / 2」 with no legend, and there was a blank under 「車輛」. The film player (`FilmPlayerSheet`) had 分享 and a red 刪除影片 of equal weight, and no 儲存到照片 (#295 item 9).

## Decision
Chiu, on #291 and #295, 2026-10-26. Where the means is this PR's rather than Chiu's words, it says so; Chiu judges it from the screenshots.
- 「完成」 becomes **「關閉」** / "Close" on the film sheet. The player gets the same label (this PR's call).
- The switch's note says what the switch does: 「每到一個地點，影片會放上你在那裡拍的照片。」 / "At each stop, the film shows photos you took there." **Draft wording**; the words are Chiu's to judge.
- 「2 / 2」 becomes **「2 張照片」**: the photos the film shows at that stop.
- **The blank under 「車輛」 goes.** It was the 35 pt between two sections, not an empty footer: dropping the footer left it at 35 pt (VERIFIED, simulator screenshots before and after). The photo-card switch therefore joins the settings card, with its note as the row's second line. The length row gets the same treatment, because as the card's footer its sentence sat under the switch and read as the switch's. The means is this PR's.
- **The player's pair is 儲存到照片 and 分享**, as on the finished screen, and it is the same component (`FilmSaveShareActions`). 刪除影片 becomes secondary and still asks first (the spirit of ADR 2026-10-02-deleting-a-stop-asks-first). It goes into ⋯ as on the finished screen (this PR's means).
- No preview of the film in this round.

## Rejected
- **Only dropping the empty footer:** the blank stayed (VERIFIED).
- **`.listSectionSpacing(.compact)`:** it narrows the blank but does not remove it.
- **✕ for close:** 「關閉」 was Chiu's first choice. While a film renders the button says 「返回」, because leaving does not cancel (2026-09-10), and a ✕ would read as cancel.
- **A red text button for Delete under the pair:** the finished screen keeps Delete in ⋯, so this keeps one place for it on both screens.

## Consequences
- New key `recap_close`. Changed values: `recap_photos_note` (both languages) and the zh `recap_stop_photo_count` (「%lld 張」 → 「%lld 張照片」). `recap_done` stays, for the film list.
- `FilmDeckRow` is shared, so the Stop Editor's photo row says 「2 張照片」 too.
- `LocalizationTests` was restated: the note names photos and stops, and no card it leaves alone. `RecapExportCopyTests` pins 「關閉」 and 「2 張照片」.
- The length's over-ceiling warning is the length row's second line, in orange as before (VERIFIED, simulator: three stops put in on a Short film, 1:32 past 1:30).
