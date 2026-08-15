# Kamome 卡摸咩 — POC Design Spec & Build Plan

**Product name:** Kamome / 卡摸咩 (かもめ, "seagull" — inspired by the Taiwanese classic 《快樂的出帆》; the seagull follows the traveler out and comes home with the memories)
**Positioning:** **"Kamome turns your road trips into stories you can relive and share."** (Owner-restated north star, 2026-07-20 — this line sits above every feature call.)

**Two-layer product evolution (2026-07-20, Chiu — supersedes the earlier "passive-capture v1" framing).** The long-term vision is unchanged: *Kamome automatically remembers your journey and directs it into a travel film worth rewatching.* But the **first shipped product is deliberately smaller, publishable, and verifiable — the Replay MVP:** *pick a past trip's photos → Kamome rebuilds the route from their EXIF place + time, snaps it to real roads, and auto-generates a cool, shareable travel-path animation (MP4).* The MVP does **not** promise full passive background recording or the automatic story-directing; those are proven later (**Capture Beta**, **Story Director** — §7) and the architecture must not block them. The evolution is two layers: **(1) Replay MVP** — auto-generate a real-road trip animation; **(2) Story Director** — on top of the MVP, add automatic moment-selection, narrative, hero photos, pacing, and music, becoming a true trip-memory director. Do not cram Story Director into the MVP now. **Do not let MVP copy claim 12-day zero-touch capture or imperceptible battery** — those are Capture-Beta-validated promises, not launch claims (see §1, §7, §10).

