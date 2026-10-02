# The finished screen is the film; what is not the film says less, and says it once

**Status:** Decided (Chiu, 2026-10-02)
**Supersedes:** nothing. Amends ledger entry "2026-09-26 (c)" (Export again as a text button under the pair) and the wording allowed by "2026-09-10" (the leave note)

## Context

Chiu, 2026-10-01, from two phone screenshots of a New Zealand export:
*「Saved to photos的按鈕跟旁邊share沒有對齊」*, *「重點是export的影片 要讓他大一點」*,
*「Export again要不要放在其他地方」*, *「誠實告知很好但好像有點太多了 這邊也講 完成時也講」*,
*「請他不要離開app 影片輸出才能繼續」*, and *不能影響影片程式穩定度跟效能*.

- VERIFIED (screenshot): "Saved to Photos" wrapped to two lines, so Save was taller than Share.
- VERIFIED (screenshot): under the film sat the readout, a three-line routing
  notice, the pair and Export again; the film got what height was left.
- VERIFIED (`RecapNotices`): the no-road sentence was shown while rendering and again, whole, when finished.

## Decision

Chiu, 2026-10-02, on the simulator screenshots and the wording below: *「同意」*.

1. **The pair is one row of one height.** Labels stay on one line; the saved
   state reads "Saved" / 「已儲存」. A denied or failed save is a sentence under the
   pair, never inside the button.
2. **Export again lives in ⋯**, with Delete. It comes back on screen, as the
   text button it was, only when the run found something another export fixes:
   missing photos, or legs dashed by an unreachable, busy or out-of-time routing run.
3. **A leg with no road is a fact on the finished screen, not a paragraph.** It
   joins the readout on one caption line: "Rendered in 324.8 s · 2 legs have no
   road". The three retryable causes keep their full notice.
4. **The explanation is said once, while rendering, and shorter:** "Drawn dashed
   — Kamome never draws a road that isn't there." / 「這幾段畫成虛線 —— 沒有路，就不畫成路。」
5. **The leave note leads with what to do:** "Keep Kamome open so the film can
   finish. It's fine to leave this screen." / 「請讓卡摸咩保持開啟，影片才能繼續輸出。離開這個畫面沒關係。」
   Still inside ADR 2026-09-10's bounds (`RecapExportCopyTests`, unchanged).

## Rejected

- **Dropping the no-road line when finished:** the person who left the screen
  mid-render would get a dashed film with no reason given (rule 5).
- **Export again only in ⋯, always:** the budget and missing-photo notices tell
  the person to export again; the button they name must be on the screen.
- **Moving "Rendered in X s" into ⋯:** "stays in Release" (2026-09-26) is Chiu's; not reopened.
- **A larger film by shrinking the title:** it is Chiu's copy and the moment (UX rule 6).

## Consequences

- `UI/Recap/` and three catalogue strings only. Nothing in `ExportEngine`, the
  coordinator or the render loop changes, so stability and render time cannot (VERIFIED, diff).
- UNKNOWN: how the screen reads on a phone, and with a retryable notice showing.
  Settled by one export on the phone (#112) — wording goes to the #118 batch.
