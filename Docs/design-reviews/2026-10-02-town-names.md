# Town names on the map — type, colour and ground

**Verdict:** Needs refinement — refined in the same PR; what is left is below.

Chiu asked for this while the #183 renders were being made: *「幫我注意一下地名的樣式跟顏色與背景的美感是否搭配」*.

## Evidence

Desk renders of the shipped maps, 1080 × 1920, `~/Kamome-films/2026-10-02-finer-names/`:

- `v1/dark.png`, `v1/light.png` — the names as merged in PR #184: white, Helvetica Neue Bold 44 px, the stop label's drop shadow.
- `v2/dark.png`, `v2/light.png` — ink and halo, per appearance.
- `v3/yield.png` — four frames of the arrival at the first lake stop.

New Zealand just before the first lake stop; Miyakojima on the road on day 2. Style values read off `RecapStyle.modernMinimal(_:)`. The v2 and v3 renders have dashed roads: the routing Worker was refusing (#204).

## What works

- **One voice for Kamome, one for the map.** The names share the HUD's face and weight; the map's own labels (island, peaks) are regular and pale. A viewer reads which names are the trip's without being told.
- **44 px** sits between a stop's name (76) and anything the map draws (peaks reach 20). It reads at phone size and does not compete with a stop.
- **The dot takes the trail's hue** in each appearance (the stop pin's rule), so a town reads as a place on the journey.
- **On the dark map, v2:** off-white on the map's own label halo. Crisp, and the trail no longer runs through the letters.
- **On the light map, v2:** the HUD pill's navy on a white halo. It sits with the map's own black labels as the same ink, heavier.

## Blocking

- **Light map, v1: the names were a grey smudge.** White type with a 31 px black shadow on pale terrain: the shadow was most of what showed. Fixed in this PR (ADR file `2026-10-02-a-one-town-journey-is-named-by-the-parts-of-its-town`, Decision 5); `v2/light.png` is the result.

## Recommendations

- **A stop's name stands over a neighbouring town's name for its beat** (`v3/yield.png`, frames 3–4). The town's own name now yields; a neighbour's does not. #207.
- **The vehicle parks on the dot and covers the top of the name** for a moment as it arrives (`v2/dark.png`, first frame). The 36 px gap clears a parked car; an arriving one crosses it.

## Polish

- The geocoder's names are used as given: "Aoraki Mount Cook National Park" is two lines and 430 px wide; "Pukaki Ward" is an electoral ward.
- A name over open sea (a cape stop) has nothing under it to anchor to. It reads; it is not pretty.
- The halo and the fill fade separately, so mid-fade the halo shows through the letters. Three frames at the opening.

## Kamome identity

Structural axis: clean. The names are annotation, set the way a careful map sets them, and they stay out of the photographs' way. They are not the emotional layer and should not try to be: the iceboxed place-name *title cards* are where a hand-drawn name belongs.

## Recommendation

Ship the ink-and-halo names. Take #207 next. Judge the light map on a phone before anything else: no light film has been exported on a device since the names landed.
