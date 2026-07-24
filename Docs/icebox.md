# Icebox — ideas deliberately not in the current sprint (spec §1.4/§9)

Entries move out of here only via a spec version bump.

## Creator b-roll export (post-v1 wedge candidate)
Travel creators pay for tools and their shares self-advertise. But they want
**material control, not finished TikToks**: 4K, transparent-background,
speed-adjustable map-animation b-roll that drops into their own edit. Higher
price point than consumer per-trip export (§1.6). Do not build a template
library for them.

## Group trips (v2 at the earliest)
Merging several phones' tracks into one recap is genuinely viral, but sync +
merge + everyone-must-install is a cold-start and infra trap for a solo dev.
Revisit only after fork loop (Phase 6) proves organic sharing.

## Auto trip detection (arm-nothing capture)
Passive tier v2: detect trip start with zero user action (first SLC fix far
from home region → "looks like you're on a trip — recording?" notification).
Needs the Capture Beta tier proven first; also raises the App Review bar (§6 —
current posture is "only between explicit Start/End").

## Google Timeline importer — dropped as redundant (owner 2026-07-20)
Was Phase 4 scope; cut. Photo-EXIF import already reconstructs *past* trips and
in-app capture (Capture Beta) covers *new* ones, so a Timeline parser adds
Google-export format-drift maintenance for little unique value. The
`imported_timeline` `trip.source` value stays reserved for forward-compat only.
Thaw only if real user demand for Timeline import appears. (`decisions.md`
2026-07-20 Replay MVP repositioning.)

## Subscription vs. transactional — decided, kept for the record
$4.99/mo subscription dies of churn at 2–4 trips/year usage. Transactional
per-trip export + yearly unlock-all + creator tier is the model (§1.6).

## Premium video styles / fork-count analytics
From spec v1.2 §1.6 — still parked.

## Video clips in the recap (post-P3-gate candidate)
Auto-excerpt short clips from videos the user shot mid-trip and play them at
their stop's hold (the clip replaces the photo card; the hold stretches to
clip length, still counted inside `export.max_hold_fraction`). Fits the
minimum-effort vision — zero editing by the user. Hard constraints when
thawed: **deterministic** excerpt selection (seed by trip id; §4.5 is a
deterministic frame pipeline with golden-frame tests, and re-exporting must
reproduce the same video), 2–3 s per clip (tunable), muted (consistent with
the no-music call), cap clip count. Blocked on: §4.5 steps 2–5 landed and the
<90 s render budget measured — per-frame video decode + composite is the
single biggest render-cost risk in the whole pipeline. (Decision record:
`decisions.md` 2026-07-17.)

**Video as an import source (owner idea, 2026-07-21).** The same clip bead, but
sourced from the *import* flow, not just recorded-during-trip: geotagged
**videos** (`PHAsset` `.video`, which carry `creationDate` + `location` like
photos) should contribute to a reconstructed trip two ways — (a) as ordinary
route points / stop members alongside photos (extend `PhotoLibraryImportSource`
to fetch `.video`, feed `ImportPhoto`-equivalents into the clusterer), and
(b) as a short auto-trimmed bead at their stop, "a little moving moment makes
the whole film more alive" (Chiu). Same determinism / 2–3 s / muted / cap
constraints as above. Sequence: ship the photo import + photo deck first, add
video beads (recorded and imported) after — clips are a multiplier, not the
foundation. This is a **Story Director-era** enrichment (Phase 4).

<!-- Owner journey-scope ideas, 2026-07-21 — all recorded for a later
     "when to pull in" discussion; do not build yet. -->

## Flight legs — airport-to-airport journey framing (owner idea, 2026-07-21)
A trip really starts at the airport, and the flight there is part of the story.
Add an **inferred flight leg**: between two clusters separated by a big spatial
jump over a matching time gap (crosses an ocean/country; e.g. > N km in a plausible
flight window, tunable), draw a plane animating from A to B — a great-circle arc
or a clean straight line — as an **establishing / journey-start** moment, then
again for any cross-country hops mid-trip. Symbolizes "the journey began."

Design notes for the discussion:
- **Honest by construction:** there is no GPS on a plane, so a flight leg is
  *always reconstructed*, never recorded — render it as an inferred style (§4.4
  "inferred", §3 provenance). This is a clean fit for the honesty rule, not a
  violation of it: it is explicitly "we know you flew A→B, we don't know the
  path." Never present it as a tracked path.
- **Detection** rides the existing photo-EXIF jump: the clusterer already sees
  the gap; classify a qualifying jump as a `flight` segment instead of a drive.
  Nearest-airport labeling ("Taoyuan → Haneda") needs a small airport dataset
  (bundled point list — cheap; note the data source).
- **Camera:** this is a **wide establishing shot**, not a follow-cam — a good
  concrete example of "follow-cam is one shot among many, not dogma" (§4.5).
  Story Director-era narrative beat.
- **Schema:** add a `flight` value to `segment.mode`; reuse the plane as a
  swappable marker (ties to the multi-modal icons below).
- Relates to: multi-modal journeys (below), honest provenance (§3), Story
  Director (Phase 4). Likely lands with, or just after, multi-modal.

## Beyond road trips — multi-modal journeys + per-segment mode icons (owner idea, 2026-07-21)
Extend Kamome from **road trips** to **any self-guided trip** (e.g. a Japan trip:
trains, metro, walking, cycling, buses, ferries interleaved). Capture the
different modes + their routes, and in the replay **auto-swap the moving marker
per segment** to the right icon (train / metro 🚇 / bike 🚲 / ferry ⛴ / walk 🚶),
so the animation reads the journey's texture, not just "a car."

Design notes for the discussion:
- **Positioning impact:** this widens the north star from "road trips" to
  "journeys" — a real repositioning, so discuss deliberately before pulling in
  (§1.4 is a contract). It is probably the single biggest scope expander here.
- **Capture (Capture Beta era):** `segment.mode` already models
  drive/scooter/walk/cycle/transit/unknown, and §1.7 has scooter + a transit
  speed heuristic — the model is ready; recording multi-modal fidelity is a
  Capture Beta concern (CMMotionActivity gives walking/cycling/automotive; rail
  via the speed heuristic). For *imported* (photo) trips, per-segment mode is a
  coarse guess from speed between clusters — note it will be approximate and
  must stay honest (inferred where unsure).
- **Routing caveat:** trains/metros/ferries do **not** follow the road network,
  so OSRM's car profile won't snap them — they draw inferred, or need a rail/
  ferry network (data cost). Don't force rail onto roads.
- **Rendering:** per-segment mode → marker icon is a `RecapTheme` / overlay-asset
  concern; it generalizes the existing swappable-marker idea (car/seagull/scooter/
  bike, §4.5) from one trip-wide marker to automatic per-segment icons.
- Relates to: flight legs (above, a `flight` mode is the first non-road example),
  Capture Beta (Phase 5), Story Director (Phase 4), themes.
