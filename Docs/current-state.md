# Kamome — current state

A compact snapshot of the project TODAY. This is an **index**, not a fourth
source of truth: every claim carries a pointer, and the pointed-at document wins
on detail. Created 2026-08-21 by the documentation-governance pass
(`Docs/_archive/audit-2026-08-21.md`).

## Staleness protocol

Last synced: 2026-09-04 against decisions.md **2026-09-04** and `main` at
**PR #35**. Re-synced by the type-2 opening-retime session across its PO review:
the ledger tail, every `HANDOFF.md` line and every *Blockers* line were re-read.
*Active work* gains the retime and the plane; *Blockers* gains the
`Geo.distanceM` finding; the `crossing_beat_s` 6.0 claim was corrected wherever
it appeared.

✅ **This is checked now, not remembered** — `Scripts/check-staleness.sh`, in
every `./check.sh` run (ADR 2026-09-02 (b)).

⚠️ **On `main` this line reads exactly one PR behind, and that is correct.** The
line is written inside a PR that is not yet merged, so it can never name the PR
containing it — #20 named #16, #27 named #26, #29 named #28. **The check
therefore runs on the branch, before the merge**, which is the only place the
rule is satisfiable. **Two behind is a real failure**, and that is what happened
on 2026-09-01. Do not "fix" a failure by bumping the number: the line claims
someone re-read the ledger and `HANDOFF.md` and brought *Active work* and
*Blockers* up to date, and that is the half that rotted twice while the number
was right.

⚠️ **The protocol gained a second half on 2026-08-30, because the first half was
not enough.** It used to key on the ADR ledger alone, so this file could pass its
own check while its *Active work* and *Blockers* sections were weeks out of date.
That happened twice: on 2026-08-28 ("Last synced: 2026-08-21" matched the newest
ADR exactly while the three visual checks were still called "NOT YET RUN" after
they had run and merged), and again on 2026-08-30, when the 2026-08-29 re-sync
passed the check while leaving three blocker lines that `HANDOFF.md` had already
closed. **A check that certifies only the decisions half will keep passing while
the state half rots.**

So "Last synced" now names **two** things, and both must be true:

1. the newest entry in `Docs/decisions.md`, and
2. the newest **merged PR** on `main` (`gh pr list --state merged --limit 1`).

If either is behind, this file is STALE. `Docs/decisions.md` wins on decisions,
`HANDOFF.md` wins on live findings and blockers, and the session must report the
staleness before proceeding.

This file MUST be updated when any of the following occur:
- a new entry is appended to Docs/decisions.md
- **a PR merges to `main`** — added 2026-08-30
- the current phase changes
- the Product Owner makes an explicit decision that changes anything above

## Product

Kamome (卡摸咩) is a **memory engine for road trips**: import (or later,
capture) a journey once, then turn it into a cinematic recap film (MP4) worth
keeping and sharing. Not a GPS visualizer (spec §0 rule 6). Reference:
`Docs/kamome-poc-spec.md` v1.8; north star in `PO.md`.

**No release is in flight.** The current work proves the *artefact* — films
worth keeping — deliberately ahead of productisation (Chiu 2026-08-15,
`Docs/decisions.md`). The next release target is Phase 2 (App Store), gated by
`Docs/pre-launch.md`; nothing there blocks Phase 4.

## Current phase

**Phase 4 — films worth keeping** (opened 2026-08-15, `Docs/decisions.md`):
1. ✅ Vehicle sprites (top community request) — shipped PR #15, 2026-08-20.
2. Cross-region flight/crossing display (`Docs/cross-region-journeys.md`;
   camera design decided-to-recommend in `Docs/camera-arcs.md`). **Live.**
3. ~~Export that survives~~ — **dissolved 2026-09-02** (ADR). Its film-quality
   half (the shake) closed with ADR 2026-08-31 (b); its release half is
   `Docs/release-readiness.md` D1–D3. Both documents tracked it under two names,
   which is why "is item 3 done?" had no single answer.

⚠️ **Phase 4 has no hard gate and none is to be written** (ADR 2026-09-02,
amending `CLAUDE.md` rule 7 **for Phase 4 only**). It closes when Chiu judges a
film good enough to release. Do not propose a checklist for it.

