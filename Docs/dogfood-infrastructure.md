# Dogfood infrastructure — routing + map regions for the Replay MVP gate

What the §6 gate needs that a laptop cannot provide: an OSRM the phone can reach
from anywhere, and map tiles for wherever the three real trips actually went.

Decisions this implements (Fable architecture review, 2026-07-26):

- **PD-5** — one small VPS running a **single merged-extract** OSRM covering
  every dogfood region. The gate has to be runnable from a phone on cellular,
  not only on the LAN next to a laptop.
- **PD-7** — dogfood `.pmtiles` are **side-loaded over Finder**, not bundled
  into the build. Region files are tens of megabytes and change per trip; putting
  them in the binary means a rebuild per region and an App Store-sized download
  for data that is scaffolding.

Neither is the long-term answer. Worldwide routing and worldwide tile serving are
explicitly deferred (spec P7); this is the smallest thing that makes three real
trips renderable.

---

## 1. The VPS — one merged extract, one OSRM

### Why merged rather than one process per region

`Docs/osrm-setup.md` runs one OSRM per extract on its own port, because OSRM
serves exactly one dataset per process. That is fine on a laptop where the app is
pointed at a port by hand, but `matching.base_url` is a **single** value in
`Config/TrackingConfig.json` — the app cannot pick a port per trip, and teaching
it to would be building the region-routing infrastructure that PD-5 exists to
avoid. Merging the extracts first gives one dataset, one process, one URL.

### Sizing

`osrm-extract` is the memory-hungry step. Rough figures for the car profile:

| Merged extract | RAM for extract | Disk after customize |
|---|---|---|
| Western Australia + Taiwan | ~6 GB | ~4 GB |
| + one European country | ~10 GB | ~8 GB |

A **4 vCPU / 8 GB** VPS with 40 GB disk handles the first row. Preprocessing can
also be done on a bigger machine (or your laptop) and the `.osrm.*` files copied
up — the server only needs `osrm-routed`, which is comparatively light.

### Setup

```bash
ssh root@YOUR_VPS
apt-get update && apt-get install -y docker.io osmium-tool curl
mkdir -p /srv/kamome-osrm && cd /srv/kamome-osrm
```

Download one extract per dogfood region (`Docs/osrm-setup.md` §1 has the URL
shape; prefer state/country-level extracts over continents):

```bash
curl -LO https://download.geofabrik.de/australia-oceania/australia/western-australia-latest.osm.pbf
curl -LO https://download.geofabrik.de/asia/taiwan-latest.osm.pbf
```

Merge them into a single dataset:

```bash
osmium merge western-australia-latest.osm.pbf taiwan-latest.osm.pbf \
  -o kamome-dogfood.osm.pbf
```

Preprocess once (MLD pipeline, car profile — drive and scooter legs both use it;
walks stay raw by design, PD-8):

```bash
for step in "osrm-extract -p /opt/car.lua /data/kamome-dogfood.osm.pbf" \
            "osrm-partition /data/kamome-dogfood.osrm" \
            "osrm-customize /data/kamome-dogfood.osrm"; do
  docker run --rm -t -v "$PWD:/data" osrm/osrm-backend $step
done
```

Serve it, restarting on reboot:

```bash
docker run -d --name kamome-osrm --restart unless-stopped \
  -p 127.0.0.1:5000:5000 -v "$PWD:/data" osrm/osrm-backend \
  osrm-routed --algorithm mld --max-matching-size 1000 /data/kamome-dogfood.osrm
```

### Put TLS in front of it

Bind OSRM to localhost (above) and terminate TLS with Caddy, which gets a
certificate automatically:

```bash
apt-get install -y caddy
cat >/etc/caddy/Caddyfile <<'EOF'
osrm.example.com {
    reverse_proxy 127.0.0.1:5000
}
EOF
systemctl restart caddy
```

**Do not expose port 5000 directly.** OSRM has no authentication and no rate
limiting; an open instance is someone else's free routing service, and iOS ATS
blocks plain HTTP from the app anyway.

For a private dogfood box, also require a token:

```
osrm.example.com {
    @unauthorized not header X-Kamome-Token "PASTE_A_LONG_RANDOM_STRING"
    respond @unauthorized 403
    reverse_proxy 127.0.0.1:5000
}
```

⚠️ The app does **not** send that header today — `OSRMMatchProvider` and
`OSRMRouteProvider` build a bare `URLRequest`. Use the token block only if you
also add the header to those two providers; otherwise stick to the plain
reverse-proxy above and keep the hostname unpublished.

### Point the app at it

```json
"matching": { "base_url": "https://osrm.example.com" }
```

Everything else in the `matching` block stays as shipped. Verify from the VPS
and then from the phone's browser:

```bash
curl -s "https://osrm.example.com/route/v1/driving/115.075,-33.955;115.104,-33.856?overview=false" | head -c 200
```

`{"code":"Ok",...}` means the merged dataset covers that region. `NoSegment`
means the coordinates are further from a road than `route_waypoint_radius_m`
(500 m); `NoRoute` means there is genuinely no drivable path — both are handled,
and the leg renders dashed rather than inventing a road (PD-2).

---

## 2. Map regions — build and side-load

### Build one region per trip

```bash
./Tools/build-dogfood-region.sh margaret-river 114.8,-34.3,115.4,-33.5
```

Bounds are `W,S,E,N`. **Pad them.** `RecapMapTiles` requires a region to cover
the *whole* trip and falls back to Apple's map otherwise — partial coverage would
render half the film as blank ocean, which reads as a broken app rather than a
missing download.

Check what the app will actually read, optionally against the trip's own bounds:

```bash
./Tools/pmtiles-bounds.sh ~/kamome-osrm/planetiler-out/margaret-river-2026-07-26.pmtiles \
  114.99,-33.98,115.10,-33.86
```

It prints the header bounds and exits non-zero if they do not cover the trip.

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

## 3. Gate checklist

Before running the §6 three-trip gate:

- [ ] Merged extract covers all three trip regions — `curl` a `/route` in each.
- [ ] `matching.base_url` points at the HTTPS hostname, not an IP or `http://`.
- [ ] OSRM reachable from the phone **off** the LAN (cellular, Wi-Fi off).
- [ ] One `.pmtiles` per trip side-loaded, each verified with `pmtiles-bounds.sh`
      against that trip's bounds.
- [ ] A render of each trip shows the souvenir map, not Apple's — an Apple-looking
      map means the region did not cover the trip.
- [ ] Reconstructed legs draw solid and unroutable ones dashed (PD-1). All-dashed
      means the app never reached OSRM.

## Cost

A 4 vCPU / 8 GB VPS runs about **$20–25/month** (Hetzner CPX31, DigitalOcean
8 GB). It can be destroyed between dogfood sessions — preprocessing is the only
slow part, and the `.osrm.*` files can be kept in object storage or rebuilt.
