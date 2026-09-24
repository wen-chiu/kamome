# `Docs/decisions.md` — index

One row per ADR, newest last, in ledger order. **This is a finding aid, not a
summary**: the ledger is the decision, and the newest entry on a subject wins
over any older entry, any handoff, and `CLAUDE.md`.

Use it to find the entry to read. `Docs/decisions.md` is ~2,900 lines and is
never read whole; grep the title from the row you want.

**The "superseded / amended" column is not a currency claim.** A cell is filled
only where the repository states the relationship explicitly, and it carries the
citation. An empty cell means *this pass found no supersession statement* — it
does **not** mean the entry is current. Establishing that for every entry was
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
| 38 | `2026-08-09` | The recap camera: a configured zoom, and a wider establishing shot | Amended by `2026-09-24`: now the rule each camera area applies to itself |
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
| 52 | `2026-08-27 (b)` | The subject shrinks 30%, and the mark's fraction is spent doing it | ⚠️ pin spends the relational guarantee — next size move is a fresh judgement |
| 53 | `2026-08-29` | The fallback marker becomes a badge, and it is one badge for both appearances |  |
| 54 | `2026-08-30` | The second round of outside feedback: shake is a P0, the film gets a frame, and the trip gets a name |  |
| 55 | `2026-08-31` | The opening cuts out of a title card, and the frame it cuts out of is the country |  |
| 56 | `2026-08-31 (b)` | The P0 is closed: the loop reprojects one snapshot instead of cross-fading two |  |
| 57 | `2026-09-01` | Kamome's films are three types, and the film ends where the trip does |  |
| 58 | `2026-09-02` | Phase 4 has no hard gate: Chiu judges the film, engineering guarantees the rest | **amends `CLAUDE.md` rule 7 for Phase 4 only** |
| 59 | `2026-09-02 (b)` | The staleness protocol could never be satisfied, and it is a check now | **corrects the diagnosis in 2026-09-02 §6** |
| 60 | `2026-09-03` | The corpus is cut in half: closed work is archived, and the live set has a ceiling |  |
| 61 | `2026-09-03 (b)` | The crossing beat is 4.0 s because that is how long a boarding pass takes to read | **re-decides `crossing_beat_s` 6.0 from 2026-09-02; amends `Docs/handoff-type2-films.md`'s closeout** |
| 62 | `2026-09-04` | The Worker gets a spend ceiling, and it fails closed | ⚠️ day + burst are complements, not substitutes — do not switch to a Durable Object |
| 63 | `2026-09-04 (b)` | The crossing flies a plane, and its two ends are marked and named | **reclaims `cross-region-journeys.md` requirement 2; answers the closeout's handover item 1; thaws neither place-name lock** |
| 64 | `2026-09-05` | The Worker gets a burst limit, and its no-log property becomes a gate | closes `Docs/release-readiness.md` **S4**; implements the 2026-09-04 re-rating; **retires** that re-rating's named settling test as a null result; **addendum 2026-09-06: deployed and probed, Version `09e248ee`** |
| 65 | `2026-09-05 (b)` | The user is told once, before any coordinate leaves, and the telling is not a question | **answers the question `Docs/release-readiness.md` S3 left open** |
| 66 | `2026-09-05 (c)` | One orange, a plane that reads, a mark that hands over, and a card the map survives | **re-decides `trailOnLight` `#FF8A5B` from 2026-08-29; reverses "the name follows the mark" from 2026-09-04 (b) §3; closes `Docs/design-reviews/2026-09-04-open-questions-type2-opening.md`** |
| 67 | `2026-09-05 (d)` | The end card is the map again: a slight dim, and the summary floating on it | **supersedes 2026-09-05 (c) §4(a) and §4(c); `endChrome` and `RecapTrip.statsLines` change shape; §6 registers its three tuned values against the 2026-09-09 substrate change** |
| 68 | `2026-09-08` | The config flip: the key stops shipping, and the counter is the proof | **Chiu 2026-09-05.** Closes **S6**; opens **S7** (key rotation, which the flip does not do); artifact check owed to Chiu |
| 69 | `2026-09-08` | A finished film becomes a thing that exists | Phase 4 closeout step 1/4; `film` table v5; Photos save is explicit user tap (§0); does NOT settle D1 or D5 |
| 70 | `2026-09-09` | The export substrate leaves Apple Maps: OpenFreeMap + MapLibre, and this round only looks at it | **Chiu 2026-09-09.** Reopens the **2026-08-15** MapLibre park for the export path; opens the **2026-08-15 label lock for evaluation only**, without unlocking it; the §0 shipping question is **deferred**, not answered; **correction 2026-09-10: `MKMapSnapshotter` DOES draw the Apple logo (legal link still absent); `mountain_peak` INFERRED → VERIFIED** |
| 71 | `2026-09-10` | The Phase 4 closeout is four steps, and the last two wait for the substrate | **Chiu 2026-09-10.** Names the four steps (① film record ② export service ③ D1–D5 ④ performance); **defers ③ and ④** behind ADR 2026-09-09 because both price `MKMapSnapshotter`; closes step ②; corrects `ExportLifecycleGuard`'s 270 s / 600 s to a SIMULATOR 65.6 s; does **NOT** settle D1 |
| 72 | `2026-09-12` | Committed Apple Map Data removed from the public repository | Implements ADR 2026-09-09's finding on already-committed artifacts; tombstones satisfy the closed P3 and P3.5 gates; closes the §0 real-trip-films owner question; does **NOT** rewrite git history |
| 73 | `2026-09-12 (b)` | The map credit goes into the film, and this amends 2026-08-17 | **Chiu 2026-09-12. AMENDS the 2026-08-17 "never in the rendered film" decision** — ODbL binds the produced work, which Apple's terms never did; `AboutView` keeps everything it carries. Built on the **MapLibre path only** and draws nothing on MapKit (rule 5 + ADR 2026-09-09). Turns `MLNMapSnapshotter`'s `showsAttribution`/`showsLogo` **off**; does **not** decide the substrate switch |
| 75 | `2026-09-12 (c)` | Third-party licences reproduced in the app | GRDB (MIT) and MapLibre (BSD-2-Clause) licence notices now ship as bundled resources in an Acknowledgements section; `check-attribution.sh` gates every `Package.resolved` pin. Wording and placement are drafts (Chiu's / `DESIGNER.md`). Film attribution not decided |
| 76 | `2026-09-12 (d)` | The routing key has no build path | The `Info.plist` field, `project.yml` mapping, and xcconfig include are **removed** — the config flip (ADR 2026-09-08) made the key unnecessary, this makes it unreachable. `check-archive.sh` fails if the field exists. ⚠️ Code cites as "ADR 2026-09-12" (suffix collision with #72) |
| 77 | `2026-09-12 (e)` | The local-network permission is Debug-only | `NSAllowsLocalNetworking` and `NSLocalNetworkUsageDescription` gated behind Debug via a post-build phase; Release ships neither. `check-archive.sh` step 5 gates it. ⚠️ Code cites as "ADR 2026-09-12 (b)" (suffix collision with #73) |
| 78 | `2026-09-13` | The credit's licence position, verified; and the plate gets lighter | **Extends 2026-09-12 (b).** Chiu 2026-09-13: **the string does not change**. VERIFIED against the OSMF Attribution Guidelines + openfreemap.org — the string satisfies OpenFreeMap's mandatory attribution and names OSM acceptably; **ACCEPTABLE KNOWN RISK (Chiu's)**: it does not state ODbL and a film cannot carry the preferred link — the six-character remedy is costed and **must not be implemented**. Records that a platform's centre crop removes the credit entirely, making `marginPx` 34 a floor |
| 79 | `2026-09-16` | The production switch: OpenFreeMap + MapLibre becomes what ships | **Chiu 2026-09-16. Implements ADR 2026-09-09's evaluation conclusion.** Two frozen Liberty styles (dark + light); Apple fallback **removed** (DPLA §2.3/§2.5); `fixedAppearance` nil → ADR 2026-08-27 is true again; new §0 exception: tile fetching sends coordinates to OpenFreeMap; privacy notice updated |
| 80 | `2026-09-17` | The home is journey discovery: the library is read, nothing is saved until a journey is opened | Chiu's brief 2026-09-17. Schema **v6** `trip.discovery_key`; `discovery` config block (all values INFERRED); one geocode per discovered journey is the §0 delta and is Chiu's to keep; app follows system appearance, making 2026-08-27 true on the shipping path |
| 81 | `2026-09-18` | The home and the journey are timelines, and the photographs are evidence inside them | **Chiu 2026-09-18.** A UX correction to 2026-09-17, not an architecture change: hierarchy inverted to TIME → PLACE → EVENT → PHOTO, photo covers removed from Home and the detail, one shared timeline rail, editorial serif for content. Held to the cover-the-photographs test |
| 82 | `2026-09-18 (b)` | Journey Discovery is an added feature in beta; S1 stays the home | **Chiu 2026-09-18.** Restores `HomeView` and `TripDetailView` from `9313573` (reversing the in-place replacement in 2026-09-17 and 2026-09-18); the feature moves to `UI/Discovery/` behind one toolbar button. 🔴 **Reverts the appearance fix with S1**: films are dark again whatever the device — Chiu's to lift |
| 83 | `2026-09-18 (c)` | Before merge: home is never looked up, the welcome card says what leaves, and S1's title is S1's | **Corrects 2026-09-17** (the home geocode is removed; home's country comes from the device region) **and 2026-09-18 (b)** (S1's title had changed). 🔴 Records a conflict between 2026-09-16 (light ships) and Chiu's keep-S1 instruction: S1's `.preferredColorScheme(.dark)` makes the light style unreachable — on `main` already, his call |
| 84 | `2026-09-18 (d)` | The app follows the device's appearance; S1's dark override goes | **Chiu 2026-09-18.** Resolves the 2026-09-18 (c) §4 conflict; amends 2026-09-18 (b)'s byte-identical S1 by one line; 2026-08-27 true again. **Addendum same day: Chiu approves the light style** (closes 2026-09-16 §6 D2) |
| 85 | `2026-09-18 (e)` | Journey Discovery's two open questions are closed | **Chiu 2026-09-18.** `discovery` thresholds ship as INFERRED and are revised from real usage; the stop-name lookup at discovery is accepted as built. Nothing to build |
| 86 | `2026-09-18 (f)` | A terrain source is credited in the film only where its licence requires it | **Chiu 2026-09-18.** USGS/NOAA are public domain → no credit; LINZ, GA, EU-DEM, UK, AT, NO, CA, MX require one → region-conditional credit. The unapproved `USGS/LINZ/GA` string is wrong both ways (EU-DEM missing for Iceland, INFERRED). OSM credit untouched |
| 87 | `2026-09-19` | Kilometres where they can be known; two findings closed; the desk harness routes through the Worker | **Chiu 2026-09-19.** Title card measures the drawn journey when there are no `TripStats` (Home / Trip Detail stay empty by Chiu's choice — showing them needs an interface change); `Geo.distanceM`'s 121 km error accepted; ferry classifier still deferred; `RecapDemoFilmTests` defaults to the shipped Worker, not `api.geoapify.com` |
| 88 | `2026-09-19 (b)` | Reading photos is not downloading them; the film's photos are fetched from iCloud before the render | **Chiu 2026-09-19.** Metadata scan stays pixel-free; previews stay small; after Export, only the film's photos are fetched — local first, iCloud-only after, with progress, timeout and Cancel. Reverses the "iCloud original fetching" deferral. INFERRED: derivative size; UNKNOWN: peak memory |
| 89 | `2026-09-23` | Trip Detail's provenance note and films row move onto the map; a coordinate is never a stop name | **Chiu 2026-09-23.** Provenance note → S1 badge chip + popover (2026-07-20 still met, not reopened); films row → 64 pt poster, format/date/size to the player; open-sea coordinate names → ocean or unnamed, and re-queued. INFERRED: `ocean` present at sea |
| 90 | `2026-09-23 (b)` | The Miyakojima film: a trip that begins at the airport flies, the film ends at the destination, every crossing is a plane, and the export no longer crashes | **Chiu 2026-09-23.** Trip ends count as ground when their crossing outspans the ground beside it (replaces a test that pinned the defect); ADR 2026-09-01's "no return flight" built — cut by time at the first crossing landing within `discovery.away_radius_m` of home; every crossing flies the plane (reverses `9064921`); snapshotters released on main (device crash). INFERRED: home side was airport-only; MapLibre frames. Device re-export owed |
| 91 | `2026-09-23 (c)` | "No road" splits in two: a beach is not a crossing | **Chiu 2026-09-23**, opening the `RouteProvider` boundary. Geoapify's `No suitable edges` → new `offTheRoadNetwork` / `off_road_network`, never a crossing; `No path could be found` and unknown 400s stay the crossing verdict. Schema v7 clears legacy `no_road` for one re-ask. Both wordings measured live (VERIFIED). Ferries still fly |
| 92 | `2026-09-23 (d)` | Home: import stays the hero, recording is one named button; a repeat import offers the trip that exists | **Chiu 2026-09-23.** S1's caption + segmented picker + "Start Journey" become one bordered 「記錄一趟旅程」 button opening `StartRecordingSheet`. Repeat imports: sheet offers the existing trip or a second copy; Discovery stops offering it. New key `import.duplicate_photo_share` 0.5, INFERRED |
| 93 | `2026-09-23 (e)` | The beta timeline goes compact: place and date on one line, visits and time at home, provenance by exception | **Chiu 2026-09-23.** Discovery list only: three lines, no thumbnails; recorded journeys get a glyph, photo ones nothing (2026-07-20 not reopened); "3rd trip to Japan" abroad, overlaps one visit; "2 months at home" behind `discovery.show_home_gaps`; coordinates never milestones. INFERRED: visit wording within the lookback |
| 94 | `2026-09-23 (f)` | The entry gets a drawer; kilometres are ground-only; the visit is a pill | **Chiu 2026-09-23.** Two collapsed lines (route + days + ground km); chevron opens photos (8), route, counts, 「相簿裡第2次到日本 · 上次是…」 and the diary link in place; km = ground modes with a road verdict, flights and unrouted legs out. INFERRED: transit is always ground |
| 95 | `2026-09-24` | The body is framed area by area: a town at town scale, a drive at drive scale | **Chiu 2026-09-24**, reopening one-span-per-trip by name. Areas from stop-to-stop stretches within `camera_area_split_ratio` (1.5, INFERRED); zoom only in a reframe beat with the vehicle waiting, stop shown at the tighter framing; travel paced by screen distance; pan floor on dolly travel; one area = old film bit for bit; `FollowCamera` clamp snap fixed. Amends 2026-08-01, 2026-08-02, 2026-08-09 |
| 96 | `2026-09-24 (b)` | Trips can be merged: one journey, one film, whatever recorded it | **Chiu 2026-09-24**, taking all three recommendations. Recorded + photo-rebuilt parts mix; provenance per segment, the whole marked reconstructed and its stats cleared. Far ends → a `merge_gap` leg, routed like `exif` and dashed without a road; near ends → an overnight stop. Films kept. Earliest trip survives; overlaps refused; irreversible. New key `trip.merge_gap_min_m` 500, INFERRED |
| 97 | `2026-09-24 (c)` | Before TestFlight: deleting a trip stops its work, Home asks first, the side-load is a switch | **Chiu 2026-09-24**, from the pre-TestFlight architecture review. `TripDeletion` cancels a trip's export and routing before deleting; Home's swipe confirms (recorded trips warned, draft wording); side-load keys only with `KAMOME_SIDELOAD_REGIONS=YES` (Debug on, Release off), tile search follows the same key, `check-archive.sh` refuses it. Amends PD-7 |
