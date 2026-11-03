# An imported trip draws only the route between its stops

**Status:** Decided (Chiu, 2026-10-30)
**Supersedes:** nothing. Before this, every stored leg was drawn whatever the stops; no decision chose that.

## Context
- An import stores its legs apart from its stops (`PhotoImportClusterer`): one leg into each stop, plus legs from any loose photographs before the first or after the last. `deleteStop` removes the stop and leaves its legs.
- Chiu, on the phone, 2026-10-30: a trip that began at a transit airport, with that stop deleted. Trip Detail's map still drew the leg from it into the first stop he kept. The film reads the same legs. Seen in his screenshot; not reproduced at the desk.

## Decision
Chiu: 「我刪除景點之後路線還是在 這是轉機點 我不想他出現 只要有目的地的路徑」.
- A trip imported from photographs draws a leg only when the leg lies between its first stop's arrival and its last stop's departure (`TripRoute`). Before the first stop or after the last, the leg leads from, or to, a place the trip no longer has.
- One rule for Trip Detail's map and its day chips, the film and its photo plan, and the kilometres Home, Footprints and Trip Detail print.
- Applied when the trip is read. Nothing is deleted, so the legs come back if the rule changes.
- A stop deleted *between* two kept ones keeps the route through it, because that route still ends at a stop the trip keeps.

## Implementer's choices (INFERRED; Chiu can overrule)
- **Recordings keep every leg.** A recording starts where the person actually set off. Chiu's example was an import. Settle by asking him.
- **Fewer than two stops keeps every leg.** With one stop nothing lies between two stops, and the film needs a line.
- **Loose photographs before the first stop or after the last** lose their legs too. No stop was deleted there, but those legs also lead from nowhere the trip names.
- **Routing still asks about trimmed legs**, and GPX export still writes them. GPX export is the person's own data, unchanged.

## Rejected
- **Deleting the legs with the stop:** trips already edited would stay wrong, and the change could not be undone.
- **Deleting only flight legs:** the leg's verdict often isn't known yet when the stop is deleted, and Chiu asked for "only routes that have a destination", not "no flights".

## Consequences
- `App/Services/TripRoute.swift` (`TripDetail.routeSegments`), used by `TripDetailModel`, `RecapComposer.filmComposition` and `filmPlan`, and `LegLength.groundMeters(trip:repository:)`. Held by `TripRouteTests`.
- Films already made are MP4s and do not change. A new film of the trip opens at the first stop the person kept.
- UNKNOWN until seen on the phone: Chiu's trip with the flight gone, map and film. Opening that trip and making its film would settle it.
