# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.7, 2026-07-20 **Replay
MVP repositioning** — see below; the first release ships a **photo-import
recap**, not passive capture). Phase map: **P3.5 = Replay MVP (current
release target)**, P4 = Story Director, P5 = Capture Beta, P6 = Plans, P7 =
backend. Earlier: v1.5 recap visual pivot, v1.4 fork = mechanism (user-facing
copy says Save / Get this route, never "fork"), v1.3 battery-moat. Read it
before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device, honest provenance (never
"Verified Trip" — recorded vs reconstructed-from-photos is a product rule).

## §0 · Location data never leaves the device by default (Chiu 2026-08-03)

**A standing principle, not a checklist item.** Kamome's subject matter *is* a
record of where someone was and when. That is among the most sensitive data a
phone holds, and the product's whole claim is that it is safe to keep here.

A user's real trip, route or location history is **never** logged off-device,
transmitted, synced, sent to analytics or crash reporting, or committed to this
repository. The single exception is an explicit, user-initiated share of one
trip that the user actively chooses — never a default, never bundled into
another action, never opt-out.

This governs work that does not exist yet, which is the point of writing it
here: any P7 backend sync, any analytics or crash reporter, any telemetry, any
"help us improve" toggle is designed against this rule rather than measured
against it afterwards. If a feature needs real coordinates to leave the device,
that is a product decision for Chiu, not an implementation detail.

Concretely, today:
- `Tools/exif-to-fixture.sh` writes to `Tests/Fixtures/trips/local/`, which is
  gitignored as a whole directory. The render harnesses prefer a dump there over
  the committed synthetic fixture of the same name, so real trips drive desk
  review while CI keeps deterministic placeholders.
- Committed fixtures are hand-written plausible coordinates only.
- `KamomeLog` may name *which* stop failed to geocode; it may not log the
  coordinates.

It was broken once, on 2026-08-02: a real 160-photo dump of an actual trip was
committed. Caught before any push and rewritten out of history the same day.

## Replay MVP repositioning (spec v1.7, 2026-07-20, Chiu) — READ FIRST

Long-term vision unchanged (Kamome auto-remembers a journey and directs it
into a film worth rewatching). But the **first release is smaller and
verifiable — the Replay MVP:** pick a past trip's photos → reconstruct from
EXIF place+time → snap to real roads (OSRM, already landed) → souvenir-map
recap → **MP4** → share. Two-layer evolution: (1) Replay MVP, (2) Story
Director (auto-select/narrative/hero/music) — build the MVP without blocking
layer 2. `decisions.md` 2026-07-20. Consequences:

- **Phase 3.5 renamed → Replay MVP**; **photo-EXIF import pulled forward**
  into it (was old P4). Work order = `Docs/handoff-P3.5.md`, resequenced:
  **Photo EXIF Import first** → MapLibre souvenir map → Modern Minimal (the
  ONE MVP theme) → vehicle follow-cam (primary dynamic, NOT "always-centred"
  dogma) → basic photo deck (0.8 s, explicitly *basic*) → **three-real-trip
  dogfood** → TestFlight.
- **P3.5 gate is now a product release gate** (three real trips → shareable
  films, in-app only, no DB edits / no CapCut; ≥1 published; limited-photo on
  device; stable MP4 export; per-trip time *product-acceptable*, the single
  <90 s number retired). Map-vs-Apple side-by-side = design review, NOT the
  gate. "Worth publishing," not "prettier map." Three trips is hard, never one.
- **MP4 is the launch format; GIF demoted to non-blocking.**
- **P3 device items redistributed (none faked passed):** export/S5-UX/
  limited-photo → Replay MVP gate; 2 h drive + region-resume → Capture Beta
  (`Docs/device-test-P3.md` re-tagged).