**Explicitly closed:** Phase 3.5 (Replay MVP) closed 2026-08-15 — §6a passed,
§6b did NOT pass; its six unmet items moved to Phase 2 (`Docs/pre-launch.md`
"§6b six"). Do not reopen 3.5. Phases 0–3 done. P5 Capture Beta / P6 Plans /
P7 backend deferred.

## Current architecture

- **Story ↔ Rendering separation** (`PO.md` Core Principle): the story layer
  never depends on the rendering substrate.
- **Rendering:** `RecapSnapshotProviding` is the boundary; each renderer is
  confined to one file. **In practice the app renders Apple Maps** — MapLibre
  is parked, not removed (ADR 2026-08-15); the provider fallback fires because
  no `.pmtiles` region is installed.
- **Routing:** `RouteProvider`-shaped boundary; provider is **Geoapify** (ADR
  2026-08-20 (a)), migrated in PR #16 (`e366df2`), API key behind a
  Cloudflare Worker (`556f828`). Detour-ratio gate (2.5) carried out of the
  provider file; no snap radius exists or is needed (ADR 2026-08-20 (d)).
  Routing is bounded (`matching.trip_budget_s` 120, measured — `1cedbd2`),
  cancellable, and reports which of four failure causes dashed a film (ADR
  2026-08-15).
- **Camera:** `FollowCamera` dead-zone dolly, pre-simulated; one span per trip;
  opening/ending beats per `CLAUDE.md`-era ADRs (2026-08-02 → 2026-08-09). Two
  continuity gates (`RecapCameraContinuityTests`) — never relax them.
- **Config:** no magic numbers; all tunables in `Config/TrackingConfig.json`.
- **Infrastructure:** `.xcodeproj` generated by `xcodegen` from `project.yml`;
  env-gated harnesses via `TEST_RUNNER_` build settings declared in
  `project.yml`; `Deploy/` (self-hosted OSRM + tiles) kept dormant as fallback.

## Locked decisions a fresh session needs

