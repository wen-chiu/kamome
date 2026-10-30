# Warning text takes a deeper orange in light mode

**Status:** Decided (Chiu, 2026-10-29)
**Supersedes:** nothing. Warning text was the system `.orange`, never a decision; ADR 2026-10-26-text-and-controls-take-a-deeper-teal covered the accent only.

## Context
- Six warnings draw their words in orange: the film length over its ceiling, the one-film-at-a-time label, the missing-photos and routing notices on the film sheet, an import that failed, and a stop's photos being full.
- VERIFIED by calculation (#319): the system orange `#FF9500` is **2.20 : 1** on white and **1.97** on the grouped grey `#F2F2F7`, against WCAG's 4.5 for text. In dark mode `#FF9F0A` passes on every ground (6.78 on the dark sheet `#2C2C2E`).

## Decision
Chiu 2026-10-29, choosing between a deeper orange for the words, orange for the icon only, and leaving it: *文字用深橘*.
- A colour asset, **`WarningText`**: `#C93400` in light, `#FF9F0A` in dark. `#C93400` is Apple's own increased-contrast orange, not a new hue: 5.28 on white, 4.73 on the grouped grey. Dark keeps the system orange.
- All six warnings use it, icon and words together. The pin's orange badge and the film sheet's orange swipe button are fills, not text, and stay the system orange.

## Rejected
- **Orange for the icon only, the sentence grey:** the warning would no longer read as one at a glance.
- **Leave it:** 2.20 : 1 is under half of what body text needs.

## Consequences
- `App/Resources/Assets.xcassets/WarningText.colorset`. Held by `AccentContrastTests`: the asset's two values, `WarningText` at 4.5 on the page, the grouped grey and a row in light, dark and the dark sheet, and no `foregroundStyle` in `UI/` drawing `orange`. That last check fails against `main`'s six warnings (watched red).
- Seen on the simulator: the over-ceiling length warning in light and dark. In light, `#C93400` reads closer to red than the system orange did.
