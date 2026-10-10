# A crossing inside the trip splits it only when it outspans the ground on both sides

**Status:** Decided (Chiu, 2026-10-10)
**Supersedes:** nothing — extends ledger entry "2026-09-23 (b)" (a trip's ends count as ground when their crossing outspans the ground beside it) to the crossings between them

## Context
`RecapFilmType` split a trip at every crossing. A mainland drive, a short ferry
Geoapify answered "no road" for, and an island drive counted two local
journeys: the trip became "one destination abroad", `RecapTypeTwoFilm` trimmed
everything before the ferry (3 of 7 stops in the synthetic case), and the
opening flew a plane with a pass from the country to itself (VERIFIED, desk,
#276). How often real ferries route as "no road" is UNKNOWN; the export log's
film-type line counts crossings and journeys for any film that hits it.

## Decision
Chiu: option 1 of #276. A crossing between two runs of road splits the trip only
when it is **longer than the ground on both sides is wide** — the same
threshold-free test the trip's ends use: the crossing's straight length against
each side's bounding-box diagonal. A flight away from a city or an island
still splits. The bounding-box fold now merges until no two regions overlap, so
the count no longer depends on the order of the trip.

## Rejected
- Keep the rule and let a mid-trip ferry start the film at the island.
- "Shorter than *either* side": a long drive then a short flight to a small
  island would become a local film, which is the domestic-flight trip
  (Tokyo → Miyakojima) the 2026-09-01 rule exists for.

## Consequences
- A ferry to an island narrower than the ferry is long still splits, and the
  film starts on the island. Revisit with a film if one appears.
- The type-2 trims still key on the trip's *first* crossing. A trip with a gap
  ferry before its flight is trimmed at the ferry — no worse than before, when
  the same trip counted three journeys and was trimmed there too.
- `ExportQualityMatrixTests` holds the mid-trip ferry as a local film.