- **The division of labour** (ADR 2026-09-02, Chiu's words): **Chiu owns whether
  the film is good enough**; **engineering owns that the code does not break and
  that a release carries no security, licence or privacy fault.** The consequence
  for a session: you may not answer "is this ready?" with a film — answer with the
  gates, and where a gate does not exist, say so instead of reasoning about the
  property. Your half is `Docs/release-readiness.md`.

- **§0 privacy principle, as amended** — location data never leaves the device
  by default; the decided exceptions are routing payloads to Geoapify (ADRs
  2026-08-16, 2026-08-20 (b)/(c)); honest disclosure is the posture
  (`Docs/pre-launch.md` item 7). Anything further is Chiu's decision.
- **MapLibre parked, Apple Maps ships** (ADR 2026-08-15). Pixel Art and map
  labels parked with it. Reopening condition is Chiu's, verbatim in the ADR.
- **The film follows the device's system appearance** (ADR 2026-08-27), one
  `RecapAppearance` selecting both the map's trait and the overlay palette,
  captured at export and never read inside the render loop. A **manual picker is
  deferred** — do not build one. The light trail is `RecapStyle.routeAccent`
  `#FF8A5B` and the glow is off in both appearances (Chiu 2026-08-29).
- **Routing is Geoapify** (ADR 2026-08-20 (a)–(d)); detour gate stays 2.5. The
  Iceland film was the acceptance test and **it passed** — Chiu judged the 49
  solid legs correct (owner report, 2026-08-21), closing ADR 2026-08-20 (d)
  item 4. The film is `~/Kamome-films/2026-08-21-iceland-geoapify.mp4`, outside
  the repository deliberately (§0).
- ~~**Snapshot numbers frozen**~~ **LIFTED 2026-09-01 — the freeze's subject no
  longer exists.** The 2026-08-15 freeze held `keyframe_interval_frames` (15) and
  the opening's every-frame interval until Chiu judged the camera-arc Pass 1
  render. He judged it and it merged (PR #26) — and crop-scaling **removed the
  key's last shipping reader** (VERIFIED 2026-09-01: `keyframeIntervalFrames`
  survives in `Core`/`UI`/`App` only inside a past-tense comment in
  `RecapRenderLoop`). Snapshots are now planned by `RecapSnapshotStations`, and
  the two tunables that matter are `snapshot_station_max_magnification` (1.1) and
  `snapshot_station_padding` (1.03). ⚠️ **`keyframe_interval_frames` is now dead
  config** — same class as `route_waypoint_radius_m`. Do not tune it expecting an
  effect; see `HANDOFF.md` for the test that may still be measuring it.
  ⚠️ **There are three such keys, not two** — `export.total_duration_max_s`
  joined them (VERIFIED 2026-09-02, `Docs/release-readiness.md` C1), and it is
  the dangerous one: film duration is an open question and that key is the first
  thing anyone would reach for.
- **Variant B (shipped `highlight` mode) is not to be tuned**; Variant A is
  harness-only env overrides, never config edits (memory + HANDOFF archive).
- **Film duration must scale with trip size — direction decided, rule NOT**
  (Chiu 2026-08-14, `HANDOFF.md`). Do not implement the candidate rule as if
  settled.
- **The subject is 157.5 px and the mark is pinned at `length_fraction` 1.0**
  (ADR 2026-08-27 (b)). ⚠️ That pin **spends** the relational guarantee `cb14ae8`
  built the fraction for: next time `subject_length_px` moves, the mark follows at
  full rate and its size becomes a fresh judgement.
- **The fallback marker is a badge, not a bare bird** (ADR 2026-08-29): one
  `#1D6FE0` disc with a white ring and gull, **the same in both appearances**, at
  `fallbackMarkerLengthFraction` **0.60** of the subject. The bare
  `VehicleMarker.seagull` stays the **end-card brand mark** and the future
  cross-region narrator — three gull objects, do not restyle in place.
- **The opening cuts out of a title card, and that card is held over the
  COUNTRY** (ADR 2026-08-31): country name and place name as **text**, the cut
  lands *as the title leaves*, and beat 2 onward is the film proper — continuous,
  no cuts, and its frame is a picture never a label. The country's extent comes
  from a **built-in table** (`CountryExtent`), not from MapKit or `CLGeocoder`:
  a geocoded lookup would send a real coordinate off-device to draw a wider
  opening, and Chiu declined to open a §0 exception for framing.
- **Kamome's films are three types; 1 and 2 ship, 3 is deferred** (ADR
  2026-09-01). **The film ends at the destination — there is no return flight.**
  A film's type is *distinct local journeys*, folding a return to a region already
  visited — never crossings (a round trip has two) and never countries (a domestic
  flight has one).
- **Camera shake / ghosting: CLOSED** (ADR 2026-08-31 (b)) — the loop reprojects
  one snapshot instead of cross-fading two. Frame-to-frame swing 1.402 → 0.747,
  stop beats pixel-exact.
- **The user names the trip; recording ships behind a beta marker**
  (ADR 2026-08-30). Neither is built yet. `Trip.title` already exists and already
  reaches the title card — what is missing is an edit surface, not a schema.
- **Reindeer sets are choosable subjects**, not crossing art (2026-08-20 (3d),
  `HANDOFF.md`).
- **Honest provenance** — never "Verified Trip"; recorded vs
  reconstructed-from-photos is a product rule; a wrong road is never drawn as
  fact (spec §0, v1.8 §4.4.1).

## Active work

**One live line: the type-2 film form** (ADR 2026-09-01). Everything else below
is closed.

