# The film names the trip's own towns on the map, and the base map names no town

**Status:** Decided (Chiu, 2026-10-02: 「#113,選 2」, then of the render 「地圖本來的城鎮名關掉」); the look of the names is a first cut
**Supersedes:** the map-labels lock in `CHARTER.md` §6 and its CONFLICT of 2026-09-28 (#113)

## Context

Chiu, on his New Zealand film: *「地名放大一點 使用者比較能知道自己在哪裡」*.

- The base map's names cannot do it (VERIFIED, style JSON and `zoomLevel`). The village the film stays in is drawn at 10–12 px, under peaks at 16–20 px, and its layer starts at zoom 9 — the zoom of a 118 km frame at that latitude.
- Their size belongs to the map's place classes, not to the trip.
- He was offered two ways and chose the second: (1) enlarge village names in the style; (2) Kamome draws the towns the trip went to.
- `Docs/_archive/icebox.md` "Place names as narrative rhythm" is a different thing — title cards timed between beats — and stays parked. This is its static counterpart, "where am I right now".

## Decision

1. **Every town one of the film's stops is in is named on the map** (`RecapTrip.Stop.locality`), once, at the middle of its stops. Nothing is looked up for it, and nothing is named that the trip did not stop in.
2. **When:** from the zoom out of the title card, through the body and the end reveal. Never over the title card, the end card, or a flight (that frame names its two ends already).
3. **Which name gives way:** the towns are ordered by how long the film stays in them. Where two would overlap, the later one is not drawn. This is decided over every name, in frame or out, so no name appears or vanishes as the camera pans.
4. **Look (first cut, INFERRED — Chiu judges):** 44 px at the 1080 reference, the flight ends' size and face; a dot on the town, the name under it; two lines past 430 px; a name near the edge slides inside the frame.
5. `OverlayContent.placeNames` crosses the waist as data; the renderer projects and lays out. Style tokens are in `RecapPlaceNameStyle`.
6. **The base map names no settlement** — round 6 of the fork. Chiu, shown one town named twice: *「地圖本來的城鎮名關掉」*. Both frozen styles lose `label_city`, `label_city_capital`, `label_town`, `label_village` and `label_other` (hamlets, suburbs). Countries, states, islands, water and peaks keep their names, as rounds 3–5 chose them.

## Rejected

- **Enlarging the style's village names:** a fixed size for every village on earth, and still gone below zoom 9.
- **Naming stops rather than towns:** a stop's own name already stands over its pin while the film is there.
- **Deciding overlaps only among the names in frame:** a name would pop out when another panned in.

## Consequences

- **A trip that is all one town has one name.** Miyakojima geocodes to one municipality: its close frames (8 km) now carry no place name at all (VERIFIED, render). Chiu's to judge; an issue is open.
- The towns the trip passed but did not stop in are no longer named (Geraldine, Timaru on the NZ film).
- Seen on the render and not solved here:
  - a name held at the bottom edge sits under the map credit;
  - the geocoder's town is used as given ("Aoraki Mount Cook National Park", "Pukaki Ward").
- Names change which ones are drawn while the camera zooms (opening, end reveal). UNKNOWN whether that reads as a flicker; settled by watching a whole film.
- `Scripts/freeze-liberty-styles.py` makes the same removal, last; `FrozenStyleEquivalenceTests` holds the shipped styles to round 6. The desk harness draws the shipped dark map with `KAMOME_MAP_SUBSTRATE=liberty-fork-r6`.
- Tests: `RecapPlaceNamesTests` (seven), `LibertyForkRound6Tests` (three). Renders: `~/Kamome-films/2026-10-02-nz-scale/`.
- Owed: a device re-export.
