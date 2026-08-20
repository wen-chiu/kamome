# HANDOFF — current state

**Updated 2026-08-08.** Branch `feature/typed-legs-routing` (PR #12 → `phase-3-recap`;
PR #11 is `phase-3-recap` → `main` and holds until the §6 gate). Written so a fresh
session (or a fresh person) can pick this up without being briefed by hand.

Read `CLAUDE.md` first for the standing rules — especially **§0, location data
never leaves the device**, which constrains the fixture work below more than
anything else here.

Scope notes: `Docs/handoff-P3.5.md` is the Replay MVP work order;
`Docs/gate-P3.5-checklist.md` is the §6 gate runbook. This file is the *session
state* on top of them — what is done, what is open, and why.

---

## Findings — PO/Architecture session (2026-08-20)

**Context.** Chiu ran the Geoapify survey on 2026-08-19 and selected the provider.
ADR: `Docs/decisions.md` 2026-08-20. These are the items the survey did not close,
or closed differently from how it reported them. Ordered by what can go wrong
silently.

---

### 1. 🔴 The migration PR carries **two** policies out of `OSRMRouteProvider`, not one

**Decision.** `matching.route_waypoint_radius_m` (500 m) is Kamome honesty policy,
exactly like the detour-ratio gate, and it must be carried across deliberately.

**Why.** `OSRMRouteProvider.requestURL` sends `radiuses=` per waypoint — "photos sit
beside roads, not on them". Under OSRM, a waypoint further than 500 m from a road
returns `NoSegment`, so the leg draws **dashed**. Geoapify's `/v1/routing` has a
different URL shape and **no snap-radius parameter was tested.** Chiu's own survey
measured what happens without one: a waypoint 1 km off-road returned **200, 20.33 km
for an 11.29 km leg, ratio 2.247**.

**Evidence.** `matching.route_max_detour_ratio` is **2.5**; 9.05 km straight × 2.5 =
22.62 km allowed vs 20.33 km returned → **the wrong-road route passes the gate**, is
stored by `setMatchedPolyline`, and draws as solid road. The 2 km case (2.007) passes
too. Verified by arithmetic over the survey's own table and `Config/TrackingConfig.json`.

**Risk.** Do **not** respond by tightening the ratio. Legitimate routes measured
1.15–1.49 and wrong-road routes 2.0–2.25, which looks separable — but a fjord or
peninsula drive is legitimately 2–4×, and Iceland is made of them. The ratio cannot
distinguish a wrong road from an indirect one; the snap radius can, because it acts
before a route exists.

**Next.** First establish whether Geoapify `/v1/routing` accepts a per-waypoint snap
radius (one parameter on the existing survey script). **If it does not, stop and
bring it to Chiu** — "a photo 1 km from a road draws dashed" vs "draws a road the
traveller did not take" is a product decision, not an implementation detail.

---

### 2. 🟠 Do not delete `RouteProviderFailure.rateLimited`

Geoapify produces no 429, no `Retry-After`, and no rate-limit headers at 28.7 req/s;
overload arrives as TCP reset. The case becomes unreachable code on this provider.
**Keep it, and keep both strings.** The pre-launch Cloudflare Worker (`Docs/pre-launch.md`)
is the natural place to throttle and *can* emit a real 429 — the distinction is
recoverable in a component already planned. Arch.md §7.2/§7.3: a case you merely
believe is dead is one you have not tested.

---

### 3. ✅ DECIDED 2026-08-20 — the retry sentence stays; the copy work is smaller than it looked

Chiu asked for "再匯出一次會有幫助" to be dropped. That sentence lives on
**`recap_routing_budget_detail`** only:

> The trip ran past our time limit. What's already matched is saved — export again
> and it picks up from there.

That is Kamome's own budget, and the promise is **verified true in code**:
`RouteMatchService.shouldReconstruct` requires `segment.matchedPolyline == nil`, so a
second run skips every leg already matched and genuinely resumes. "Kamome only
promises what Kamome controls" — this is the one promise that survives.

The pair the survey actually undermined is `unreachable` / `rate_limited`, and
**neither contains that sentence.** `recap_routing_unreachable_detail` ("we just
can't reach the routing service right now") already describes a TCP reset fairly.
So the copy work is smaller than it looks: nothing has to be rewritten, and
`.rateLimited` simply stops being reachable (item 2).

**Chiu confirmed this reading on 2026-08-20.** So: **no string is edited.**
`recap_routing_budget_detail` keeps its retry promise, `recap_routing_unreachable_detail`
stands as written, and `.rateLimited` simply becomes unreachable on this provider
(item 2 — keep the case).

---

### 3b. ✅ DECIDED 2026-08-20 — walks route on a walking profile and draw solid

**His question**, recorded as asked: OSRM and Geoapify only carry car roads, so a
hiking trail or footpath has no route; since Kamome must support every travel mode
including walking and public transit, a walk off the road network should **draw a
road that was not walked, rather than a dashed line**.

**Two facts change the question before it is answered.**

1. **A recorded walk already draws solid.** `RecapComposer.provenance(for:)` dashes
   raw geometry only on `.exif` / `.timeline` segments. A `.gpsHifi` / `.gpsPassive`
   walk is `.recorded` → **solid**, drawn on the trace the phone actually saw, which
   is more accurate than any road-snapped version. The dashed-walk problem exists
   **only for photo-imported trips**, where the input really is 2–5 photo positions.
2. **"Only car roads" is Kamome's decision, not the provider's limit.**
   `RouteMatchService.shouldReconstruct` returns false for `.walk`, `.cycle`,
   `.transit`, `.unknown` — PD-8, and its comment says why: *snapping a stroll to
   the nearest street invents a journey.* **That reasoning was written against a
   car-profile server.** OSM carries `highway=path` / `footway` / `steps`, and a
   hosted provider exposes profiles the self-hosted four-region car graph never had.

**Chiu decided (2026-08-20): the recommendation below, as written.** Spec amended to
**v1.8**, new §4.4.1 — journeys are multi-modal by design, car ships first. Do not fabricate.
Get the same outcome honestly by **routing walks on a walking profile** — a real
footpath drawn solid is both what Chiu wants and what PD-1/PD-2 allow. Then the
residual dashed cases (a beach, a glacier, a field, indoors) are rare rather than
pervasive.

**Test before deciding — one row on the existing survey script:** does Geoapify
`/v1/routing` accept `mode=walk` / `mode=hike`, and does it return trail geometry
for a known trail?

**Transit is a different problem and must not ride along.** A Shinkansen leg routed
on any road profile draws the **expressway** — a different line in a different place,
claimed as real. Chiu's own cross-region decision already contains the honest answer:
known endpoints, unknown path, its own sprite and its own beat
(`Docs/cross-region-journeys.md`, requirement 4).

**⚠️ §0 consequence, and it is Chiu's call.** Walk legs are currently **never sent
anywhere** — `shouldReconstruct` refuses them, so they have never left the device.
Routing them would send a person's city wandering to a third party, which is more
intimate than the drive legs the 2026-08-16 ADR accepted.

---

### 3c. 🟠 The album path is promoted — it is now the privacy notice's control (2026-08-20)

Selecting an **album** at import (`Docs/cross-region-journeys.md` requirement 1, the
cheap half — "a list and a fetch") is no longer just a cross-region convenience. Chiu's
privacy decision states the notice will say a **date range** decides what is sent
*and* that the user can control which places are given **by choosing an album**.

**A notice may not promise a control the app does not offer.** So the album path ships
with the notice, or the notice does not mention it. Free-form photo selection remains
a later design pass — do not bundle them.

ADR: `Docs/decisions.md` 2026-08-20 (c).

---

### 4. 🟡 `matching.trip_budget_s` — measure it, do not pick a number

Survey latency: 0.48–2.53 s a leg cold, 440–840 ms back-to-back with connection
reuse (which `URLSession.shared` gives us). Iceland is 58 legs → somewhere between
**≈35 s and ≈88 s, derived arithmetic not a measurement**, against a 60 s budget.

`matchTrip` already logs `STOPPED after N legs — trip_budget_s exhausted`. **The
first real Iceland import against Geoapify is the measurement.** Read the line, then
set the number, and say in the commit which run it came from.

---

### 5. 🟡 Untested and cheap: the waypoint cap on a GET-only endpoint

`POST /v1/routing` returns 404 — the endpoint is **GET-only**. `matching.chunk_size`
is 100 waypoints, which becomes ~2 KB of query string, and Geoapify's own per-request
waypoint cap for `/routing` was never probed. Same script, one more row.

---

### 6. ℹ️ The 1500 m map-matching ceiling is a **Capture Beta** item, not a today item

The survey concluded that sparse photo points defeat the matcher. They do not reach
it: EXIF legs go through `RouteReconstructing.route` (`/v1/routing`); only `.gpsHifi`
/ `.gpsPassive` reach `/v1/mapmatching` (`RouteMatchService.route`). Where it will
bite is Capture Beta, and specifically the known region-resume hole (2026-07-19:
32 min / 13 km lost), which returns **200 with points silently unmatched**. Same for
`matching.timeout_s` (10 s) against a measured 9.6 s for 1000 points.

---

### 0. ✅ Reviewed — the key plumbing already in the working tree

`Config/Base.xcconfig` + `Secrets.xcconfig.example` → `Info.plist` → `AppConfig`,
with `apiKey` deliberately outside `Matching.CodingKeys` and a test proving the
committed file cannot supply one. A keyless build degrades into routing-off, which
is an existing designed state with copy already written, and the release guard is
unchanged. **No architecture objection** — the boundary held and `OSRMRouteProvider`
was correctly left alone.

Two notes rather than objections: `matching.apiKey` is carried but not yet used by
any request, so the next commit is exactly the one items 1–3 below constrain; and
`"replace-me"` is a magic string, justified in its doc comment but still a string.

---

### 0b. 🔴 §0 — do not log the request URL when the new provider misbehaves

`/v1/routing` is **GET-only**, so the request URL will contain **both the API key and
real trip coordinates** in its query string. The natural move when a new provider
returns something surprising is to log the URL. §0 forbids it — `KamomeLog` may name
*which* stop failed, never its coordinates — and it would put the key in the device
log beside them.

The existing logs are already correct and should be the pattern: `OSRMRouteProvider`
logs `config.baseURL` (host only), never the built URL. **Keep it that way in the
new provider file**, and if a full URL is ever needed to debug, redact both before it
reaches `KamomeLog`.

---

### 7. ℹ️ 45 shipped vehicle sprites are modified in the working tree and uncommitted

Same dimensions and bit depth, ~3× smaller files, **different decoded pixels**
(`sips`→TIFF md5 on `boat/n.png`). Consistent with an in-place `Tools/center-sprites.py`
run that was never committed. So "vehicle sprites done" currently describes art that
is not in git. `./Tools/center-sprites.py --check` on both versions says which set is
the centred one.

## 🐛 Known and not fixed — the import date range clips at timezone edges (2026-08-18)

**Symptom you will meet:** a photograph taken early on the first morning of a
trip, or late on the last night, is missing from an imported trip — and the date
range plainly covers that day.

**Cause.** A photo's `creationDate` is an absolute instant. `ImportFlowModel.dayBounds()`
turns the picked days into instants with `Calendar.current`, which is the
*device's* zone at the moment of import. Import an Iceland trip while sitting in
Taiwan and the day boundary moves by eight hours, so "1 August" means 1 August in
Taipei — clipping the Icelandic small hours at each edge of the range.

**Why it is not fixed here.** Doing it properly needs each photograph's own
timezone, which PhotoKit does not hand over with `creationDate`; it would mean
reading EXIF `OffsetTimeOriginal` per asset, or inferring the zone from the
photo's coordinates. Both are real work, and the clipping is small — hours at two
edges of a multi-day range.

**What to do if it bites.** Widen the picked range by a day at each end; the
clustering drops the extra photos anyway if they are not part of the journey.
Written down so the next person meeting a missing first-morning photo does not go
hunting for a clustering bug that is not there.

**Deliberately correct, do not "fix":** `dayBounds` widening the end to that
day's last second (there is no "lost the last day" bug), and the `min`/`max` swap
that makes an inverted range harmless.

## ▶ RESUME HERE — MVP desk renders, 3 of 3 rendered, review in progress (2026-08-13)

Branch `phase-3-recap`, suite green (197), `swiftlint --strict` clean. PR #11
(`phase-3-recap` → `main`) stays draft and **held** — now until **§6b**, per the
gate split below; #12 and #13 are merged into this branch.

**The §6 gate split into §6a / §6b on 2026-08-13** (Chiu). §6a is the film gate:
desk, **Variant A**, three trips, "is this worth publishing". §6b is the product
gate: real iPhone, **Variant B**, three trips, "does the app do this by itself".
Items in `Docs/handoff-P3.5.md` §6; ADR in `Docs/decisions.md` 2026-08-13. Neither
is downgraded below three trips.

### The task in flight

All three MVP films are rendered in **Variant A**, with real stop names:

| | Miyakojima | New Zealand | Iceland |
|---|---:|---:|---:|
| status | ✅ rendered | ✅ rendered | ✅ rendered |
| photos in dump | 53 (of 406 files) | 160 | 2300 |
| presented stops | 10 | 20 | 65 |
| photographs shown | 23 | 45 | 144 |
| stops with no photo | 0 | 0 | 0 |
| stops unnamed | 0 | 0 | 0 |
| film length | 103.7 s | 193.7 s | **598.7 s** |
| render cost | 3,110 frames / 149 s | 5,810 / 600 s | 17,960 / 1,782 s |
| dashed drive legs | 0 | 1 of 17 | **11 of 59** |

Films are in `~/kamome-renders/`. **That directory is §6a release output, not
scratch** — the first Miyakojima render was written to `/tmp` and swept before it
could be reviewed.

**Owner review — all three judged (Chiu 2026-08-13). See "§6a film review" below
for the verdicts and what they do and do not tick.** The one §6a item still open
is **≥ 1 published publicly**.

**Spans, measured** (env-gated `RecapTimelineReportTests`, same Variant A config
and installed region the films used):

| | established | body | ratio |
|---|---:|---:|---:|
| Iceland | 736.8 km | 294.7 km | **2.50×** |
| New Zealand | 845.3 km | 338.1 km | **2.50×** |
| Miyakojima | 47.2 km | 18.9 km | **2.50×** |

These match the `Deploy/regions.json` derived figures to the decimal, so the
derived numbers were right and the camera is doing exactly what is configured.
**That question is closed** — do not re-derive it, and do not treat the spans as
a diagnosis for anything.

**The render command** (Miyakojima shown; swap fixture, photo folder, and note
that `KAMOME_PILOT_SECONDS=9999` means "the whole film", not a pilot):

```
TEST_RUNNER_KAMOME_PILOT_FILM=miyakojima \
TEST_RUNNER_KAMOME_PILOT_SECONDS=9999 \
TEST_RUNNER_KAMOME_RECAP_MODE=full \
TEST_RUNNER_KAMOME_GEOCODE_STOPS=1 \
TEST_RUNNER_KAMOME_OSRM_BASE_URL=http://127.0.0.1:5100 \
TEST_RUNNER_KAMOME_TILES_PATH=$HOME/kamome-osrm/tiles \
TEST_RUNNER_KAMOME_TERRAIN_PATH=$HOME/kamome-osrm/terrain \
TEST_RUNNER_KAMOME_STOP_PHOTOS=$HOME/Desktop/Miyakojima \
TEST_RUNNER_KAMOME_RENDER_OUT=$HOME/kamome-renders \
xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:KamomeTests/RecapPilotFilmTests
```

⚠️ **Write renders to `$HOME/kamome-renders`, not `/tmp`.** The Miyakojima film was
written to `/tmp` and swept before it could be re-reviewed; it costs 156 s to
regenerate, and Iceland would cost far more.

### Variant A vs Variant B

- **Variant A** = `KAMOME_RECAP_MODE=full`: every clustered stop presented, no
  duration cap, and `allocation_zero_share` forced to 0 so no stop shows a pin
  with no photograph. Desk MVP renders only.
- **Variant B** = shipped default (`recap_mode: highlight`), **unchanged and not
  in scope to tune**. Both overrides are harness-only; `TrackingConfig.json` is
  never edited between runs.

### Owner decisions carried in

- **Miyakojima EXIF: do not investigate.** 53 of 406 files carry GPS+timestamp;
  the rest were stripped at export. Chiu is checking the export source himself.
  Render from the 53 and re-run later if originals turn up.
- **Region headroom: do not fix this round.** After all three renders, *propose*
  (do not implement) making the headroom check automatic at trip-dump /
  region-install time. It has now caught 2 of 3 trips manually (Iceland,
  Miyakojima), which is the argument. The raw material exists:
  `Tools/tile-headroom.sh` computes the verdict and `exif-to-fixture.sh` already
  prints the trip bbox — they just need to meet.
- **iCloud grey-card resolver: untouched**, deferred to device testing.

### Local state that is not in git

- `~/kamome-osrm/tiles/` — `iceland-2026-08-08b`, `miyakojima-2026-08-09`,
  `new-zealand-2026-07-29`, `finland-2026-07-29`. Superseded regions parked in
  `~/kamome-osrm/tiles-superseded/` (outside the scanned directory).
- `Tests/Fixtures/trips/local/` — Iceland, New Zealand, **Miyakojima** dumps.
  Gitignored per §0; never commit them.
- OSRM `:5100` is `docker compose up -d` from `Deploy/`, healthy, restart-safe.

## ✅ §6a — CLOSED by owner (Chiu 2026-08-14)

All six items satisfied. **The remaining work on the Replay MVP is §6b**, the real
iPhone gate, plus the duration rule that has to land in front of it.

**The published film, recorded precisely because the wording matters:**

- **Iceland, Variant B, 210 s** — the duration-target render of 2026-08-14.
- **Shared privately to friends**, not posted publicly. The gate item reads "≥ 1
  published publicly"; Chiu judged the private share sufficient and closed the item
  on 2026-08-14. The intent — an unedited film in front of a real audience —
  is met; the literal wording is not. **Recorded as what happened rather than as
  what the item says, so a later reader does not go looking for a public post.**
- No external editing, which is the half of that item that was never in doubt.

### ⚠️ The app cannot reproduce the film that was published

Its 210 s came from `KAMOME_FORCE_DURATION_S`, a harness override pinning both
duration bounds by hand. **No rule in the product derives it**, and the shipped
`.highlight` path would render that same trip at 90 s and 8 stops.

So the duration rule (see "Pending decision" below) is not polish after the fact —
**it is what turns the published artifact into something the product actually
makes.** That is also why it sits in front of the §6b sitting rather than after it:
export time and memory are frame-count-bound, and 90 s → 210 s is 2,700 → 6,300
frames.

## ✅ §6a film review — all three judged (Chiu 2026-08-13)

**Place names are deliberately absent from this section.** The routing report this
was written from named the stops; per §0 and the same rule that gitignores
`*-names.json`, a place name is a record of where Chiu was and does not enter the
repository. Legs are identified by ordinal and by geometry, which is everything a
later reader needs. **Do not "helpfully" restore the names.**

### The verdicts

- **Iceland — a film he wants to keep.** *"這是我自己會想留著看的影片, 確實勾起我一點
  回憶."*
- **Miyakojima, New Zealand — 很好.**
- **Iceland's opening reads fine** (0–10 s), which settles the question below.
- **The one dashed leg that mattered — accepted.** See "Leg 12" below.

**What this ticks in §6a:** three trips reconstructed from EXIF; films Chiu wants
to keep; no external editing; the final "worth publishing" judgment. **What it
does not tick: ≥ 1 published publicly.** Nothing has been published yet, and that
is now the only §6a item outstanding.

### The car's late entry on Iceland was never an anomaly — CLOSED

Iceland is the only one of the three where the vehicle appears *after* the opening
ends and after the first stop's card and first photograph (9.33 s, against an
opening ending at 5.50 s). New Zealand and Miyakojima put the car on screen during
the opening (6.67 s of 9.00 s; 3.17 s of 5.50 s).

**That is the documented second sequence, not a defect.**
`LinearTimeline.subjectArrivalStartS` specifies two orderings chosen by what the
trip opens on (Chiu 2026-07-31), and Iceland is simply the first real trip whose
journey *starts at* a photo-bearing stop:

    opening → [first stop's pin/title/photos] → car appears → first leg
    opening → car appears → first leg

The rationale in that comment still holds — a car that appears only to park a
moment later at the origin reads as a false start, and no dwell tuning fixes a
sequencing choice. **Chiu watched it and confirmed it reads correctly.** The
2026-07-31 decision is now validated on a real render rather than only specified.

### Dashed legs — the honest ones, and the one that was a judgment call

Iceland: **10 dashed drive legs of 58 routable** (64 legs = 58 drive + 6 walk; all
6 walks dash by design). Corrected from an earlier count of 11 taken off the
render log.

| cause | count | verdict |
|---|---:|---|
| `NoSegment` | 9 | **Correct behaviour, no action.** These cluster on glacier tongues and national-park interiors — photo positions with no drivable segment near them. OSRM answered correctly; drawing them dashed is the honest-provenance rule working, not a defect. |
| detour-gate rejection | 1 | **Leg 12 — accepted by Chiu.** |

**Leg 12, and why it was the only real question.** 17.5 km of straight line
standing in for 61.6 km of routed road (3.5×, over the 2.5× threshold) on a
stretch where the road rounds a bay — so the straight line crosses **water**.
§6a's item reads "no obvious sea-crossing straight line", and this is one.

**Chiu accepted it (2026-08-13):** the film is honest about not knowing, and one
such leg does not cost the film. ⚠️ **This is a judgment on one instance, not a
new rule.** The §6a item's wording still says what it says; a future trip with a
longer or more prominent water crossing is not covered by this precedent and gets
its own call. Do not cite this as "water crossings are fine".

**The mechanism worth remembering.** The detour gate rejected that route as
implausible — but in fjord and peninsula terrain a 3.5× road *is* the real
geography, not a bad EXIF fix. And the fallback for "this route looks implausible"
is a straight line, which here is **more** implausible than the route it rejected.
The safety mechanism's failure mode is worse than what it prevents. Nothing is
being changed about it now; this is recorded so the next person meeting a dashed
leg over water knows it may be the gate and not the data.

### New Zealand's single dashed leg — deferred, but it found a real gap

Leg 14, within a town: **0.4 km routed vs 0.1 km straight (4.6×)**, detour gate.
**Chiu: 沒關係, 我根本沒發現** — revisit if a similar issue surfaces later.

Worth keeping anyway, because it is the cheapest finding here: **the detour gate is
a pure ratio with no absolute floor**, so 300 m of difference on a 100 m leg trips
the same threshold that protects against a 300 km fabrication. An absolute floor
would remove this class outright at no risk — and would **not** help Leg 12, whose
44 km absolute difference is real. Two separate problems; only this one is cheap.

Miyakojima: **zero dashed drive legs** (9 of 9 reconstructed); its one dashed leg
is a walk.

**Attribution method, since it is not obvious it is sound:** `matchTrip` awaits
legs sequentially, so the k-th `[routing] route:` line is the k-th routable leg.
Cross-checked three ways — 58 route lines for 58 routable legs, 10 failures for
exactly 10 dashed drive legs, and every failure landing on the ordinal of a leg
the timeline independently reports as dashed. Same alignment held on NZ.

**Also reconfirmed:** the `RouteMatchService.swift:39` base-URL log lie reproduced
exactly — `matchTrip … against "(none — matching disabled)"` in the same run where
48 legs routed fine. Second confirmed sighting; still unfixed, still the line you
would otherwise trust.

## ⏳ Pending decision — film duration must scale with trip size (2026-08-14)

**The direction IS decided (Chiu 2026-08-14). The rule is NOT.** Do not implement
the shape below as though it were settled, and do not promote it to
`Docs/decisions.md` until it has been validated on renders — including on trips it
was not fitted to. Written here rather than as an ADR for exactly that reason.

### What was decided

> Film length must be **flexible, derived from how long the user's journey
> actually was**, so that different trips produce different films.
> — Chiu 2026-08-14

His targets, stated as durations — and **which of them have been watched**, which
is the whole point of rendering them before writing a rule:

| trip | trip stops | target | presented stops | status |
|---|---:|---:|---:|---|
| Miyakojima | 10 | 90 s | 8 | ✅ *"90 秒只適合宮古島"* — confirmed by statement |
| New Zealand | 20 | **150 s** | 15 of 20 | ⬜ **rendered, not yet judged** |
| Iceland | 65 | **210 s** | **21** of 65 | ✅ *"三分半鐘的那個版本是個不錯的折衷"* (2026-08-14) |

Films are in `~/kamome-renders/duration-targets/`; the Variant A and 90 s Variant B
sets are intact beside them.

**Iceland's anchor is 21 stops, not the 22 the arithmetic predicts.**
`keptStopCount` floors a division and 210 s lands at `21.999999999999996` in
IEEE754. So the film Chiu approved presents 21 stops, and a rule built to produce
22 would not be the film he watched. **Anchor on 21.**

That off-by-one is also a **third argument for the inversion below**: computing
duration *from* a stop count has no division to floor, so this entire class of
boundary artifact disappears rather than needing a guard.

### What the Variant B renders exposed

Every trip presents **exactly 8 stops and exactly 24 photographs**, whether it has
10 stops or 65 — Iceland's shipped edit is 12% of its stops and 24 of the 144
photographs its Variant A film shows. Measured 2026-08-13, all three trips.

**This is not a defect and not drift.** `StopPhotoAllocator.keptStopCount` is
`(duration − opening − end card) × max_hold_fraction ÷ presentation cost`, which
lands on 8 at the shipped `total_duration_max_s` of 90 s and on 11 at the 120 s the
2026-08-06 ADR quotes. The formula is fine. **Trip size simply never enters it**,
because duration is clamped to the same 60–90 s window for every trip.

### The shape recommended (NOT approved, NOT implemented)

**Invert the model.** Today duration is clamped and the stop count falls out of it;
instead let the trip earn a stop count and let duration fall out of *that*:

    duration = opening + end card + (earned stops × presentation cost) ÷ max_hold_fraction

Trip size then enters the model in exactly one named place. A second benefit:
`max_hold_fraction` stops deciding how many stops the shipped edit presents and
goes back to being purely a pacing knob — removing the double duty found on
2026-08-13.

Converting Chiu's three targets back through the existing arithmetic shows the
real intuition is about **places, not seconds**: 8 of 10 stops (80%), 15 of 20
(75%), 22 of 65 (34%). Growth must therefore be **sub-linear** — a 65-stop trip
does not earn 6.5× the film of a 10-stop one.

Candidate rule, statable in one sentence: **each doubling of a trip's stop count
earns ~7 more presented stops, floored at 8 and capped at 22.** That reproduces all
three targets exactly (10 → 8 → 90 s; 20 → 15 → 150 s; 65 → capped 22 → 210 s).

### ⚠️ The warning that matters more than the rule

**Those three parameters were reverse-derived from three trips, which is exactly
how `body_span_padding` and `tier_skip_share` were derived — and both failed.**
`body_span_padding` was fitted to Iceland and gave New Zealand 4.14×;
`tier_skip_share` needed 0.82 for Iceland and 0.5 for New Zealand and was deleted
for it.

The one property that makes this shape better is that it is **bounded at both ends
and sub-linear by construction**, so its failure modes are known rather than
discovered: it cannot explode on a huge trip or collapse on a tiny one. A bare
constant has no such property.

**Therefore the acceptance condition, decided in advance so it is not
re-litigated:** the rule must report what it produces for trips it was **not**
fitted to — Finland (3 stops), Margaret River (4), and the committed synthetic
fixtures — before any of it ships. Fitting three points and shipping is the failure
mode; validating on a fourth is the step this repo has twice skipped.

### Open sub-questions, none decided

- **Does a longer film mean more places, or also more photographs per place?**
  Measured 2026-08-14 and currently the former only: NZ at 150 s shows 43
  photographs across 15 stops (2.9 each) and Iceland at 210 s shows 63 across 21
  (3.0 each) — both pinned at `allocation_max_photos` (3). So duration buys stops
  and never buys depth. **This is a second, independent dimension**, and the rule
  should not be built assuming one answer. Iceland at 210 s still shows 63 of the
  144 photographs its Variant A film carries, out of 2300 in the dump.
- Is **stop count** the right measure of "how long the journey was", or should it
  be days, distance, or photograph count? Chiu's phrasing was "旅程多長". Stop
  count is what the arithmetic above uses because it is what the cost model already
  prices; that is a convenience, not an argument.
- **Iceland's longer run-in.** At 210 s the first stop arrives at 11.53 s against
  5.53 s in the 90 s cut — the opening still ends at 5.50 s, so there is ~6 s of
  travel before the first place. NZ barely moved (9.33 s vs 9.43 s). Chiu approved
  the 210 s film as a whole; whether that run-in specifically reads as breathing
  room or dead air was not called out either way.
- Do `total_duration_min_s` / `total_duration_max_s` survive as absolute bounds
  behind the earned-stops rule, or are the stop floor and cap now the only bounds?
- Does the same scaling apply to Variant A, which has no ceiling at all today?

## ⏳ Pending experiment — travel pacing in Variant A (2026-08-13) — NOTHING DECIDED

**Status: an experiment with a hypothesis, not a decision.** No config key is
changing, no code is changing, and `travel_max_s` below is a *candidate name for a
thing that does not exist*. Do not implement it, do not cite it as settled, and do
not let it leak into `TrackingConfig.json`. It earns a decision only if a render
Chiu watches says it should.

**Status (2026-08-14).** Still wanted, and Chiu has now named *when*: **the longer
the trip, the faster the vehicle should move in Variant A.** It is not a blocker —
all three films were accepted as they are — but it is no longer optional polish
either.

**Sequence it after the duration inversion above.** In `.full` this knob was always
safe (there is no duration cap for it to divide, so it moves only pacing — the
double duty found on 2026-08-13 is a `.highlight` problem). But the inversion
removes that double duty entirely, after which `max_hold_fraction` means one thing
in both modes and the experiment reads cleanly instead of needing a caveat.

It still interacts with the open §6a item: if Iceland is the film that gets
published, Chiu may want the faster-travel cut first. **That ordering is his call
and has not been made.**

**What Chiu observed** (2026-08-13, from the three Variant A films):
photographs hold his attention; **travel between stops does not, once the film is
long.** Miyakojima (1.7 min) and New Zealand (3.2 min) held; Iceland (10.0 min)
lost him during the driving. He asked whether the vehicle can move faster on
Iceland specifically.

**What the arithmetic says.** In `.full`, `RecapDurationPlan.uncapped` sizes the
body as `parked / max_hold_fraction`, so stop dwells take that share and **travel
gets whatever is left**. `max_hold_fraction` is 0.6 today, and being a ratio it is
scale-free:

| | photo time | travel time | travel share |
|---|---:|---:|---:|
| Miyakojima | 47.0 s | 44.7 s | 48.7% |
| New Zealand | 93.0 s | 88.7 s | 48.8% |
| Iceland | 300.0 s | **286.7 s** | 48.9% |

⚠️ **These are computed from the config, not printed by a harness.** The model
reproduces the rendered lengths (NZ 193.7 s exactly; Iceland 595.2 vs 598.7;
Miyakojima 99.2 vs 103.7, the deltas being the opening estimate), which is why it
is trusted this far — but it is derived, and the span/ratio prints landing in
`RecapTimelineReportTests` are the measurement that should replace it.

**The reading.** All three sit at the same share, so what broke was not a
proportion — it was **4 minutes 47 seconds of travel as an absolute quantity.**
88.7 s held; 286.7 s did not. That points at an absolute ceiling on travel time
rather than a per-trip constant, which matters because a per-trip constant is
exactly what the 2026-08-09 camera ADR rejected and for the same reason:
`body_span_padding` was reverse-derived from Iceland and told us nothing about the
next trip.

**The experiment, in order — measure the preference first, encode it second.**

1. A harness-only override for `max_hold_fraction` (same shape as
   `withAllocationZeroShare`), so `TrackingConfig.json` is untouched and the
   change reverts by deleting an env var.
2. **One Iceland render at 0.75.** Predicted: film 9.9 → 8.0 min, travel 4.8 →
   2.8 min, **photo time unchanged at 300 s**. Iceland costs ~30 min a render, so
   this is a single point, not a sweep.
3. Chiu watches it. If the pacing is right, the travel seconds it landed on
   (~169 s) become the evidence for a real tunable. If it is still slow, 0.85
   (travel 1.9 min) is the next point — watching for whether it starts to feel
   rushed.
4. Only then: a config key, its typed mirror, and `ConfigLoaderTests` assertions,
   per the standing no-magic-numbers rule.

**Does the vehicle actually move faster, or does the camera just pull back?**
It should genuinely move faster — **INFERRED from the code, not yet seen.** Since
2026-08-09 the body span comes from `target_zoom_ratio` (2.5) against the
established span; `camera_pan_window_fraction_per_s` (0.35) is only a **floor**,
and `HANDOFF` records that it does not bind on the real trips. So shortening
travel does not widen the span — the same ground stays in frame and the subject
crosses it in fewer seconds. The floor is the built-in safety: push travel short
enough and it takes over and widens the span instead of letting continuity break.
Rough arithmetic says Iceland has a lot of headroom before that happens, but that
is arithmetic, and the render is what settles it.

**Not decided by any of the above:** whether Iceland stays a Variant A trip at
all. Switching it to Variant B is a live alternative Chiu named, and the §6a/§6b
split means both films of the same trip exist anyway.

## 🔴 Open — intermittent `KamomeCore_KamomeExportEngine` bundle crash (2026-08-13)

**Not diagnosed, deliberately not chased, and explicitly not a flake.** Logged
here because it is a §6b gate risk and the evidence would otherwise live only in a
chat transcript.

**Symptom.** `Fatal error: unable to find bundle named
KamomeCore_KamomeExportEngine`, thrown during map-renderer creation — after the
region resolves, before any frame is drawn.

**Evidence in hand.** Hit on 2 of 3 New Zealand render attempts; never on
Miyakojima; never on the Iceland run. Cleared on retry, and again under
`-retry-tests-on-failure`. The resource bundle **is** present in the built
`Kamome.app`, so this is a runtime lookup failure, not a packaging fault. Timing-
or state-dependent, not deterministic.

**Why it matters more than a harness annoyance.** `Bundle.module` is used at
`Core/ExportEngine/RecapCarSprite.swift:75` to load the vehicle sprite, and
`RecapSubjectRenderer.swift:39` draws that sprite **on the shipped export path**.
SwiftPM's generated `Bundle.module` accessor calls `fatalError` when it cannot
locate the bundle, so the defensive `guard … else { return nil }` immediately
below it — and the `if let` at the call site — **can never run.** That is an
unguarded crash on the path §6b requires to be crash-free on a real device.

**Whether it reproduces on device is UNKNOWN.** The desk is the only place it has
been seen. §6b carries a "watch for this crash" item; the device sitting is what
answers it.

**Not fixed this round** (owner call): it is app code, and the renders came first.
The eventual fix is small and defensive — a non-trapping bundle lookup — but it is
a change to shipped behaviour and needs its own pass.

## ✅ REVIEWED AND APPROVED — recap camera (2026-08-09)

Chiu reviewed the round-4 renders and approved both. **This closes the camera
work only** — the §6 Replay MVP gate is untouched and still open (see below).

| | established | body | zoom | opening | country beat |
|---|---|---|---|---|---|
| **Iceland** | 736.8 km | 294.7 km | **2.50×** | 5.50 s | no |
| **New Zealand** | 845.3 km | 338.1 km | **2.50×** | 9.00 s | **yes** |

### Owner decision — the wider establishing shot wins (Chiu 2026-08-09)

New Zealand's opening runs 9.00 s because its country beat survives: its installed
region is the whole country while the trip is the South Island, so there genuinely
is wider context to show. The alternative was cutting NZ's region to ~1.5× its
trip, which collapses that beat and gives a 5.50 s opening at the same 2.50×.

**Chiu chose the wider establishing shot.** A longer opening is the price of
showing where the journey sits in the country, and that is what the establishing
shot is for. **No code or region change** — the rendered behaviour is the decision.

The earlier "9.00 s is too long" note is withdrawn: it was raised when the opening
was long *and* the zoom was wrong (4.14×). With the zoom corrected the length is
paying for something.

### The mechanism, and why the constant it replaced could not work

`body_span_padding = 0.6` was reverse-derived from one trip (736.8 / 2.5 / 491).
Algebraically it is `wide_span_padding / target_zoom_ratio`, so it only produced
2.5× for a trip whose opening establishes on its **regional** beat. New Zealand
establishes on a **country** beat much wider than its trip, so the same constant
gave 4.14×.

Now `body = established / target_zoom_ratio` (2.5), where `established` is the
span of the opening's *first* beat — the picture at t=0. Each trip divides its
own, so the ratio holds whatever the geometry. This was only possible because
`buildWideOpening` took a `bodySpanM` parameter it never read: removing it lets
the opening be built **before** the body span rather than after.

### The pan floor is a floor now, and that matters

Deriving the body purely from the ratio broke the continuity gate on **128
assertions** — Iceland moved 34.5 km per snapshot across a 57.8 km frame, 39% of
the picture surviving against a 40% floor. A tight frame does not slow the vehicle
down; it just means more of the screen is replaced each second.

`camera_pan_window_fraction_per_s` is restored to **0.35** (its value before the
2026-08-02 wide baseline set it to 0.05) and is now a genuine **lower bound**.
Previously it was computed and discarded — `min(max(raw, cameraSpanM), ceiling)`
meant the ceiling always won, so it had not decided anything in months. As a floor
it yields the ratio wherever that is safe and overrides it where it is not: a trip
whose establishing shot is too tight to divide simply does not zoom, instead of
strobing. It does **not** bind on either real trip, so both land at exactly 2.50×.

### New Zealand's country beat is real, not a side effect

Asked explicitly, so measured explicitly. `countryAddsContext` is

    contained(region) > fittingSpan(trip) × wide_span_padding × opening_collapse_zoom_ratio
    845.3 km          > 340.4 × 1.5 × 1.25 = 638.2 km          → true

**The body span is not among its inputs**, under either the old formula or the
new one. It survives because NZ's installed region is the whole country while the
trip is the South Island — there genuinely *is* wider context to show. Iceland has
no country beat only because its region was deliberately cut to 1.5× for headroom.

**So the fix does not shorten NZ's 9.00 s opening, and cannot.** Opening length is
beats × holds + transitions; it is independent of the body span. If 9.00 s is too
long, the lever is the region, not the camera: cutting NZ's region to ~1.5× its
trip collapses the country beat, giving a 5.50 s opening and an established span
of 510.6 km — **still 2.50×**, because the ratio divides whatever it establishes
on. That is a product choice between a wider establishing shot and a shorter
opening, and it has not been made.

### What it actually was

Not the enum migration, not the naming commit, not the stop pins. The bisect in
the previous version of this section was chasing a regression that was not one:
**every fixture had this defect from the moment the wide baseline landed**, and
New Zealand was simply the first whose numbers crossed the floor.

`cappedToRegion` refuses to frame ground the installed tiles cannot draw. When a
trip nearly fills its region — the real Iceland ring road does, and NZ's bounding
box is 205 km wide by 74 km tall so the widest *portrait* frame fitting inside it
is only 41 km — that cap lands on the same span the body camera uses. The "wide"
establishing beat is then no wider than the body: there is no establishing shot to
be had. It stayed centred on the trip anyway, so the closing zoom had no zoom left
in it and was a pure translate from the middle of the trip to its start.

| fixture | pan ÷ span across a snapshot | verdict |
|---|---:|---|
| new-zealand | 0.69 | ❌ over the 0.60 floor |
| nz-real | 0.46 | passed, same defect |
| iceland (committed) | 0.32 | passed, same defect |
| iceland (real, 65 stops) | 120 km at a flat 291.5 km span | passed, same defect |

**Two things were wrong, one behind the other.**

1. A wide beat that cannot contain the trip must frame the journey's *start* — an
   establishing shot with nothing wider to say should establish where the trip
   begins. Beats that can contain the trip are untouched, so the ordinary case
   (region wider than the trip) keeps country-then-region exactly as before.
2. `bodyFrame` claimed to be "what the follow simulation converges on" and was
   only where the dolly *starts*. The vehicle waits at the route's origin through
   the opening — `buildTimeline` gives that stretch an explicit `.travel(0, 0)`,
   so it is stationary but **not parked** — and the dead-zone spring runs the whole
   time and settles on the dead-zone boundary around it, 25 km away on NZ. Both
   the wide beat's anchor and the closing-zoom decision were reading it.
   `FollowCamera.restingFrame` now states the simulation's fixed point in closed
   form and `bodyFrame` delegates to it.

`FollowCameraRestingFrameTests` measures prediction against simulation on every
fixture (0–43 m committed, 669 m worst case on the real Iceland dump = 0.46% of a
144 km frame) and measures the seam itself. Do not let those drift.

### Effect on the real films — checked against the ground rule

Measured with the installed regions, before vs after:

| trip | change |
|---|---|
| New Zealand (20 stops) | **none, in any respect** |
| Iceland (65 stops) | drops a 2.5 s beat that held span flat at 291.5 km while panning 120 km sideways; everything downstream starts 2.43 s earlier; total length unchanged at 90 s |

Iceland is a film Chiu has already judged, so this is a visible change to it.
Rendered before/after delivered 2026-08-08; **awaiting his review.**

**Byte comparison cannot answer the NZ question.** A control render — identical
code, run twice — produced a *larger* file-size spread (7.11 vs 7.43 MB) than
before-vs-after did (7.11 vs 7.31 MB). The MP4/MapLibre path is **not
byte-deterministic**, so pixel identity is not available as evidence. The
"unchanged" claim rests on the timeline and camera-path measurements, which are
identical across all three runs (opening ends 6.50 s · first stop 6.70 s · first
photo 7.70 s · car 5.27 s). Say it that way; do not claim pixel identity.

### The test that was pinning the bug

`testOpeningCollapsesBeatsThatDoNotMoveTheCamera` built its extent from the trip's
own bounds — but that sample route is a straight north-south line, so the box had
**zero longitude extent**, `containedSpanM` came out 0, and both wide beats floored
onto `camera_span_m`: a 1.5 km frame for an 89 km trip, and what "still ran" was a
45 km translate across thirty frame-widths. It now uses a snug region with actual
area, which collapses the beats *and* zooms, as the test says it does.

**Worth keeping:** a synthetic extent built from a synthetic route can be
degenerate in ways real map regions never are. A region has area.

### Still true from the old section

- **Fixture shadowing is real.** `RecapTripFixtures.tripFixture` prefers
  `Tests/Fixtures/trips/local/<name>.json` (real dumps, gitignored per §0) over the
  committed fixture. Local and CI therefore test different geometry — NZ is 20
  stops locally, 3 on CI. To reproduce CI, move `local/` **outside the repo**
  (not to a dotfile inside it — only `Tests/Fixtures/trips/local/` is gitignored)
  and re-run.
- **`850a995` does not compile.** A parallel session's push swept in an
  uncommitted edit and CI died at lint before building. Harmless at the tip;
  `git bisect` across it will hit it.

---

## ▶ Substrate decision — OSRM + MapLibre, behind swappable boundaries (2026-08-08)

**Canonical text and full rationale: `Docs/decisions.md` 2026-08-08.** Summary:

> The MVP rendering and routing substrate is OSRM + MapLibre because it is
> already implemented and validated against real trips. The application must keep
> routing and rendering behind stable boundaries so future releases may substitute
> MKDirections + Apple Maps without changing the story model or replay pipeline.
>
> Pixel Art remains a post-MVP visual differentiation path enabled by retaining
> MapLibre.

**Do not re-open or re-argue this.** MapLibre is retained precisely because it is
the only substrate that keeps the Pixel Art / custom-map identity path viable —
a deliberate trade-off. Any Apple Maps evaluation happens after MVP validation
and is settled by **rendered A/B comparison**, never by reasoning about
story-model independence.

**Deferred by decision, not by blocker** — do not pick up opportunistically, even
if one looks like a quick win while you are in the area:

- MKDirections integration
- the Apple Maps substrate (MKMapSnapshotter / MKDirections / any Apple-Maps
  rendering path)
- Pixel Art theme implementation (spike branch stays parked)
- an Apple-Maps label workaround as a MapLibre glyph substitute

MapLibre place labels stay iceboxed on the glyph/fontstack problem. **That Apple
Maps supplies labels for free is explicitly out of scope as an argument.**

**Superseded:** an earlier 2026-08-08 note here recorded "the app ships Apple
Maps, MapLibre is Chiu's own MVP path". That is no longer the decision.

### What this changes about `establishing` — now core-path, not a prerequisite

`establishing` is a single `RecapBounds?` carrying **two unrelated facts**:

| fact | kind | read by |
|---|---|---|
| how long the film runs / how stops are weighted | **story** | `LinearTimeline.pacing` |
| how wide the camera may frame before it runs off the tiles | **render** | `CameraPath.cappedToRegion` |

Pacing must never query tile coverage. The span cap legitimately must. Because
they share one parameter there is no way to have one without the other, and a
trip no installed region covers falls back to a flat 30 s film with no prologue.

On the committed substrate this is a **core-path defect**, not an Apple-Maps
prerequisite: any trip outside the four installed dogfood regions hits it.

## ▶ Pre-Phase-2 blocker — OSRM hosted-endpoint TOS unverified (2026-08-08)

The OSRM **demo/hosted endpoint's terms of service for commercial use have not
been verified.** Not urgent for the personal-use MVP (the desk harness points at
a local server), but it is a **blocker on routing-endpoint configuration work
before Phase 2** — shipping an app that calls a public demo endpoint is a
licensing question, not an engineering one. Resolve before any release that
routes on someone else's server. Related, still open: the shared-token auth work
in `Docs/handoff-P3.5.md`, which must ship server and app halves together.

## ✅ CLOSED — lint split (2026-08-07, landed as `4460d8d` / `850a995` / `6ae62a7`)

**Status: `swiftlint --strict` is clean project-wide (0 violations, 141 files),
full suite green (249 tests, 0 failures), both `RecapCameraContinuityTests` gates
pass.** The 10 violations tracked below are all fixed. Verified with:

```
XCODE_DEFAULT_TOOLCHAIN_OVERRIDE=/Library/Developer/CommandLineTools swiftlint lint --strict
```

**What actually shipped, vs. the plan this section used to describe:** the
`CameraPath.init` extraction alone (`openingPlan`, as originally planned) got the
initialiser from 82→71 lines — nowhere near the ≤50 limit, because most of the
82 lines were comments (excluded from the count either way). Getting
`CameraPath.swift` clean needed the full "option 1" struct/statics split below
*and* two more initializer extractions (`bodySpan`, `simulatedTrack`) beyond what
was written here. Left as a record for next time a "roughly N lines" estimate
shows up in a handoff: re-derive it from `swiftlint --strict` output, don't trust
the arithmetic.

| file | was | now |
|---|---|---|
| `Core/ExportEngine/CameraPath.swift` | file 555, struct body 325, init 71 | 0 violations |
| `Tests/AppTests/RecapDemoFilmTests.swift` | file 447, class 283, func 63 | 0 violations |
| `Tests/CoreTests/CameraPathTests.swift` | file 404, class 301 | 0 violations |
| `Core/ExportEngine/FollowCamera.swift` | func 71 | 0 violations |
| `Tests/CoreTests/RecapPacingTests.swift` | class 253 | 0 violations |

### `CameraPath.swift` — "option 1" landed as designed

Moved `Position`, `Phase`, `TimelineEntry`, `Hold`, plus the pure statics
(`distance`, `travelSeconds`, `coordinate(atDistance:route:cumulativeM:)`,
`smoothstep`, `stopAnchors`, `cappedToRegion`, `bodyFrame`, `confine`) into a new
file, `Core/ExportEngine/CameraPathCore.swift` — an `extension CameraPath`
alongside the existing `CameraPathActs.swift` / `CameraPathPrologue.swift`
pattern. `bodyFrame` and `confine` went `private static` → `static`, same as the
existing statics in that file; nothing else changed access level. No instance
member moved or widened — the construction/sampling split Chiu rejected earlier
stays rejected.

Two more pure-static extractions came out of the initializer beyond the original
plan, once "extract `openingPlan`" alone proved insufficient (see above): `bodySpan`
(the provisional-timeline + capped-span calculation) and `simulatedTrack` (the
per-frame body-camera simulation), both also in `CameraPathCore.swift`. Both took
>6 positional parameters, so each got a small request struct
(`BodySpanRequest`, `TrackRequest`) rather than tripping
`function_parameter_count` — same shape as `OpeningRequest`/`OpeningPlan` in
`CameraPathPrologue.swift`.

### The other four files — mechanical, same recipe throughout

Every fix was "split a class/file, or extract one self-contained function,"
never a behavior change:

- **`FollowCamera.track`** (71-line function): the per-frame physics step
  extracted into a private `step(_:point:parked:constants:)`, carrying state
  through a new `SimState` struct and constants through `StepConstants` — the
  `for` loop in `track` now just calls `step` once per frame. Same computation,
  same order, nothing behavioral changed.
- **`CameraPathTests.swift`** (file 404, class 301): the "Dead-zone follow
  camera" `MARK` section (10 tests) moved to `CameraPathContinuityTests.swift`
  as `extension CameraPathTests`. Its fixtures (`straightRoute`, `longRoute`,
  `exportConfig`) went `private` → internal (no `private` keyword) since
  `private` is file-scoped and the extension is a different file — the same
  constraint that shaped the `CameraPath.swift` split above.
- **`RecapPacingTests.swift`** (class 253, only 3 over): the "Opening sequence"
  `MARK` section (3 tests) moved to `RecapPacingOpeningSequenceTests.swift` the
  same way; `config`, `deck`, `timeline`, `establishing` went internal.
- **`RecapDemoFilmTests.swift`** (file 447, class 283, func 63): `GPXFilmParser`
  (self-contained, unrelated to the class) moved to its own file unchanged.
  `photoTile(index:)` never used `self`, so it became a free function in
  `RecapDemoFilmAssets.swift` — the call site didn't even need to change.
  `importedRecap`'s per-stop photo-selection loop became
  `RecapDemoFilmTests.stopPhotoSelections(detail:full:)` in
  `RecapDemoFilmStopPhotos.swift`, returning a `StopPhotoSelections` struct
  (three dictionaries would have tripped `large_tuple`).

**Ran `xcodegen generate` after adding each new file** — the `.xcodeproj` is
generated and didn't pick up new files under `Tests/AppTests` until regenerated
(silent "cannot find X in scope" otherwise; `Core/ExportEngine` picked up its new
file without regenerating, so this is inconsistent — worth remembering, not worth
chasing down further right now).

### Two gates guard `CameraPath.swift` — reconfirmed green, not just assumed

`RecapCameraContinuityTests` samples `cameraFrame(atTime:)` frame by frame (≥50%
shared ground) and the subject-margin gate samples `position(atTime:)` (≤80% of
the half-frame). Both ran and passed after the full split, not just after the
`openingPlan` step.

### Landed

Both commits are in (`4460d8d` CameraPath split, then the other four files), plus
`6ae62a7`'s `RecapMode` migration. The push gave CI its first verdict on these 90
commits, and it came back red on the continuity gate — see the closed section at
the top of this file for what that turned out to be.

**The claim this section originally made — "both gates pass" — was true locally
and false on CI**, because of fixture shadowing. That is the third instance in one
session of validating under a different configuration than CI enforces
(`swiftlint` without `--strict`; the macos-15 / Xcode-26.6 gap; this). **Check
local-vs-CI parity explicitly; do not assume it.**

---

## Committed on this branch

- `762b8cb` **fix(recap)** — the opening hands over to where the camera is
  (continuity gate green; see the closed section at the top).
- `6ae62a7` **refactor(config)** — one `RecapMode`, replacing three booleans.
  `recap_mode: "highlight"` replaced `tiering_enabled`, `uncapped_enabled`,
  `photo_allocation_enabled` and `tier_skip_share` — **those keys no longer
  exist**; earlier notes in this file that mention them describe history.
- `4460d8d` / `850a995` **refactor(recap)** — the `swiftlint --strict` split.
  ⚠️ `850a995` does not compile in isolation.
- `94a864e` **feat(import)** — `PHAsset.isFavorite` plumbing and the opaque ice
  layer.
- `6f44b57` **docs(adr)** — the budget law, written down once (`Docs/decisions.md`).
- `ea32ce9` **feat(recap)** — kept-stop count derived from the film's duration.
- `69b5ad5` **fix(recap)** — stop pins sit on the route (two bugs, one symptom).
- `2b7b657` **fix(naming)** — landmark → town → address, never "Unnamed stop".
- `229ab39` and earlier — see `git log`.

**Working tree is clean as of 2026-08-08 and PR #12's CI is green** (run
31250437647). `RecapReviewGeocoder` and the quiet-stop pins referenced by earlier
versions of this section landed with the commits above — verify against
`git status` rather than trusting this list.

**Not merged to main:** PR #11 (`phase-3-recap` → `main`) holds until the §6 gate
passes (owner call). PR #12 stacks on it.

`Tests/Fixtures/trips/local/` is gitignored and always dirty by design; that is
real trip data and must never be added — nor moved to another path inside the
repo, which is not covered by the ignore rule.

## "Unnamed stop" — CLOSED 2026-08-04

Verified on the iPhone 17 Pro simulator against the real 170-photo Iceland
library imported through the actual S1 → S3 flow (18 stops):

- wait for naming, then export → **18 of 18 stops named**;
- with the gate temporarily removed → the export screen opens with **6 of 18
  still unnamed**, which is the original failure reproduced.

What went wrong before, and the lesson worth keeping: the 2026-08-03 throttle fix
was reported green against `GeocodePolicy` alone — a pure struct with no queue,
no retry and no database — while `StopNamer` owned a concrete `CLGeocoder` and
was therefore unreachable from any test. **The desk render path never geocodes at
all** (`RecapDemoFilmTests.importedRecap` builds an in-memory DB and reads
`stop.name ?? "Unnamed stop"`), so no amount of desk rendering could ever have
verified it. Naming runs only from `TripDetailModel.load()`.

Now in place:

- `App/Services/StopGeocoding.swift` — the protocol seam; `CLGeocoderStopGeocoder`
  is the only place CLGeocoder lives.
- `StopNamer` reports `Progress`; S3 shows "Identifying stops… n of N" and
  disables the film button until every stop has left the queue.
- `Tests/AppTests/StopNamerTests.swift` — three deterministic tests over a stub,
  plus `testLiveGeocoderNamesStops` (env-gated, real network, passed 3/3 on the
  simulator). The throttle test was validated by *reverting the fix*: without it
  the third lookup fires 1.5 ms after the second.

---

## Deck budget — RESOLVED 2026-08-06 (`ea32ce9`, ADR in `Docs/decisions.md`)

**The defect.** Above roughly ten presented stops, every stop showed a single
photograph: the duration ceiling scaled all dwells down by one global factor and
`deck_photo_min_hold_s` then truncated each deck to what its window could afford.

**The fix.** How many stops a film may present is now *derived from its duration*
rather than configured — see the ADR for the formula and the reasoning. A 120 s
film keeps 11 stops for a 65-stop trip and a 20-stop trip alike, each showing 3
photographs, with no per-trip tuning.

**The evidence, kept because it is what the law was built from:**

| trip | presented stops | film | photos per stop |
|---|---:|---:|---|
| Iceland | 65 | 30 / 60 / 90 / 180 / 195 s | **1 at every length** |
| Iceland | 25 | 195 s | 1 |
| Iceland | 14 | 195 s | 2 |
| Iceland | 7 | 195 s | 6 |
| New Zealand | 20 | 90 s | 1 |
| New Zealand | 20 | 195 s | 2.9 mean |

Duration alone never fixed it — above ~20 presented stops no watchable length
works, so the lever is *how many stops the film presents*.

**Why CI never caught it.** The committed fixtures are Iceland 16 photos/6 stops
and New Zealand 13/3, both just under the cliff.
`RecapDeckBudgetTests.testARealScaleTripDoesNotCollapseToOnePhotoPerStop` builds a
20-stop trip arithmetically and guards it. It is still wrapped in
`XCTExpectFailure` **because it measures the default policy, which has not
changed** — it skips itself under `.highlight` (see `RecapDeckBudgetTests`), which
is now the shipped `recap_mode`. Remove the expectation only when the default mode
is one that provably prevents the collapse for every trip size.

**Superseded and gone:** `tier_skip_share` as a tuning knob — the config key no
longer exists (it needed 0.82 for Iceland and 0.5 for NZ, which is what prompted
the ADR). `StopWeighting`'s
waypoint threshold remains in the tree but was measured as far too conservative to
matter — 8 of 65 stops on Iceland — and is not the mechanism anything relies on.

**Measurement aids, marked temporary in-code:** `Export.withTotalDuration`,
`RecapDeckBudgetTests.testReportRealFixtureBudgetSweep` (`KAMOME_BUDGET_FIXTURE`,
`KAMOME_BUDGET_DURATIONS`), and `KAMOME_FORCE_DURATION_S` in the render harness.

---

## `stop_weighting_enabled` — reachable in BOTH modes, containment only empirical

**Corrected 2026-08-07.** An earlier note in this file claimed it was "unreachable
by construction" under `.highlight`. **That was wrong**, and the error was
overclaiming a structural property from two datasets. Chiu asked for the verdict
to be split per mode, which is what exposed it. Classified separately, both
answers are *empirical*, and neither is safe to rely on for a removal PR.

### Under `.highlight` — NOT dead by construction. Empirically zero on big trips only.

Tiering keeps the top `keptStopCount` stops by score, and `StopWeighting` demotes
stops with ≤ `waypoint_max_photos` (2) *and* a short dwell. Those sets are disjoint
**only while the trip has more stops than the film can keep** — because then only
heavily-photographed stops survive the cut.

**When a trip has fewer stops than the budget keeps, every stop survives, including
two-photo ones, and `StopWeighting` fires.** Measured at a 120 s film
(`keptStopCount` = 11):

| fixture | stops | waypoints under `.highlight` + weighting |
|---|---:|---:|
| Iceland | 65 | 0 |
| New Zealand | 20 | 0 |
| **Margaret River** | **4** | **1** ← fires |
| Finland | 3 | 0 |

So the "0 waypoints" result on Iceland and NZ is a consequence of those trips being
*large*, not of the filters being mutually exclusive. A short trip reaches it.

### Under `.full` — non-dead, and the containment is empirical too.

It fires: 8 of 65 on Iceland, 1 of 20 on NZ. The claim that its targets are always
inside the allocator's bottom-`allocation_zero_share` (40%) zeroing is **not
structural**: the allocator ranks by *relative* score, so whether a two-photograph
stop lands in the bottom 40% depends on the distribution of the rest of the trip.
On a trip where most stops carry two photographs, a two-photograph stop can rank
well above the 40th percentile and be given photos by the allocator that
`StopWeighting` then strips.

Iceland and New Zealand both have long, heavily-skewed tails (2 → 252 photographs),
which is exactly the shape that makes containment hold. **It has not been shown to
hold on a flat distribution, and no such trip has been tested.**

### What this means before running `.full` on new data

Chiu intends to use `.full`. Margaret River, Miyakojima and the WA trip have **not**
been measured under it. `StopWeighting` applies *after* the mode in
`RecapComposer`, so it can strip photographs the allocator granted — the mechanism
is live, not theoretical.

### The removal criterion (Chiu 2026-08-07) — decided in advance so it is not re-litigated

Two **separate** questions, to be measured separately on Margaret River,
Miyakojima and the WA trip under `.full`:

1. **Structural eligibility** — does `stop_count <= keptStopCount` reliably predict
   when `StopWeighting` fires? This is the technical question above: *can* the code
   path execute, and is there a rule that says when.
2. **Perceptual impact** — when it *does* fire, is the rendered film perceptibly
   different? Render both ways and compare the actual output, not the stop table.

They are complementary, not alternatives. A path can be technically live and
visually irrelevant.

**The criterion: if question 2 comes back "not distinguishable" consistently across
all three trips, that is grounds to remove the feature outright — regardless of
whether the code path still technically executes.** A live-but-invisible branch is
not a reason to keep configuration surface.

Conversely, a single trip where the film is visibly different keeps it, and the
answer to question 1 then decides whether the trigger needs to become structural
rather than incidental.

**A removal PR must not cite "provably contained".** It must either measure the new
datasets, or make the containment structural (e.g. run the classifier *before*
allocation, or fold its threshold into the allocator's scoring).

**Not removed** (Chiu 2026-08-07): timing and review scope, decided separately after
the `RecapMode` migration lands and passes CI.

## Open question — RecapMode may be two axes, not one (Chiu 2026-08-06)

`RecapMode` is being introduced as a two-case enum (`highlight` | `full`).
**Deliberately no placeholder cases**: every `switch` over it is exhaustive with
no `default:`, so the compiler forces every call site to be revisited when a case
is added. That is the extensibility mechanism — not speculative cases sitting
unused.

The note worth keeping: the next variant Chiu has in mind — *full stop coverage,
zero photographs* — mixes **two independent axes**:

| axis | today's cases differ on it |
|---|---|
| which stops survive | `highlight` keeps ~11, `full` keeps all |
| how many photographs each gets | `highlight` gives 3, `full` gives 0–3 |

"Full stops, no photos" is the first combination that needs one axis without the
other, and a third case would encode a *pair* of choices as a single name. If a
fourth follows, `RecapMode` should probably split into two orthogonal enums rather
than grow. **Not acting on this now** — recorded so the pressure is recognised
when it arrives instead of being rediscovered.

## Known cosmetic tradeoff — flat glacier (Chiu 2026-08-06: leave it)

`Config/RecapThemes/modern-minimal.json` draws the `ice` layer **opaque**
(`#4e5c64`) to kill the pale cross over Vatnajökull — a z6 tile seam where the ice
polygon runs into the tile buffer and both neighbours draw the overlap
(diagnosed `71caf77`). An opaque fill cannot double-blend.

The cost: `hillshade` is layer 1 and `ice` is layer 5, so **the glacier renders
flat, without terrain texture**. Chiu has seen it and chosen to keep it for now —
cosmetic polish, not urgent. The proper fix is clipping the landcover buffer in
Planetiler and rebuilding all four regions, which keeps translucency; do not do
that rebuild without asking.

## Phase 2 (real app release) — parked, not blockers for Phase 1

Phase 1 is Chiu's own desk-rendered films at release visual quality. These three
matter only for an App Store release and are deliberately not being solved now
(Chiu 2026-08-05):

- **On-device render time is unmeasured.** Iceland at 6m44s is 12,110 frames and
  took ~1000 s on this Mac. The only budget ever discussed is "<90 s for a 30 s
  film". A long film on a phone could be tens of minutes — this is the single
  biggest viability risk for uncapped mode on device.
- **Routing endpoint.** The app ships `matching.base_url: ""`, so a real user's
  film is dashed everywhere while desk pilots (pointed at a live OSRM) draw solid.
  Either ship a server, bundle route data, or accept dashed — a product decision.
- **Device-representative run.** No import→Trip Detail→export run has ever been
  done with the experimental modes on. iCloud-resident photos, memory and thermals
  at 12k frames are all untested.

## Base map — MapLibre is the substrate; MapKit is the uncovered-trip fallback

**Framing corrected 2026-08-08** (`Docs/decisions.md`). MapLibre is the committed
MVP substrate. `MapKitSnapshotProvider` is **not** a candidate primary — it is the
fallback that keeps a trip outside the installed regions from rendering blank
frames.

`RecapModel.snapshotProvider(for:)` picks per trip by whether a `.pmtiles` region
covers it (`RecapMapTiles.tilesURL`). No region ⇒ `MapKitSnapshotProvider`. The
simulator has no region installed unless `KAMOME_TILES_PATH` is set, so an in-app
recap there renders on Apple's map — a **test-environment** artifact, not the
product's substrate. The review harnesses (`RecapReviewScene`) require a region
and therefore always exercise MapLibre.

Two things that remain true and matter:

1. **Visual parity does not exist, and is not expected to.** The souvenir-map look
   is a Kamome-authored style JSON only MapLibre consumes; MapKit renders Apple's
   own tiles — the look rejected in the v1.5 pivot. Overlays, subject, chrome and
   the camera are renderer-independent and work over either. Any future
   substrate comparison is settled by **rendered A/B**, per the ADR.
2. **The fallback silently degrades pacing.** `establishing == nil` drops the film
   to the retired flat `target_duration_s` with no prologue. On the committed
   substrate that makes every uncovered trip a 30 s film for reasons that have
   nothing to do with its content — see the `establishing` split above. This is
   the core-path defect, and it is what makes the fallback currently dishonest
   rather than merely plainer.

## Fixtures and the §6 gate — Stage 0

`Tools/exif-to-fixture.sh` re-run 2026-08-04 with `exiftool` 13.55 (Homebrew).
**This mattered more than expected:** the previous run used `mdls`/Spotlight,
which saw only **170** of the Iceland folder's geotagged photos. exiftool sees
**2300**. Every measurement taken against the old dump was against a 13×
under-sample.

Current local dumps (gitignored, `Tests/Fixtures/trips/local/`):

| fixture       | photos | span    | stops |
|---------------|-------:|--------:|------:|
| `iceland`     | 2300   | 318.2 h | **65** |
| `new-zealand` | 160    | 272.2 h | **20** |

New Zealand really is 160 — only 160 of its 1272 jpegs carry GPS. That is the
data, not the tool.

**The unresolved tension, stated plainly.** Stage 0 wanted real-scale fixtures so
bugs like the deck budget reach CI. But `exif-to-fixture.sh` writes to a
gitignored directory *on purpose* — a real dump is a record of where a person
was, and §0 forbids committing it. **A gitignored fixture cannot run in CI by
definition.** These two requirements cannot both be met by committing a real
dump; that is precisely what went wrong on 2026-08-02.

The split adopted here:

- **Real dumps** drive desk review and gate renders (`KAMOME_PILOT_FILM`,
  `KAMOME_STOP_STILL`, `KAMOME_TIMELINE_REPORT`), which is what Stage 0 is
  actually for.
- **CI guards generate their own scale** — `RecapDeckBudgetTests` proves nothing
  about the defect depends on *where* the stops are, only how many there are and
  how many photographs each carries.

**Still missing for §6:** three real trips → shareable films, ≥1 published,
limited-photo re-check on device, stable MP4 export. Two real trips exist as
dumps (Iceland, New Zealand); the third is not collected. Photo sources live at
`~/Desktop/Iceland` and `~/Desktop/NZ` — outside the repo, deliberately.

---

## Environment gotchas that cost time

- **The desk render path and the app disagree about routing.** `matching.base_url`
  ships `""`, so the shipped app reconstructs **no** legs and draws everything
  dashed; the desk harness defaults to `http://127.0.0.1:5100` and reconstructs
  most of them. A film that is dashed everywhere is almost certainly an app-config
  artifact, not a regression.
- **`RouteMatchService` logs the wrong base URL** when a reconstructor is injected
  (which every desk harness does): it prints `config.matching.baseURL`, so the log
  says `"(none — matching disabled)"` in the same run where legs reconstruct
  against a live OSRM. `App/Services/RouteMatchService.swift:39`. Unfixed; it is
  the line you would otherwise trust to answer "which server did this build ask?".
- **Agent shells here are sandboxed.** `curl` to localhost and `docker ps` fail
  with what look like "server is down" errors even when the server is running.
  Confirm through a test run, not through curl.
- **OSRM on `:5100` is compose-managed and restart-safe** — corrected 2026-08-09.
  It is the `osrm` service in **`Deploy/docker-compose.yml`** (container
  `kamome-osrm`, `restart: unless-stopped`, healthcheck green), so it comes back
  on its own provided Docker Desktop starts at login. Start it with
  `cd Deploy && docker compose up -d`.

  The stale claim this replaces — "started ad hoc, will not come back" — was
  reading `~/kamome-osrm/docker-compose.yml`, a **legacy file** carrying only
  taiwan:5002 and australia:5001. Nothing runs from it; the per-region servers
  were replaced by the single merged extract when `Deploy/` landed (`0924eca`).
  It is outside the repo and harmless, but it is what to ignore when checking
  whether routing is up. `docker ps` is the answer, not that file.
- Tiles/terrain: `~/kamome-osrm/tiles`, `~/kamome-osrm/terrain`.
- `simctl addmedia` fails with LaunchdSimError 133 unless the device is actually
  booted — boot it first, the error does not say so.

## Tile regions need establishing headroom, not just coverage (2026-08-08)

**A region that merely covers a trip renders a flat opening.** Derivation and
numbers: `Deploy/regions.json` `_establishing_headroom`. The rule:

    containedSpan(region) >= wide_span_padding x fittingSpan(trip)   (1.5x)

`containedSpan` is the widest **portrait** frame fitting inside the region, so for
a wide region it is bounded by *latitude*: `0.5625 x latExtent`. In latitude the
rule is **2.67×** the trip's fitting span.

Two things that cost a tile build each:

1. **This was briefly 1.875×.** While the body span also used `wide_span_padding`,
   the establishing beat and the body were the same expression, so the only zoom
   available came from a third, wider *country* beat that had to beat the regional
   beat by `opening_collapse_zoom_ratio`. Iceland was rebuilt to 1637 km of
   latitude for a shallow 1.25× zoom sitting on the collapse threshold. Splitting
   `body_span_padding` out removed the need entirely: the zoom now comes from
   regional → body, the region can be **smaller** and the zoom **deeper** (2.5×).
   If `body_span_padding` ever returns to ≥ `wide_span_padding`, this goes back to
   1.875×.
2. **A margin on the trip's own bbox is the wrong mechanism** and can shrink
   coverage: 1.4× Iceland's trip bbox is 365 km tall, smaller than the 518 km
   region it already had. There is also no code that sizes coverage to a trip —
   regions are hand-authored in `Deploy/regions.json`.

`Tools/tile-headroom.sh` reports this for any `.pmtiles`, and `build-tiles.sh`
runs it after every build so a region that will render flat is visible at build
time rather than in a finished film.

### Size cost, and the Phase 2 flag

Iceland **158.7 MB → 159.5 MB (+0.5%)** for 518 km → 1322 km of latitude — cheap
because the added area is open sea and empty tiles dedupe in PMTiles. (Measured
with `ls`. An earlier version of this section said +11%; that mixed `du` disk
blocks with `ls` bytes and was wrong.)

**Flagged for Phase 2, not solved now:** a margin that falls on **land** is
different in kind, and not only for size. The Geofabrik extract stops at the
country, so a neighbouring landmass inside the bounds has no OSM data and
**renders as ocean**. Iceland's margin is open sea so it does not bite here; a
continental region cannot be widened this way without widening the extract too.

**Local tile state:** `~/kamome-osrm/tiles/iceland-2026-08-08b.pmtiles` is the
1.5× build the harnesses now pick up. Superseded regions are parked in
`~/kamome-osrm/tiles-superseded/` (outside the scanned directory, so they cannot
be selected by accident): the original whole-island build, and the abandoned
1.875× one.

**Terrain was not rebuilt.** `iceland-terrain.pmtiles` still covers the old island
bounds, so the establishing shot's outer margin has no hillshade. It is open sea,
so nothing is visibly missing — but a wider terrain build is the honest follow-up.

## The seam is bounded by the collapse rule, not by taste

`FollowCameraRestingFrameTests.testTheOpeningHandsOverWithoutAJump` asserts the
one-frame step at the opening→body seam is within
`export.opening_collapse_drift_fraction` (15%) of the frame. That is not a chosen
number: when the closing zoom plays it ends exactly on the live track and the seam
is ~0, and when it is *collapsed*, `isEffectivelyTheSame` is what permitted the
collapse — so its drift allowance is precisely the largest cut the design allows.
Margaret River sits at 8.6% of that 15%.

An earlier version asserted a flat "under 5% of the frame", which was fine while
the seam was always a cut and started failing the moment `body_span_padding` made
the closing zoom a real 2.5× move.