- **P5 Passive Capture Tier renamed → Capture Beta**, moved *after* the video
  product; inherits the tracking/battery device gates; only place "Arm once,
  forget it" is validated. **P4 Import & Matching renamed → Story Director**
  (EXIF half moved to MVP; Story Director is **deterministic — no AI/LLM
  tokens** (scoring/selection over trip data); Google Timeline importer
  **dropped** as redundant — EXIF import + in-app capture cover it).
- **Honest provenance:** schema v2 `trip.source` (recorded | imported_photos |
  imported_timeline) lands with the MVP; UI labels imported trips
  "reconstructed from photos"; low-confidence legs render inferred.

## Recap visual pivot (spec v1.5, 2026-07-19, Chiu)

*(Phase/gate framing here is superseded by the Replay MVP section above — kept
for the substrate ADR + boundary-discipline detail, which still hold.)*

Chiu rejected the P3 demo's Apple-tile look — Kamome is a **travel
storytelling engine**, not a GPS visualizer (now spec §0 rule 6: every
motion/visual decision must serve the journey's narrative; a replay must be
recognizably Kamome without branding). Vision:
`Docs/kamome-animation-vision.md`. Consequences:

- **P3 scope frozen as the pipeline milestone** — its machinery (CameraPath,
  OverlayTimeline, compositor, encoders, S5) all survives. Gate items
  unchanged (device: 2 h drive, limited-photo re-check, < 90 s budget, S5
  UX); the "Chiu posts one recap" share-worthiness item moved to P3.5.
- **New Phase 3.5 — Recap Visual System** (spec §7), strictly sequenced:
  OSRM matching §4.4 (pulled forward; route must never be straight lines
  between GPS points) → MapLibre substrate → Modern Minimal theme.
- **Substrate ADR** (decisions.md 2026-07-19): MapLibre Native +
  self-hosted vector tiles (Planetiler → PMTiles, same extracts as OSRM),
  Kamome-authored style JSON per theme. Implementer guide:
  `Docs/vector-tile-pipeline.md` — includes the **quality bar** (must be
  clearly better-designed than Apple Maps for replay, judged side-by-side
  vs. the P3 artifact, Chiu signs off; unreachable bar ⇒ reopen the ADR).
- **Boundary discipline, not premature abstraction** (Chiu): no generic
  multi-renderer interface. `RecapSnapshotProviding` already is the
  boundary (`import MapKit` lives only in `MapKitSnapshotProvider.swift`;
  MapLibre types get the same one-file confinement). Deferred gaps, built
  only when their consumer exists: pitch/bearing in the snapshot request
  (isometric camera), `RecapTheme` overlay tokens (defined during Modern
  Minimal). Engine ↔ theme fully decoupled; Modern Minimal is the first
  theme, never a structural assumption.

**Prototype validation (2026-07-20, `Docs/prototype/`, decisions.md
2026-07-20).** Direction de-risked in a throwaway web prototype on Chiu's
real 170-photo Iceland trip; owner sign-off "收斂回 app". Locked constraints
for §4.5/§7 (no architecture change — they constrain existing components):
(a) base map = **real geometry + subtractive style** = 紀念品地圖 (reaffirms
substrate ADR; abstract map rejected); (b) stop photos = **rotating deck at
the place**, hero cross-fades 3–8 photos at **0.8 s each** (OverlayTimeline);
(c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle
is the subject, close heading-up zoom) — the prototype's one unmet item;
top-down car default, seagull/scooter/bike swappable. Positioning restated →
spec header v1.6 ("stories you can relive and share"). Forward directions
recorded: photo-EXIF import first (prototype IS that importer, §4.7), video
"beads" (auto-trim 2–3 s, muted), beat-synced royalty-free music.

## Current phase: **4 — films worth keeping.** Phase 3.5 CLOSED 2026-08-15

**Phase 3.5 (Replay MVP) is closed.** §1–§5 all landed; **§6a passed** (three real
trips, three films Chiu wants to keep, one published, community feedback good);
**§6b did NOT pass** and its six unmet items moved to Phase 2 (App Store release).
Closing ADR: `Docs/decisions.md` 2026-08-15. Do not reopen 3.5 to finish §6b —
those items have a new home.

