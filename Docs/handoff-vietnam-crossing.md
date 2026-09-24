# Vietnam film: the Taiwan → Vietnam leg is not a crossing

**Opened 2026-09-24** from one device screenshot. No trip data was read, and
none may be (§0).

## Symptom (VERIFIED from the screenshot)

The film opens in Taiwan (Day 1, 381 km on the counter) and the trip's vehicle
(the scooter) rides a **dashed straight line** south-west across the Taiwan
Strait past Penghu. There is no plane and no crossing beat.

## What that proves (VERIFIED from the code)

- A leg becomes a crossing on exactly one thing: `segment.routability ==
  'no_road'` (`RecapComposer.isCrossing`). That value is written only when
  Geoapify answers **400 `No path could be found`**
  (`GeoapifyRouteProvider.verdict(for400:)`).
- Dashed plus the trip's own vehicle means the stored verdict is **something
  else**: NULL, `implausible_route` or `off_road_network`.
- **Not the cause:** mode typing (`ImportService.mode(for:)` types any
  faster-than-walking leg `drive`, so it is sent to routing); the longitude
  ceiling (about 15° here against `crossing_flight_max_longitude_deg` 70);
  export racing routing (`RecapExportJob` waits on the coordinator).

## Which of the three (INFERRED, ranked)

1. **NULL: the request timed out or got a 5xx.** Taiwan is not an isolated
   graph once OSM's Taiwan–Fujian ferries are routable (Taichung/Taipei–Pingtan,
   Kinmen–Xiamen). A "no path" search to Vietnam may then walk the whole Asian
   network, and a found path runs 2,000 to 3,500 km. `matching.timeout_s` is 10 s,
   which was already tight for a 1,000-point match (decisions.md, 2026-08-15).
   A timeout is `unreachable`: the verdict stays NULL and is **re-asked on every
   export with the same result**, so the problem never fixes itself.
2. **`off_road_network`**: one end photo (apron, pier, beach) has no road near
   it, which gives `No suitable edges`. Less likely, because airports routed
   cleanly for Miyakojima.
3. **`implausible_route`**: a ferry route came back and failed the 2.5× detour
   gate. Unlikely: through Fujian the ratio is about 1.3 to 1.8×, which would
   pass and draw **solid** through China, and that is not what we saw.

**The cheapest thing that settles it:** read the device Console, subsystem
Kamome, category `routing`, during a re-export. Look at the
`matchTrip …: N/M legs reconstructed; … unreachable …` line and any
`TRANSPORT FAILED` / `HTTP 5xx` / `REJECTED by the detour gate` line. A second
way: from a desk, send the relay one GET with **public airport coordinates
only** (TPE `25.0777,121.2328` → SGN `10.8185,106.6588`, `mode=drive`), timed.
This container's egress policy blocks the relay, so neither check has been run.

## What a fix would touch (Chiu's call: rule 2, product behaviour)

- If (1): raising `matching.timeout_s` is a config change, but every leg would
  then wait longer on a slow provider, and it may still not be enough.
- A **pace ceiling** would catch this class without the network. Nothing types a
  leg as a flight today, so a 1,700 km leg across a few hours is a "drive". But
  `isCrossing` is deliberately "one stored verdict and nothing else, no distance
  and no mode", so a pace-based crossing reopens that rule. That needs an ADR.

## Status: layer 1 built (ADR 2026-09-24 (f), DRAFT)

Chiu reopened `isCrossing` and asked for layer 1. `LegPace` now judges every
imported leg before routing. A leg too fast to have been driven is stored as
`beyond_driving`, is a crossing, and is never sent to Geoapify. The time-zone
allowance keeps a clock error from faking a flight.

**Owed:**
- Compile and run `./check.sh` on a Mac. This was written in a container with
  no Swift toolchain, so the code has not been built.
- Re-export the Vietnam film on the device. Expect a plane over the strait,
  and `N too fast to drive` in the `routing` log.
- If the Taiwan and Vietnam photos are more than about 8 h apart, pace cannot
  fire, and the leg still depends on routing (layer 2, `avoid=ferries`).
