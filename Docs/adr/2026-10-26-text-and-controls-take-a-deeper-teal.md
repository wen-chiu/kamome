# Text and controls take a deeper teal; #2DBDD0 stays the brand colour for drawings

**Status:** Decided (Chiu, 2026-10-26; pins on the in-app map amended by 2026-10-29-a-stop-pin-is-a-control-in-the-accent)
**Supersedes:** nothing — `#2DBDD0` was the asset's value, never a decision

## Context
The accent `#2DBDD0` failed WCAG contrast as text (#294): white type on it
2.26 : 1, it on a `.bordered` button's grey 1.85 : 1, against 4.5 for body text
and 3 for large. The asset had no dark variant. Three options were measured on
#294 (2026-10-11).

## Decision
Chiu, on #294: option A. **AccentColor is `#1B727E` in light and `#42C5D6` in
dark; filled buttons in dark mode use dark text `#0B2E33`. `#2DBDD0` stays the
brand colour for non-text uses only. The film's colours are out of scope.**

In the app, three colour assets:
- **`AccentColor`**: text, controls and selection — filled and bordered
  buttons, links, checkmarks, a selected chip, tile or photo ring.
- **`OnAccent`** (white light, `#0B2E33` dark): text on an accent fill. Every
  filled button goes through `.buttonStyle(.prominent)`
  (`UI/Shared/ProminentButtonStyle.swift`); a disabled one keeps the system's
  label. Chips and count badges on the accent use it too.
- **`BrandTeal`** (`#2DBDD0`, both appearances): drawings that carry no text,
  as #294 named them — the gull (the export animation, the Footprints
  illustration), pins and routes on the in-app maps, and the large glyphs of
  empty, priming and placeholder states.

Contrast, VERIFIED by calculation from sRGB, and "px" where read off simulator
pixels: white on `#1B727E` 5.59 px; `#0B2E33` on `#42C5D6` 7.01 px; the
bordered label on `#E9E9EB` 4.61 px, on `#262629` 7.32 px; `#1B727E` on
`#F2F2F7` 5.01; `#42C5D6` on `#1C1C1E` 8.26. `AccentContrastTests` measures
the pairs from the built assets and UIKit's system colours.

## Rejected
- **B, bright teal fills with dark text:** two teals on every button, and dark
  mode still undesigned.
- **C, one darker teal `#1E7E8A`:** 4.11 as text on grey, 4.41 on black.

## Consequences
- The film never read the asset: `Core/ExportEngine` is a package without the
  app's catalog, and its accent is `RecapStyle.routeAccent`. No film changes.
- The vehicle picker's chosen tile lays its 14 % tint over the tile's surface,
  not the page's grey, where its caption read 4.16 (now 4.59).
- `.bordered` draws `secondarySystemFill`; on the grouped grey `#F2F2F7` its
  label would be 4.21. Put a bordered button on a white surface.
- A map pin in `BrandTeal` is 2.26 against its white disc in light — under
  WCAG's 3 : 1 for controls. Kept as #294 named it; Chiu's to judge (PR).
