# Kamome 卡摸咩 — POC Design Spec & Build Plan

**Product name:** Kamome / 卡摸咩 (かもめ, "seagull" — inspired by the Taiwanese classic 《快樂的出帆》; the seagull follows the traveler out and comes home with the memories)
**Positioning:** The memory engine for road trips — you don't have to remember the app; it remembers the journey. Arm it once, get a cinematic recap video, and share a route others can save and drive. Fork is the underlying mechanism (§3.1), not the marketing language: user-facing copy says **Save / Get this route / Inspired by**, never "fork" ("GitHub for road trips" is engineer-brain framing — ordinary travelers save and get inspired; they don't fork). **Taiwan-first launch, English-ready by design.**
**Brand element:** the animated "you are here" head marker in the recap video is a small seagull, not a dot. This is the mascot and the app icon.
**Platform:** iOS 17+, Swift 5.10+, SwiftUI. Base localization zh-Hant, second locale en. All user-facing strings in String Catalogs from Phase 0 — never hardcoded.
**Audience for this doc:** Claude (Claude Code) as the implementing engineer. Chiu as product owner / reviewer.
**Doc version:** 1.4 (2026-07-18) — fork demoted from positioning to mechanism: positioning line rewritten (memory-engine framing), §1.5 fork row relabeled P6 bet, §4.5 end card copy → "Get this route"; all user-facing copy uses Save / Get / Inspired by (S6/S7 screen wording settled at P6 — internal names, table `plan.forked_from`, and `.kamome` schema unchanged). v1.3 (2026-07-15) — battery-moat repositioning: passive capture tier (§1.8, §2.3), map matching promoted to core (§4.4), trip import (§4.7), phases renumbered (fork → Phase 6, backend → Phase 7), transactional monetization note (§1.6). v1.2 (2026-07-11) added Roadtrippers analysis, Taiwan-market adaptations, Kamome branding, handoff checklist & kickoff prompt.

> **Naming due-diligence (do before locking bundle ID):** search App Store for existing "Kamome" apps, check TIPO (Taiwan) and JPO trademark registers in app/software classes — note JR Kyushu operates a Shinkansen named かもめ (different class, likely fine, verify anyway). **IP caution:** the song 《快樂的出帆》 inspires the *name only*. Never use its lyrics or melody in the app, recap videos, or marketing — the composition is almost certainly still in copyright. Original seagull branding only.

---

## 0. Rules of Engagement for Claude Code

These override any default behavior:

1. **Phase gates are hard gates.** Do not start Phase N+1 until every acceptance criterion in Phase N passes its listed verification command. No self-certification — a criterion is "done" only when the command output proves it.
2. **All tunables live in config.** Sampling rates, thresholds, speeds, timeouts → `Config/TrackingConfig.json` loaded at startup. No magic numbers in code.
3. **Prefer boring tech.** No reactive frameworks beyond what SwiftUI requires. Use Swift Concurrency (async/await) only where the OS API forces it (location callbacks, photo fetches, video export). No Combine pipelines for business logic.
4. **Every phase ends with a demo artifact** (screen recording script or exported file) placed in `Docs/demos/phaseN/`.
5. **Hardware reality:** building/running requires Xcode on macOS and a physical iPhone for background-location and battery testing. The simulator + GPX fixtures cover logic testing only. Flag any step that needs the physical device instead of silently skipping it.

---

## 1. Product Definition

### 1.1 One-sentence pitch
"Arm it once when the trip starts, forget the app for 12 days — get a cinematic map video of your road trip and a route plan anyone can fork, with battery drain you can't measure."

The zero-effort promise is differentiator #1 (§1.8): Relive makes you start/stop every activity — forget once and that leg is gone forever. Kamome's capture must never depend on the user remembering anything mid-trip.

### 1.2 Personas
- **P1 The Road Tripper (primary):** plans multi-day self-drive trips, wants a beautiful record and stats without manual journaling. (Reference user: an 8-day Perth → Margaret River → Albany loop.)
- **P2 The Trip Planner:** hasn't gone yet; browses real driven routes, forks one, edits stops, uses it as the plan.
- **P3 The Audience:** friends/family receiving the recap video or follow link. Never installs the app. They are the viral vector.

### 1.3 Core loops
1. **Capture loop:** Arm once at trip start → auto-track segments (drive/walk/transit) across days with zero mid-trip interaction → auto-detect stops → attach photos → End at trip end.
2. **Share loop:** Trip → one-tap animated recap (MP4/GIF) → posted to socials → watermark/link drives installs.
3. **Fork loop:** Published trip → viewer forks it into an editable Plan → drives it → publishes their version → network effect.
4. **Import loop (cold start, §4.7):** Google Timeline / photo EXIF → last year's trip becomes a recap within minutes of install — value before the user's next vacation, and the acquisition hook.