### 🔴 P0, above everything — the app died on someone else's device (2026-08-15)

The first person other than Chiu to install Kamome could not use it: with a large
photo library the app dies outright, and date selection misbehaves. **This is the
first outside signal the product has ever received and it takes priority over all
planned work.** Leading hypothesis is a build shipped with a LAN `matching.base_url`
that does not resolve on their network — `matchTrip` awaits legs sequentially, so
more photos means more stops, more legs, and more back-to-back timeouts. Not
confirmed. Diagnose before fixing; the fixes differ completely.

⚠️ That device belongs to someone else. Read only what identifies the failure;
**never copy their photographs, place names, coordinates or identifiers into this
repo** — §0's reasoning applies at least as strongly to a third party.

**The mechanism is now structurally closed, whatever the trigger was**
(2026-08-15, `decisions.md`). Still diagnose — a LAN URL and a slow provider need
different follow-ups — but the app can no longer be held by either:
- `AppConfig.loadOrDie` **refuses a release build** whose `matching.base_url` is
  not empty or `https`, and CI refuses the committed one. A debug run against
  `http://192.168.x.x` is untouched, which is what device testing needs.
- Import returns when the trip is saved; routing runs detached, is cancellable
  per leg, and is bounded by `matching.trip_budget_s` (60 s) for the whole trip.
  The import sheet's Close button is always enabled.
- A dashed film now says **which** of four things happened — no road route, the
  provider unreachable, rate-limited, or the budget ran out. Only the first is
  the journey being drawn honestly; the other three are worth retrying.

Date selection misbehaving is **not** addressed — the month-reset in
`ImportSheet.linkEndToStart` and the unbounded range are still open, under
Phase 4 item 3.

### Phase 4 scope (Chiu 2026-08-15)

Chosen over productisation deliberately: *"方便的產品都沒有這是足夠好的作品更吸引
人"* — a good enough artefact matters more than a convenient product, so the films
come first and export convenience is discussed after.

Reordered 2026-08-15 around the first outside feedback: **nobody mentioned the
map; the most common request was to change the vehicle.**

1. **Vehicle sprites** — the top community request, and the prerequisite for the
   cross-region plane/ship/seagull. The 8-direction technique and its art
   constraints are in `Docs/handoff-recap-visuals.md` §3; swapping a set is
   already a pure asset swap.
2. **Cross-region flight display** — `Docs/cross-region-journeys.md`. Every
   overseas trip hits this on device, because the app imports a date range from
   the whole library while the desk fixtures were hand-curated folders.
3. **Export that survives** — import and export must be **interruptible,
   observable and budgeted**. One design problem, not five fixes: the import
   cancel path, progress reporting, a trip-level routing budget, the unbounded
   date range, and the month-reset at `ImportSheet.swift:133`. The cheapest single
   lever is `keyframe_interval_frames` (15 today = a snapshot every half second);
   30 halves every export, and costs a 1 s cross-fade instead of 0.5 s.

   ⚠️ **Measured 2026-08-15, and the lever is the wrong one.**
   `RecapSnapshotBudgetTests` on the real Miyakojima dump (offline, all legs
   inferred): an 88 s / 2,640-frame film costs **191 snapshots — 151 of them in
   the 9 s opening**. The opening is 10% of the film and **79% of the snapshot
   budget**, because `RecapRenderLoop` snapshots it *every frame*
   (`movingUntilFrame = openingS × fps`) while the body gets one per interval.
   `keyframe_interval_frames` 15 → 30 therefore takes 191 → 176, **−8%**, not
   half: it halves a body that is only 21% of the cost. Running the opening at
   the coarse interval instead would be ~58 snapshots, ≈3.3× cheaper — *derived
   from the measured split, not itself measured*, because measuring it needs a
   code change and that is Chiu's call against renders. The loop's stated reason
   for the fine opening ("the coarse interval is sized for a **static** camera")
   went stale with the FollowCamera rebuild: the body camera moves every keyframe
   now too. Cross-fade quality is what the coarse interval spends.

   🔒 **Both numbers are frozen — this is a recorded fact, not a pending change**
   (Chiu 2026-08-15). Neither `keyframe_interval_frames` nor the opening's
   every-frame interval is to be touched, and the three-way render comparison is
   not owed. They are held for a design conversation about **how the camera
   crosses large spatial gaps**: the opening's panorama-to-detail move and the
   cross-region flight (item 2) are the same problem, and will be designed
   together rather than tuned separately. The measurement above exists so that
   conversation starts from a number instead of an intuition.

