# Dogfood infrastructure — routing + map regions for the Replay MVP gate

What the §6 gate needs that the app cannot provide by itself: an OSRM the phone
can reach, and map tiles for wherever the real trips actually went.

**Local first** (Chiu 2026-07-29). The gate runs against OSRM on the laptop over
home Wi-Fi; a VPS comes later, for production. Nothing here is local-only by
construction — `Deploy/docker-compose.yml` is the same file on both, and the
migration is a `.env` edit plus `--profile public`.

Everything is declared in [`Deploy/`](../Deploy/README.md). `Deploy/regions.json`
is the single source for both halves of the stack; the scripts read it, and
adding a region is an edit there.

Decisions this implements (Fable architecture review, 2026-07-26):

- **PD-5** — **one merged routing dataset** covering every region. OSRM serves
  exactly one dataset per process and `matching.base_url` is a single value, so
  the app cannot pick a server per trip. Merge first, serve once.
- **PD-7** — dogfood `.pmtiles` are **side-loaded over Finder**, not bundled.
  Region files are tens of megabytes and change per trip; bundling means a
  rebuild per region and an App Store-sized download for scaffolding.

Worldwide routing and worldwide tile serving stay deferred (spec P7). This is the
smallest thing that makes the gate's real trips renderable.

## Regions

Four, chosen because there are real photos from each (Chiu 2026-07-29):
**Iceland**, **New Zealand**, **Finland**, **Miyakojima**. Geofabrik files
Okinawa under `asia/japan/kyushu`, so Miyakojima is clipped out of that extract
rather than downloaded on its own.

## 1. Build and run it locally

```bash
./Deploy/bin/fetch-extracts.sh     # Geofabrik sources, ~1.4 GB
./Deploy/bin/build-osrm.sh         # clip → merge → one routing dataset
./Deploy/bin/build-tiles.sh        # one .pmtiles per region
cd Deploy && docker compose up -d
```

Point the app at it in `Config/TrackingConfig.json`:

```json
"matching": { "base_url": "http://127.0.0.1:5100" }
```

From a real iPhone use the Mac's LAN address instead — `ipconfig getifaddr en0`
— and keep both on the same Wi-Fi. The simulator can use `127.0.0.1`.

Verify:

```bash
curl -s "http://127.0.0.1:5100/route/v1/driving/-21.94,64.15;-21.13,64.26?overview=false" | head -c 200
```

`{"code":"Ok",...}` means the merged dataset covers that region. `NoSegment`
means the coordinates are further from a road than `route_waypoint_radius_m`
(500 m); `NoRoute` means there is genuinely no drivable path — both are handled,
and the leg renders dashed rather than inventing a road (PD-2).

### Sizing

`osrm-extract` is the memory-hungry step, and it is what decides whether this
builds on a laptop. Rough figures for the car profile:

| Merged extract | RAM for extract | Disk after customize |
|---|---|---|
| Iceland + Miyakojima | ~1 GB | ~1 GB |
| + New Zealand | ~4 GB | ~6 GB |
| + Finland | ~8 GB | ~14 GB |

If `osrm-extract` is killed (exit 137 = out of memory), add or tighten a `bbox`
in `Deploy/regions.json` — that is the intended lever, and clipping a country to
the area you actually travelled costs nothing you will miss.

## 2. Later: moving to a VPS

Not provisioned yet. When it happens (Hetzner, tentatively):

1. Copy `Deploy/` and `$KAMOME_DATA_DIR` up, or rebuild there — only the
   `.osrm.*` files are slow to produce.
2. `cp Deploy/.env.example Deploy/.env`; set `OSRM_BIND=127.0.0.1` and
   `OSRM_DOMAIN`.
3. Point the DNS name at the box.
4. `docker compose --profile public up -d` — this starts Caddy, which gets a
   Let's Encrypt certificate automatically and proxies only `/route`, `/match`
   and `/nearest`.
5. Set `matching.base_url` to `https://your-domain`.

