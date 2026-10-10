# Footprints hides by swipe as well as long-press, and a hidden journey still happened

**Status:** Decided (Chiu, 2026-10-10)
**Supersedes:** nothing; carries out 2026-09-30-footprints-sits-beside-journeys's "Swipe: hide"

## Context
The 2026-10-09 walk of 足跡 (#267) found, VERIFIED on the simulator:
- the diary counted 「N 個停留」 where the list counts 「N 個地點」;
- one trip printed its dates four ways; the diary's `.long` form is
  「2026/8/3至2026/8/5」 in zh-TW;
- 「在家 N 個月」 under a journey ran across a hidden one, calling weeks away
  "at home";
- the ADR table promised a swipe to hide, but the list was a `ScrollView`
  and only the context menu hid.

## Decision
Chiu, 2026-10-10: 「1 地點, 2 OK, 3 keep, 4 count, 5 update code that both
long-press and swipe can hide」.
1. The diary counts places with `journey_places`, as the list does.
2. The diary masthead and the hidden row print the list's form with its year
   (`JourneyDateText.rangeWithYear`, template `yMMMd`).
3. A day with no place stays skipped, as now.
4. A home gap is measured to the journey just before, hidden or not. A hidden
   journey has no row of its own.
5. A found journey hides by a trailing swipe (grey, not destructive: the
   hidden row shows it again) and by its menu. A stored trip offers neither.

## Rejected
- Swipe only, dropping the menu: long-press already worked and is the
  accessible path.
- A red swipe: hiding is undone from the hidden row; red says "gone".

## Consequences
Footprints is a `List` drawn like the stack it replaced, one list row per year,
entry and home gap. Trap, VERIFIED with four lists side by side on the
simulator: `.buttonStyle(.borderless)` on a row turns that row's swipe actions
off. A button inside a row that must answer only its own tap sets the style on
itself (the hidden row's 「重新顯示」, the Selected Photos button).
`Docs/current-state.md`'s "Last synced" names this file.