### 1.4 What we deliberately do NOT build (POC)
- No social feed, comments, likes, or follower graph.
- No live "follow me in real time" sharing (Polarsteps owns this; it's a server cost trap).
- No printed books, no Android, no iPad-optimized UI.
- No accounts until Phase 7. Local-first: the app is fully useful offline with zero backend.

### 1.5 Differentiators vs. incumbents
| Capability | Polarsteps | Relive | Roadtrippers | Google Timeline | Kamome POC |
|---|---|---|---|---|---|
| Auto route tracking | ✅ | ✅ (activity) | ❌ | ✅ | ✅ |
| Road-snapped route fidelity | ❌ (straight lines, gaps — top user complaint) | partial | n/a (plans only) | ✅ (private) | ✅ **core feature** |
| Save a real driven route as an editable plan (fork mechanism) | ❌ | ❌ | ❌ (editorial guides only) | ❌ | ✅ **P6 bet — validated by §10, not assumed** |
| Plan-vs-actual diff after the trip | ❌ | ❌ | ❌ | ❌ | ✅ |
| One-tap animated route video with photos | ✅ (Trip Reels) | ✅ | ❌ | ❌ | ✅ (must match or beat quality) |
| Works with zero account / zero server | ❌ | ❌ | ❌ | ❌ | ✅ |
| Zero mid-trip interaction, multi-day battery story (§1.8) | ❌ (gaps are its top complaint) | ❌ (manual start/stop per activity) | n/a | ✅ (but private, no output) | ✅ **differentiator #1** |
| Import past trips (Timeline export / photo EXIF) | ❌ | ❌ | ❌ | export-only | ✅ **acquisition hook** |
| Taiwan / Asia market coverage | generic | generic | ❌ (US/CA/NZ/AU POI database) | generic | ✅ **home turf** |

### 1.6 Roadtrippers — why it doesn't kill this idea
Roadtrippers is a pre-trip **planning and booking funnel**, not a journey recorder: A-to-B routing with POI discovery along the way, fuel cost estimation, hotel/campground booking, RV tooling, and membership upsells (deals, roadside assistance). Its moat is a POI database explicitly covering the United States, Canada, New Zealand, and Australia — Taiwan and most of Asia are outside it entirely. It records nothing, generates no recap media, and its shareable "Trip Guides" are editorial content, not real driven routes.

Three strategic takeaways it hands us:
1. **Zero overlap with Kamome's core loop** (capture → recap → fork). The overlap is only with our S6 Plan Editor — the least differentiated part of our app.
2. **Do NOT build a POI database.** That's their capital-intensive moat and an unwinnable game solo. In the fork model, *the community's real stops are the POI database* — every published trip seeds verified, actually-visited places with photos. Cold-start content = Chiu's own trips.
3. **They validate the money.** 38M+ trips planned, monetized via subscriptions and booking commissions — proof that road-trip planning has willing payers. Kamome's future monetization (post-POC, icebox): **transactional, not subscription** — a 2–4-trips-per-year product dies of subscription churn (Strava's weekly cadence is why its subscription works). Candidates: per-trip HD/no-watermark export (~US$3–5), yearly unlock-all, higher-priced creator tier (4K b-roll export). Premium video styles, fork-count analytics for creators — not bookings. Details in `Docs/icebox.md`.

### 1.7 Taiwan-first market adaptations
The launch market changes real requirements, not just translations:

