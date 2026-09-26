## Visual Review: S5 — the export sheet (Trip Recap)

### Verdict: Needs refinement

The desk half of D5 (`Docs/release-readiness.md`; checklist in
`Docs/device-test-P3.md` §G). The device half is still owed.

### Evidence

iPhone 17 Pro simulator, iOS 26.5, `-demo-seed -demo-open-trip` (the seeded
Perth → Margaret River trip, synthetic, so no §0 exposure). Walked in light and
dark: form → rendering → finished MP4 → finished GIF → Save to Photos → the stop
photo picker. Render times are **SIMULATOR** (MP4 172.1 s, GIF 52.1 s / 96.9 s)
and say nothing about a phone. Chiu's own Iceland screenshot (2026-09-25) is
where the Export button went missing below the photo list.

### What Works

- One sheet, one job. The defaults make a film without anyone touching anything
  (UX rule 2).
- The iCloud and routing warnings are specific and give the user something to do.
- The rendering copy promises exactly what `ExportLifecycleGuard` delivers.

### Blocking (fixed — PRs #96, #98, #99)

| # | finding | status |
|---|---|---|
| B1 | Export was the form's last row, below every stop's photos, so on a real trip it sat off screen | fixed #96: a pinned bottom bar. VERIFIED by render |
| B2 | Raw keys on screen: `recap_photos_section`, its footer, and **all 11 `stop_photos_*` keys**, including the only sentence explaining tap = star / hold = leave out | strings: #98, which reworked the picker in parallel (its wording is the one kept). #99 adds `LocalizationCoverageTests`, which fails on any key the UI uses that has no string. VERIFIED by render |
| B3 | A GIF film could not be previewed (AVPlayer shows a struck-through play glyph), and Save to Photos always failed, showing `PHPhotosErrorDomain error 3302` inside the primary button | fixed: `AnimatedGIFView` (streamed through ImageIO); the GIF is saved as a photo; failures show a sentence and log domain · code. VERIFIED by render: it animates and it saves |
| B4 | "Export again" started a render immediately, although its doc comment said it returned to the form, so changing the vehicle or photos between films meant deleting the first film | fixed: back to the form, settings kept. VERIFIED by render and by `RecapExportFindingsTests` |
| B5 | The photo-shortfall and routing notices lived only in `Running`, so the finished film came back with blank cards and no reason given, to the very person the copy had invited to leave | fixed: `RecapExportCoordinator.Findings` are kept with a finished outcome and cleared with it. VERIFIED by render |

### Recommendations (fix before the milestone)

**Status 2026-09-26 (PR #103, ADR 2026-09-26):** 1, 2 and 4 resolved; 3 waits on Chiu.
Evidence and screenshots are in the PR description; all renders are the seeded
Perth trip on a simulator.

| # | status |
|---|---|
| 1 | ✅ #103: title line (Chiu's copy, drawn verbatim), Save + Share paired, Delete in ⋯ (confirmation kept), Export again a text button. "Rendered in X s" stays in Release (Chiu). VERIFIED by render, en + zh-Hant, light + dark |
| 2 | ✅ #103: `RecapExportChannel.stage` (Chiu: option a), percentage while drawing, the form folds away. "Preparing photos" and "Rendering n%" VERIFIED by render; "Finding roads" UNKNOWN on screen (the seeded trip passes it in under a second). The sheet's middle is empty while rendering |
| 3 | ⏸ Chiu's answer arrived incomplete ("so the"); asked again. `LinearTimeline` needs a composed trip, and compose runs after routing; stop and photo counts are cheap via `FilmPhotoChoices` |
| 4 | ✅ #103: the toggle and its note form one section; Format follows the stops. GIF kept. VERIFIED by render |
| 5 | now **VERIFIED** by render: with the last vehicle (海鷗) selected, the sheet opens with it off screen. Fix still to build |

1. **The finished screen is not yet a moment (UX rule 6).** Delete is a
   full-width red button with the same weight as Share. Suggest: Save and Share
   side by side as the pair; Delete moved to a ⋯ menu; Export again as a text
   button; one warm line of title copy. ⚠️ The four actions are Chiu's
   (2026-09-05) and the render-time line is the §4.5 readout, so this changes
   their weight, never whether they exist. Hiding the readout in Release is
   Chiu's call.
2. **Rendering gives almost no information.** A 1–3 minute wait shows one bar
   with no number, under a form that has been disabled. Suggest a percentage,
   the named stage, and collapsing the disabled form.
3. **No preview before the wait (UX rule 3).** Suggest one line above Export,
   "≈ 45 s · 8 stops · 24 photos", which the timeline already knows. INFERRED
   that it is cheap; settle it by checking that `LinearTimeline` is available
   before compose.
4. **The photo-card note reads as a caption for Format.** It is the footer of
   the section that holds both rows. Split the toggle and Format into two
   sections; GIF is a minority choice.

### Polish (batch later)

5. **The selected vehicle can start off screen.** In Chiu's screenshot the chip
   before the selected one is clipped. INFERRED; settle it by choosing the last
   vehicle, closing the sheet and reopening it. The fix is a `ScrollViewReader`
   scroll to the selected chip on appear.
6. ~~**Stops outside the film are invisible here.**~~ Resolved by #98
   (`FilmStopsSections`, "Other stops"), which landed while this review was in
   flight.

### Kamome Identity: Partially

Structurally sound Apple layout; the emotional layer has not reached this screen
yet: no warmth at completion, no anticipation while waiting.

### My Recommendation

Ship B1–B5. Take 1–4 as one S5 pass, which is most of D5's desk half. Settle 5
with one render before building anything.
