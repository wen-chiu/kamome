# A stop pin on Trip Detail's map is a control, so it is the accent; its photo count is black

**Status:** Decided (Chiu, 2026-10-29)
**Supersedes:** the "pins" in ADR 2026-10-26-text-and-controls-take-a-deeper-teal's list of `BrandTeal` drawings. Routes, the gull and the large state glyphs stay `BrandTeal`.

## Context
- A stop pin is a button: it opens the stop. WCAG 2.1 SC 1.4.11 asks 3 : 1 for a control.
- VERIFIED (#312, by calculation and off simulator pixels, 2026-10-27): in `BrandTeal` `#2DBDD0`, the pin is 2.26 : 1 on its white disc and **1.07** on Apple Maps' light sea. Only the thin white ring told it from the water. In the accent, `#1B727E` light / `#42C5D6` dark, it is 5.59 on the disc and 2.32 on the light sea; in dark mode both colours pass.
- VERIFIED (2026-10-29, while checking #312): the photo count on the pin's orange badge had no colour of its own, so it took the button's tint. The accent on the system orange is 2.54 in light and **1.00** in dark, where the digit was invisible.

## Decision
Chiu 2026-10-29, on #312, choosing the accent over keeping the brand teal: *改用深青*. On the badge, choosing black over a deeper orange fill with white: *黑字*.
- The pin is `Color.accentColor`, so it follows the appearance like every other control.
- The badge's count is black on the system orange: 9.55 : 1 light, 10.22 dark. The badge stays orange.

## Rejected
- **Keep `BrandTeal` for pins:** on a light sea the pin and the water are one colour.
- **White on a deeper orange badge:** a new fill colour, and dark mode would need its own orange as well.

## Consequences
- `TripDetailView+Map.stopPin`. Held by `AccentContrastTests`: the pin is the accent and not `BrandTeal`, and black on the system orange reads in both appearances. The source checks fail against `main`'s pin (watched red).
- Seen on the simulator, the sample trip, light and dark.
- The recording map's head marker and route stay `BrandTeal`: neither is a button.
