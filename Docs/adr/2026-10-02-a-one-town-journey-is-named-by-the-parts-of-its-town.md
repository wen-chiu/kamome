# A journey that never leaves one town is named by the parts of its town, and the names are set as map ink

**Status:** Decided (Chiu, 2026-10-02: 「#183 標更細的地名」); the type treatment is from a design review he asked for and is owed his eye
**Supersedes:** nothing. Amends ADR file 2026-10-02-the-film-names-the-trips-own-towns, Decisions 1 and 4

## Context

- The film names the towns its stops are in, and the base map names no settlement (ADR file 2026-10-02). A trip in one municipality therefore had one name, and its close frames none (#183, VERIFIED on the Miyakojima render).
- Apple's lookup already answers the level below the town (VERIFIED, desk probe of the Miyakojima stops): `subLocality` is Hirara, Irabu, Gusukube — the former towns. It is nil on the New Zealand and Western Australia stops.
- Chiu, while the renders were made: *「幫我注意一下地名的樣式跟顏色與背景的美感是否搭配」*. Review: `Docs/design-reviews/2026-10-02-town-names.md`.

## Decision

1. **A stop keeps the part of its town** (`stop.sub_locality`, schema v15), from the same one lookup that names it. Nothing new leaves the phone (§0). NULL = never asked; stops named earlier are asked once more, behind naming, as v9's towns and v14's zones were.
2. **A journey whose stops are all in one town is named by those parts** — when they are in two or more of them; a stop with no part keeps the town. One part is no finer than the town and less known, so then the town stays. Each side of a flight is its own journey.
3. A journey between towns is named by its towns, as before.
4. **A name sits on a stop**: the one nearest the middle of its place's stops. The middle itself put a name in the sea.
5. **The names are ink with a halo of the ground under them, per appearance** — off-white on the dark map's own label halo; the HUD's navy on white for the light map. White with a drop shadow, the stop label's treatment, was a grey smudge on the light map (review: Blocking).
6. **A town's name yields while a stop is presented under the same name**, and returns on the road. Most stops are called by their town; the word was set twice, 100 px apart.
7. Names are held clear of the HUD's row and the map credit's.

## Rejected

- **Naming by the stops' own names:** on Miyakojima six of eight are "Miyakojima" (VERIFIED, cached names).
- **Parts of a town on every film:** at a 150 km frame a ward is noise, and a district's block is not a place a viewer knows.
- **A plate behind each name, like the HUD pill:** legible, and a dozen capsules on a map.

## Consequences

- Existing trips get their parts on their next open, one lookup per stop on the shared throttle. A film exported before they land names the town.
- A two-town journey (Ishigaki, Taketomi) is framed as closely as a one-town one and still has one name per town. Not covered; UNKNOWN whether it reads as bare.
- Seen on the render and not solved: a stop's own name stands over a neighbouring town's name for its beat (#207).
- Tests: `RecapPlaceNamesTests` (twelve; one restated — a name sits on a stop, not at the mean), `StopNamerSubLocalityTests` (two). Two fixtures that mean "a stop with nothing left to ask" now set the part as well.
- The desk harness draws the shipped light map with `KAMOME_MAP_SUBSTRATE=shipped-light`.
- Renders: `~/Kamome-films/2026-10-02-finer-names/`. The routing Worker refused every request while the last were made (#204), so their roads are dashed; the names are what they show.
- Owed: a device re-export in both appearances.