**Map work is NOT in Phase 4.** Tiles, labels and the tile server all left the
roadmap with the 2026-08-15 substrate ADR. What Chiu wants from "big cute place
names" is a **Kamome-drawn overlay**, not a base-map feature — it is iceboxed as
"Place names as narrative rhythm", it is substrate-independent, and the app
already geocodes every stop so it has the names in hand.

**Routing is Geoapify — CLOSED 2026-08-20**, on Chiu's own survey against a live
free-plan key (`Docs/decisions.md` 2026-08-20; `Docs/routing-provider-selection.md`
is now the record of what was asked, not an open question). §0's cost was accepted
on 2026-08-16 and stands: real trip coordinates leave the device to a third party.
The scaling trap that forced it, 2026-08-15: a self-hosted OSRM only routes the
regions it preloaded, and `Deploy/regions.json` carries four — a friend's Tokyo trip
had no routable legs at all, because the Japan extract is Kyushu.

⚠️ **The migration PR carries two policies out of `OSRMRouteProvider`, not one.**
The detour-ratio gate is on record; **`matching.route_waypoint_radius_m` (500 m,
sent as OSRM's `radiuses=`) is not, and it is the one that matters more.** It is
what makes a photo taken 1 km from a road draw **dashed**. Chiu's survey measured
Geoapify without it: that photo returns 200 and a **20.33 km route for an 11.29 km
leg (ratio 2.247)** — which **passes** the 2.5 detour gate, is stored, and draws as
solid road the traveller never took. Do not fix that by tightening the ratio: a
fjord drive is legitimately 2–4×, so the ratio cannot tell a wrong road from an
indirect one. Whether Geoapify accepts a snap radius at all is **untested**, and if
it does not, the choice between dashed and fabricated comes back to Chiu.

### What the export numbers actually said (2026-08-15, device)

| trip | frames | snapshots | export | per snapshot |
|---|---:|---:|---:|---:|
| Miyakojima | 4,065 | ~~271~~ **wrong** | 270 s | ~~≈1.0 s~~ **wrong** |
| New Zealand | 4,635 | ~~309~~ **wrong** | 600+ s | ~~≈1.9 s~~ **wrong** |

⚠️ **These two columns are not merely estimates — the method is wrong, and the
measured numbers are in the Phase 4 section above.** Do not average the two sets
and do not quote these. Only `frames` and `export` are real.

The counts were computed as `frames ÷ keyframe_interval_frames`, which assumes one snapshot every interval
for the whole film. `RecapRenderLoop` snapshots the **opening every frame**
(`movingUntilFrame = openingS × fps`), so the real count is higher and the real
per-snapshot cost lower — in the same proportion for both rows, so the
substrate comparison's ordering survives and the absolute figures do not.
`Tests/AppTests/RecapSnapshotBudgetTests.swift` counts them through the shipped
loop; replace this table with measured numbers when a device run is next made.

**Export time ≈ snapshot count × snapshot cost; nothing else is the bottleneck.**
Both films ran on Apple Maps, so every snapshot was an `MKMapSnapshotter` **network
fetch**. MapLibre reads local `.pmtiles` from disk, and **has never been measured on
device** — the souvenir map may be substantially faster, not merely different.

That reopens tile provisioning as a *performance* question, not only a visual one.
The honest comparison is **one large reusable download** versus **small fetches on
every export**, not download versus none. A user who makes one film may be better
off on Apple's map. Regions are 3 MB (Miyakojima) to 640 MB (New Zealand).

**The export also fails if the app is backgrounded or the screen sleeps.**
*(Addressed 2026-08-15: `ExportLifecycleGuard` holds the idle timer and a
background-task assertion for the render's duration, and cancels cleanly at a
frame boundary if iOS reclaims the assertion. This is not resumable export —
`AVAssetWriter` cannot resume across process death, and that remains a project.)*

### Two 2026-08-01 blockers — both closed

1. Multi-day inter-day legs typed `.walk` — **fixed** 2026-08-02 by
   `import.pace_unknowable_gap_s`.
2. iCloud-optimised photos resolving to empty cards — **mitigated** (option C): the
   resolver still downloads nothing, but the recap screen names the shortfall.
   Option B (actually fetching originals) stays iceboxed.

### Camera architecture (rebuilt 2026-08-01 → 2026-08-02, Chiu)

The recap camera was rebuilt after the NZ device film. `CameraPathActs` framed
each act to its own bounds while timing came from a separate clock, so motion
came from **data shape** rather than spatial continuity — acts collapsed onto the
`camera_span_m` floor and the camera crossed 110 km between them. What replaced
it, all of which is load-bearing:

- **`FollowCamera`** — a dead-zone dolly, pre-simulated once at build time so
  `cameraFrame(atTime:)` stays pure and random-access. Inertia is simulation
  state, never a post-process. A world-bounds clamp keeps the frame inside the
  route's extent, and **yields to the subject** when the two disagree.
- **One span per trip**, from `RecapDurationPlan.bodySpanM`. Never adaptive —
  recomputing mid-film is what produced a 97× zoom-out before the end card.
- **Wide baseline (2026-08-02) SUPERSEDED 2026-08-08** (Chiu, from renders). It
  framed the *body* to the whole trip via `wide_span_padding` 1.5 — but the
  opening's regional beat used the same expression, so establishing and body were
  the same number and the film opened flat. `body_span_padding` (0.6) now sizes
  the body separately: the establishing shot frames the whole trip, the body
  follows the vehicle inside it. Iceland 737 km → 295 km = a 2.5× zoom.
  `camera_pan_window_fraction_per_s` stays 0.05.
- **`CameraPathActs` keeps only discontinuity detection** — a ferry is a fact
  about the journey; framing was a decision about the camera, and conflating them
  is what made acts visible to the audience.
- **The opening** is country → region → body, the country beat framed to fit
  *inside* the tile extent (never shows past the data), dropped entirely when the
  region is no wider than the trip. Held beats are capped at ~1 s **after the
  title card**; the title beat itself holds `title_card_s`. The closing zoom is
  skipped when the body frame already matches the regional beat.
- **The ending** pulls back past the body (`end_reveal_padding` 1.9) so the last
  frame is the complete journey; `end_card_style` selects `.full` (free) or
  `.minimal` (held for a paid tier).

**Two gates guard all of it** (`RecapCameraContinuityTests`, offline, every
fixture, `base_url=""` for worst-case inferred legs):
- consecutive frames share ≥50% of their ground (measured ≥97%);
- the subject never passes 80% of the half-frame (measured 43–54%).
Do not relax either — they exist because a still frame is trivially correct and a
strobing one is only wrong *between* frames.

**Deferred, scoped, wanted:** map reference labels — handoff §"Map reference
labels". Blocked on a missing `glyphs` fontstack (MapLibre cannot draw Latin
labels without one); tile data already carries the names. Related but separate:
landmark title cards as narrative rhythm (`icebox.md`).