Founder motivation (Chiu, keep verbatim): *built first for myself — I love travelling but can't be bothered to organize; the trip ends and Kamome has already made the movie.* This is a **storytelling / memory** product, not a GPS or planning tool. Fork is the underlying mechanism (§3.1), not the marketing language: user-facing copy says **Save / Get this route / Inspired by**, never "fork" ("GitHub for road trips" is engineer-brain framing — ordinary travelers save and get inspired; they don't fork). **Taiwan-first launch, English-ready by design.**
**Brand element:** the animated "you are here" head marker in the recap video is a small seagull, not a dot. This is the mascot and the app icon.
**Platform:** iOS 17+, Swift 5.10+, SwiftUI. Base localization zh-Hant, second locale en. All user-facing strings in String Catalogs from Phase 0 — never hardcoded.
**Audience for this doc:** Claude (Claude Code) as the implementing engineer. Chiu as product owner / reviewer.
**Doc version:** 1.7 (2026-07-20) — **Replay MVP repositioning** (owner decision, `decisions.md` 2026-07-20). The first shipped product is redefined from "passive-capture v1" to the **Replay MVP**: photo-EXIF import → OSRM road reconstruction → souvenir-map recap → MP4 share, validated on **three real past trips**. Consequences: **Phase 3.5 is renamed Replay MVP** and absorbs **photo-EXIF import** (pulled forward from the old Phase 4); its gate becomes a **product release gate** (three shareable films), not a static-visual gate. The tracking/battery device gates (2 h drive, region-resume re-validation, long-duration background, process-death recovery, passive capture, ≥ 3-day battery, the "Arm once, forget it" promise) leave the release path for a new **Capture Beta** (Phase 5, renamed from Passive Capture Tier — the checklists are preserved and moved, never marked passed). **Story Director** (automatic moment-selection, narrative, hero photos, chapters/elision, licensed music + beat-sync) becomes **Phase 4** (renamed from Import & Map Matching — its EXIF half moved into the MVP; the Google Timeline importer is **dropped as redundant** — EXIF import covers past trips, in-app capture covers new ones; owner decision 2026-07-20). Story Director is **deterministic — no AI/LLM tokens** (scoring-and-selection over structured trip data, §7 Phase 4). Plans & Fork (Phase 6) and Backend (Phase 7) are unchanged and further deferred. **MP4 is the launch format; GIF is demoted to non-blocking.** Honest provenance added (§3, §6): `trip.source` distinguishes Kamome-recorded from reconstructed-from-photos, and UI copy never says "Verified Trip". Positioning de-overclaimed (header above). — v1.6 (2026-07-20) — recap visual system validated via a throwaway web prototype on real data (Chiu's 170-photo Iceland ring-road trip); owner sign-off "prototype 蠻成功的，收斂回 app". Findings + the data pipeline + engine source: `Docs/prototype/` (also `decisions.md` 2026-07-20). Locked-in constraints for §4.5/§7: (a) base map = **real geometry + hand-written subtractive style** = "紀念品地圖" (souvenir map), reaffirming the MapLibre substrate ADR; (b) stop photos = a **rotating photo deck at the stop location**, hero cross-fades through 3–8 photos at **0.8 s each** (not the old single card); (c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle is the subject, close heading-up zoom) — the prototype's one unmet requirement; top-down car is the default marker, seagull/scooter/bike swappable. Positioning line restated (above). Forward directions recorded: photo-EXIF import first (the prototype IS that importer, §4.7), video clips as auto-trimmed muted "beads", and royalty-free **beat-synced** music (bundled library + offline beat maps, events quantized to the beat; free=silent export, premium=in-app track). No architecture change — these constrain existing components (`RecapSnapshotProviding`, `CameraPath`, `OverlayTimeline`, `RecapTheme`, `ImportKit`). v1.5 (2026-07-19) — recap visual pivot (owner decision after reviewing the P3 demo artifact): the recap is a stylized, premium animated replay, not Apple-tile output — vision in `Docs/kamome-animation-vision.md`; recap base-map substrate moves MKMapSnapshotter → MapLibre Native + self-hosted vector tiles with Kamome-authored themed styles (ADR in `Docs/decisions.md` 2026-07-19; implementer guide `Docs/vector-tile-pipeline.md`); §0 gains rule 6 (storytelling engine + recognizable identity); §4.5 step 2 rewritten + visual quality bar added; Phase 3 scope frozen as the pipeline milestone; new **Phase 3.5 Recap Visual System** (OSRM §4.4 pulled forward → MapLibre substrate → Modern Minimal theme; no renumbering of P4–P7). v1.4 (2026-07-18) — fork demoted from positioning to mechanism: positioning line rewritten (memory-engine framing), §1.5 fork row relabeled P6 bet, §4.5 end card copy → "Get this route"; all user-facing copy uses Save / Get / Inspired by (S6/S7 screen wording settled at P6 — internal names, table `plan.forked_from`, and `.kamome` schema unchanged). v1.3 (2026-07-15) — battery-moat repositioning: passive capture tier (§1.8, §2.3), map matching promoted to core (§4.4), trip import (§4.7), phases renumbered (fork → Phase 6, backend → Phase 7), transactional monetization note (§1.6). v1.2 (2026-07-11) added Roadtrippers analysis, Taiwan-market adaptations, Kamome branding, handoff checklist & kickoff prompt.

> **Naming due-diligence (do before locking bundle ID):** search App Store for existing "Kamome" apps, check TIPO (Taiwan) and JPO trademark registers in app/software classes — note JR Kyushu operates a Shinkansen named かもめ (different class, likely fine, verify anyway). **IP caution:** the song 《快樂的出帆》 inspires the *name only*. Never use its lyrics or melody in the app, recap videos, or marketing — the composition is almost certainly still in copyright. Original seagull branding only.

---

## 0. Rules of Engagement for Claude Code

These override any default behavior:

1. **Phase gates are hard gates.** Do not start Phase N+1 until every acceptance criterion in Phase N passes its listed verification command. No self-certification — a criterion is "done" only when the command output proves it.
2. **All tunables live in config.** Sampling rates, thresholds, speeds, timeouts → `Config/TrackingConfig.json` loaded at startup. No magic numbers in code.
3. **Prefer boring tech.** No reactive frameworks beyond what SwiftUI requires. Use Swift Concurrency (async/await) only where the OS API forces it (location callbacks, photo fetches, video export). No Combine pipelines for business logic.
4. **Every phase ends with a demo artifact** (screen recording script or exported file) placed in `Docs/demos/phaseN/`.
5. **Hardware reality:** building/running requires Xcode on macOS and a physical iPhone for background-location and battery testing. The simulator + GPX fixtures cover logic testing only. Flag any step that needs the physical device instead of silently skipping it.
6. **Kamome is a travel storytelling engine, not a GPS visualizer or vehicle animation engine.** (Added v1.5; full vision in `Docs/kamome-animation-vision.md`.) Two binding consequences: (a) the judgment criterion for every future camera movement, pause, transition, and visual effect is *does it serve the narrative of the journey* — not *does it display the data*; (b) a Kamome replay must never look like Apple/Google Maps with an animated route on top — the visual language must be distinctive enough to recognize a Kamome replay instantly, even with branding stripped. Corollary: the replay engine and the rendering theme are fully decoupled; Modern Minimal is merely the first theme implemented, never a structural assumption, and nothing theme-specific may leak into the replay engine.

---

## 1. Product Definition

### 1.1 One-sentence pitch

**Replay MVP (what ships first, what launch copy may claim):** "Pick a past trip's photos — Kamome rebuilds the route on real roads and turns it into a share-worthy travel animation, no journaling."

**Long-term vision (validated later; NOT an MVP claim):** "Arm it once when the trip starts, forget the app for days — get a cinematic map video of your road trip, with battery drain you can't measure." This zero-effort passive-capture promise is the eventual differentiator #1 (§1.8), but it is proven in **Capture Beta** (§7), not at MVP launch. When capture does ship, its rule holds: Kamome's capture must never depend on the user remembering anything mid-trip (Relive makes you start/stop every activity — forget once and that leg is gone forever).

### 1.2 Personas
- **P1 The Road Tripper (primary):** plans multi-day self-drive trips, wants a beautiful record and stats without manual journaling. (Reference user: an 8-day Perth → Margaret River → Albany loop.)
- **P2 The Trip Planner:** hasn't gone yet; browses real driven routes, forks one, edits stops, uses it as the plan.
- **P3 The Audience:** friends/family receiving the recap video or follow link. Never installs the app. They are the viral vector.

Ordered by when they ship. Loops 1–2 are the **Replay MVP**; loops 3–4 are later phases.

1. **Import loop (§4.7) — the MVP's core loop:** photo EXIF → last year's trip becomes a recap within minutes of install, before the user's next vacation. This is the acquisition hook *and* the way Chiu dogfoods recap quality on real past trips.
2. **Share loop:** Trip (imported or recorded) → one-tap animated recap (MP4) → posted to socials → watermark/link drives installs.
3. **Capture loop (Capture Beta, §7):** Arm once at trip start → auto-track segments (drive/walk/transit) across days with zero mid-trip interaction → auto-detect stops → attach photos → End at trip end. Feeds the *same* recap pipeline as import; not in the MVP.
4. **Fork loop (Phase 6):** Published trip → viewer saves it into an editable Plan → drives it → publishes their version → network effect. Deferred until the video product proves people share.

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
| One-tap animated route video with photos | ✅ (Trip Reels) | ✅ | ❌ | ❌ | ✅ **Replay MVP — the launch product; must match or beat quality** |
| Works with zero account / zero server | ❌ | ❌ | ❌ | ❌ | ✅ |
| Zero mid-trip interaction, multi-day battery story (§1.8) | ❌ (gaps are its top complaint) | ❌ (manual start/stop per activity) | n/a | ✅ (but private, no output) | ✅ **eventual differentiator #1 — Capture Beta, not an MVP claim** |
| Import past trips (photo EXIF) | ❌ | ❌ | ❌ | export-only | ✅ **Replay MVP core loop — photo-EXIF import** |
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

> **Sequencing note (2026-07-20):** this section is the **Capture Beta** thesis (Phase 5), not a Replay MVP claim. The MVP ships the *import* application of this same matching pipeline (§4.7) — sparse geotagged photos snapped to roads — which needs no background capture and no battery proof. The passive-capture tier below is real and load-bearing for the long-term vision, but nothing in the MVP release depends on it, and MVP copy must not promise it.

Relive-class trackers need high-frequency GPS because trails are not on any road network — the raw points *are* the route. A road trip is the opposite: ~99% of it happens on a known network, so sparse, nearly-free signals (iOS significant-location-change, ~500 m / minutes granularity, plus `CLVisit` for stops) can be **snapped back onto the road network with map matching (§4.4)** and look as good as continuous tracking — a car can only be where roads are. Relive cannot copy this: their core scenario has no network to snap to. This, not "they do outdoors, we do driving," is why the markets don't overlap.

Product consequence — two capture tiers, user-selectable at Start (passive is the default for multi-day trips):

- **Passive tier (Capture Beta, Phase 5):** arm the trip once, forget the app for days, battery impact indistinguishable from zero. Sparse fixes + CLVisit stops + map matching + daily CMMotionActivity backfill. This kills the "forgot to press start" failure mode entirely — but the claim is only usable once Capture Beta's ≥ 3-day battery + integrity gate passes on real hardware.
- **High-fidelity tier (the Phase 1 engine):** continuous adaptive GPS (§2.3 table) for single-day drives where turn-level fidelity matters, off-network driving (gravel, private roads), or when matching confidence is low.

Import (§4.7) is the same insight applied backwards, and it is **what the MVP ships**: past trips already exist as sparse data (photo EXIF geotags) — the identical matching pipeline turns them into recaps with zero capture and zero battery cost. **One pipeline, three sources: import (MVP), passive capture (Capture Beta), high-fidelity capture (Capture Beta).**

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
│   PhotoKit (read-only)  MapKit (S2/S3)  MapLibre (recap, P3.5) │
└────────────────────────────────────────────────────────────────┘
        Replay MVP (P3.5) core sidecar: OSRM /match (Docker, self-hosted)
        Replay MVP adds Core/ImportKit (photo-EXIF importer §4.7)
        Phase 7: Supabase (Postgres+PostGIS, Auth, Storage)
```

### 2.2 Key technology decisions (with trade-offs)

| Decision | Choice | Rejected alternative | Why |
|---|---|---|---|
| Persistence | **GRDB + SQLite** | SwiftData | A full day of tracking ≈ 20–40k trackpoints. GRDB gives bulk inserts, raw SQL, and R*Tree spatial index. SwiftData bulk-insert performance and migration story are weaker, and a coding agent hits fewer undocumented quirks with GRDB. |
| Maps (interactive screens S2/S3) | **MapKit** | Mapbox | Free, native, adequate for live HUD and trip detail. (Pre-v1.5 this row also covered recap frames via `MKMapSnapshotter`; that materialized as the §9 "too plain" risk — recap substrate split out below.) |
| Recap base map (Phase 3.5) | **MapLibre Native + self-hosted vector tiles, Kamome-authored style per theme** | Fully custom renderer; Mapbox; restyling MapKit (no styling API exists) | Owner-rejected Apple-tile look (ADR 2026-07-19). Full control of colors, typography, and what is *omitted*; PMTiles = static-file hosting, no tile server; same regional OSM extracts as OSRM; checked-in tiles make golden frames bit-stable. Must clear the §4.5 quality bar or the decision gets revisited. Guide: `Docs/vector-tile-pipeline.md`. |
| Map matching (snap-to-road) | **OSRM `/match`, self-hosted Docker** (app side landed in the Replay MVP / P3.5) | Mapbox Map Matching API | Free, offline-capable for a region extract (e.g. Australia OSM ≈ 1 GB, Taiwan ≈ 100 MB), no per-request cost. Mapbox is easier but meters every request. Phases 1–3 shipped raw polyline + Douglas-Peucker; from the Replay MVP matching is **core infrastructure** — photo-EXIF import (§4.7) is load-bearing on it (sparse geotags look wrong unsnapped), and the passive tier (§1.8, Capture Beta) later too — but trip completion/import must still never block on it. |
| Transport mode | **CMMotionActivityManager primary, speed heuristic fallback** | ML model | Apple's on-device classifier (automotive/cycling/walking/stationary) is free and battery-neutral. Speed heuristic covers devices/regions where it's unreliable. |
| Video | **Snapshot-provider frames → AVAssetWriter** (provider = MapLibre from Phase 3.5; MKMapSnapshotter was the P3 bootstrap) | Screen-record a map camera flight | Deterministic, background-renderable, testable frame-by-frame — property of the frame pipeline, independent of which provider renders the base map. |
| Backend (Phase 7 only) | **Supabase** | Custom FastAPI | Auth + Postgres/PostGIS + storage + row-level security in one; solo-maintainable. |

### 2.3 Battery budget (non-functional requirement — applies to capture; **Capture Beta**, not the Replay MVP)
Two capture tiers (§1.8). The battery story is the eventual differentiator #1 — treat a regression here like data loss. (The Replay MVP imports past trips and records nothing, so this NFR does not gate it; it gates Capture Beta.)

**Passive tier (default for multi-day trips; Capture Beta, Phase 5).** Target: **drain attributable to Kamome < 1%/day** — unmeasurable over a multi-day trip.
- `startMonitoringSignificantLocationChanges()` — cell-tower granularity (~500 m / ≥ 5 min); relaunches the app after suspension or termination, so an armed trip survives process death and reboots.
- `CLVisit` monitoring — arrival/departure events become `stop` candidates (replaces §4.2's sliding-window dwell, which needs dense points).
- Route fidelity comes from map matching (§4.4), not sampling density; low-confidence gaps render as "inferred" dashed lines.
- Mode labeling: `CMMotionActivityManager.queryActivityStarting(from:to:)` backfill once per day (the API keeps ~7 days of history) classifies segments drive/walk/transit after the fact.
- Tunables live in a `passive` block of `TrackingConfig.json` (visit min-dwell, matching confidence floor, backfill cadence — defaults set in Capture Beta).

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
  matched_polyline TEXT           -- Google-encoded polyline AFTER map matching (landed in Replay MVP / P3.5)
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
- **Honest provenance (2026-07-20).** `trip.source` is load-bearing, not cosmetic: it separates what Kamome **actually recorded** (`recorded`) from what was **reconstructed from photo locations** (`imported_photos`) or a Timeline export (`imported_timeline`). Both produce first-class recaps, but the distinction must surface in the UI (S1 card badge, S3 detail — §5). GPS and EXIF are **not** tamper-proof evidence; never present an imported trip as proof, and never use copy like "Verified Trip". This is a product rule, not a nicety (§6).
- **Schema v2 (one forward migration, lands with the Replay MVP — photo import needs it):** `trip.source TEXT NOT NULL DEFAULT 'recorded'` (`recorded | imported_timeline | imported_photos`), `segment.source TEXT` (`gps_hifi | gps_passive | timeline | exif`), plus `photo_ref.order_idx` (the deferred S4 reorder — bundled per `Docs/decisions.md` 2026-07-12). The `gps_passive` value is written later by passive capture (Capture Beta). `imported_timeline` / `timeline` stay in the enum as **reserved forward-compat only** — no Google Timeline importer is planned (dropped as redundant, owner decision 2026-07-20; §4.7).

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
- **Replay MVP / P3.5** (app side landed, `decisions.md` 2026-07-19; **core**, promoted from stretch — §1.8): batch segments (≤100 pts/request) to OSRM `/match?geometries=polyline&tidy=true`; store result in `segment.matched_polyline`. One pipeline serves three sources: imported photo-EXIF points (load-bearing — sparse geotags look wrong without snapping; this is the MVP's dependency), later imported Timeline points and passive-tier fixes (Capture Beta), and high-fidelity recordings (cosmetic win). On failure (no OSRM reachable / confidence below `matching_confidence_min`), fall back to simplified raw polyline, mark segment `matched=false`, render **"inferred" (honestly low-confidence) style** — the Replay MVP gate forbids inventing a route that crosses sea/mountain or a wrong road, so low-confidence legs must read as inferred, never as fact. **Never block trip completion or import on matching.**

### 4.5 Recap video (ExportEngine)
Deterministic frame pipeline, 1080×1920 (9:16 social) default, 30 fps:
1. Compute camera path: interpolate along full-trip polyline; speed-warp so total video = `target_duration_s` (default 30 s) regardless of trip length; ease-in/out at stops.
2. For each frame: a `RecapSnapshotProviding` provider renders the base map for the camera position (snapshot per keyframe every N frames, cross-fade between, to keep render time sane); the compositor draws the traveled route portion + animated head marker via CoreGraphics overlay, projecting through the snapshot's own projection. From Phase 3.5 the shipping provider is **MapLibre Native over self-hosted vector tiles with a Kamome-authored theme style** (ADR 2026-07-19; `Docs/vector-tile-pipeline.md`); `MapKitSnapshotProvider` was the P3 bootstrap, `FlatSnapshotProvider` keeps golden-frame CI deterministic. Boundary discipline: renderer SDK types never leak past the provider file (§0 rule 6 corollary).
3. At each stop: 1.5 s hold, photo card animates in (highlight photo), stop name label, day badge.
4. Title card (trip name, dates, distance) + end card (stats + "Get this route" QR → share URL/file).
5. Encode via `AVAssetWriter` (H.264). GIF export: same frames at 12 fps, 480 px wide, `ImageIO` with palette quantization.
Acceptance bar (**revised 2026-07-20**): each of the three real dogfood trips exports on a real iPhone in a **product-acceptable** time, **recorded per trip** via the S5 readout — no crash, no unacceptable memory pressure. The single "< 90 s on an iPhone 13-class device" number was a simulator-era target and is **not** re-used as a pass/fail line without fresh device data; it survives only as a rough sanity reference. What actually gates is Chiu's judgment that the film is worth sharing (§10). This feature is the marketing engine — over-invest here.

The camera treatment for the MVP is a **vehicle-locked follow-cam** (§4.5 step 1 / prototype §2.3), which reads as *driving forward through terrain*. This is the MVP's primary dynamic — but it is **not an unchallengeable product dogma**: "the vehicle is always centered for the whole film" is an MVP simplification, not a permanent law. Story Director (§7) will make the follow-cam **one narrative shot among many** (chapter transitions, establishing shots, hero holds), so build `CameraPath` to emit the follow trajectory *and* explicit wide keyframes, never hardwiring "centered vehicle" as the only camera mode.

**Visual quality bar (v1.5, judged during the Replay MVP as a design review — NOT the release gate):** the reason we carry self-hosted tiles instead of free Apple Maps is that MapLibre + a Kamome style sheet must produce output **clearly better-designed than native Apple Maps for journey replay**. Concretely: zero business-POI noise; deliberate use of empty space — subtractive cartography that shows only what serves the journey; distinctive road and route treatment; instantly recognizable Kamome identity with branding stripped (§0 rule 6). Judged by side-by-side stills against the P3 Apple-tiles artifact (`Docs/demos/phase3/`) at matched camera positions, reviewed by Chiu; a style sheet that fails side-by-side is not shippable, and if the bar proves unreachable the substrate decision itself is revisited (ADR 2026-07-19). **Scope correction (2026-07-20):** this side-by-side is a design checkpoint that keeps the substrate honest — it **does not replace** the Replay MVP release gate. The release gate is the full-video product judgment across three real trips (§10): "map looks prettier than Apple Maps" is necessary, not sufficient; "is this a travel-path animation worth publishing" is the real bar. The route must always follow real roads — never straight lines between GPS points (matching §4.4 is a Replay MVP prerequisite, already landed app-side). Themes are swappable without touching animation logic; **one theme (Modern Minimal) is the MVP target — multiple themes are explicitly not an MVP success condition**; how the seagull head marker (brand element, page 1) composes with the per-trip vehicle icon (§1.7) is settled during Modern Minimal theme design, not here.

### 4.6 Plan-vs-actual diff
Given `trip.origin_plan_id`: match plan_stops to actual stops by name-similarity + distance < 1 km. Output: visited / skipped / unplanned-extra + dwell delta per stop + total distance delta. Rendered as a "trip report card." (Unique feature — no incumbent has it.)

### 4.7 Trip import (the cold-start killer — and the Replay MVP's core)
Nobody should wait for their next vacation to see Kamome's value. **One importer** (`Core/ImportKit/`, the **photo-EXIF importer**), feeding the normal pipeline (map matching §4.4 → stops → photo matching §4.3 → recap §4.5):
- **Photo EXIF (Replay MVP — the MVP's core):** user picks a date range or album; geotagged photos cluster into `stop` rows + photo groups + a coarse route (time-gap + distance heuristics, tunables in config), which OSRM (§4.4) snaps to real roads. Photos are attached to their stops by construction — zero matching ambiguity. Imported trips write `trip.source = 'imported_photos'`, `segment.source = 'exif'` (§3), and must be honestly labeled as reconstructed-from-photos (§6), never as recorded. The prototype (`Docs/prototype/`) already proved this end-to-end on a real 13-day, 170-photo trip — that pipeline *is* this importer.

**Google Timeline importer — dropped (owner decision 2026-07-20).** Considered and cut as redundant: photo-EXIF import already covers *past* trips, and in-app capture (Capture Beta) covers *new* ones, so a Timeline parser adds format-drift maintenance for little unique value. The `imported_timeline` enum value is reserved for forward-compat only (§3). Revisit only if real demand appears (`Docs/icebox.md`).

Imported trips are first-class: same S3 detail, same recap, same fork-to-plan. Acceptance bar (Replay MVP): album/range selected → the trip reconstructs and a recap can render, in a **product-acceptable** time recorded per trip; the render itself meets §4.5's (revised) bar. This is the acquisition hook (§1.3 loop 1) — the first share happens before the user ever records.

---

## 5. UI Spec (SwiftUI screens)

| # | Screen | Contents / behavior |
|---|---|---|
| S1 | Home / Trip List | Cards: cover map thumbnail, title, dates, distance, **source badge** (recorded vs reconstructed-from-photos — §3 honest provenance). **`Import from photos`** is the MVP hero action (§4.7 photo EXIF); `Start Journey` (live capture) arrives with Capture Beta. Empty state sells import first — value in minutes, not after the next vacation. |
| S2 | Recording HUD | Live map, traveled polyline, current mode icon (car/walk), elapsed / km, battery-friendly note. Buttons: `Add Stop Note`, `Pause`, `End Trip`. Lock-screen Live Activity showing distance + duration (Phase 2 nice-to-have). |
| S3 | Trip Detail | Full map with matched route colored by mode (drive = solid, walk = dotted), **inferred/low-confidence legs shown honestly** (dashed), stop pins with photo thumbnails, day filter chips, stats strip (distance, drive time, stops, top speed), **provenance note** for imported trips ("reconstructed from photos", never "verified"). Timeline list below map. |
| S4 | Stop Editor | Rename, note, reorder photos, mark highlight, delete false-positive stop, merge stops. |
| S5 | Export | Aspect ratio picker (9:16 / 1:1 / 16:9), duration, **MP4 (launch format)** with GIF as an optional non-blocking extra, live preview of first seconds, progress bar, cancel, render-time readout, share sheet. |
| S6 | Plan Editor | Day-grouped reorderable stop list + map. Search-to-add stop (MKLocalSearch). Per-day drive-time estimate (MKDirections, cached). Import `.kamome` = pre-filled editor with "Forked from …" banner. |
| S7 | Convert / Fork | From S3: `Publish as Plan` → generates plan from stops → S6. From received file: `Fork` → S6. |
| S8 | Settings | Tracking profile (Battery saver / Balanced / High fidelity → maps to config presets), permissions status + fix-it deep links, data export (GPX + JSON), delete all data. |

Design language: map is the hero on every screen; one accent color; dark-mode-first (maps look better). No onboarding carousel — permission priming happens contextually at first `Start`.

---

## 6. Permissions & App Store Compliance

- Location: request **When In Use** at first Start, escalate to **Always** with a priming screen explaining background tracking only during an active trip. Purpose strings must say exactly that.
- `UIBackgroundModes = [location]`; expect App Review to ask for justification — include a review note + demo video showing tracking stops when the user ends a trip. Never track outside an active trip. This is both an ethics line and the reason review will pass.
- Passive tier (Capture Beta, Phase 5): requires **Always** at arming (significant-change and CLVisit deliver while the app is dead). The priming copy must say a multi-day trip keeps a low-power recorder alive until you End Trip. The review posture is unchanged — capture runs only between an explicit Start and End, and End Trip verifiably stops all monitoring. (Not in the Replay MVP: the MVP requests only Photos, no background location.)
- Motion & Fitness permission for CMMotionActivity (graceful degradation to speed heuristic if denied).
- Photos: `PHPhotoLibrary` **limited access compatible** — the picker flow must work if the user grants only selected photos.
- Privacy nutrition label: location + photos, "data not collected" (true until Phase 7 — a genuine marketing point: "your location history never leaves your phone"). Import strengthens the point: photos and any Timeline export are parsed on-device and never uploaded.
- **Honest provenance in copy (§3).** A recap built from imported photos is presented as *reconstructed from your photos*, never as a recorded or "Verified Trip". GPS/EXIF are not tamper-proof; do not imply they are. This is both an ethics line and a trust line for the share loop.

---

## 7. Build Plan — Phases & Hard Gates

> Each phase = one milestone PR. Verification commands run from repo root. GPX fixtures live in `Tests/Fixtures/` and include `perth_margaret_river_day1.gpx` (synthetic 280 km drive with 4 stops + 2 walk loops), `taiwan_huandao_9days.gpx` (synthetic round-island loop, mixed car + scooter + one TRA rail leg — exercises transit heuristic and 環島 loop detection), and `city_walk_flapping.gpx` (mode-flapping torture test).

**Phase map (revised 2026-07-20 — Replay MVP repositioning, `decisions.md`):**

| Phase | Name | Status | Role |
|---|---|---|---|
| 0 | Skeleton | ✅ done | project, GRDB, config, CI |
| 1 | Tracking Engine | ✅ done (device gate → Capture Beta) | high-fidelity capture |
| 2 | Stops, Photos, Trip Detail | ✅ done | S3/S4, photo matching |
| 3 | Recap Export Pipeline | ✅ engineering done (device items redistributed) | frame pipeline, MP4/GIF, S5 |
| **3.5** | **Replay MVP** (recap from photos) | **← current, RELEASE TARGET** | import → souvenir map → follow-cam → MP4 share; 3-trip dogfood gate |
| 4 | Story Director | after MVP proves sharing | **deterministic (no-LLM)** moment-selection, narrative, hero, chapters, pacing, music |
| 5 | Capture Beta | after MVP (hardware-gated) | passive capture, battery, "arm once" — inherits the moved tracking device gates |
| 6 | Plans & Get this route | further deferred | fork mechanism |
| 7 | Backend & Community | post-POC | Supabase, web pages |

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

### Phase 3 — Recap Export Pipeline (✅ engineering complete 2026-07-19; device items redistributed 2026-07-20)
Scope: ExportEngine §4.5 pipeline mechanics (camera path, overlay timeline, frame compositor, MP4/GIF encoders, progress/cancel), S5. The recap's *visual system* is the Replay MVP / P3.5 (decisions.md 2026-07-19) — all of this phase's machinery survives that substrate swap. Its **development purpose is done**; but no unverified device item is marked passed (§0 rule 1).
**Gate — engineering items (passed):** golden-frame tests (render frames 0/N/last for fixture trip, compare hash within tolerance) — done, CI green.
**Gate — device items, redistributed 2026-07-20 (nothing faked passed; `Docs/device-test-P3.md`):**
- **Fold into the Replay MVP gate:** on-device MP4 export, S5 UX / progress / cancel / share sheet, limited-photo re-check, per-trip render time recorded. GIF is now **non-blocking** — MP4 is the launch format, so the old "GIF < 8 MB" line is retired as a gate.
- **Move to Capture Beta:** the 2 h real drive and region-resume re-validation (tracking/battery items, not recap-video items). The single "< 90 s on device" number is retired as a pass/fail line (§4.5 revised).
- The original share-worthiness item ("Chiu posts one recap and it doesn't embarrass him") is now part of the **Replay MVP** gate, where the visual system can actually meet it.

### Phase 3.5 — Replay MVP (recap from photos) ← the first shippable product / RELEASE TARGET
Renamed & rescoped 2026-07-20 (decisions.md; was "Recap Visual System"). Ships the loop **pick past photos → reconstruct trip → snap to real roads → souvenir-map recap → MP4 → share.** Work order and full detail in `Docs/handoff-P3.5.md`; the OSRM matching app side is already landed (do not redo). Sequence:
1. **Photo EXIF import (§4.7)** — `Core/ImportKit/` + schema v2 (`trip.source` / `segment.source`, honest provenance §3). Pick an album / date range → cluster geotagged photos into stops + photo groups + a coarse route → OSRM snap (§4.4). Imported trips flow through the existing Trip Detail (S3), RecapComposer, and ExportEngine **unchanged**. The prototype (`Docs/prototype/`) is this importer, proven on a real 13-day trip.
2. **MapLibre souvenir-map substrate** — `MapLibreSnapshotProvider` behind the existing `RecapSnapshotProviding` boundary; real geometry + Kamome hand-written **subtractive** style (no generic nav map, no POI noise); MapLibre types confined to that one file; no abstraction layer without a consumer. Guide: `Docs/vector-tile-pipeline.md`.
3. **Modern Minimal theme** — the ONE publishable theme. Multiple themes are **not** an MVP success condition; theme swap stays feasible via the boundary but is not a product deliverable to spend time proving.
4. **Vehicle-focused follow-cam** (§4.5 step 1) — close, heading-aware follow trajectory as the primary dynamic; wide shots as explicit keyframes. "Centered vehicle for the whole film" is an MVP simplification, **not dogma** — Story Director makes it one shot among many.
5. **Basic photo deck** — deterministic 3–8 photos @ ~0.8 s at the real location (OverlayTimeline). Labeled explicitly as the MVP's **basic** photo presentation, not final Story Director; no long-term assumption that every stop has equal narrative weight.
6. **Three real-trip dogfood** — Chiu's three different past trips, each run fully in-app: photos import → matching → recap → MP4 → share. **No hand-edited DB, no prototype-script data-patching, no CapCut / external-tool rescue.**
7. **TestFlight / public demo** — only after the three trips pass = release candidate.

**Replay MVP hard gate (a product release gate — replaces the old static-visual gate):**
- Three real trips of **different character** all import successfully from photos.
- All three complete **entirely in-app**: import → route reconstruction → recap → MP4 → share — with **no DB edits and no repo-external tools** to fix results.
- The route has **no obvious sea-crossing / mountain-crossing straight line and no gross wrong-road**; low-confidence inference is presented **honestly** (inferred style, §4.4), never as fact.
- All three films are ones **Chiu genuinely wants to keep and share**.
- **≥ 1 actually published publicly**, without external-editing rescue.
- **Limited Photo Library path passes on a real device.**
- All three export **stably on a real iPhone** — no crash, no unacceptable memory pressure.
- **Per-trip export time recorded** (S5 readout), judged **product-acceptable** — the retired single < 90 s number is not the criterion.
- MapLibre-vs-Apple-Maps side-by-side may stay as a **design review** but does **not** replace the full-video product judgment.
- The final criterion is **not "the map looks prettier" but "is this a travel-path animation worth publishing".**
"Three real trips" stays a **hard** condition — never downgraded to a single video. **Chiu signs off.** Demo artifacts in `Docs/demos/phase3_5/`. **This gate = Replay MVP release candidate.**

### Phase 4 — Story Director (est. TBD) ← only after the Replay MVP proves films get shared
Renamed 2026-07-20 (was "Import & Map Matching"): matching already landed and the photo-EXIF importer moved into the Replay MVP, so **no importer remains here** (the Google Timeline importer was dropped as redundant — §4.7). This phase turns *Replay* (faithful playback) into *direction* — the product that **dares to choose and to omit**. Start only once the Replay MVP has real evidence people share the films.

**Feasibility — deterministic, no AI/LLM tokens (owner constraint 2026-07-20).** Story Director is a **scoring-and-selection engine over structured trip data** (stops, segments, photos, timestamps, geography) — pure algorithm, no LLM, no network, no per-call cost, and deterministic (which *keeps* golden-frame CI stable rather than breaking it). Moment salience = a weighted sum of photo count, `is_highlight`, dwell duration, geographic novelty (distance from the last kept moment), and day-boundary signals — weights are `TrackingConfig.json` tunables; select top-N with non-maximum suppression for spacing; omit the rest and speed-warp the gaps; scale per-photo hold by salience. Hero-photo pick uses **on-device Vision** (saliency / face detection — free, local, no tokens, no network, not an LLM; owner-confirmed 2026-07-20) to rank a stop's photos, falling back to `is_highlight` → nearest-the-dwell-midpoint → chronological when Vision yields no signal. Vision confined to its own boundary file (SDK-confinement rule); its scores are cached so re-exports stay deterministic. The manual "replace / remove" controls are the taste escape hatch. Scope:
- Automatic selection of **5–8 key moments**, ranked by photos, dwell time, geographic change, `is_highlight`, and day transition.
- **Hero photo** treatment; **chapters & elision**; **variable photo dwell pacing** (drop the MVP's equal-weight simplification).
- A few light **"replace this scene / remove this stop"** controls — director's touch-ups, not a full editor.
- **Video beads** — auto-trim 2–3 s, muted, hard-capped, deterministic (icebox constraints; golden-frame-safe).
- **Licensed music + beat-sync** — bundled royalty-free library + offline beat maps, recap events quantized to the beat; free = silent export, premium = in-app track (§1.6 transactional).
Core principle: **Kamome is ultimately not a full playback of all trip data — it is a travel director that dares to select and to omit.** The selection algorithm above *is* that director — deterministic, not learned.
**Gate:** defined when the phase starts; do not design now.

### Phase 5 — Capture Beta (est. 3–5 sessions) ← the passive-capture / battery moat, now a beta *after* the video product
Renamed & resequenced 2026-07-20 (was "Passive Capture Tier / v1"). This is where the long-term "arm once, forget it" promise is finally built and proven — the promise the Replay MVP deliberately does **not** claim. Scope: significant-location-change + CLVisit adapter in `LocationService`; armed-trip persistence across process death + relaunch resume (SLC launch key); passive samples → matching → segments; CMMotionActivity daily backfill; tier choice at Start (passive default for multi-day); `passive` config block; S2 HUD passive variant ("recording quietly — battery-free").

**Open question — what does capture add over photo reconstruction? (owner-raised 2026-07-20, decide from MVP feedback, do not assume).** Since photo-EXIF import already reconstructs most photo-rich trips, Capture Beta must earn its background/battery engineering by selling the **three things photos structurally cannot**: (1) a **truth-path** — the actual road every turn, not an OSRM guess between sparse photos that can pick the wrong parallel road or miss an unphotographed detour (this *is* the `recorded` vs `reconstructed-from-photos` line, §3); (2) **stops/scenes with no photo** (a meal, gas, a viewpoint you didn't shoot) — invisible to EXIF; (3) **true zero-effort** — you didn't even have to take photos (scooter 環島, night, rain, driving-focused trips), the purest form of the founding motivation. Whether these justify the build is validated after the MVP, not presumed here.
**Gate — inherits the tracking/battery device items moved here 2026-07-20 (checklists preserved in `Docs/device-test-P1.md` / `-P3.md` / `-P5.md`, none faked passed):**
- Sparse-fix replay fixture (`perth_margaret_river_day1` downsampled to SLC density) produces a matched route within tolerance of the dense-replay route.
- Process-kill / relaunch preserves the armed trip (process-death recovery).
- **2 h real drive** and **region-resume re-validation** — moved out of the old Phase 3 gate (device-test-P3 items C + H's drive).
- **Physical device: ≥ 3-day armed period, drain attributable to Kamome < 1%/day, route + stops correct — Chiu signs off** (`Docs/device-test-P5.md`).
- **Only after this gate** is "Arm once, forget it" validated and usable in product copy.

### Phase 6 — Plans & Get this route (est. 3–4 sessions; further deferred 2026-07-20)
Do not start until **both** the Replay MVP and Story Director have real sharing evidence — plan/fork must never block or delay the video product. Scope: plan tables, S6/S7, trip→plan conversion, `.kamome` export/import + URL scheme, plan-vs-actual diff §4.6, drive-time estimates. Stretch: 環島 loop detection + progress ring + badge (§1.7).

**Forward note (owner, 2026-07-20 — discuss later, do not design now).** Plans is where **captured road-detail data** earns unique value: a shared "Get this route" from *recorded* driving is higher-fidelity than one reconstructed from a stranger's photos — so this phase benefits from Capture Beta existing. Community route-sharing is also the intended **virality engine** (share loop → installs). This links Capture Beta → Plans; sequencing is a later discussion.
**Gate:** round-trip property test (trip → plan → file → import → identical plan); fork lineage preserved; diff report correct on fixture (planned 6 stops, drove 5 + 1 extra → report says exactly that). **This gate = POC complete.**

### Phase 7 — Backend & Community (post-POC, only if Phase 6 telemetry says people fork)
Scope: Supabase auth (Sign in with Apple), publish plan → public web page (Next.js or Supabase edge-rendered) with map + "Open in app" fork button, PostGIS storage, route browse/search by region. Web page is the SEO/discovery surface ("best Perth to Albany road trip route" queries).
**Gate:** defined later; do not design now.

**Estimates (revised 2026-07-20).** The near-term release is the **Replay MVP** (through Phase 3.5) — the remaining MVP build is import + substrate + theme + follow-cam + photo deck, then the three-trip dogfood day. **Story Director** (Phase 4) and **Capture Beta** (Phase 5) follow the MVP; Plans (6) and Backend (7) after. Budget calendar time for the Replay MVP device day (Chiu's iPhone + three real past-trip photo sets) and, later, for Capture Beta's several ordinary days carrying the phone with a trip armed.

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
| ~~MKMapSnapshotter too slow/plain for video~~ **Materialized 2026-07-19** — owner rejected the Apple-tile look outright | — | Recap substrate replaced: MapLibre + self-hosted vector tiles, Phase 3.5 (ADR 2026-07-19). Keyframe + crossfade rendering strategy survives unchanged. |
| Kamome style sheet fails the §4.5 quality bar (MapLibre output not clearly better than Apple Maps for replay) | Medium | Side-by-side design review during the Replay MVP before theme work is declared done (a checkpoint, not the release gate — §4.5); iterate style JSON (cheap — no code); if the bar proves unreachable, revisit the substrate ADR rather than shipping a mediocre look. |
| Imported recap read as recorded fact (route reconstructed from photos mistaken for a verified GPS trip) | Medium | Honest provenance is a product rule (§3/§6): `trip.source` badge on S1/S3, "reconstructed from photos" copy, inferred legs drawn dashed; never "Verified Trip". A wrong-road or sea-crossing inference must read as inferred — the Replay MVP gate rejects gross fabrication. |
| Self-hosted vector tiles add ops/size burden | Medium | PMTiles = single static file per region, no tile server; regional extracts only (TW ≈ 100 MB OSM, matching OSRM's footprint); tile generation is a documented offline step (`Docs/vector-tile-pipeline.md`), not runtime infrastructure. |
| App Review rejects background location | Low-Med | Tracking only during explicit trips, review notes + video, honest purpose strings. |
| Passive tier fidelity: SLC too sparse, or matcher snaps to the wrong parallel road | Medium | Confidence gating + "inferred" rendering; per-trip high-fidelity opt-in; tune against real multi-day wear at the Capture Beta gate (Phase 5) — not an MVP concern. |
| Fork loop needs a network no solo dev has | High (business risk, not tech) | `.kamome` file works peer-to-peer day one; build-in-public content channel is the distribution hedge; Phase 7 web pages capture search traffic. |
| Scope creep toward Polarsteps parity | High | §1.4 is a contract. New feature ideas go to `Docs/icebox.md`, not the sprint. |
| Name/IP conflict (Kamome trademark; 《快樂的出帆》 music rights) | Low-Med | Trademark search (App Store, TIPO, JPO) before bundle-ID lock; name inspiration only — zero lyrics/melody anywhere. |

---

## 10. Success Criteria (staged to the phase map, §7)

Decisions are staged: the **Replay MVP** release is judged first, **Capture Beta** and the fork bet later. Restructured 2026-07-20 — the old "passive-capture v1" criteria moved to Capture Beta, not deleted.

### Replay MVP — release-candidate gate (Chiu, before any TestFlight)
The §7 Phase 3.5 hard gate, restated as the go/no-go: three real past trips of **different character** each go **photos → import → route reconstruction → recap → MP4 → share, entirely in-app** — no DB edits, no repo-external tools; routes are honest (no gross sea/mountain/wrong-road fabrication; low confidence shown as inferred); all three films are ones Chiu wants to keep and share; **≥ 1 published publicly** without external editing; limited-photo path passes on device; stable export on a real iPhone (no crash, acceptable memory); per-trip export time recorded and product-acceptable. The bar is **"worth publishing," not "prettier map."** "Three trips" is hard — never downgraded to one.

### Replay MVP — market validation (after TestFlight / public demo)
- ≥ 5 of 10 testers **import a past trip from photos** in their first session (the cold-start hook working).
- ≥ 3 recap videos **voluntarily shared** by testers.
- ≥ 1 payment signal for HD / no-watermark export (fake-door price probe is fine at this stage).
- Tester pool: recruit at least half from Taiwan 環島 / road-trip communities so localization and scooter mode get real coverage.

### Capture Beta — success criteria (the old "passive-capture v1" bar, moved here; **not** MVP criteria)
- ≥ 7 of 10 testers complete a real trip with **zero mid-trip interaction** (not just zero mid-drive).
- Battery complaint count: 0; passive-tier drain < 1%/day on tester devices.
- Chiu's own verdict after using the passive tier on the Feb 2027 WA trip — the ultimate *capture* acceptance test (the recap quality is already validated at the Replay MVP gate).

### Phase 6 continue/kill (the fork bet, decided only after the video product proves sharing)
- ≥ 1 organic fork (someone saves & gets someone else's `.kamome`).

---

## 11. Handoff Checklist & Kickoff (added v1.2)

### 11.1 Human prerequisites — Chiu does these once, Claude Code cannot
1. **Mac with Xcode 16+** and command line tools; a **physical iPhone** with a cable (needed from Phase 1 gate onward).
2. **Apple Developer:** free personal team is enough for most of the Replay MVP (7-day dev provisioning). Paid Program (US$99/yr) is required at the **Replay MVP TestFlight** (Phase 3.5 gate) — the first time the cost is unavoidable.
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
One phase-gate per PR; review diffs before merging (you are the second pair of eyes the solo project otherwise lacks). The **Replay MVP** device day needs Chiu's iPhone plus **three real past-trip photo sets** (import → recap → MP4 → share on device); the **Capture Beta** gate later needs your car (2 h drive) and several ordinary days of carrying the phone with a trip armed — schedule them like sprint reviews, not afterthoughts.