- **環島 (round-the-island) mode.** The iconic Taiwanese road trip is the island loop — by car, scooter, or bicycle. Feature: automatic 環島 detection (trip polyline closes a loop encircling the island's centroid) → progress ring during the trip ("環島 62%"), completion badge, and a dedicated recap video template. This is the single strongest local hook and shareable brag. Phase 6 stretch goal; loop-closure math is cheap.
- **Scooter as a first-class mode.** 機車環島 is a rite of passage. CMMotionActivity classifies scooters as `automotive`; disambiguation is unreliable, so: per-trip vehicle selector (car 🚗 / scooter 🛵 / bicycle 🚲 / mixed) at Start, which tunes the sampling table (scooter = lower speeds, more stops) and sets the recap icon. `segment.mode` enum gains `scooter`.
- **Transit interleaving matters more.** Taiwanese multi-day trips commonly mix TRA/HSR legs with driving. Speed >130 km/h sustained + no highway match = rail heuristic → mode `transit`, drawn as a distinct line style. (In AU this was an edge case; in TW it's normal.)
- **Localization architecture:** String Catalogs from Phase 0, zh-Hant as development language, en as first export locale. Stop names via CLGeocoder honor device locale (Chinese place names natively). App Store metadata, screenshots, and privacy labels prepared in both zh-Hant and en-AU/US.
- **Map/data fit:** Taiwan OSM extract is ~100 MB — OSRM self-hosting for map matching is trivial and free. Apple Maps Taiwan coverage is adequate for display.
- **Distribution channels (content plan, not code):** 環島 and road-trip communities on Dcard/PTT/Facebook groups + Chiu's Mandarin build-in-public channel. The app *is* the content engine: every dev milestone demos with a real Taiwan route.
- **Do not geo-fence anything.** Nothing above blocks worldwide use — the Feb 2027 WA trip remains the flagship acceptance test and proves the app works far from home.

### 1.8 The battery moat — why passive capture beats Relive structurally

Relive-class trackers need high-frequency GPS because trails are not on any road network — the raw points *are* the route. A road trip is the opposite: ~99% of it happens on a known network, so sparse, nearly-free signals (iOS significant-location-change, ~500 m / minutes granularity, plus `CLVisit` for stops) can be **snapped back onto the road network with map matching (§4.4)** and look as good as continuous tracking — a car can only be where roads are. Relive cannot copy this: their core scenario has no network to snap to. This, not "they do outdoors, we do driving," is why the markets don't overlap.

Product consequence — two capture tiers, user-selectable at Start (passive is the default for multi-day trips):

- **Passive tier (Phase 5):** arm the trip once, forget the app for 12 days, battery impact indistinguishable from zero. Sparse fixes + CLVisit stops + map matching + daily CMMotionActivity backfill. This kills the "forgot to press start" failure mode entirely.
- **High-fidelity tier (the Phase 1 engine):** continuous adaptive GPS (§2.3 table) for single-day drives where turn-level fidelity matters, off-network driving (gravel, private roads), or when matching confidence is low.

Import (§4.7) is the same insight applied backwards: past trips already exist as sparse data (Google Timeline export, photo EXIF geotags) — the identical matching pipeline turns them into recaps. **One pipeline, three sources: passive capture, high-fidelity capture, import.**

---

## 2. Architecture

### 2.1 High-level (Phases 0–6: fully on-device)

```
┌─────────────────────────── iOS App ────────────────────────────┐
│                                                                │
│  SwiftUI Views ── ViewModels (@Observable)                     │
│        │                                                       │
│  ┌─────┴──────────┬───────────────┬──────────────┐             │
│  │ TrackingEngine │ TripComposer  │ ExportEngine │             │
│  │ CLLocation +   │ segmentation, │ MapSnapshot  │             │
│  │ CMMotion       │ stop detect,  │ + AVAsset    │             │
│  │ adaptive       │ photo match,  │ Writer →     │             │
│  │ sampling       │ map matching  │ MP4 / GIF    │             │
│  └─────┬──────────┴──────┬────────┴──────┬───────┘             │
│        │                 │               │                     │
│  ┌─────┴─────────────────┴───────────────┴──────┐              │
│  │        Persistence: GRDB (SQLite)            │              │
│  │  trips / segments / trackpoints / stops /    │              │
│  │  photo_refs / plans / plan_stops             │              │
│  └──────────────────────────────────────────────┘              │
│   PhotoKit (read-only)      MapKit (render)                    │
└────────────────────────────────────────────────────────────────┘
        Phase 3 stretch → Phase 4 core sidecar: OSRM /match (Docker, self-hosted)
        Phase 4 adds Core/ImportKit (Timeline + EXIF importers, §4.7)
        Phase 7: Supabase (Postgres+PostGIS, Auth, Storage)
```

### 2.2 Key technology decisions (with trade-offs)

| Decision | Choice | Rejected alternative | Why |
|---|---|---|---|
| Persistence | **GRDB + SQLite** | SwiftData | A full day of tracking ≈ 20–40k trackpoints. GRDB gives bulk inserts, raw SQL, and R*Tree spatial index. SwiftData bulk-insert performance and migration story are weaker, and a coding agent hits fewer undocumented quirks with GRDB. |
| Maps | **MapKit** | Mapbox | Free, native, `MKMapSnapshotter` gives us video frames. Mapbox looks better but adds $ + SDK weight. Revisit at Phase 7 if snapshot styling is too limited. |
| Map matching (snap-to-road) | **OSRM `/match`, self-hosted Docker** (Phase 4 — core) | Mapbox Map Matching API | Free, offline-capable for a region extract (e.g. Australia OSM ≈ 1 GB, Taiwan ≈ 100 MB), no per-request cost. Mapbox is easier but meters every request. Phases 1–3 ship raw polyline + Douglas-Peucker; from Phase 4 matching is **core infrastructure** — import (§4.7) and the passive tier (§1.8) are load-bearing on it — but trip completion must still never block on it. |
| Transport mode | **CMMotionActivityManager primary, speed heuristic fallback** | ML model | Apple's on-device classifier (automotive/cycling/walking/stationary) is free and battery-neutral. Speed heuristic covers devices/regions where it's unreliable. |
| Video | **MKMapSnapshotter frames → AVAssetWriter** | Screen-record a MapKit camera flight | Deterministic, background-renderable, testable frame-by-frame. |
| Backend (Phase 7 only) | **Supabase** | Custom FastAPI | Auth + Postgres/PostGIS + storage + row-level security in one; solo-maintainable. |

### 2.3 Battery budget (non-functional requirement)
Two capture tiers (§1.8). The battery story is differentiator #1 — treat a regression here like data loss.

**Passive tier (default for multi-day trips; Phase 5).** Target: **drain attributable to Kamome < 1%/day** — unmeasurable over a 12-day trip.
- `startMonitoringSignificantLocationChanges()` — cell-tower granularity (~500 m / ≥ 5 min); relaunches the app after suspension or termination, so an armed trip survives process death and reboots.
- `CLVisit` monitoring — arrival/departure events become `stop` candidates (replaces §4.2's sliding-window dwell, which needs dense points).
- Route fidelity comes from map matching (§4.4), not sampling density; low-confidence gaps render as "inferred" dashed lines.
- Mode labeling: `CMMotionActivityManager.queryActivityStarting(from:to:)` backfill once per day (the API keeps ~7 days of history) classifies segments drive/walk/transit after the fact.
- Tunables live in a `passive` block of `TrackingConfig.json` (visit min-dwell, matching confidence floor, backfill cadence — defaults set in Phase 5).

**High-fidelity tier (the Phase 1 engine; per-trip opt-in).** Target: **≤ 5% battery per 8h tracking day** (Polarsteps claims ~4%; that is the market bar).
Strategy — adaptive sampling driven by motion state:

| Motion state (CMMotionActivity) | desiredAccuracy | distanceFilter | Effective rate |
|---|---|---|---|
| Automotive, speed > 20 km/h | `nearestTenMeters` | 50 m | ~1 pt / 3–8 s |
| Automotive, slow / traffic | `nearestTenMeters` | 20 m | higher fidelity at turns |
| Walking | `nearestTenMeters` | 10 m | captures on-foot exploring |
| Stationary ≥ 3 min (dwell) | pause GPS, start `CLMonitor` region (150 m) | — | ~0 drain at stops |
| Region exit | resume GPS | — | — |

`allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false` (we manage pausing ourselves), `activityType = .automotiveNavigation` while driving.

---

## 3. Data Model (GRDB schema v1)

```sql
CREATE TABLE trip (
  id TEXT PRIMARY KEY,            -- UUID
  title TEXT NOT NULL,
  started_at REAL NOT NULL,       -- unix epoch
  ended_at REAL,
  status TEXT NOT NULL,           -- recording | paused | completed
  origin_plan_id TEXT,            -- non-null if this trip executed a Plan (enables diff)
  stats_json TEXT                 -- denormalized: distance_m, drive_s, walk_s, top_speed…
);

CREATE TABLE segment (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trip(id),
  mode TEXT NOT NULL,             -- drive | scooter | walk | cycle | transit | unknown
  started_at REAL NOT NULL,
  ended_at REAL,
  matched_polyline TEXT           -- Google-encoded polyline AFTER map matching (Phase 4)
);

CREATE TABLE trackpoint (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  segment_id TEXT NOT NULL REFERENCES segment(id),
  ts REAL NOT NULL,
  lat REAL NOT NULL, lon REAL NOT NULL,
  h_acc REAL, speed REAL, course REAL, altitude REAL
);
CREATE INDEX idx_trackpoint_segment_ts ON trackpoint(segment_id, ts);

CREATE TABLE stop (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trip(id),
  lat REAL NOT NULL, lon REAL NOT NULL,
  arrived_at REAL NOT NULL, departed_at REAL,
  name TEXT,                      -- reverse-geocoded, user-editable
  note TEXT,
  kind TEXT                       -- auto | manual
);

CREATE TABLE photo_ref (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trip(id),
  stop_id TEXT REFERENCES stop(id),   -- null = attached to route point
  ph_asset_id TEXT NOT NULL,          -- PhotoKit local identifier; NEVER copy image bytes
  taken_at REAL, lat REAL, lon REAL,
  is_highlight INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE plan (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  forked_from TEXT,               -- plan id or share URL of ancestor
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL,
  meta_json TEXT                  -- days, notes, vehicle, season…
);

CREATE TABLE plan_stop (
  id TEXT PRIMARY KEY,
  plan_id TEXT NOT NULL REFERENCES plan(id),
  order_idx INTEGER NOT NULL,
  lat REAL NOT NULL, lon REAL NOT NULL,
  name TEXT NOT NULL,
  planned_dwell_min INTEGER,
  day_idx INTEGER,                -- which trip day
  note TEXT
);
```

**Rules:**
- Photos are referenced by PhotoKit identifier only — never duplicated into app storage (storage + privacy win). Handle deleted-asset gracefully (placeholder tile).
- `trip → plan` conversion and `plan → .kamome` export are pure functions over these tables; keep them in `Core/PlanKit/` with unit tests.
- **Schema v2 (one forward migration, lands with Phase 4):** `trip.source TEXT NOT NULL DEFAULT 'recorded'` (`recorded | imported_timeline | imported_photos`), `segment.source TEXT` (`gps_hifi | gps_passive | timeline | exif`), plus `photo_ref.order_idx` (the deferred S4 reorder — bundled per `Docs/decisions.md` 2026-07-12).

### 3.1 `.kamome` interchange file (the fork mechanism, pre-backend)
A versioned JSON document — this is the product's contract, treat schema changes like API changes:

```json
{
  "schema": "kamome/plan@1",
  "title": "WA South-West Loop, 8 days",
  "forked_from": null,
  "source_trip": { "distance_m": 1234000, "days": 8, "recorded": true },
  "days": [
    { "idx": 1, "stops": [
      { "name": "Perth City Sixt", "lat": -31.95, "lon": 115.86, "dwell_min": 30, "note": "pick up car" },
      { "name": "Busselton Jetty", "lat": -33.65, "lon": 115.34, "dwell_min": 90 }
    ]}
  ],
  "route_hint_polyline": "encoded-polyline-of-actual-drive-or-null"
}
```
Shared via iOS share sheet (file + custom UTI + `kamome://` URL scheme). Opening one on a device with the app = instant fork. This gives the fork loop **with zero servers**.

---

## 4. Core Algorithms (spec level)

### 4.1 Segmentation (mode changes)
Input: motion-activity events + speed. A mode change opens a new `segment` when the new activity is sustained ≥ `mode_confirm_s` (default 60 s, config) to avoid flapping at traffic lights. Confidence below `.medium` → fall back to speed heuristic: >20 km/h sustained = drive; 4–20 km/h = cycle/unknown; <4 km/h = walk.

### 4.2 Stop (dwell) detection
Sliding window over trackpoints: if all points in the last `dwell_window_s` (default 180 s) fit within a circle of radius `dwell_radius_m` (default 80 m) → close segment, create `stop`, enter low-power region-monitoring state. On region exit → reopen segment. Reverse-geocode stop name via `CLGeocoder` (throttled, cached).

### 4.3 Photo matching
On trip completion (and on-demand): `PHAsset.fetchAssets` with predicate `creationDate BETWEEN trip.start AND trip.end`. For each asset: if it has GPS → attach to nearest stop within 300 m, else attach by timestamp to the stop whose `[arrived, departed]` interval contains it; else leave as route-attached. User can re-assign by drag in UI. Photos with `is_highlight = 1` get large treatment in the video.

### 4.4 Route simplification & matching
- Phase 1–3: Douglas-Peucker per segment, epsilon `simplify_eps_m` (default 15 m) for display; raw points kept in DB.
- Phase 4 (**core**, promoted from stretch — §1.8): batch segments (≤100 pts/request) to OSRM `/match?geometries=polyline&tidy=true`; store result in `segment.matched_polyline`. One pipeline serves three sources: high-fidelity recordings (cosmetic win), passive-tier fixes, and imported Timeline/EXIF points (load-bearing — sparse data looks wrong without snapping). On failure (no OSRM reachable / confidence below `matching_confidence_min`), fall back to simplified raw polyline, mark segment `matched=false`, render "inferred" style. **Never block trip completion or import on matching.**

### 4.5 Recap video (ExportEngine)
Deterministic frame pipeline, 1080×1920 (9:16 social) default, 30 fps:
1. Compute camera path: interpolate along full-trip polyline; speed-warp so total video = `target_duration_s` (default 30 s) regardless of trip length; ease-in/out at stops.
2. For each frame: `MKMapSnapshotter` renders base map for camera position (cache tiles by region — snapshot per keyframe every N frames, cross-fade between, to keep render time sane), draw traveled polyline portion + animated head dot via CoreGraphics overlay.
3. At each stop: 1.5 s hold, photo card animates in (highlight photo), stop name label, day badge.
4. Title card (trip name, dates, distance) + end card (stats + "Get this route" QR → share URL/file).
5. Encode via `AVAssetWriter` (H.264). GIF export: same frames at 12 fps, 480 px wide, `ImageIO` with palette quantization.
Acceptance bar: an 8-day, 1,200 km trip renders in **< 90 s on an iPhone 13-class device** and looks share-worthy. This feature is the marketing engine — over-invest here.

### 4.6 Plan-vs-actual diff
Given `trip.origin_plan_id`: match plan_stops to actual stops by name-similarity + distance < 1 km. Output: visited / skipped / unplanned-extra + dwell delta per stop + total distance delta. Rendered as a "trip report card." (Unique feature — no incumbent has it.)

### 4.7 Trip import (the cold-start killer)
Nobody should wait for their next vacation to see Kamome's value. Two importers (Phase 4, `Core/ImportKit/`), both feeding the normal pipeline (map matching §4.4 → stops → photo matching §4.3 → recap §4.5):
- **Google Timeline:** parse the user-obtained Timeline export JSON (Google Takeout or the Maps in-app export; the format drifts — version-pin a parser per known variant, reject unknown variants with a friendly error, one fixture per variant in CI). Place visits → `stop` rows; activity-segment waypoints → trackpoints with `segment.source='timeline'`.
- **Photo EXIF:** user picks a date range or album; geotagged photos cluster into stops + a coarse route (time-gap + distance heuristics, tunables in config). Photos are attached to their stops by construction — zero matching ambiguity.
Imported trips are first-class: same S3 detail, same recap, same fork-to-plan. Acceptance bar: file selected → recap rendering starts in **< 30 s** for a 12-day Timeline export; the render itself meets §4.5's budget. This is the acquisition hook (§1.3 loop 4) — the first share happens before the user ever records.

---

## 5. UI Spec (SwiftUI screens)

| # | Screen | Contents / behavior |
|---|---|---|
| S1 | Home / Trip List | Cards: cover map thumbnail, title, dates, distance. Big `Start Journey` button + `Import a past trip` (Timeline / photos, §4.7, from Phase 4). Empty state sells import first — value in minutes, not after the next vacation. |
| S2 | Recording HUD | Live map, traveled polyline, current mode icon (car/walk), elapsed / km, battery-friendly note. Buttons: `Add Stop Note`, `Pause`, `End Trip`. Lock-screen Live Activity showing distance + duration (Phase 2 nice-to-have). |
| S3 | Trip Detail | Full map with matched route colored by mode (drive = solid, walk = dotted), stop pins with photo thumbnails, day filter chips, stats strip (distance, drive time, stops, top speed). Timeline list below map. |
| S4 | Stop Editor | Rename, note, reorder photos, mark highlight, delete false-positive stop, merge stops. |
| S5 | Export | Aspect ratio picker (9:16 / 1:1 / 16:9), duration, GIF vs MP4, live preview of first seconds, progress bar, share sheet. |
| S6 | Plan Editor | Day-grouped reorderable stop list + map. Search-to-add stop (MKLocalSearch). Per-day drive-time estimate (MKDirections, cached). Import `.kamome` = pre-filled editor with "Forked from …" banner. |
| S7 | Convert / Fork | From S3: `Publish as Plan` → generates plan from stops → S6. From received file: `Fork` → S6. |
| S8 | Settings | Tracking profile (Battery saver / Balanced / High fidelity → maps to config presets), permissions status + fix-it deep links, data export (GPX + JSON), delete all data. |

Design language: map is the hero on every screen; one accent color; dark-mode-first (maps look better). No onboarding carousel — permission priming happens contextually at first `Start`.

---

## 6. Permissions & App Store Compliance

- Location: request **When In Use** at first Start, escalate to **Always** with a priming screen explaining background tracking only during an active trip. Purpose strings must say exactly that.
- `UIBackgroundModes = [location]`; expect App Review to ask for justification — include a review note + demo video showing tracking stops when the user ends a trip. Never track outside an active trip. This is both an ethics line and the reason review will pass.
- Passive tier (Phase 5): requires **Always** at arming (significant-change and CLVisit deliver while the app is dead). The priming copy must say a multi-day trip keeps a low-power recorder alive until you End Trip. The review posture is unchanged — capture runs only between an explicit Start and End, even when that window spans 12 days, and End Trip verifiably stops all monitoring.
- Motion & Fitness permission for CMMotionActivity (graceful degradation to speed heuristic if denied).
- Photos: `PHPhotoLibrary` **limited access compatible** — the picker flow must work if the user grants only selected photos.
- Privacy nutrition label: location + photos, "data not collected" (true until Phase 7 — a genuine marketing point: "your location history never leaves your phone"). Timeline import strengthens the point: the exported file is parsed on-device and never uploaded.

---

## 7. Build Plan — Phases & Hard Gates

> Each phase = one milestone PR. Verification commands run from repo root. GPX fixtures live in `Tests/Fixtures/` and include `perth_margaret_river_day1.gpx` (synthetic 280 km drive with 4 stops + 2 walk loops), `taiwan_huandao_9days.gpx` (synthetic round-island loop, mixed car + scooter + one TRA rail leg — exercises transit heuristic and 環島 loop detection), and `city_walk_flapping.gpx` (mode-flapping torture test).

### Phase 0 — Skeleton (est. 1–2 sessions)
Scope: Xcode project, GRDB integration, schema v1 + migrations, TrackingConfig.json loader, String Catalogs wired (zh-Hant dev language + en), CI (`xcodebuild test` via GitHub Actions macOS runner), repo structure below.
**Gate:** `xcodebuild -scheme Kamome test` green; `swiftlint` clean; schema round-trip test (insert/read 50k trackpoints < 2 s in-memory).

### Phase 1 — Tracking Engine (est. 3–5 sessions) ← the POC's heart
Scope: TrackingEngine state machine (idle → recording → dwell-paused → recording → completed), adaptive sampling table §2.3 with per-vehicle presets (car/scooter/bicycle per §1.7), segmentation §4.1 incl. transit heuristic, dwell detection §4.2, S1/S2 minimal UI with vehicle selector at Start, GPX replay harness that feeds fixtures through the real engine in tests.
**Gate:**
- Replaying `perth_margaret_river_day1.gpx` yields exactly 4 stops (±0), ≥ 2 drive segments, ≥ 2 walk segments; assert in unit test.
- `city_walk_flapping.gpx` produces ≤ 1 spurious segment.
- Physical device test (manual, checklist in `Docs/device-test-P1.md`): 2 h real drive, battery drain measured, route visually continuous. **Chiu signs off on this gate.**

### Phase 2 — Stops, Photos, Trip Detail (est. 2–3 sessions)
Scope: reverse-geocode names, PhotoKit matching §4.3, S3/S4 screens, stats computation, Douglas-Peucker display simplification.
**Gate:** unit tests for photo→stop assignment (timestamp-only, GPS, conflict cases); a seeded demo trip renders S3 with photos on correct pins (screenshot in demo folder); limited-photo-access path manually verified.

### Phase 3 — Recap Video/GIF (est. 3–5 sessions)
Scope: ExportEngine §4.5, S5. Optional stretch (early start on Phase 4's core): OSRM matching §4.4 (Docker compose file + `Docs/osrm-setup.md`; Taiwan + Australia extracts).
**Gate:** golden-frame tests (render frames 0/N/last for fixture trip, compare hash within tolerance); 1,200 km fixture trip exports MP4 < 90 s on device; exported GIF < 8 MB; Chiu posts one recap somewhere real and it doesn't embarrass him.

### Phase 4 — Import & Map Matching (est. 3–4 sessions) ← the acquisition hook
Scope: OSRM matching §4.4 as core infrastructure (if not landed as Phase 3 stretch); schema v2 (§3 rules); `Core/ImportKit/` — Google Timeline importer + photo-EXIF importer §4.7; S1 import entry point; imported trips flow through stop-naming/photo/recap pipelines unchanged.
**Gate:** fixture Timeline export (in `Tests/Fixtures/`, one per known format variant) imports to a trip with expected stop count and total distance; EXIF importer clusters a fixture photo set into expected stops; matched polyline for `perth_margaret_river_day1.gpx` stays on the road network (assert via recorded OSRM responses replayed in CI; live-OSRM run documented in demo folder); device demo: import → recap end-to-end, artifact in `Docs/demos/phase4/`.

### Phase 5 — Passive Capture Tier (est. 3–5 sessions) ← the battery moat
Scope: significant-location-change + CLVisit adapter in `LocationService`; armed-trip persistence across process death + relaunch resume (SLC launch key); passive samples → matching → segments; CMMotionActivity daily backfill; tier choice at Start (passive default for multi-day); `passive` config block; S2 HUD passive variant ("recording quietly — battery-free").
**Gate:** sparse-fix replay fixture (`perth_margaret_river_day1` downsampled to SLC density) produces a matched route within tolerance of the dense-replay route; process-kill/relaunch test preserves the armed trip; **physical device test: ≥ 3-day armed period, drain attributable to Kamome < 1%/day, route + stops correct — Chiu signs off** (checklist `Docs/device-test-P5.md`). **This gate = v1 complete. Ship to TestFlight, recruit 10 road trippers** (≥ half from Taiwan 環島/road-trip communities, §10).

### Phase 6 — Plans & Fork (est. 3–4 sessions; start only if v1 TestFlight validates capture + import + recap)
Scope: plan tables, S6/S7, trip→plan conversion, `.kamome` export/import + URL scheme, plan-vs-actual diff §4.6, drive-time estimates. Stretch: 環島 loop detection + progress ring + badge (§1.7).
**Gate:** round-trip property test (trip → plan → file → import → identical plan); fork lineage preserved; diff report correct on fixture (planned 6 stops, drove 5 + 1 extra → report says exactly that). **This gate = POC complete.**

### Phase 7 — Backend & Community (post-POC, only if Phase 6 telemetry says people fork)
Scope: Supabase auth (Sign in with Apple), publish plan → public web page (Next.js or Supabase edge-rendered) with map + "Open in app" fork button, PostGIS storage, route browse/search by region. Web page is the SEO/discovery surface ("best Perth to Albany road trip route" queries).
**Gate:** defined later; do not design now.

**Total estimate: Phases 0–5 (v1) ≈ 15–24 Claude Code sessions; + Phase 6 (POC complete) ≈ 18–28.** Budget calendar time around Phase 1, 3 and 5 device testing — those need your hands, your car, and (Phase 5) several ordinary days of carrying the phone.

---

## 8. Repo Structure

```
Kamome/
├── App/                    # entry, DI container, config loader
├── Core/
│   ├── TrackingEngine/     # state machine, sampling policy, segmentation, dwell
│   ├── TripComposer/       # stats, photo matching, geocoding, simplification
│   ├── PlanKit/            # plan model, .kamome codec, diff, fork lineage
│   ├── ExportEngine/       # camera path, frame renderer, AVAssetWriter, GIF
│   └── Persistence/        # GRDB setup, migrations, repositories
├── UI/                     # one folder per screen S1–S8
├── Config/TrackingConfig.json
├── Tests/                  # unit + GPX replay harness
│   └── Fixtures/
├── Docs/                   # decisions.md (ADR log), device-test checklists, demos/
└── .github/workflows/ci.yml
```

Conventions: `@Observable` view models; repositories are the only layer touching GRDB; every ADR-worthy decision appended to `Docs/decisions.md` (date, context, decision, alternative rejected).

---

## 9. Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| iOS kills background tracking → gaps (the exact failure users crucify Polarsteps for) | High | Always-authorization + background mode + region-monitor resurrection at dwells; on relaunch, stitch gap with MKDirections route between last/first points and mark it "inferred" visually. |
| Battery > 5%/day | Medium | Adaptive table is config-driven — tune on real drives; Battery Saver preset. |
| MKMapSnapshotter too slow/plain for video | Medium | Keyframe + crossfade strategy first; if quality insufficient, Phase-3 spike: Mapbox static images API behind the same FrameSource protocol. |
| App Review rejects background location | Low-Med | Tracking only during explicit trips, review notes + video, honest purpose strings. |
| Passive tier fidelity: SLC too sparse, or matcher snaps to the wrong parallel road | Medium | Confidence gating + "inferred" rendering; per-trip high-fidelity opt-in; tune against real multi-day wear before v1 TestFlight (Phase 5 gate). |
| Google Timeline export format drift breaks the importer | Medium | Versioned parser per known variant, friendly "unsupported version" error, one CI fixture per variant. |
| Fork loop needs a network no solo dev has | High (business risk, not tech) | `.kamome` file works peer-to-peer day one; build-in-public content channel is the distribution hedge; Phase 7 web pages capture search traffic. |
| Scope creep toward Polarsteps parity | High | §1.4 is a contract. New feature ideas go to `Docs/icebox.md`, not the sprint. |
| Name/IP conflict (Kamome trademark; 《快樂的出帆》 music rights) | Low-Med | Trademark search (App Store, TIPO, JPO) before bundle-ID lock; name inspiration only — zero lyrics/melody anywhere. |

---

## 10. Success Criteria (v1 decision after Phase 5 + 4 weeks of TestFlight; fork decision after Phase 6)

v1 (validates capture + import + recap — "will anyone pay for a trip animation?"):
- ≥ 7 of 10 testers complete a real trip with **zero mid-trip interaction** (not just zero mid-drive).
- Battery complaint count: 0; passive-tier drain < 1%/day on tester devices.
- ≥ 5 of 10 testers import a past trip in their first session (the cold-start hook working).
- ≥ 3 recap videos voluntarily shared by testers.
- ≥ 1 payment signal for HD/no-watermark export (fake-door price probe is fine at this stage).
- Your own verdict after using it — passive tier — on the Feb 2027 WA trip; that trip is the ultimate acceptance test.
- Tester pool: recruit at least half from Taiwan 環島/road-trip communities so localization and scooter mode get real coverage.

Phase 6 continue/kill (the fork bet, decided only after v1 passes):
- ≥ 1 organic fork (someone imports someone else's `.kamome`).

---

## 11. Handoff Checklist & Kickoff (added v1.2)

### 11.1 Human prerequisites — Chiu does these once, Claude Code cannot
1. **Mac with Xcode 16+** and command line tools; a **physical iPhone** with a cable (needed from Phase 1 gate onward).
2. **Apple Developer:** free personal team is enough through Phase 4 (7-day dev provisioning, background location works in dev builds). Paid Program (US$99/yr) required at Phase 5 for v1 TestFlight — defer the cost.
3. `brew install xcodegen swiftlint` — the Xcode project is **generated from `project.yml` via XcodeGen**, never hand-edited. Rationale: `.pbxproj` is merge-hostile and agent-hostile; a YAML-defined project keeps every change reviewable in diffs.
4. Create the GitHub repo (private), default branch `main`, empty.
5. Bundle ID: use placeholder `com.chiu.kamome.dev` until the trademark check (§ header note) clears; renaming a bundle ID pre-TestFlight is free.
6. Put this spec at `Docs/kamome-poc-spec.md` in the repo — it is the single source of truth.

### 11.2 Repo-level CLAUDE.md (create in Phase 0, keep <60 lines)
Must contain only: pointer to `Docs/kamome-poc-spec.md` as authoritative; current phase number and its gate criteria verbatim; the three commands (`xcodegen generate`, `xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 16'`, `swiftlint`); the Rules of Engagement §0 by reference, not copied. Phase state updates when a gate passes — nothing else accumulates here.

### 11.3 Phase 0 kickoff prompt (paste into Claude Code in the empty repo)
```
Read Docs/kamome-poc-spec.md fully. You are implementing Phase 0 only.
Follow §0 Rules of Engagement strictly — phase gates are hard gates.
Tasks: XcodeGen project.yml (iOS 17 min, zh-Hant dev language), GRDB via SPM,
schema v1 from §3 with migration test, TrackingConfig.json + typed loader,
String Catalog setup, swiftlint config, GitHub Actions CI per §7 Phase 0,
CLAUDE.md per §11.2, and generate the three GPX fixtures in Tests/Fixtures/
per §7 (synthetic data is fine; document generation params in each file header).
Definition of done: every Phase 0 gate criterion in §7 passes with command
output shown. Do not begin any Phase 1 work.
```

### 11.4 Session cadence recommendation
One phase-gate per PR; review diffs before merging (you are the second pair of eyes the solo project otherwise lacks). Device-test days for Phase 1/3 gates need your car and ~2 h; the Phase 5 gate needs several ordinary days of carrying the phone with a trip armed — schedule them like sprint reviews, not afterthoughts.