**Still not merged to main:** PR #11 holds until §6 passes (owner call).

## Phase 3 history (recap pipeline, spec §4.5/§7) — started 2026-07-16

Gate restructure (decisions.md 2026-07-16, Chiu): the 2 h drive
(`Docs/device-test-P1.md`) and the limited-photo-access re-check moved from
Phase 3 *preconditions* to Phase 3 *gate items* — P3 dev is fixture-driven,
but **P3 cannot close without both**. *(Superseded 2026-07-20: the 2 h drive
moved to Capture Beta; the limited-photo re-check stays as a Replay MVP gate
item.)* The 2026-07-16 smoke drive surfaced:

- Road deviation in the polyline is expected (sparse drive sampling + ε=15 m
  display simplification); fix is OSRM matching (§4.4, P3 stretch / P4 core),
  raw points are retained — do NOT tighten sampling config for this.
- Phantom-trip guard landed (PR #7, CI green): `trip.min_duration_s` /
  `trip.min_distance_m` in `TrackingConfig.json`; `TrackingSession.end()`
  discards sub-minimum recordings (`TripGuard`, Core/TripComposer). PR #7
  also fixed the local smoke's stale missing-key expectation.
- P3 milestone branch `phase-3-recap` (stacked on PR #7): `KamomeExportEngine`
  target started with `CameraPath` (§4.5 step 1 — speed-warp to
  `export.target_duration_s`, per-stop holds pinned on-route, smoothstep
  easing, new `export.max_hold_fraction` tunable caps holds on stop-dense
  trips).
- §4.5 steps 2, 4, 5 landed 2026-07-18 (three commits on `phase-3-recap`):
  frame renderer (`RecapFrameCompositor` + `RecapRenderLoop`, keyframe
  snapshots cross-faded per `export.keyframe_interval_frames`, projection
  travels with `MapSnapshot` so MKMapSnapshotter's `point(for:)` stays
  authoritative; `FlatSnapshotProvider` keeps golden-frame gates
  deterministic), title/end cards as new OverlayEvent kinds (photos toggle
  gates stop cards only — decisions.md 2026-07-18 recap-chrome, **confirmed
  by Chiu**; chrome-free export = separate future option, never this
  toggle), `RecapQRCode`, and `RecapExporter` → H.264 MP4 +
  decimated GIF with progress/cancel. New export tunables: frame size,
  camera_span_m, keyframe_interval_frames, title_card_s, end_card_s.
  S5 landed 2026-07-19: `RecapComposer` (trip DB → cards; recap geometry
  goes through Douglas-Peucker at simplify.epsilon_m), `RecapModel`/
  `RecapView` (photos toggle labeled "停留照片卡" + always-on chrome note,
  MP4/GIF picker, progress/cancel, share sheet, render-time readout), film
  button on S3. Render-loop snapshot prefetch + `video_bitrate_mbps` (5)
  landed after 2026-07-19 benchmarks (sim: pipeline 22.8 s, snapshots
  0.67 s each, demo end-to-end 34.6 s). Demo artifact:
  `Docs/demos/phase3/` (perth fixture, real tiles). QR payload =
  `kamome://route/<id>` placeholder until P6/P7.
  Remaining for P3 (all need the physical device, `Docs/device-test-P3.md`
  F–H): render budget < 90 s via S5 readout, S5 UX pass, 2 h drive,
  limited-photo re-check.
- Recap product decisions (decisions.md 2026-07-17, Chiu): overlay moments
  (stop cards, and later route-attached photo fly-bys) are **timeline events**
  built alongside CameraPath in step 2 — don't hardwire rendering to
  `holdingStopIndex`. S5 gets a photos on/off toggle (route-only animation =
  overlay events off) — P3 scope. Route-photo fly-bys = P3 stretch after the
  render budget is proven; video clips in recap = icebox (deterministic
  excerpts only — random breaks golden-frame CI).
- Photo fixes landed 2026-07-16: route-attached photos (stop_id NULL) get an
  S3 strip; Selected-Photos access shows a banner + limited-library picker;
  re-match preserves highlights. Limited-access box stays unticked until Chiu
  re-checks on device.
- Evening dwell_pause without dwell_resume was benign (parked until End
  Trip). Region-resume got its first hardware proof on the 2026-07-19 drive
  and **failed half-open**: resume fired, iOS suspended the app ~10 s after
  the region-exit wake, 32 min / 13 km lost (straight line in the recap,
  second stop unrecordable). Fix landed on `phase-3-recap` (decisions.md
  2026-07-19 region-resume): background-flag re-assert on resume, trip-long
  significant-location-change safety net, `sampling.recovery_gap_s` (60)
  silent-death watchdog, engine-side resume now also restarts GPS
  (`resumeActiveTracking`). New CSV events `region_exit` / `gps_recover`.
  Re-validation = device-test-P3 item C (needs the physical device).
- Stop detection redesigned after the 2026-07-18 17:04 drive missed both real
  stops (ADR 2026-07-18): DwellDetector is streak-based (age-based span check
  never fired on sparse real sampling); engine never dwell-pauses mid-walk;
  `StopDeriver` (TripComposer) adds silence-gap + walk-visit (loop-closure)
  stops at trip end. Trip stop semantics = live ∪ derived; new dwell tunables
  gap_min_s / visit_min_s / visit_return_radius_m.
- `stop.kind` wired (ADR 2026-07-18 stop-kind): `dwell` | `walk_visit` via
  `StopKind`; silence-derived = dwell (detection ≠ kind); pre-existing rows
  say "auto" — readers treat unknown as dwell. Compositor renders walk visits
  with walking duration/trace (recovered via time overlap with the walk
  segment — no Place/Visit abstraction, owner decision). Next-drive
  validation items tracked in `Docs/device-test-P3.md` (A–E). POI naming
  (MKLocalSearch → geocode fallback) = next standalone PR after the first
  end-to-end replay; do not block compositor on it.

### Desk harnesses: how `TEST_RUNNER_` works now (fixed 2026-08-15)

The documented invocation works and survives `xcodegen generate`:

```bash
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:KamomeTests/RecapTimelineReportTests TEST_RUNNER_KAMOME_TIMELINE_REPORT=miyakojima
```

It had been silently broken on Xcode 26.6 — every env-gated harness skipped while
the run reported success. Three findings, each isolated by changing only itself,
and the fix follows from the third:

1. With no `environmentVariables`, XcodeGen emits the test action with
   `shouldUseLaunchSchemeArgsEnv = "YES"`, so it takes the **Launch** action's
   environment. Declaring anything flips it to `"NO"`.
2. **That alone fixes nothing.** On this toolchain xcodebuild's `TEST_RUNNER_`
   injection never reaches the test process, with the flag either way — so
   declaring the variables empty-and-disabled changes nothing, because there was
   no injection to un-shadow. (This is the step that produced a false positive
   once: a run that "passed" was reading a value left in a stale scheme.)
3. What xcodebuild *does* do with `TEST_RUNNER_FOO=bar` is define it as a **build
   setting**, and scheme environment values expand build settings.

So `project.yml` declares each harness variable as `$(TEST_RUNNER_<VAR>)`. One
consequence to know: an unset variable now arrives as a defined **empty string**,
not as nothing — harnesses must read it through `HarnessEnv.value`, which
collapses empty back to nil. Adding a harness variable means adding a line to
`project.yml`, or it can never be set.

## Verification commands (run from repo root)

```bash
xcodegen generate
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
swiftlint
```

(Local Xcode is 26.6 → destination iPhone 17 Pro; CI auto-picks its simulator.
swiftlint locally needs `XCODE_DEFAULT_TOOLCHAIN_OVERRIDE=/Library/Developer/CommandLineTools`
— Rosetta swiftlint can't load Xcode 26's arm64-only SourceKit.)

The `.xcodeproj` is generated — never hand-edit it; change `project.yml` and
re-run `xcodegen generate`.
