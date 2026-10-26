# zh-Hant uses one word for each thing, and this file is the glossary

**Status:** Decided (Chiu, 2026-10-26)
**Supersedes:** ledger `2026-09-26 (c)` item 5 (「a stop is 停留點」, the film's figure labels keeping 停留)

## Context
A first-time-user walk on 2026-10-10 found the zh-Hant catalogue using several words for one thing (VERIFIED from both `.xcstrings`, #289): 匯出 / 輸出 / 算圖 for making the film, 相片 beside 照片, 您 beside 你, Kamome inside Chinese sentences, 停留點 / 停留 / 停留地點 / 地點 for a stop, 行程 beside 旅程. #289's comment of 2026-10-11 proposed one word per row.

## Decision
Chiu (#289, 2026-10-26): the 2026-10-11 glossary is adopted in full, and the home-screen name stays Kamome.

| concept | the word | retired | kept, and why |
|---|---|---|---|
| making the film | **製作** | 匯出 · 輸出 · 算圖 | 匯出 only for a file that leaves the app (「匯出診斷紀錄」). 匯入 (import) is a different word and stays |
| what gets made | **旅程影片** | 回顧 · 回顧影片 | 回憶 (memory) is a different word |
| photographs | **照片** | 相片 | 相簿, 「照片」App and 照片圖庫 are iOS's own words |
| addressing the person | **你** | 您 | — |
| the app in a zh sentence | **卡摸咩** | Kamome | the home-screen name (`CFBundleDisplayName`, `CFBundleName`) stays Kamome |
| a place in the trip (a stop) | **地點** | 停留點 · 停留 · 停留地點 | 拍攝地點 is where a photo was taken, not a stop |
| a trip | **旅程** | 行程 | — |

The sweep changed words only, never what a sentence says. English was unchanged (the sweep's brief, 2026-10-26).

**Where to look it up:** this file is the glossary. `ZhHantGlossaryTests` fails when a zh-Hant value in either catalogue uses a retired word outside its allowed keys, and its message names the word to use. `Docs/current-state.md` points here. New zh-Hant copy, starting with #290, #291 and #293, uses these words. A new exception needs Chiu's decision, then the key goes in the test's allowed list.

## Rejected
- **停留點 for a stop** (ledger 2026-09-26 (c)): it reads as GIS jargon, and 足跡 already counted 地點 (PR #284, for #267).
- **Keeping 停留 on the film's end card** (#289 offered it to save a re-render): not taken, as the glossary was adopted in full. 地點 is the same two characters, so the space reason in 2026-09-26 (c) no longer applies.
- **做影片** (#289's first suggestion): 製作 matches the button Chiu worded on 2026-10-10, 「製作旅程影片」.
- **卡摸咩 as the home-screen name**: it stays Kamome, matching the App Store name, the film's wordmark and the icon. The wordmark's own spelling is #119, still open.

## Consequences
- 77 zh-Hant values changed: 75 in `Localizable.xcstrings`, 2 in `InfoPlist.xcstrings`. The before and after of every key is in the implementing PR.
- The film's end card now says 地點. The bundled `sample-film-zh-Hant.mp4` was re-rendered so the sample does not show the retired word. The English film needed nothing.
- Tests that quoted the old wording were updated, and each still checks the same thing (`LocalizationTests`, `DiscoveryLocalizationTests`, `RecapRoutingCopyTests`).
