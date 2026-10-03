# A routed road is stored only if it could have been driven in the time, and witnessed

**Status:** Decided (Chiu, 2026-10-03)
**Supersedes:** nothing — extends ledger `2026-09-24 (f)` / `2026-09-26 (b)`

## Context
On Chiu's device trip a layover flight across connected land was **stored as
`road`** (VERIFIED: the trip map draws it along roads) and the trip logged `0/34
legs marked crossing` → film type UNKNOWN, framed as one local journey
(VERIFIED, diagnostics 2026-10-03). Three gaps line up (code read, VERIFIED):
imported legs default to `drive`; `LegPace` misses a flight whenever the photos
either side are more than ~20 h apart, which the rule itself names as one-sided;
routing never says "no road" where land connects, and the detour gate judges only
shape (an overland answer is ≈1.0–1.4× the straight line, gate 2.5×). Whether
this leg was routed before `LegPace` existed (2026-09-24) or after a long gap is
UNKNOWN; both end the same way.

## Decision
Two tests on every road the router returns for an imported leg
(`RouteFeasibility`), before it is stored:
1. **Time.** Routed distance ÷ (elapsed + `LegPace`'s clock allowance:
   |Δlon|/15 h + `crossing_pace_clock_margin_s`, +1 day over the antimeridian)
   ≥ `crossing_route_pace_min_kmh` → `beyond_driving`, a crossing. Chiu:
   「超速寬限 就用時速120公里吧 多數高速島路限速應該是這樣」. Photo times are
   `PHAsset.creationDate` instants; a camera without a zone offset is what the
   allowance absorbs (「時間要加入判斷時區」).
2. **Witness.** A stretch of the road longer than `route_unwitnessed_max_drive_s`
   of driving at that pace with no photograph along it → `implausible_route`:
   dashed, never road, **not** a crossing. Chiu: 「第 1 點要一起做」 — the answer
   when the clocks cannot be trusted (overnight departures, no photo at the
   layover or on landing). 36,000 s is the implementing session's number, from
   EU Regulation 561/2006 Art. 6 (nine hours a day, ten twice a week) — INFERRED
   as a fit for "a day's driving"; Chiu may restate it.

**Stored verdicts are not re-judged** (Chiu: 「不用 我會自己刪掉重跑」), so
`SegmentRoutability.rulesVersion` stays 2, deliberately against its "bump on a
rule change" note: a bump would re-ask every stored `road` of every trip.

## Rejected
- Geoapify's `time` field — needs the `RouteProvider` boundary to carry it; the
  120 km/h ceiling needs only the geometry already returned.
- A straight-line distance cap, or "Airport" in a stop name — a number nobody can
  justify; an airport car rental would be flown.
- Re-judging stored roads offline from their polyline length — Chiu declined.

## Consequences
New `matching` keys `crossing_route_pace_min_kmh` 120 and
`route_unwitnessed_max_drive_s` 36000; `RouteMatchReport.routedButNotDriven`;
a feasibility log line per long leg (km and hours, no coordinates). Owed: a
photograph taken in flight as proof of flying (#224); asking the person "was
this a flight?" for unwitnessed legs (#225); the export failing when a frame
reaches past MapLibre's latitude limit (#223).
