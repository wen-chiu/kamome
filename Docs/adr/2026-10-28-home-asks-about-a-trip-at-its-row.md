# Home's 「刪除旅程」 question points at the trip that was swiped

**Status:** Decided (Chiu, 2026-10-28)
**Supersedes:** nothing

## Context
- VERIFIED (#295 item 8, simulator, iOS 26.5; on 2026-10-10 and again on 2026-10-28): on iOS 26 a confirmation dialog is a popover, and its arrow points at the view it hangs on. Home's hung on the `List`, so the arrow pointed at the import button at the list's foot, not at the trip being deleted.
- VERIFIED (2026-10-28, 2 of 2): the dialog cannot hang on the row itself. Moved there, it is created and taken down within 1.1 s, and nothing can be deleted. This is the same failure as #189's share sheet.
- VERIFIED (2026-10-28, probe build): a dialog hung on a clear view laid over the list at the row's place stays up, and its arrow points at that row.
- VERIFIED (2026-10-28, A/B on one list at its foot): with `role: .destructive`, the swipe button animates its row out and back while the question is asked. That scrolled the list by about a row and took the row under the import button, so the arrow followed it there. Tinted red, with no role, the list stays still.

## Decision
Chiu 2026-10-28, on #295: fix it. 「刪除旅程」 anchors to the swiped row, and deleting still asks first (ADR 2026-10-02-deleting-a-stop-asks-first). After the probe, Chiu chose option 1 (an anchor laid over the list) and approved tinting the swipe button instead of giving it the destructive role.

What is built:
- Each trip row reports where it is on screen (`onGeometryChange` on the row's label). `TripDeletionPrompt` keeps the places out of observation and follows only the asked-about row. While the dialog is up, the arrow goes where that row goes.
- The dialog hangs on a clear view over the list at that row (`confirmationDialog(_:isPresented:pointingAt:actions:)`). The row itself presents nothing.
- The swipe's 刪除 is `.tint(.red)`, not `role: .destructive`. It looks the same (VERIFIED, screenshot). A full swipe still opens the question.
- The wording, the buttons and what is deleted are unchanged. Cancelling keeps the trip, and 刪除 deletes it (VERIFIED, simulator).

## Rejected
- The dialog on the row: taken down as it appears (#189).
- A centred `.alert`: it has no arrow, but it changes the presentation and departs from the other delete confirmations.
- Leaving it: the arrow kept pointing at the import button.
- Keeping `role: .destructive`: at the list's foot, the row went under the import button while being asked about.
- Measuring on the row rather than its label: it switched off `.listRowSeparator(.hidden, edges: .top)`, and the top rule and the row separators came back (VERIFIED in the probe).

## Consequences
- New: `UI/Home/TripDeletionPrompt.swift`. Tests: `TripDeletionPromptTests` (which row, following it, and the source checks for #189 and the role).
- Where the arrow lands is checked only by screenshots, because no unit test can see a popover. The screenshots are in the PR.
- Trip Detail's 刪除地點 has the same problem (VERIFIED 2026-10-28): #326, for Chiu to decide whether it takes the same change.
