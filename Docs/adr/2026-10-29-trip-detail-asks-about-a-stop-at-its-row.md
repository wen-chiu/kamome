# Trip Detail's 「刪除地點」 question points at the stop that was swiped

**Status:** Decided (Chiu, 2026-10-29)
**Supersedes:** nothing. It extends ADR 2026-10-28-home-asks-about-a-trip-at-its-row to Trip Detail's stop list, which that ADR left to Chiu (#326).

## Context
- VERIFIED (#326, simulator, iOS 26.5, 2026-10-28, 2 of 2): 「刪除地點」 hung on the whole `List`, so its arrow sat between the map and the first stop, whichever stop was swiped, and the dialog covered the map.
- VERIFIED (2026-10-29, same simulator, the sample trip): "a swiped stop loses its name" is iOS sliding the whole row left by the width of its two swipe buttons, about 185 pt. The name sits at the row's leading edge, so it goes off-screen; the photos at the trailing edge stay. It is not a layout bug in the row.

## Decision
Chiu 2026-10-29, on #326: *比照首頁修* — Home's fix, for the stop list. What is built:
- Each stop row reports where it is (on its label, as Home's rows do), and the dialog hangs on a clear view over the list at that row. The type that does this is shared: `RowDeletionPrompt` (`UI/Shared/`), which Home uses as `TripDeletionPrompt`.
- The swipe's 刪除地點 is `.tint(.red)`, not `role: .destructive`. Tapped, the row slides back, so under the dialog the stop shows its name and time again. VERIFIED on the simulator: the arrow points at the swiped row (都蘭, the fourth), and the row reads 「都蘭 下午 3:00」.
- The wording, the buttons, 與前一個合併 and what is deleted are unchanged. Cancel keeps the stop; 刪除地點 deletes it and its photos stay in the trip (VERIFIED, simulator).

## Rejected
- Keeping the name visible while the row is swiped open: that needs fewer or narrower swipe buttons, which moves 與前一個合併 somewhere else. That is a bigger change than #326 asked for.
- A centred `.alert`, or the dialog on the row: rejected for Home, for the same reasons (ADR 2026-10-28).

## Consequences
- `UI/Home/TripDeletionPrompt.swift` moved to `UI/Shared/RowDeletionPrompt.swift`, generic over the row's item. Home's code and tests are unchanged.
- New `StopDeletionPromptTests`; with `main`'s Trip Detail they fail 6 times (watched red).
