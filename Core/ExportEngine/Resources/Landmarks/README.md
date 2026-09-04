# Landmarks — marks Kamome draws *on* the map, not *across* it

Artwork for the **flight-end marks**: one on each end of a type-2 film's crossing,
over the opening's still frame (Chiu 2026-09-04, ADR 2026-09-04).

## 🔴 This is a placeholder

`flight-end.png` is a **copy** of `Vehicles/seagull/omni.png`, made 2026-09-04 on
Chiu's instruction — *"先用這個圖，之後會再改"*. It is expected to be replaced by
artwork drawn for this purpose. Replacing it is dropping in a new
`flight-end.png`; nothing else has to change.

**A copy, deliberately — not a symlink and not a path back into `Vehicles/`.**
The whole point of the separate directory is that this can be replaced without
touching a vehicle sprite, and that a vehicle sprite can be replaced without
silently restyling the map's landmarks. Two files that happen to be identical
today is the correct state, not duplication to clean up.

## Why this is a fourth gull, and not one of the three that exist

`VehicleCatalog.crossingSubjectId` carries a warning that three gull objects
already exist and are easy to confuse. This is the **fourth**, and it is not any
of them:

| object | what it means | why it is not this |
|---|---|---|
| `Vehicles/seagull/` (`omni.png`) | the **subject** sprite — *a seagull is flying this leg* | since ADR 2026-09-04 a plane flies a crossing that carries a boarding pass; using the subject sprite as an endpoint would say the leg is flown by a gull |
| `VehicleMarker.seagull` (vector) | the **brand mark** on the title and end cards | it is the wordmark's bird, and it must not be restyled in place (`HANDOFF.md` 2026-08-29 finding 5b) — it is the *fallback* here, not the artwork |
| `VehicleMarker.seagullBadge` | **the artwork failed to load** | using it would re-create the collision PR #23 closed, where one symbol meant both "unclassified" and "asset missing" |
| **`Landmarks/flight-end.png`** | **here, and there** — a place the flight touches | — |

## What this is not

- **Not a subject.** It is not in `vehicles.json`, it is not selectable, and no
  code path can draw it as the moving subject. `VehicleCatalog` never sees it.
- **Not a map label.** It carries no text. The country name drawn beneath it is a
  separate overlay with its own rules (ADR 2026-09-04 §3), and neither thaws the
  base map's labels or the `Docs/icebox.md` place-name entry.

## If it fails to load

`RecapOverlayJourneyCardArt.drawFlightEnds` falls back to the vector
`VehicleMarker.seagull` **and logs it**. It never draws nothing, and it never
degrades in silence — this project has been bitten by a silent artwork failure
once already (`Docs/handoff-subject-lookup.md`) and by a silent defaulted `nil`
in `FrameCompositor` as recently as 2026-09-04.
