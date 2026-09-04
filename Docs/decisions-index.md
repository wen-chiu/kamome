# `Docs/decisions.md` — index

One row per ADR, newest last, in ledger order. **This is a finding aid, not a
summary**: the ledger is the decision, and the newest entry on a subject wins
over any older entry, any handoff, and `CLAUDE.md`.

Use it to find the entry to read. `Docs/decisions.md` is ~2,300 lines and is
never read whole; grep the title from the row you want.

**The "superseded / amended" column is not a currency claim.** A cell is filled
only where the repository states the relationship explicitly, and it carries the
citation. An empty cell means *this pass found no supersession statement* — it
does **not** mean the entry is current. Establishing that for all 54 entries was
not done here.

`Scripts/check-decisions-index.sh` fails if the ledger gains an entry this file
does not.

| # | date | subject | superseded / amended |
|---:|---|---|---|
| 1 | `2026-07-12` | GRDB 6.x, not 7.x |  |
| 2 | `2026-07-12` | Core code lives in a root SwiftPM package (KamomeCore) |  |
| 3 | `2026-07-12` | `kamome-smoke` executable mirrors the Phase 0 gate tests |  |
| 4 | `2026-07-12` | Generated `.xcodeproj` is gitignored |  |
| 5 | `2026-07-12` | postGenCommand downgrades project format for Xcode 15.4 | superseded by 2026-07-14 (`decisions.md`:78) |
| 6 | `2026-07-12` | Phase 1 device-test gate deferred (owner decision) |  |
| 7 | `2026-07-14` | Xcode 26.6 upgrade: objectVersion workaround removed |  |
| 8 | `2026-07-12` | S4 photo reorder deferred (needs schema v2) |  |
| 9 | `2026-07-12` | Walk threshold raised to 6 km/h; mid band is non-evidence |  |
| 10 | `2026-07-12` | Derived speeds use a 30 s displacement baseline |  |
| 11 | `2026-07-15` | Dwell resume via CLLocationManager region monitoring, not CLMonitor |  |
| 12 | `2026-07-12` | Config loader module is `Core/ConfigLoader`, not `App/` |  |
| 13 | `2026-07-15` | Spec v1.3: battery-moat pivot (passive tier, import; fork deferred) |  |
| 14 | `2026-07-16` | Phase 3 starts now; device drive + photo-access check become P3 gate items |  |
| 15 | `2026-07-18` | Speed evidence gated by accuracy; geocoded names need address context |  |
| 16 | `2026-07-17` | Recap video: route photos in, export gets a photos toggle, video clips parked |  |
| 17 | `2026-07-18` | Fork demoted from positioning language to mechanism |  |
| 18 | `2026-07-18` | Stop detection redesigned around real stops: streaks, walk visits, silence gaps |  |
| 19 | `2026-07-18` | Recap chrome: photos toggle gates stop cards only; title/end cards always render |  |
| 20 | `2026-07-18` | stop.kind = what happened, never how it was detected |  |
| 21 | `2026-07-19` | Recap visual pivot: P3 frozen as pipeline milestone, Phase 3.5 opened |  |
| 22 | `2026-07-19` | ADR: recap substrate = MapLibre Native + self-hosted vector tiles | substrate parked 2026-08-15 (`PO.md`, Locked Decisions) |
| 23 | `2026-07-19` | Drive finding: region-resume died after wake; recovery watchdog added |  |
| 24 | `2026-07-19` | Owner call: continue into Phase 3.5 while P3's device items stay open |  |
| 25 | `2026-07-19` | §4.4 map matching: app side landed, server-side deferred to setup doc |  |
| 26 | `2026-07-20` | Recap visual system validated on real data via a web prototype |  |
| 27 | `2026-07-20` | Replay MVP repositioning: photo-import recap ships first; capture → Capture Beta; Story Director & Plans deferred; honest provenance |  |
| 28 | `2026-07-21` | Replay MVP §2: MapLibre substrate landed (provider in app target, pmtiles ingestion, MapKit kept alive) |  |
| 29 | `2026-07-21` | §3 Modern Minimal: kicked off as a DRAFT (visual sign-off is Chiu's, on a real render) |  |
| 30 | `2026-07-22` | pmtiles ingestion CONFIRMED in-sim: `pmtiles://file://`, MapLibre renders in the simulator |  |
| 31 | `2026-07-22` | §3 visual direction corrected: dark atmospheric souvenir map (not pale "Modern Minimal") |  |
| 32 | `2026-07-22` | §3 signed off as the substrate; recap-output redesign moved to its own session |  |
| 33 | `2026-07-23` | Follow-cam camera core: wide-to-close framing, camera ≠ vehicle |  |
| 34 | `2026-07-31` | Stop presentation ported from the prototype's CSS, and the stop group flips as one cluster |  |
| 35 | `2026-07-31` | Day and distance become persistent HUD, not stop chrome |  |
| 36 | `2026-08-06` | Stop presentation is budget-constrained — derive the count, never assume one |  |
| 37 | `2026-08-08` | MVP substrate is OSRM + MapLibre, behind swappable boundaries | **amended by 2026-08-15** (`decisions.md`:1314) |
| 38 | `2026-08-09` | The recap camera: a configured zoom, and a wider establishing shot |  |
| 39 | `2026-08-13` | The Replay MVP gate splits: §6a the film (desk, Variant A), §6b the product (phone, Variant B) | closed by 2026-08-15 (Phase 3.5) |
| 40 | `2026-08-15` | Phase 3.5 closes: §6a passed, §6b did not, and the phase map catches up |  |
| 41 | `2026-08-15` | MapLibre is parked, Apple Maps is what ships, and routing moves behind an API |  |
| 42 | `2026-08-15` | Routing is bounded, cancellable, and says which of four things went wrong | provider chosen in 2026-08-20 (a) |
| 43 | `2026-08-15` | Export variation enters as a seed, never as randomness |  |
| 44 | `2026-08-16` | Routing moves to a commercial API's free tier, and real coordinates leave the device | provider chosen in 2026-08-20 (a); §0 exception stands |
| 45 | `2026-08-20` | Geoapify is the provider, and **two** policies must survive the migration | **snap-radius text corrected by 2026-08-20 (d)** (`PO.md`) |
| 46 | `2026-08-20 (b)` | Geoapify's terms, read; and what Kamome now commits to on privacy |  |
| 47 | `—` | Chiu's decisions, 2026-08-20 |  |
| 48 | `2026-08-20 (c)` | The terms risk is accepted; traces are sent; the notice must say what is actually sent |  |
| 49 | `2026-08-20 (d)` | The snap radius was the wrong mechanism, and it was never guarding what I said |  |
| 50 | `2026-08-21` | The Iceland film passed: the Geoapify migration is accepted |  |
| 51 | `2026-08-27` | The film follows the device's system appearance, and light gets a warm trail |  |
| 52 | `2026-08-27 (b)` | The subject shrinks 30%, and the mark's fraction is spent doing it |  |
| 53 | `2026-08-29` | The fallback marker becomes a badge, and it is one badge for both appearances |  |
| 54 | `2026-08-30` | The second round of outside feedback: shake is a P0, the film gets a frame, and the trip gets a name |  |
| 55 | `2026-08-31` | The opening cuts out of a title card, and the frame it cuts out of is the country |  |
| 56 | `2026-08-31 (b)` | The P0 is closed: the loop reprojects one snapshot instead of cross-fading two |  |
| 57 | `2026-09-01` | Kamome's films are three types, and the film ends where the trip does |  |
| 58 | `2026-09-02` | Phase 4 has no hard gate: Chiu judges the film, engineering guarantees the rest | **amends `CLAUDE.md` rule 7 for Phase 4 only** |
| 59 | `2026-09-02 (b)` | The staleness protocol could never be satisfied, and it is a check now | **corrects the diagnosis in 2026-09-02 §6** |
| 60 | `2026-09-03` | The crossing beat is 4.0 s because that is how long a boarding pass takes to read | **re-decides `crossing_beat_s` 6.0 from 2026-09-02; amends `Docs/handoff-type2-films.md`'s closeout** |
| 61 | `2026-09-04` | The crossing flies a plane, and its two ends are marked and named | **reclaims `cross-region-journeys.md` requirement 2; answers the closeout's handover item 1; thaws neither place-name lock** |