⚠️ **`OSRM_BIND=127.0.0.1` is not optional on a public box.** Left at `0.0.0.0`,
OSRM is exposed directly: no authentication, no rate limiting, no request
budget — someone else's free routing service. iOS ATS blocks plain HTTP from the
app anyway, so TLS is required regardless.

⚠️ **Token auth is written down but not implemented.** `Deploy/Caddyfile` carries
the server half commented out; the app half does not exist — `OSRMMatchProvider`
and `OSRMRouteProvider` both send bare requests. Enabling the Caddy block alone
makes every request 403, and because a routing failure means "keep the raw leg"
(PD-2), **every leg would silently render dashed** with nothing in the UI saying
why. Ship both halves in one change. Tracked in `Docs/handoff-P3.5.md` under
"VPS migration — deferred security work".

## 3. Map regions — build and side-load

### Build

`./Deploy/bin/build-tiles.sh` builds every region in the manifest;
`KAMOME_REGIONS="iceland" ./Deploy/bin/build-tiles.sh` builds one.

Bounds come from the manifest's `bbox` (`W,S,E,N`, `null` = whole extract).
**Pad them.** `RecapMapTiles` requires a region to cover
the *whole* trip and falls back to Apple's map otherwise — partial coverage would
render half the film as blank ocean, which reads as a broken app rather than a
missing download.

Check what the app will actually read, optionally against the trip's own bounds:

```bash
./Tools/pmtiles-bounds.sh ~/kamome-osrm/tiles/iceland-2026-07-29.pmtiles \
  -21.95,63.41,-19.00,64.33
```

It prints the header bounds and exits non-zero if they do not cover the trip.
`Tools/exif-to-fixture.sh` prints a trip's bbox in exactly this form.

### Side-load over Finder

The app declares `UIFileSharingEnabled`, so its Documents folder is visible in
Finder:

1. Connect the iPhone by cable and trust the Mac.
2. Finder → the iPhone in the sidebar → **Files** tab.
3. Expand **Kamome** and drag the `.pmtiles` file in.

Multiple regions can sit there at once; the app matches each render against the
trip it is rendering. Files land loose at the top level, which the lookup
handles, and a `tiles/` subfolder works too.

No rebuild is needed — drop a region in and export again.

### How a region gets chosen

`RecapMapTiles.tilesURL(covering:)`, in order:

1. `KAMOME_TILES_PATH` — an explicit override for demo renders. A **file** is
   taken at its word (that is what lets a demo run against a deliberately cropped
   fixture); a **directory** is scanned like the rest.
2. Documents, and `Documents/tiles/` — the Finder side-load target.
3. Application Support, and its `tiles/` — where a future download would land.
4. The app bundle.

Within a location, every `.pmtiles` file is read for its own v3 header bounds;
regions that cover the whole trip qualify, and the **smallest** one wins — a
build cut around one trip carries more detail at recap zoom than a state-sized
extract that happens to include it. A file whose header cannot be read (a
truncated drag-and-drop) is skipped, not fatal.

There is no manifest. A region announces its own extent, so nothing can go stale.

---

## 4. Gate checklist

Before running the §6 three-trip gate:

- [ ] Merged dataset covers every trip region — `curl` a `/route` in each.
- [ ] `matching.base_url` set: the Mac's LAN address for a device, `127.0.0.1`
      for the simulator (port 5100 by default — see below).
- [ ] Phone and Mac on the same Wi-Fi, and OSRM reachable from the phone's
      browser. (Cellular will *not* work locally — that is what the VPS is for.)
- [ ] One `.pmtiles` per trip side-loaded, each verified with `pmtiles-bounds.sh`
      against that trip's bounds.
- [ ] A render of each trip shows the souvenir map, not Apple's — an Apple-looking
      map means the region did not cover the trip.
- [ ] Reconstructed legs draw solid and unroutable ones dashed (PD-1). All-dashed
      means the app never reached OSRM.

## Cost, when the VPS happens

A 4 vCPU / 8 GB box is about **€15–25/month** (Hetzner CPX31 or CCX13). It can be
destroyed between sessions — preprocessing is the only slow part, and the
`.osrm.*` files can be kept in object storage or rebuilt from the manifest.