- ✅ **Type 2 — home → one destination abroad — is BUILT and judged** (PR #31).
  The type is **derived, never stored**. The measurement it was gated on came
  back: **MapKit saturates at ~109° of longitude**, so a long-haul frame often
  does not exist and Taiwan→Iceland fails at every padding — the frozen country
  card is a **main path**, not a fallback. ⏳ Three things were handed over rather
  than defaulted, and the 70 threshold is **Chiu's to decide**.
  → `Docs/handoff-type2-films.md` closeout, `HANDOFF.md`.
- ✅ **The type-2 opening is RETIMED and the crossing carries a boarding pass**
  (2026-09-03, ADR **2026-09-03**). `crossing_beat_s` is **4.0, not 6.0** — the
  beat is no longer a screen-speed choice, it is how long the **Journey Card**
  takes to read. Measured: the trip starts at **13.09 s** (was ~16), the
  departure airport shows **2 photographs for 3.59 s**, the sprite runs
  **24.6 %/s**, and the odometer reads **269 km** where it read 9,024. ⏳ **Chiu
  judges the films**.
  → `Docs/handoff-type2-opening-retime.md`, `Docs/design-reviews/2026-09-02-cross-region-opening.md`.
- ✅ **The pass is laid out to Chiu's own mockup, the crossing flies a plane, and
  the flight's two ends are marked** (2026-09-04, ADR **2026-09-04**). One
  condition decides the pass and the airframe; every other crossing keeps the
  seagull. The two end marks answer the closeout's *"the wide flight frame loses
  the viewer"* — `crossing_flight_max_longitude_deg` **stays 70** and the map
  place-names icebox **stays frozen**, because the marks carry no text.
  Each mark carries **its country's name**, from the value the pass already
  resolved. 🔴 **Neither place-name lock is thawed** — the base map still draws
  nothing, and the icebox entry is a whole-film narrative system, not two
  endpoints. 🔴 **Known boundary: no classifier, so a ferry gets the pass and the
  plane too.** ⏳ `subject_length_px` deliberately unchanged; Chiu judges the form
  first. ⏳ **Four visual questions are with the designer**
  (`Docs/design-reviews/2026-09-04-open-questions-type2-opening.md`).
- ⏳ **Open and Chiu's, all waiting on a film rather than a session**: the
  long-haul flight frame's 70 threshold (above); the title card's text, which still shows
  trip title + dates rather than the country name (a DESIGNER question); the
  badge's 0.60 size (ADR 2026-08-29); the residual 0.747 sharpness step at hold
  boundaries (ADR 2026-08-31 (b) — accepted as it stands).
- 🧊 **Deferred by name, not forgotten**: the crossing **mode classifier**
  (plane / ship / seagull — crossing session 2 of 2), and **type 3**,
  multi-region films (ADR 2026-09-01 — a loop over type 2, not a new mechanism).
- **Pre-launch list** (`Docs/pre-launch.md`) stands as the submission gate, but
  `Docs/release-readiness.md` is the thing you read to find out where the release
  stands (ADR 2026-09-02 §3). Item 2 is the crossing beat, **now built**; item
  3's shake is **closed** (ADR 2026-08-31 (b)); items **6 and 7 — attribution and
  the privacy notice — are built** (2026-09-02, `release-readiness.md` S2/S3),
  with their wording and placement still Chiu's. What is left there is **device
  verification** (D1–D5) and Apple's App Privacy questionnaire. The export-time
  estimate's benchmark was re-derived in PR #30; the device figure is still owed.
- **Pull requests** — read live state with `gh pr list`, never from this line.

## Blockers / risks

*Closed items are removed rather than struck through; the ledger keeps the
history. Trimmed 2026-09-01.*

- 🟠 `KamomeCore_KamomeExportEngine` **subject lookup misses silently** — the
  `fatalError` was removed 2026-08-15 (`b44a7fc`), so it no longer crashes; the
  same miss now degrades a film without saying so. A diagnostic shipped
  2026-08-29 to name the next occurrence. Rate and trigger **UNKNOWN**.
  `Docs/handoff-subject-lookup.md`.
- 🟠 **MapKit rastered at 3× when asked for 2×, once, and nobody knows why.** Not
  reproduced across 18 probe snapshots. It cannot misproject — the correction
  factor is the requested scale by construction — but a **non-uniform** raster
  would abort an export at the guard. Trigger UNKNOWN, deliberately unchased.
- 🟠 **The routing key is still inside every IPA.** The Worker is deployed and
  serves keyless (2026-08-29), but `matching.base_url` is still `""` and
  `api_key_required` still `true`, so builds call Geoapify directly. Nothing has
  changed for builds already on other people's phones.
- 🟡 **No spend ceiling exists anywhere.** VERIFIED from Geoapify's own pages:
  limits are **soft** on every tier, there is no customer-settable cap, and the
  escalation ends in **account blocking** — so the worst case is every user
  losing routing until Chiu resolves it with the provider by hand. The only
  ceiling that can exist is a per-day counter in Kamome's Worker, and it lands
  **with or before** the app-side wiring (`Docs/pre-launch.md` item 5).
- 🐛 **The import date range clips at timezone edges** — known, deliberately not
  fixed; workaround in `Docs/handoff-known-bugs.md`.
- 🟠 **`Geo.distanceM` is equirectangular and every camera quantity rides on it**
  (VERIFIED 2026-09-03). Over Taipei → Auckland it is **121 km short**, which is
  where the 8,755 km in `Docs/handoff-type2-films.md` came from. Harmless for the
  camera — one consistent axis — and **not** harmless for a printed figure, so
  `Geo.greatCircleM` was added beside it and the Journey Card uses that. ⚠️ No
  sweep has been done for other places a `Geo.distanceM` result reaches a
  viewer. → `HANDOFF.md`.
- ⚙️ **Two sessions sharing one checkout contaminate each other's test and lint
  counts**, and **six concurrent `xcodebuild` processes against one simulator
  killed six renders and were nearly recorded as a machine fault**
  (ADR 2026-08-31 (b)). Run one render at a time, and confirm your branch and
  your distance from `origin/main` before trusting anything on disk.

## Deferred — do not implement opportunistically

- MapLibre substrate work, tiles, tile server, map labels, Pixel Art (parked,
  ADR 2026-08-15).
- Story Director's remaining content: hero photos, chapters, music, video beads.
- Transit routing — handled as a crossing beat, never a road profile (spec
  v1.8 §4.4.1); walk-narrowing for recorded trips parked to Capture Beta
  (ADR 2026-08-20 (c) tail).
- The duration rule's candidate formula; the travel-pacing tunable
  (`Docs/handoff-pacing.md` — experiments, nothing decided).
- Per-act / per-segment camera framing (rejected 2026-08-02; see
  `Docs/_archive/handoff-camera-arc-findings.md` finding 5 for the one sanctioned
  derivation change).
- iCloud original fetching (option B); "Place names as narrative rhythm"
  (`Docs/icebox.md`).

## Authoritative sources (when two disagree, the higher wins; newest wins within a level)

| what | where |
|---|---|
| Product intent & rules | `Docs/kamome-poc-spec.md` (v1.8 — reference, not status) |
| Decisions (append-only ledger) | `Docs/decisions.md` — newest entry on a subject wins |
| Current state | this file; `CLAUDE.md` (boot, 80-line budget); `HANDOFF.md` (live index, 300-line budget, pointing at `Docs/handoff-*.md`) |
| Rule rationale | `Docs/rule-rationale.md` — the incident behind each `CLAUDE.md` rule |
| Finding an ADR | `Docs/decisions-index.md` — one row per ledger entry |
| Governance / conduct | `PO.md` (product-owner charter), `Arch.md` (engineering) |
| Release gate | `Docs/release-readiness.md` — supersedes `Docs/pre-launch.md` as the gate; `pre-launch.md` keeps the reasoning and the accepted risks |
| Task docs | `Docs/camera-arcs.md`, `Docs/cross-region-journeys.md`, `Docs/eng-session-*.md` (each carries a status line; **no new ones** — ADR 2026-09-02 §6) |
| History | `Docs/_archive/handoff-2026-08.md`, `Docs/decisions.md` entries, `Docs/demos/`, `Docs/device-test-*.md`, `Docs/prototype/`; bannered-in-place legacy docs (kept for inbound citations): `Docs/handoff-P3.5.md` (§6 item definitions stay authoritative), `Docs/handoff-recap-visuals.md` (§3 sprite constraints stay authoritative), `Docs/handoff-render-layers.md`, `Docs/kamome-animation-vision.md` (vision, substrate parts parked) |
