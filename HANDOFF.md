# HANDOFF — current state

**Updated 2026-08-30.** `main` carries PRs #16–#24; the cross-region crossing
beat is on `feature/p4-cross-region-crossing`, unmerged and unjudged. Written so
a fresh session can pick this up without being briefed by hand.

🔴 **The P0's falsification pair has been rendered and the mechanism is
CONFIRMED** — see the crossing-beat session's finding 3, which supersedes the
"effect INFERRED" status the 2026-08-30 PO findings' item 1 carries.

⚠️ **CI is blocked account-wide from 2026-08-29** (Actions spending limit) — a red
check right now is not a test failure. See finding 2.

Read `Docs/current-state.md` first for the project snapshot, then `CLAUDE.md`
for the standing rules — especially **§0, location data never leaves the device
by default**, as amended by the routing ADRs (`Docs/decisions.md` 2026-08-16 and
2026-08-20 (b)/(c)).

**This file holds only what is current**: live findings, open experiments, and
known bugs. Closed, resolved, and superseded sections were moved verbatim to
`Docs/_archive/handoff-2026-08.md` on 2026-08-21 — that file is history, never
current state.

---

## Findings — engineering session, the cross-region crossing beat (2026-08-30)

**Context.** `Docs/eng-session-cross-region.md`, session 1 of 2: the crossing as
a beat and a camera move, **no classifier**, plus the P0's measurement (step 5b).
Branch `feature/p4-cross-region-crossing`. Nothing here is in
`Docs/decisions.md` — Chiu has not judged the film.

⚠️ **Read findings 1 and 2 before believing anything anyone has written about
the destination's scale, including this session's own brief.** Both are
measurements that contradict a documented premise.

---

### 1. 🔴 THE PAN FLOOR IS NOT WHAT MAKES THE DESTINATION A SMUDGE — measured, and it changes what fixes symptom 2

`Docs/camera-arcs.md` §5 and `HANDOFF.md` 2026-08-21 finding 5 both say, in
almost the same words, that `RecapDurationPlan.bodySpanM`'s pan floor is the
mechanism: *"the flight's 450 km is what forces the destination to render as a
smudge — symptom 2 of `cross-region-journeys.md`, in exact code terms."*

**On the shipped path that is false**, and the correction step 3 of the brief
asks for therefore buys nothing there. Measured on the new crossing fixture,
same trip, four configurations:

| configuration | body span | worst snapshot overlap | breaks |
|---|---:|---:|---:|
| crossing established, `establishing` = synthetic extent | 18.6 km | 38% @ 64.0 s | 4 |
| **crossing established, `establishing: nil` — what ships** | **274 km** | 98% | 0 |
| no crossing, synthetic extent (the pre-change film) | 39.5 km | 50% | 0 |
| **no crossing, `establishing: nil`** | **274 km** | 70% | 0 |

The two shipped rows are **the same number**. Taking the crossing's 307 km out of
the pan floor changed the body span by nothing at all, because the pan floor was
never binding: `bodySpanM` returns `min(max(asked, floor), established)` with
`asked = establishedSpanM / target_zoom_ratio`, and on this trip `asked` is
~274 km against a pan floor of ~16 km. **`target_zoom_ratio` over the
establishing shot is what sets the body span, and the establishing shot is the
whole trip's bounds × `country_view_padding` — which includes the crossing.**

So symptom 2's actual cause is the **opening**, not the pan floor. That lands it
squarely in `HANDOFF.md` 2026-08-30 finding 2 (the opening has never shown a
country, because `establishing` is permanently nil) — the two are one defect seen
from two ends, and this session was explicitly told not to fix that one.

**The correction is still right and still landed.** It binds the moment a region
*is* installed — 39.5 km → 18.6 km, 2.12× tighter, on the row above — and it is
what stops a future tiles build from reintroducing the smudge. It is simply not
sufficient on its own. `RecapCrossingArcTests.testTheCrossingsDistanceLeavesTheBodySpan`
prints both spans on every run.

**Visible in the judgement film, which is the point.** At 27.0 s the apex has
both Taiwan and the Yaeyama islands on screen with the dashed leg and the plane
between them — the beat works exactly as `camera-arcs.md` §3 describes. Six
seconds later the camera has closed in and **Ishigaki is a smudge about a fifth
of the frame wide, floating in open ocean**, which is symptom 2 unchanged. Stills
in `~/Kamome-films/2026-08-30-crossing/`, named for what they show.

**INFERRED, not verified:** that framing the opening on the *first local journey*
rather than the union (`cross-region-journeys.md` requirement 5) would fix the
shipped case. Cheapest thing that would settle it: build the crossing fixture's
timeline with `establishing` derived from the destination segment's bounds and
print `bodySpanM`. Twenty minutes; not done here because the opening is another
session's.

### 2. ⚠️ The continuity gate has never measured the shipped camera

`RecapCameraContinuityTests` passes a **synthetic `establishing` extent** (the
trip's own bounds) with the comment *"Widening the trip's own bounds is what the
prologue does when no region is available, so this is the same code path, not a
stub."*

**That claim is wrong.** A non-nil `establishing` takes the *other* branch of
`buildWideOpening` and, more importantly, activates `cappedToRegion` in three
places. The shipped app has passed `establishing: nil` since MapLibre was parked
on 2026-08-15. On one fixture the two configurations differ by **18.6 km vs
274 km of body span** — an entirely different camera.

Not changed here, deliberately: `establishing: nil` yields a *wider*, more
forgiving span, so switching the gate to it would weaken what it catches, and
that is a bar move for Chiu (`Arch.md` §7.1). **Recorded so the gate's own
comment stops being believed.** The cheap fix is probably to scan **both**
configurations rather than to swap one for the other.

### 3. ✅ THE P0's FALSIFICATION PAIR: the mechanism is CONFIRMED, end to end

`HANDOFF.md` 2026-08-30 finding 1 was *mechanism VERIFIED, effect INFERRED* —
"nobody has yet rendered the pair." Rendered now, and the prediction holds
exactly.

**Method.** `miyakojima` (the local dump), 10 s of **body** at 20.0–30.0 s,
rendered twice through the shipped loop, identical in every respect but
`keyframe_interval_frames` — 15 versus 1. Both runs routed identically
(`walk/inferred` + 9 × `drive/reconstructed`), so the geometry is the same film.
Frames extracted and compared per frame in greyscale.

**Result — the ghosting is a sawtooth locked to the blend, exactly as the
mechanism predicts.** Mean absolute difference between the two clips, by phase
within the 15-frame snapshot cycle:

| blend | 0.00 | 0.13 | 0.27 | 0.40 | **0.53** | 0.67 | 0.80 | 0.93 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| difference | 0.07 | 0.35 | 0.49 | 0.55 | **0.57** | 0.54 | 0.44 | 0.26 |

At blend 0 the two clips are the *same picture* — that frame is a real snapshot
either way. It diverges monotonically to a maximum at the half-blend and comes
back. That is `FrameCompositor`'s `context.setAlpha(background.blend)` and
nothing else.

**And the second half of the prediction — "absent during stop beats" — holds.**
The harness now prints the hold windows it encoded, so this is checked and not
inferred:

```
KAMOME_PILOT_HOLDS window 20.00–30.00s contains 20.00–23.86s, 26.06–30.00s
```

against the measured difference:

| stretch | what it is | mean diff | peak |
|---|---|---:|---:|
| 20.00–23.43 s | inside stop beat 1 | **0.00** | 0.03 |
| 23.50–26.00 s | **travelling** between the holds | **1.60** | **3.21** @ 24.77 s |
| 26.06–30.00 s | inside stop beat 2 | ~0.06 | 0.12 |

103 consecutive frames with *zero* difference during the first hold, a 75-frame
burst during travel, quiet again during the second. The small residue just after
26.06 s is the dead-zone dolly settling, and the burst starting ~0.35 s before
23.86 s is the `subject_park_s` (0.4) pull-away ramp — the camera starts moving
before the hold formally ends. **Verdict: CONFIRMED.** Finding 1 can be marked
VERIFIED end to end.

**The cost of the naive fix, as a number.** Snapshots for that same 10 s window,
counted through the shipped loop:

| interval | snapshots in the window |
|---|---:|
| 15 (shipped) | **8** |
| 1 | **66** |

**8.25×, not 15×** — the value cache collapses every frame where the camera is
parked, which is most of a stop beat. At the device figure of 0.72–1.55 s per
snapshot that is 6–12 s of export becoming 47–102 s, **for ten seconds of film**.
Unshippable, exactly as finding 1 says; and the 8.25× is a *better* ratio than
the ~15× the finding assumed, which is worth knowing when Pass 1 is costed.

⚠️ **Not fixed here, and `keyframe_interval_frames` was not touched.** The fix is
camera-arc Pass 1's crop-scaling (`Docs/camera-arcs.md` §7). The two clips are
`~/Kamome-films/pilot-miyakojima-from20s-interval{15,1}.mp4`.

### 4. ⚠️ `Docs/camera-arcs.md` §8 states an invariant no arc can satisfy

The design says:

> For any two frames sampled a snapshot interval apart, **the tighter must lie
> entirely inside the looser.**

Asserted literally, that fails on the crossing fixture — on exactly six sample
pairs, **all of them straddling the apex**, by up to 14.8 km. It fails there *by
construction, not by defect*: an arc opens out and closes back in, so a pair
taken either side of the widest point is two different sub-rectangles of the
apex and neither contains the other. A pure translation can never satisfy it
either, for the same reason.

**The property the design needs survives, in two halves**, and that is what
`RecapCrossingArcTests` now asserts:

1. **within either half** (span monotonic) the tighter frame lies entirely inside
   the looser — measured slack 4 m, i.e. positive but tight, which is what the
   equality condition predicts;
2. **across the apex** both frames lie inside the apex, which the film was
   showing between them — measured slack 0 m, exact by construction.

The overlap gate is untouched and unrelaxed; a 15 km shift across a 490 km frame
scores ~0.95 against its 0.40 floor. **§8 should be reworded**; not done here
because `Docs/camera-arcs.md` is a design document and this is a render-free
measurement, not a judged film.

### 5. The interpolation is where the continuity guarantee actually lives

Worth knowing before anyone touches `CameraPathCrossing`: `CameraPath.lerp` moves
span geometrically and centre **linearly in time**, and that combination does
*not* preserve containment. Opening a 20 km frame to a 400 km apex, the centre
must travel ~190 km while the first frames widen by ~30 km — the early frames
slide off ground the previous frame was showing.

`containedLerp` moves the centre **linearly in span** instead. The containment
condition at every sample then reduces to one global inequality,
`|Δcentre| ≤ (apex − source)/2`, which is *exactly* "the apex contains the
source's footprint" — the definition `apexFrame` builds to. So containment is a
consequence of how the apex is sized, not a threshold, at any zoom ratio and any
duration. **No gate was relaxed and no threshold was added.**

### 6. ✅ The gate now covers a crossing, and no exemption is used by anything

`Tests/Fixtures/trips/ishigaki-crossing.json` is the first committed fixture with
a leg that has no road under it (hand-written plausible coordinates, §0). The
gate's own line, all seven fixtures green:

```
  margaret-river     60.0s · span    3.4 km · worst frame overlap  70% at  45.9s · 0 violations · 0 permitted cuts · 0 excused · 0 arcs  ✅
  miyakojima         88.0s · span   10.5 km · worst frame overlap  69% at  31.1s · 0 violations · 0 permitted cuts · 0 excused · 0 arcs  ✅
  iceland           211.5s · span   57.8 km · worst frame overlap  70% at  62.9s · 0 violations · 20 permitted cuts · 0 excused · 0 arcs  ✅
  finland            60.0s · span    9.8 km · worst frame overlap  68% at  38.8s · 0 violations · 1 permitted cuts · 0 excused · 0 arcs  ✅
  new-zealand       154.5s · span   49.5 km · worst frame overlap  70% at 142.6s · 0 violations · 14 permitted cuts · 0 excused · 0 arcs  ✅
  nz-real            88.0s · span   60.7 km · worst frame overlap  69% at  13.7s · 0 violations · 9 permitted cuts · 0 excused · 0 arcs  ✅
  ishigaki-crossing  69.0s · span   18.6 km · worst frame overlap  70% at  52.7s · 0 violations · 3 permitted cuts · 0 excused · 1 arcs  ✅
```

**`permittedCutTimesS` answered, at last.** `HANDOFF.md` 2026-08-21 finding 3
listed as UNKNOWN whether any fixture exercises the exemption; `camera-arcs.md`
§0 then said it does, "heavily", from the *availability* count. Both were reading
the wrong column. The gate now counts cuts actually **spent**, and it is **zero
on every fixture** — 44 permitted cuts are available across the suite and not one
excuses a violation. The exemption is already dead code by measurement, so
`camera-arcs.md` §8's "make the gate fail rather than forgive" is now a safe
change. **Not made here** — it is a bar move and Chiu's (`Arch.md` §7.1).

### 7. ⚠️ The end reveal was broken for an elongated trip, and it is fixed by the 2026-08-08 precedent

The crossing fixture broke the gate at 64.0 s — **not in the arc**, in the end
reveal. `endRevealFrame` applies `cappedToRegion` to a span meant to *contain* the
route; when the cap bites, the "reveal" is centred on the route's bounding box
anyway and flies 150 km out to sea across a 47 km frame.

This is precisely the fault `wideBeat` was given a fix for on 2026-08-08 —
*"a beat that had lost its reason to exist and kept its motion"* — and the same
fix is applied: a reveal too tight to hold the journey lands where the journey
ended. **No shipped film changes** (with `establishing` nil the cap is a no-op
and the guard never fires), and the six existing fixtures' gate numbers are
bit-identical before and after.

**Reachable before this session?** No, on the fixtures in the tree: the same
fixture with the crossing unestablished (span 39.5 km) has 0 breaks. Tightening
the body span is what exposed it. It would have hit the first elongated real trip
in a tiles build regardless.

### 8. What was built, in one paragraph each

- **The verdict leaves the provider.** `RouteReconstructing` answers
  `RouteReconstruction` — `.routed` / `.noRoadHere` / `.implausible` /
  `.notEstablished(reason)` — instead of `RouteMatchOutcome?`. Six `return nil`
  sites in `GeoapifyRouteProvider` became four named answers. `RouteMatchReport`
  splits `noPlausibleRoute` into no-road, implausible and not-established; its
  headline is unchanged, because the *sentence* shown to a user is a copy
  decision nobody has made.
- **Schema v4**, `segment.routability`, nullable. `SegmentRoutability` is the
  first of the three provenance enums that **refuses to default a NULL** — the
  other two have a safe legacy meaning and this one does not. Stored rather than
  carried in the report because routing is a detached background step since
  2026-08-15 and the recap may run days later.
- **The beat.** `CameraPath.Phase.crossing`, priced at `crossing_beat_s` (6.0,
  new config key) out of the travel budget rather than per metre, capped by
  `max_hold_fraction` — reused deliberately rather than adding a second constant
  for "time not spent covering ground".
- **The arc.** `CameraPathCrossing.swift`. Apex = smallest frame containing both
  end footprints × `crossing_apex_padding` (1.5, new key — ≥ 1.25 is what keeps
  `confine` a no-op; measured subject reach **50%** of the half-frame against the
  80% safe zone, and confine never fires).
- **Fine sampling** extended from "the opening" to `fineSampledWindowsS` —
  opening plus arcs. **Temporary**, and the code says so.
- **The sprite.** `SubjectState.role` (`.vehicle` / `.crossing`), resolved to art
  by `FrameCompositor`, so the camera still knows nothing about transport
  (`camera-arcs.md` §6). Shipped default `VehicleCatalog.crossingSubjectId` =
  **the `seagull` omni sprite from `vehicles.json`** — not `VehicleMarker.seagull`
  (the end-card brand mark) and not `.seagullBadge` (the fault marker). The
  judgement film renders with `plane` via `KAMOME_CROSSING_SUBJECT`.

### 9. ⏳ Open, and Chiu's — not defaulted by this session

- **Is the crossing seagull still a choosable trip subject?** It ships
  `selectable: true`. The precedent for crossing art is `plane`/`boat`
  (`selectable: false`); the counter-precedent is the reindeer sets. Left
  untouched, because *"does the seagull carry the brand or dilute it?"* is an open
  question in `cross-region-journeys.md` and a brand decision.
- **Does the apex want a hold?** The arc is two smoothstepped halves with no
  pause at the widest point, where both places are on screen together. A hold
  there is a story judgement from the film.
- **`crossing_beat_s` = 6.0 s** is reasoned (two `zoom_transition_s` eases plus a
  beat at the apex), not measured against a judged film.
- **Case C is not built.** A trip that *begins* with the crossing
  (`camera-arcs.md` §4) still gets an opening and then an arc; merging them is
  named in the code and deferred.

### 10. What the crossing costs, and what to watch when Pass 1 lands

Measured through the shipped loop (`RecapSnapshotBudgetTests`, `establishing:
nil`, i.e. the device path):

| film | snapshots | opening | body |
|---|---:|---:|---:|
| `miyakojima` (unchanged control, reproduces the 2026-08-21 figure exactly) | 191 | 151 | 40 |
| `ishigaki-crossing`, **crossing not established** | 185 | 151 | 34 |
| `ishigaki-crossing`, **crossing established** | **367** | 151 | **216** |

**The arc costs 182 snapshots over a 180-frame window** — one per frame, which is
what fine-sampling means, and it very nearly doubles the film's whole budget. On
device at 0.72–1.55 s per snapshot that is 133–287 s becoming 264–569 s for a
69-second film. **This is the number camera-arc Pass 1's crop-scaling has to
refund**, and it is now a measurement rather than an estimate.

⚠️ Note the opening is **151 in every row** — unchanged, as it must be. If a
later change moves it, something has touched the prologue.

### Delivery

- Branch `feature/p4-cross-region-crossing`. **Local verification only: CI has
  been dead account-wide since 2026-08-29** — `main` itself fails in ~5 s with
  zero steps executed, so a red check on this branch says nothing. Re-checked
  2026-08-30.
- `xcodebuild -scheme Kamome test` — **366 executed, 25 skipped, 0 failures**
  (baseline before this work: 359 / 25 / 0). The seven new tests are four in
  `RecapCrossingArcTests`, two in `SchemaTests` and one in
  `RouteReconstructionTests`; **no test was deleted or weakened**, and the two
  that changed shape did so because the rule moved (`Arch.md` §7.5): a nil that
  used to mean "no route" now has to say *which* kind. `swiftlint` **0 violations
  in 174 files** (baseline 0 in 170).
- Films in `~/Kamome-films/` (outside the repo, §0):
  `pilot-ishigaki-crossing-from0s-interval15.mp4` (the judgement film, whole
  69 s, `plane`), `pilot-miyakojima-from20s-interval{15,1}.mp4` (the P0 pair),
  and four stills in `2026-08-30-crossing/`.
- **Two harness intermittents cost time**: a second `xcodebuild` against the same
  simulator kills the first (`Mach error -308`), and a full 2,070-frame MapKit
  render died once inside GeoServices even alone. `-retry-tests-on-failure` and
  one render at a time.

---

## Findings — PO/Architecture session (2026-08-30)

**Context.** A full direction-and-architecture recovery audit, plus Chiu's second
round of outside feedback. The product decisions from it are `Docs/decisions.md`
**2026-08-30**; the documentation contradictions it found are **fixed** in the
same pass and listed in finding 6. What is below is what an implementer needs and
would not otherwise see.

⚠️ **Read finding 1 before touching the render loop, the camera, or
`keyframe_interval_frames`.**

---

### 1. 🔴 The shake and the ghosting are **one mechanism**, and the obvious fix is the wrong one

**The single most important finding of this session.** Chiu's P0
(`Docs/decisions.md` 2026-08-30): *"影片晃動感太明顯 不夠流暢 會有殘影."*

**VERIFIED from code** (`RecapRenderLoop.swift:93–118`, `FrameCompositor.swift:90–93`).
The base map is not drawn per frame. It is snapshotted every
`keyframe_interval_frames` (**15**), and the 14 frames in between are filled by
**alpha-blending the two neighbouring snapshots**:

    context.draw(previous.image, in: frameRect)          // the map at position A
    context.setAlpha(CGFloat(background.blend))
    context.draw(background.current.image, in: frameRect) // the map at position B

While the camera is moving, A and B are **the same map at two different
geographic positions**. Superimposed at partial alpha, every coastline, road and
label appears **twice, offset**, cross-dissolving — and the pair snaps forward
twice a second. **One mechanism, both symptoms**: the double image is the
"殘影", the 0.5 s stepping is the "晃動".

`RecapBackground.point()` interpolates the *projection* between the two snapshots
as well, so the trail and the vehicle are drawn at a blended projection — they sit
correctly on **neither** of the two images, but between them.

**Why it is there, and why nobody noticed.** The loop's own comment says it:

> `keyframe_interval_frames` (15 → two map updates a second) **is sized for a
> static camera**, where consecutive keyframes are identical and the value cache
> makes them free.

That was true on **2026-07-25**, when Chiu made the camera static. `FollowCamera`
— a continuously-moving dead-zone dolly — landed **2026-08-01**. The premise
expired and the number did not move. The same comment shows the defect was
already met once and only half-fixed:

> The opening prologue is the one stretch where the camera actually moves, and at
> that interval the map steps twice a second while the overlays run at 30 —
> **which is exactly what read as a janky zoom.** Snapshot every frame there and
> nowhere else.

The opening was fine-sampled; the body was left at 15 because the body camera was
believed to be static. It is not.

**A precise, cheap falsification** — do this before anything else:

- **Prediction:** ghosting and stepping appear **during travel** and are **absent
  during stop beats**. During a stop the subject is stationary, the dead-zone
  dolly parks, `previousKey == nextKey`, and the loop takes the
  `RecapBackground(current:)` branch — no blend at all.
- **Test:** render ~10 s of *body* (not opening) twice, identical but for the body
  interval — 15 versus 1 — and compare. Minutes, on the existing still/film
  harnesses.
- **Pass/fail:** if interval 1 is clean and interval 15 shows a double image, the
  mechanism is confirmed and this entry can be marked VERIFIED end to end. If
  interval 1 still judders, the cause is elsewhere and **stop** — the camera track
  itself is next (`FollowCamera` is pre-simulated and pure, so dump
  `(t, lat, lon, spanM)` and look at the second derivative).

⚠️ **Do NOT "fix" this by lowering `keyframe_interval_frames`.** Three reasons,
and the third is the one that matters:

1. It is **frozen** (`Docs/current-state.md`, Chiu 2026-08-15).
2. Fine-sampling the whole body multiplies snapshots by ~15. On device a snapshot
   costs **0.72–1.55 s**; a 3.5-minute film already costs about six minutes to
   export and the phone thermally throttles. This turns it into an hour.
3. **The right fix is not more snapshots — it is not cross-fading.** Between two
   keyframes the correct operation is to *reproject* one snapshot to the current
   camera (translate, and scale when the span changes), which is exactly
   **crop-scaling** — `Docs/camera-arcs.md` §7, camera-arc Pass 1. The machinery
   is half-present already: `RecapBackground.point()` proves the projection
   relationship between the two frames is known.

**Status: mechanism VERIFIED, effect INFERRED.** Nobody has yet rendered the pair
above. Do not write it up as the confirmed cause of what users saw until they
have.

> ✅ **SUPERSEDED 2026-08-30 — the pair was rendered and this is now VERIFIED end
> to end.** The difference between the two clips is a sawtooth locked to
> `RecapBackground.blend`, zero at every real keyframe and maximal at the
> half-blend; it is 0.00 through a 103-frame stop beat and peaks at 3.21 grey
> levels while travelling, exactly as predicted above. The naive fix costs
> **8.25×** the snapshots, not the ~15× assumed here. Full numbers in the
> crossing-beat session's finding 3.

### 2. 🟠 The opening has never shown a country — VERIFIED, and it is a parking casualty

The East Australia complaint (*"看不到整個澳洲… 不知道在哪裡"*) is not a camera
tuning problem.

`RecapModel.swift:204` builds `establishing` **only** from an installed `.pmtiles`
region. MapLibre was parked 2026-08-15 and nothing installs one, so `establishing`
is permanently `nil`. `CameraPathPrologue.buildWideOpening`'s own doc states the
consequence:

> Without it (no vector tiles, so Apple's map renders) the country view falls back
> to **the trip's own bounds widened by `country_view_padding`**

`country_view_padding` is **2.2** (`Config/TrackingConfig.json:131`). So the
"country" beat has always been *this trip, ×2.2*. On a compact trip inside a large
country that is geographically meaningless — which is precisely what was reported.

**The useful part for whoever fixes it:** parking MapLibre made this *easier*, not
harder. Apple Maps is a **global** base map with no extent limit — the original
constraint ("never wider than the tiles we have") no longer applies to what ships.
The app already geocodes every stop, so a country-level frame is reachable.
`country_view_padding` is a config key and is **not** frozen. Not designed here.

### 3. ⚠️ A shipping-path comment is wrong, and it hides a possibly-large question

`RecapModel.swift:201–203`:

> The region's extent drives the opening establishing shot and switches the film
> onto content-derived pacing (Chiu 2026-07-30). **No region means Apple's map, no
> prologue, and the previous fixed duration.**

**"No prologue" is false.** `CameraPath.swift:166` gates the prologue on
`openingS > 0`, not on `establishing`, and `buildWideOpening` accepts a nil
`establishing` by design (finding 2). Every film gets a prologue. VERIFIED.

**Which makes the rest of that sentence untrustworthy, and it may matter a great
deal.** If "the previous fixed duration" is also true, then **content-derived
pacing is implemented but permanently dead behind a tile condition that can never
be satisfied** — and the "film duration must scale with trip size" question that
has been open since 2026-08-14 would be an *unlocking* job, not a design job.

**UNKNOWN, and worth an hour.** The cheapest thing that would settle it: trace
`totalDurationS` into `CameraPath.init` (`let total = totalDurationS ?? config.targetDurationS`)
and print the resolved duration for two fixtures of very different size through
the shipped path. **Do not assume either answer from the comment** — the comment
has already been shown wrong on its first clause.

### 4. The pattern behind findings 1–3, named, with a sweep owed

Four defects now share one shape: **a value tuned against the MapLibre souvenir
map that silently degraded when Apple Maps became what ships (2026-08-15), with
nobody re-tuning it.**

| # | what | found | how |
|---|---|---|---|
| 1 | route **glow** inverted — lightened on dark, darkened on light | 2026-08-22 | a film review |
| 2 | **cyan trail** vanishes into water on a light base | 2026-08-27 | a film review |
| 3 | **dashed leg** indistinguishable from solid on light | 2026-08-28 | a pixel probe, accidentally |
| 4 | the **establishing shot** silently lost its country beat | 2026-08-30 | this audit |
| 5 | **`keyframe_interval_frames`** — arguably the same class, one substrate earlier: a number whose premise (a static camera) expired | 2026-08-30 | this audit |

Each was found **one film at a time, by accident**. That is an expensive discovery
method and there is no reason to think 4 was the last.

**RECOMMENDATION (needs Chiu):** one deliberate sweep — go through every value and
capability that was chosen while MapLibre was the substrate and ask *"what is this
premised on, and is that still true?"*. The question that catches this class is
not "is this value good?" but **"what was this value tuned against?"** — the same
shape as the question that caught the two colour tokens on 2026-08-29 (*"what does
this colour sit on, on each base?"*). Cheaper as one pass than as four more film
reviews. **Not scheduled; not started.**

### 5. Two claims from an outside analysis, checked and **found wrong** — do not act on them

Chiu was given a third-party analysis of the feedback. Its process advice was
sound (separate the P0 from the features; specify before building; the opening and
ending fit the existing narrow-waist types). **Two of its technical claims do not
survive checking**, and both would have cost real work:

1. ❌ **"The inter-day leg → `.walk` misclassification must be fixed in
   `ImportService.mode` before cross-region can be built."** **That bug was fixed
   on 2026-08-02.** `App/Services/ImportService.swift:120–124` carries the
   `paceUnknowableGapS` guard, and its comment names this exact defect: *"Without
   that, every inter-day leg of a multi-day trip typed as a walk and drew as a
   straight line across whatever lay between."* **The dependency it names as a
   blocker does not exist.**
2. ❌ **"Trip name is a data-model change."** `Trip.title` is already a stored
   column (`Core/Persistence/Records.swift:10`), already flows to the title card
   (`LinearTimeline`: `title = trip.title`), and album imports already use the
   album's own name (`ImportFlowModel:141`). **What is missing is an edit surface,
   not a schema change** — materially smaller than described.

Recorded because both are the kind of confident, plausible claim that gets
believed. The general rule this session applied: **check a claim against the tree
before it becomes a plan**, exactly as the 2026-08-29 rule says for style values.

### 6. Documentation contradictions found and fixed in this pass

Listed so the fixes are auditable rather than silent. All were on `main`.

| what | was | now |
|---|---|---|
| `Docs/eng-session-P4-visual.md` | "Status: NOT YET RUN (2026-08-21)" — three days after it merged as PR #18, while `current-state.md` said the opposite | banner: EXECUTED AND MERGED; original line kept as the record of what was asked |
| `current-state.md` blockers | "🔴 intermittent bundle **crash**" — `HANDOFF.md` retitled it on 2026-08-28 ("it no longer crashes") | corrected to the silent-miss form |
| `current-state.md` blockers | "worktrees silently skip half the secrets guard" — closed by `2d221e0` | marked closed; the surviving half kept |
| `current-state.md` active work | two tokens "awaiting a colour judgement" — decided, then superseded by the badge | rewritten; the whole section now names one live line |
| `current-state.md` staleness | one-half check (ADR only) that passed twice over stale blockers | two halves: newest ADR **and** newest merged PR; propagated to `CLAUDE.md` and `PO.md` |
| `Docs/decisions.md` | the 2026-08-29 badge decisions existed **only in `HANDOFF.md`**, one trim from being archived out of the ledger | written up as an ADR, dated to the day of the decision |
| `PO.md` | "the implementing session writes the ADR" was only half a rule — nobody was named to write it if they didn't | second half added: the next PO session writes it, back-dated, saying why it is late |
| `Docs/_audit/inventory.md` | a 247 KB file inventory from 2026-08-21, unbannered and nine days stale | bannered as history |

### 7. ⏳ One §0 question for Chiu, raised not answered

Two films of Chiu's **real trips** are committed to this repository —
`Docs/demos/phase3/kamome-p3-recap.mp4` and
`Docs/demos/phase3_5/kamome-recap-NZ-disaster.MP4` — while current practice
deliberately writes films to `~/Kamome-films/`, "outside the repository
deliberately (§0)". They are demo artifacts, which the Rules of Engagement
require one of per phase, so the two rules genuinely pull against each other.

**They are not in §0's decided-exceptions list** (which names only the Geoapify
routing payloads and one user-initiated share). This is an owner call and only
an owner call: either they become a **recorded exception** ("phase demo artifacts
of the owner's own trips are committed, deliberately"), or they move out. What
should not persist is the current state, where a standing rule says one thing and
the tree says another.

Checked while there, and clean: `Docs/tests/` (real GPX and sqlite drive dumps) is
gitignored, and `Docs/prototype/recap_engine.html` ships `__KDATA__` as a
placeholder — **no real coordinates are committed anywhere.** The §0 wording in
`CLAUDE.md` was corrected in this pass to name both gitignored locations rather
than only one.

**Left alone, deliberately:** `HANDOFF.md`'s "Reference — Phase 4 scope…" section
still restates `current-state.md` at greater length. It is genuine duplication and
two of the contradictions above came from exactly that split — but
`Docs/eng-session-camera-arc.md` cites the freeze it records, and it carries
reasoning the index does not. **If it moves, `current-state.md` must absorb the
reasoning first.** Same for the 2026-08-21 PO findings section, which should be
archived once camera-arc Pass 1 has run and been judged.

---

## Findings — engineering session, the silent subject fallback and the badge (2026-08-29)

**Context.** The task 2026-08-28's finding 10 spawned: make the marker fallback
loud, and find out whether it is the bundle crash wearing a different symptom.
Both answered below and in the bundle-lookup entry. Chiu then approved the
resolution diagnostic and asked for two changes to the marker itself.

**Renders for review** (outside the repo, §0): `~/Kamome-films/2026-08-29-fallback-navy/`,
five stills and a `README.md` with the numbers. Same trip, same frame (t=114.3 s)
as every subject still since the size sweep; the failure visual is *forced*, so it
is judged on purpose rather than by accident.

---

### 1. ✅ FIXED — the stand-in had become larger than the thing it stands in for

`fallbackMarkerLengthPx` was a hard-coded **170** while ADR 2026-08-27 moved
`export.subject_length_px` **225 → 157.5**. From that day the fallback seagull
rendered **12.5 px longer than the car**, and nothing failed, because the two
numbers sat side by side with nothing tying them together. Chiu noticed it by
looking.

**The fix is the relationship, not the number.** `fallbackMarkerLengthFraction`
(default **1**) replaces the absolute, and `fallbackMarkerLength(subjectLengthPx:)`
is the one place it is applied. At ≤ 1 the marker is at most the subject, whatever
the subject becomes — the inversion is now structurally impossible rather than
merely corrected. Deliberately the same shape as `length_fraction` in
`vehicles.json`, whose own comment gives this exact reasoning; the manifest cannot
supply this one, because the fallback fires precisely when the manifest could not
be read.

`subjectLengthPx(configured:)` keeps its `max` as defence for a fraction above 1,
and keeps its signature, so no probe call site moved.

**Positive control, run rather than reasoned.** With the fraction set to 1.2 the
new guard fails at all five swept subject lengths —
`("135.0") is greater than ("112.5")` and so on up to `("360.0") is greater than
("300.0")` — and passes at 1. The neighbouring wiring test passed either way,
which is correct: it holds the wiring, the new one holds the bound.

### 2. `RecapRenderTestCase:57`'s `configured: 300` is consistent, not stale — reported, not changed

Asked to look at it and say what I found rather than update it silently. What I
found is that **300 is not a leftover shipped value in this file — it is this
file's own fixture.** `RecapRenderTestCase` builds its `TrackingConfig.Export`
with `subjectLengthPx: 300` (line ~119), and `vehicleHalfPx` clears
`configured: 300`. The probe clears exactly what the render under test draws, so
the two agree and nothing is wrong. 300 is also the suite-wide convention for a
synthetic subject: `CameraPathTests`, `RecapPacingTests`, `RecapEncoderTests`,
`LinearTimelineTests`, `RecapMarkerDeckStillsTests` and `RecapFollowCamStillsTests`
all use it.

**What is true is the reading risk**, and it is the same one that has now cost
this project four times: a number in a test file that resembles a shipped value
but is not one. Changing it would mean changing the fixture too, which moves what
the golden-frame probes render and clear — a real change, for no defect.
**Left alone.**

### 3. ⛔️ SUPERSEDED BY THE BADGE — which navy, and the constraint stated as a number

> **Closed 2026-08-29 without a pick.** Chiu's verdict on these stills was that
> none of them read as blue, and the measurements below say why: every candidate
> that clears a luminance ceiling is too dark for hue to register. The badge
> (finding 6) removed the premise rather than answering the question. **No navy
> was chosen and none should be.** Kept because the numbers are what made the
> badge's case, and because "the target could not be hit" is only visible from
> them.


Chiu wants the marker blue rather than the near-black ink. The constraint is
**luminance, not hue**: `testTheFallbackMarkerContrastsWithItsBaseMap` asserts
< 0.35 on light and > 0.65 on dark, and says in its own comment that it is
asserting visibility rather than an ink.

Measured on the rendered stills, in 0–255 units, against the terrain within 6 px
of the stroke:

| candidate | hex | gull L | beside | **gap** | guard |
|---|---|---:|---:|---:|---|
| white — what shipped until 2026-08-28 | `#FFFFFF` | 217.4 | 191.0 | **26.4** | ✗ |
| the ink, today | `#1C2130` | 34.0 | 190.9 | **156.9** | ✓ |
| A · near | `#17204A` | 34.0 | 190.9 | **156.9** | ✓ |
| B · deep | `#1B2A5B` | 41.5 | 190.9 | **149.4** | ✓ |
| C · bright | `#23407F` | 58.3 | 190.9 | **132.6** | ✓ |

**All three navies clear the guard — run, not calculated** (one temporary edit to
the preset per candidate, reverted; logs `~/Kamome-wt/logs-fallback-diag/guard-*.log`).
A bright cyan `#4FC3F7` was run as a control and **failed at 0.683**, so the guard
bites and is not pinning today's value.

Two things the table does not say. **The white baseline was rendered rather than
recalled** — 26.4 against 156.9 is the argument for the change, in the same frame
and the same units. And **clearing the bar is not clearing the water trap**: the
bar is brightness, the trap is hue, and `navy-C-bright` is included to show where
that begins, not as a recommendation.

**Chiu picks; nothing is committed.** The pick replaces one line in
`RecapStylePresets.modernMinimal(.light)`.

### 4. ⚠️ Base-versus-preset has now bitten four times, and the fourth is the sharp one

The glow "verified fact" quoted the neutral default's alpha 0; the PO session's
ADR quoted the neutral default's blue; both times the shipped preset said
something else. The third was spotting that the ink lives in the preset while the
base `RecapStyle.fallbackMarkerColor` is still white.

**The fourth is worse than a stale reading, and it is live.** `modernMinimal(.dark)`
**does not set `fallbackMarkerColor` at all.** The dark film therefore draws the
base default — white — and the guard's dark assertion (`> 0.65`) passes on a value
nobody wrote for dark. White happens to be right there. That is not the same thing
as it being chosen.

Two consequences worth Chiu's decision, neither acted on:

1. **Changing the base default silently changes the dark film.** This is the
   mechanical reason a navy goes in the light preset — not merely a procedural one.
2. `RecapStyle()`'s neutral defaults are load-bearing for the golden-frame gates
   (its own comment says so) *and* are the dark preset's palette by omission. Those
   are two jobs. Whether `.dark` should state its marker colour explicitly, or the
   base should be documented as "the dark preset's value, and the gates'", is a
   small design question — **reported, not folded into the colour sweep.**

### 5. ✅ RESOLVED BY THE BADGE — the fault gull and the narrator gull are no longer the same bird

**This entry stood as 🔵 CARRY. The badge (finding 6) closed it structurally**,
which is a better outcome than the decision it was waiting for.

`Docs/cross-region-journeys.md` requirement 4 — *"the load-bearing one"* — wants a
seagull as the **narrator of an unmodelled crossing**: honest provenance made
visual, and its own words are that this answer "must be cheap and
**good-looking** rather than a failure state." The fault marker was being styled
in the opposite direction. They were different objects — an omni sprite from
`vehicles.json` versus a vector arc from `RecapStyle` — but a viewer could not
tell them apart.

**A badge reads as a marker; a bare bird reads as a bird.** `.seagull` is
untouched and still drawn (see below); `.seagullBadge` is the fault indicator.
The narrator keeps the plain gull, and nothing has to be decided about which
reading wins.

### 5b. 🔴 THE NEAR-MISS — `.seagull` is also the end-card brand mark

**Found while designing the badge, and it is the reason the badge is a new case
rather than a restyle.** `RecapOverlayChromeDrawing.drawMark` draws
`VehicleMarker.seagull` as **the Kamome wordmark's bird on the end card**, in
`chromeAccentColor`, unrotated — "from the same vector the fallback vehicle
marker uses rather than a bespoke asset".

So the obvious implementation — change `drawSeagull` to draw a badge — would
have **silently turned the brand mark on every end card into a blue disc.** No
test asserts the end card's mark shape; it would have shipped.

The bare gull now has three consumers and they are properly separate: the brand
mark, the fault badge (via its own case), and the cross-region narrator that has
not been built. **Do not restyle `.seagull` in place.**

### 6. ✅ DECIDED — the badge, and the questions it handed back

**Chiu's verdict on the navy sweep: they do not read as blue**, and he is right
about why — every candidate that clears a 0.35 luminance ceiling is too dark for
hue to register. His design instead: a blue disc, a white ring, the gull in white.

**It is structurally better than any colour, and the measurements are the
argument.** Rendered, in 0–255 units:

| still | disc | ring + gull | **badge's own contrast** | terrain | disc vs terrain | ring vs terrain |
|---|---:|---:|---:|---:|---:|---:|
| light · 1.00× | 89.1 | 217.4 | **128.3** | 183.9 | 94.8 | 33.5 |
| light · 0.80× | 89.1 | 217.3 | **128.2** | 186.2 | 97.1 | 31.1 |
| light · 0.65× | 89.1 | 217.1 | **127.9** | 190.5 | 101.3 | 26.6 |
| dark · 1.00× | 89.1 | 217.4 | **128.3** | 81.6 | **7.5** | 135.8 |

The badge's own contrast is **identical to a decimal across three sizes and both
appearances** while the terrain moves 183.9 → 81.6. And the dark row is the proof
of the mechanism: **the blue disc alone is nearly invisible there (7.5)**, yet the
badge reads, because the ring stands 135.8 off it. On light the roles swap — disc
94.8, ring 33.5. Neither colour suffices alone; the pair does, on both. That is
what one colour could never do.

Stills and a README: `~/Kamome-films/2026-08-29-fallback-badge/`.

**Chiu answered two of the three (2026-08-29):**

1. ✅ **One badge for both appearances — accepted.** The token no longer varies by
   appearance: the disc and the on-disc colour live on `RecapStyle` and neither
   preset touches them. The 2026-08-28 oddity — `modernMinimal(.dark)` never set
   this token, so the guard's dark half passed on a white nobody chose — is
   **closed by the design rather than fixed**. There is no longer a dark value to
   choose, so there is nothing left to forget to choose.
2. ✅ **Size: 0.60×**, from the 1.00 / 0.80 / 0.65 sweep — smaller than the
   smallest rendered, so **0.60 was rendered on its own rather than assumed to
   carry**. It draws at **94.5 px** and **legibility does not break between 0.65
   and 0.60**: the gull's double-arc still reads and the ring is still a ring.
   ⏳ **Judged from a still, and Chiu has reserved the right to revisit it from a
   film. Not settled.**
3. ✅ **The blue: `#1D6FE0`** — see finding 6b. Decided with the numbers in hand,
   not defaulted to.

**Two caveats carried deliberately:**

- **The white ring's outer edge is soft on light** and crisp on dark, since white
  against pale terrain is a small step. Worth knowing before judging ring width.
- **`#1D6FE0` is a starting value.** It would have **failed** the old 0.35
  ceiling outright, which is the point: the badge freed the hue.

### 6b. ✅ DECIDED 2026-08-29 — the blue is `#1D6FE0`, and here is the room around it

**Nothing renders differently**: it is the value the branch already carried. What
changed is that it is now a decision. Chiu considered `#2E7FE8`, the lightest
still that clears the rule, and **moved back deliberately once the wall was
explained** — so this is a pick with the numbers in hand rather than a default
that survived.

Rendered at the shipped 0.60× so the colour was judged at the size it ships at:
`~/Kamome-films/2026-08-29-badge-060-blues/`.

| hex | token L | disc | ring + gull | badge's own | terrain | disc vs terrain |
|---|---:|---:|---:|---:|---:|---:|
| `#0B4FC4` deeper | 0.286 | 64.9 | 217.1 | **152.2** | 193.5 | 128.6 |
| `#1D6FE0` today | 0.399 | 89.1 | 217.1 | **127.9** | 193.5 | 104.3 |
| `#2E7FE8` lighter | 0.460 | 102.9 | 217.0 | **114.1** | 193.4 | 90.6 |
| `#1D6FE0` on dark | 0.399 | 89.1 | 217.1 | **127.9** | 102.9 | 13.7 |

**The boundary, stated rather than implied.** The ring and gull are white. Against
white, straddling mid-grey needs the disc below **0.50** and the 0.45 separation
needs it below **0.55**, so **0.50 is the wall** and today's 0.399 has **0.101 of
headroom**. `#2E7FE8` at 0.460 is deliberately near it — 0.040 left — so the last
usable step is visible rather than described.

**Direction: deeper and more saturated is free** (darker only widens the
separation; no lower bound). **Markedly lighter is not** — past 0.50 the badge
has no dark half and disappears on a pale map exactly as the white gull did.

**A genuinely light blue is reachable only by inverting the pair** — light disc,
dark ring and gull. The rule is symmetric and already permits it: **verified by
running the guard** against a light disc (0.685) and an ink ring (0.130), which
passes unchanged with no code change. Not built, and the still was deliberately
not rendered — it existed to inform a choice that has now been made. It is
recorded so that **the next person who wants a lighter blue finds the exit rather
than failing a test**.

**Nothing about the badge is open except the size**, which Chiu has explicitly
reserved the right to revisit **from a film**; that one is marked open in
`RecapStyle.fallbackMarkerLengthFraction`'s own comment, where it will be read.

### 6c. ⚠️ KNOWN LIMIT — nothing in this project measures post-grade output

The guard asserts **token** luminance; the viewer sees the frame **after the
film's grade**. The disc is 0.399 as a token and renders at 0.349; white renders
at 0.851. The rule survives the grade — the pair still straddles mid-grey and
stays far apart — but the numbers in the test are not the numbers on screen, and
nothing checks that they stay compatible.

**This is the same class of gap as the golden-frame gates being unable to see
`MapKitSnapshotProvider`** (2026-08-22 finding 2): a property that only exists in
the rendered output, guarded only where the rendered output is not. Named here as
a known limit rather than left implicit in a mismatch between two numbers. The
fallback marker is the first token whose entire job is how it reads against the
finished frame, so it is where the gap first bites.

### 6d. ⚠️ KNOWN GAP — nothing asserts the end card's brand mark

**The same shape as 6c, and found by the same change.** The near-miss in finding
5b — that `drawSeagull` is also the end card's brand mark, so restyling it would
have turned the wordmark's bird into a blue disc — was caught by reading the call
graph, and confirmed on this branch by a second person reading the diff.

**That is the whole safety net.** `RecapMarkerDeckStillsTests` iterates
`VehicleMarker.allCases` and *writes* stills; it asserts nothing about them. No
test anywhere asserts the brand mark's shape, so the guarantee that the end card
still shows a bird currently rests on a human noticing.

**A golden still of the end card would close it.** Not built here — it is a new
gate with its own baseline to agree, and this change is already carrying a
restated guard. Named so it is a gap on record rather than a habit of careful
reading.

### 7. ⚠️ The no-reader token cluster is now **four**, and it is growing one at a time

The badge takes its ring and gull from the new `fallbackMarkerOnDiscColor`, so the
only markers still reading `markerAccentColor` are `.scooter` and `.bike` — and
those are reachable from `RecapMarkerDeckStillsTests` and nowhere else. It is now
in the same state as `markerColor`, `cardColor` and `cardTextColor`.

**Counted deliberately, because that is the point:** `cardColor`,
`cardTextColor`, `markerColor`, `markerAccentColor` — **four** tokens that
nothing renders, plus the five `RecapOverlayRendererTests` assertions that
believe they render against an opaque card. Each arrived separately and was
reported separately, which is how a cluster grows without anyone deciding to keep
it. **Reported, not removed**: it is its own change across four test files, and
the line-art markers are not this change's to delete. The number is here so the
next one to join is the fifth rather than another isolated note.

The fallback-specific token was added rather than reusing `markerAccentColor`
because that token means "handlebars and wheels" on the line-art markers. Two
roles under one name is how `markerColor` ended up with no reader at all.



`Docs/cross-region-journeys.md` requirement 4 — *"the load-bearing one"* — wants a
seagull as the **narrator of an unmodelled crossing**: honest provenance made
visual, *"we know you went from here to there; we do not know how"*. Its own words
are that this answer "must be cheap and **good-looking** rather than a failure
state."

The marker is being styled in the opposite direction: since 2026-08-28 it is
partly a diagnostic, and it has to say *something went wrong* at a glance.

**They are different objects** — the narrator is the `seagull` subject in
`vehicles.json` (omni sprite, `length_fraction` 1.0), the fault is
`VehicleMarker.seagull`, a stroked vector arc from `RecapStyle`. **A viewer cannot
tell them apart**, and that is the collision: the same bird would mean "we could
not classify your crossing" in one film and "the artwork failed to load" in
another. Nobody has decided which reading wins, and the navy pick makes the fault
bird more distinctive, not less.

**Noted at Chiu's instruction; deliberately not designed for.**

---

## Findings — engineering session, the film follows the system appearance (2026-08-28)

**Context.** `Docs/eng-session-appearance.md` (the `Arch.md` §12 design, written
before any code), on `feature/p4-appearance-follows-system` off `main` at
`87d1d4e`. Chiu's decision of 2026-08-27: the film follows the device's system
appearance, and light mode gets an orange trail. **The first change in this series
that moves shipped behaviour.**

## Findings — PO/Architecture session (2026-08-29)

Three things that outlive the session. Everything else it found is in
`Docs/decisions.md` 2026-08-27 (b) or in the commits, and is not repeated here.

### 1. Two rules, learned the expensive way

- **Read a style value off the preset the app actually selects (`modernMinimal`),
  never off `RecapStyle`'s defaults.** The defaults are unrendered. This was got
  wrong twice from the same source — the glow brief, then a PO draft of the
  appearance ADR — and cost a correction in the ledger both times.
- **The PO session does not write an ADR for a decision an engineering session is
  actively implementing.** It drafted one for the appearance decision in parallel;
  two entries for one decision in an append-only ledger is worse than none, and the
  later-dated one would have won while being the weaker. The draft was withdrawn.
  What the PO session should record instead is what the implementer will not see:
  cross-cutting consequences, spent guarantees, and what was left undecided.

### 2. 🔴 CI is blocked account-wide — a red check currently means nothing

From 2026-08-29, GitHub Actions jobs fail in ~3 seconds with **zero steps
executed**: the Actions **spending limit** is exhausted. `main` fails identically,
so this is not a signal about any branch. Until it is cleared, **local
`xcodebuild test` is the only verification there is, and a PR must say so** rather
than let a red check read as a broken suite. It recurs when the monthly allowance
runs out unless the limit is raised.

### 3. Awaiting Chiu — a rule this session may recommend and may not write

A branch ref has silently picked up another session's commits three times, and a
`git add -A` swept an unrelated file into an unrelated commit once. **Recommendation:
a standing rule in `Arch.md` — confirm the current branch before committing, and
stage explicit paths only, never `-A` or `.`** `Arch.md` is the engineering charter,
so per `PO.md` this is a recommendation. **It is not in force until Chiu says so.**

### 4. Known remaining duplication, reported not acted on

The 2026-08-29 trim moved four merged sessions' findings to
`Docs/_archive/handoff-2026-08.md` (1,961 → ~915 lines). Two overlaps are left, both
deliberate:

- **"Reference — Phase 4 scope…"** below restates `Docs/current-state.md`'s phase,
  camera and routing entries at greater length. It is left because
  `Docs/eng-session-camera-arc.md` cites the freeze it records, and because it
  carries reasoning the index does not. **If it moves, current-state must absorb
  the reasoning first** — do not simply delete it.
- **"Findings — PO/Architecture session (2026-08-21)"** is the working analysis that
  produced `Docs/camera-arcs.md`. Once Pass 1 has run and been judged, the design
  doc is the surviving form and that section should be archived.

---

## Findings — PO/Architecture session (2026-08-21)

**Context.** Chiu opened the design conversation `CLAUDE.md` Phase 4 item 3 held
frozen: how the camera crosses a large spatial gap — the opening's
panorama-to-detail move and the cross-region flight, designed together rather than
tuned separately. The design is `Docs/camera-arcs.md`; the first engineering
session is `Docs/eng-session-camera-arc.md`. These are the findings that came out
of it, ordered by what can go wrong silently.

**Nothing here is settled.** No entry goes into `Docs/decisions.md` until a render
has been judged.

---

### 1. The 151-snapshot opening is 5 seconds of motion, not 9 seconds of opening

**Decision.** Cost the export as **the number of distinct pictures the camera
visits**, not as `frames ÷ interval` and not as a function of the opening's
length.

**Why.** `RecapRenderLoop` keys its snapshot cache by `CameraFrame` value, so a
held beat is one snapshot however long it is held. The shipped opening is
`opening_country_s` 3.0 + `zoom_transition_s` 2.5 + `opening_regional_s` 1.0 +
`zoom_transition_s` 2.5 = 9.0 s, of which only 5.0 s moves.

**Evidence.** Model: 1 + 75 + 1 + 75 = **152** distinct values, against the
**151 measured** by `RecapSnapshotBudgetTests` on the real Miyakojima dump. Within
one snapshot. Verified by reading `RecapRenderLoop`, `CameraPathPrologue` and
`Config/TrackingConfig.json` on 2026-08-21.

**Risk.** The obvious lever — shorten the opening — buys almost nothing, because
the holds are already free. Anyone reasoning from "the opening is 79% of the
budget" without this correction will reach for the wrong knob.

**Next.** `Docs/pre-launch.md` **item 5** (export-time estimate) must count
distinct camera values. `frames ÷ interval` is the exact arithmetic error
`RecapSnapshotBudgetTests` was written to correct, and it would under-count by
~3× on the opening.

### 2. Neither frozen number needs a new value — the design makes both irrelevant

**Decision.** Unfreeze `keyframe_interval_frames` (15) and the opening's
every-frame interval **by making them irrelevant to an arc**, not by tuning them.
Neither value changes.

**Why.** The fine interval exists to bound *geometric* mismatch in a cross-fade —
`RecapRenderLoop`'s own comment says the coarse interval "is sized for a **static**
camera". A contained arc rendered by cropping into a wide snapshot has no
geometric mismatch to bound: a station-boundary cross-fade is two identical
framings differing only in sharpness.

**Evidence.** Measured 191 total / 151 opening / 40 body; measured 176 at interval
30. Derived for the arc: ~45 total, ≈4.2×. Table with the measured/derived split
marked in `Docs/camera-arcs.md` §9.

**Risk.** The ≈4.2× is **derived, not measured**, and rests on a claim about how a
scaled zoom looks that only a render can settle. If it reads wrong, the 3.3× lever
is still there untouched.

### 3. No continuity exemption is needed — and the seagull is why

**Decision.** Do not write the "narrow, explicit exemption" that
`Docs/cross-region-journeys.md` anticipated. Make `permittedCutTimesS` unreachable
and assert that **nothing is excused**.

**Why.** `RecapCameraContinuityTests.groundOverlap` divides by the **smaller**
footprint, deliberately — *"a pure zoom scores 1.0 — and it should."* A
containment-preserving move is continuous **by the gate's own metric**, at any
zoom ratio. The exemption was needed because a crossing today is a smear at body
span; an arc is not.

**Evidence.** Read directly in `RecapCameraContinuityTests` on 2026-08-21,
including the comment explaining why an earlier draft's zoom-ratio divisor was
wrong.

**The connection `cross-region-journeys.md` does not spell out:** requirement 4 —
the seagull for an unmodelled crossing — is what makes *"every discontinuity is
narrated"* true, and **that** is what lets the exemption go to zero rather than be
written. Without an honest fallback, an un-narrated gap would still need
forgiving. Requirement 4 is load-bearing for the camera, not only for provenance.

**Risk.** `act_split_km` (25) may be right for "insert an arc" and wrong for "send
a bird" — a GPS dropout inside a continuous drive is not a journey between places.
If they diverge, **raise the one threshold; never add a second.**

**Next.** Free evidence nobody has collected: the gate already prints `%d
permitted cuts` per fixture. Whether any committed fixture exercises the exemption
at all is currently **UNKNOWN**.

### 4. The safe-zone gate is inherited, but the apex has to be sized for it

**Decision.** Size a crossing's apex so that **`CameraPath.confine` is a no-op**,
and assert it.

**Why.** `confine` is applied as a post-condition to every composed frame after
`openingEndsS` — its comment says explicitly that this "covers every beat by
construction, including any added later", so an arc inherits the guarantee. But a
confine that *fires* drags the frame off the arc and breaks containment: the clamp
and the arc would be fighting, and containment is what §3 depends on.

**Evidence.** At the apex the subject sits at `1 / padding` of the half-frame, so
padding ≥ 1.25 satisfies `camera_safe_zone_fraction` 0.8; at 1.5 it lands at 67%.
Arithmetic over `CameraPathCore.confine` and the config.

### 5. ⚠️ The body span is where per-act framing could come back

**Decision.** **One span per trip still — but derived from the largest local
journey, not from the union.** Do not build a span per segment.

**Why.** `RecapDurationPlan.bodySpanM` floors the span at
`routeDistanceM / (travelS × camera_pan_window_fraction_per_s)`. On a cross-region
trip `routeDistanceM` includes the crossing, so the flight's distance is what
forces the destination to render as a smudge — symptom 2 of
`cross-region-journeys.md` in exact code terms. Removing the crossing from the
term fixes it without touching the locked "never adaptive" rule.

**Risk.** A span per segment is per-act framing, rejected 2026-08-02 at the cost
of a camera rebuild. It is *reachable* later — the arc shows the viewer the change
of scale, which is what the 2026-08-02 defect lacked — but only on render
evidence, and as a product decision. **Do not let it arrive as an implementation
detail of the crossing beat.**

**Next.** `FollowCamera`'s world clamp already collapses a route narrower than the
window to a single centred framing, which its own comment describes as desired. So
a short segment framed at the large segment's span is handled by machinery that
exists. Whether it *looks* right is UNKNOWN and is a Pass 2 render question.

### 6. The opening's middle beat is stale — as a consequence of the substrate ADR

**Decision.** With `establishing == nil`, the opening should be one hold plus one
arc. This is Pass 2, not Pass 1.

**Why.** The country and regional beats are **the same shot 1.47× apart, sharing a
centre** (`country_view_padding` 2.2 vs `wide_span_padding` 1.5, both framed on the
trip's own bounds when there is no region). They survive
`opening_collapse_zoom_ratio` (1.25) on a technicality and buy a 1 s hesitation
plus a second 2.5 s ease.

**Evidence.** `buildWideOpening`'s `establishing == nil` branch, read 2026-08-21.
The two-beat structure was justified in `decisions.md` 2026-08-09 by the region
being a genuinely different subject ("New Zealand's country beat survives because
its region is the whole country"). MapLibre was parked on 2026-08-15, so there is
no region.

**Risk.** This is **not** a reversal of the 2026-08-09 camera ADR — it is a
consequence of the 2026-08-15 substrate ADR. Anyone reading it as a reversal will
either defend a dead beat or reopen a settled zoom. `target_zoom_ratio` is
untouched: the established span still comes from the first beat.

### 7. A local trip's camera does not change at all

**Decision.** Fit every arc to a **local journey**. A trip with no discontinuity is
N = 1, has exactly one arc — the opening — and renders as it does today.

**Why.** This is what makes Pass 1 film-invariant and therefore cheap to judge:
the only variable is how the base map is produced. It also answers Chiu's question
directly — a user who never leaves the island sees an identical film.

**Evidence.** Today's opening is already a contained arc. `FollowCamera`'s world
clamp keeps the body frame's centre within ~0.06 × fitting-span of the trip
centre against a body half-width of ~0.44, so the body footprint's edge lands at
~0.50 against the regional beat's 0.75 — contained on both axes, and the two wide
beats are concentric by construction. **Arithmetic from source, not measured — the
engineering session must re-verify it on at least two fixtures before building,
because the whole of Pass 1 rests on it.**

### 8. A cross-region trip that *begins* with the crossing gets one move, not two

**Decision.** When the first local journey is degenerate — photographs start at the
departure airport, so segment 1 is a point — **the opening arc IS the first
crossing arc.** The film opens at the apex, the sprite crosses, the camera closes
into the destination.

**Why.** Fitted to a one-point segment the opening would establish on a 1,500 m
view of a terminal (the `camera_span_m` floor binding). That is almost certainly
what the first Miyakojima device film hit. And the merged move is a *better*
panorama than the padded one: it is showing the actual journey rather than a
rectangle around a bounding box.

**Open, not decided:** what counts as degenerate (recommend deriving it from
extent against `camera_span_m` rather than adding a tunable), and whether opening
on the departure reads right at all for a trip the film is not about. Both are
story judgements for Chiu, from a render.

---

### Delivery

- `Docs/camera-arcs.md` — the design, with the measured/derived split marked
  throughout and §11 listing what is still open.
- `Docs/eng-session-camera-arc.md` — the Pass 1 brief, ready to paste.
- `CLAUDE.md` Phase 4 item 3 — pointer added on Chiu's approval (2026-08-21). The
  freeze on both numbers **still stands**; the design makes them irrelevant to an
  arc rather than giving either a new value, and nothing changes until the Pass 1
  render has been judged.

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

## 🟠 Open — the `KamomeCore_KamomeExportEngine` subject lookup still misses; it no longer crashes

**Retitled and corrected 2026-08-28.** This entry stood as "🔴 intermittent bundle
crash (2026-08-13)" and described an unguarded `fatalError` reached through
`Bundle.module` in `Core/ExportEngine/RecapCarSprite.swift:75`. **That mechanism
no longer exists** — its own closing line ("the eventual fix is small and
defensive — a non-trapping bundle lookup") was carried out two days later and the
entry was never updated. Kept, not deleted: the *lookup* still misses, and the
same miss now degrades a film silently instead of crashing it.

### The history, as observed (2026-08-13)

`Fatal error: unable to find bundle named KamomeCore_KamomeExportEngine`, thrown
during map-renderer creation — after the region resolves, before any frame is
drawn. Hit **2 of 3** New Zealand render attempts; never on Miyakojima, never on
the Iceland run — so it read as trip-correlated rather than evenly random.
Cleared on retry, and again under `-retry-tests-on-failure`. The resource bundle
**is** present in the built `Kamome.app`, so it was a runtime lookup failure, not
a packaging fault. (Those are this file's own 2026-08-13 figures, kept verbatim;
no wider tally is recorded in the repository.)

### What changed the symptom — VERIFIED from the tree, 2026-08-28

| when | commit | what |
|---|---|---|
| 2026-08-15 | `b44a7fc` | "the sprite fallback stops being unreachable" — the trap is replaced by a non-trapping resolver |
| 2026-08-16 | `e2a1478` | `RecapCarSprite.swift` deleted; the resolver is generalised into `VehicleResourceBundle` (`Core/ExportEngine/SpriteDirection.swift:43`). Its message: "`Bundle.module` does not return." |

`grep -rn "Bundle.module" --include="*.swift" .` returns **only comments** — no
call site anywhere in the repository, and no `fatalError` or `try!` in
`Core/ExportEngine`. **The crash as this entry described it cannot recur.** The
generated accessor still exists in DerivedSources, as it does for every target
with resources, but nothing calls it.

### What the same lookup does now — observed 2026-08-28

`VehicleCatalog.resolve` returns nil and `VehicleSubjectRenderer.make` draws the
vector seagull. **Whether `VehicleResourceBundle.resolved` was itself nil is
UNKNOWN** — nothing recorded it, which is the gap the new log line closes. Four
`RecapStopStillTests/testRenderSubjectStill` runs differing only in
`TEST_RUNNER_KAMOME_ROUTE_COLOR` produced three cars and one gull
(`light-C-deeper`, `~/Kamome-wt/logs/render-light-C-deeper.log`); the test passed
in 25.8 s with no retry.

**VERIFIED here, not taken on report:**

- The still really is the fallback. Diffing it against the re-render at >8/255 on
  any channel gives **9,291 differing pixels of 2,073,600, all inside one
  126×131 box** — the subject and nothing else. Crops confirm gull vs car.
- **Nothing distinguished the run.** Stripped of timestamps, pids and paths, the
  two console outputs are identical **line for line**; the only differences are
  the colour, the output path and the elapsed seconds.
- The harness could not have told anyone either: `RecapReviewScene` prints
  `KAMOME_REVIEW subject <id> at <n>px` **before** calling `make`, so it reports
  what was asked for, and `KAMOME_SUBJECT_STILL … (se drawing)` derives the
  direction from the heading, not from what was drawn.
- The bundle carries `Vehicles/` and nothing else (`Package.swift`,
  `resources: [.copy("Resources/Vehicles")]`), so a whole-bundle miss would
  degrade **only** the subject. The single-box pixel diff is therefore consistent
  with a whole-bundle miss and **cannot discriminate** it from missing art.

### Same mechanism — established. Same trigger — UNKNOWN.

Same bundle name, same lookup, same code lineage, same point in the sequence
(map-renderer/compositor construction), same intermittency, both cleared by a
re-run. `b44a7fc` is exactly the commit that would turn the one symptom into the
other. That is enough to call it **one mechanism with two symptoms**.

It is **not** enough to call it one root cause. Neither occurrence was diagnosed,
and two things argue for caution: the crash tracked New Zealand and is recorded
above as never having fired on the Iceland run, while this miss *was* Iceland; and
`VehicleResourceBundle` is *stricter* than `Bundle.module` was — it accepts a
candidate only if `Vehicles/vehicles.json` is findable inside it, so a bundle
directory that exists but does not answer a resource query fails here and would
have succeeded there.

### Two hypotheses tested and weakened — 2026-08-28

**An install/launch race: WEAKENED, and it was the leading idea.** The tempting
mechanism was that the bundle being probed is a directory written moments before
the process launched. **MEASURED** on iPhone 17 Pro over four runs: a run whose
build produces a changed product installs into a **brand-new container**, taking
the old one with it (`9979C474-…` 22:24:56 → `D4A52666-…` 22:27:12 →
`E91959A1-…` 22:29:19), and the installed
`Kamome.app/KamomeCore_KamomeExportEngine.bundle` carries the install time rather
than the build time. **But a run that compiles nothing does not reinstall at
all** — a fourth run with 0 `SwiftCompile` and 0 packaging tasks left
`E91959A1-…` untouched. The four appearance renders differed only in environment
variables, so on that evidence the app was installed once and reused across them,
and no install sat next to the failing launch. INFERRED for that batch — no
install record from it survives — but it points away from the race, not towards
it.

**A build-work difference: RULED OUT.** `light-C-deeper`'s build did more than
`light-A`/`light-B`'s — two `CompileXCStrings` and four `CopyStringsFile` against
one and two. That is a real difference and it is **not** the discriminator: the
clean re-render (`render-light-C-rerender.log`) ran the *same* heavier pattern
and drew the car.

### What was done about it, and what was not

**Done (this change).** `VehicleSubjectRenderer.make` now logs the miss
(`KamomeLog.recap.error`) instead of degrading in silence, per Arch.md §5, and
the doc comment that called this "a state no test can arrange" is corrected.
`KamomeLog` reaches the xcodebuild console on the simulator — the routing lines
in every render log prove it — so the next occurrence names itself in the same
file a reviewer already reads.

**Done, approved (Chiu, 2026-08-28): the lookup now says what it tried.**
`VehicleResourceBundle.resolved` logs a one-shot trace naming, per candidate, the
URL and — the fact both incidents lacked — **whether the nested bundle was on
disk**, which is what separates an install-timing fault from a packaging one.
Scope as approved: failure path only (a process that resolves logs nothing),
filesystem paths only (nothing derived from a trip, so §0 is not engaged), and
shipped rather than reached for afterwards, because an intermittent failure has
to be instrumented *before* it happens.

The walk moved into `VehicleResourceBundle.resolve(hosts:)` so the message can be
exercised — `resolved` is a lazily-initialised global with no seam, and a
diagnostic that can never be shown to fire is one nobody should trust. Order and
acceptance rule are unchanged. Two tests hold the contract in
`RecapSubjectOrientationTests`: a host with no manifest produces
`…KamomeCore_KamomeExportEngine.bundle: not on disk`, and a resolving lookup
produces an **empty** trace.

**Two lines, not one, when it next fires:** the bundle trace once per process,
and `VehicleSubjectRenderer.make`'s per-subject line naming the consequence. One
says why, the other says what the viewer will see.

**Still not measured:** the rate, and the trigger. The next occurrence is what
this exists to catch.

**Stale references left alone, deliberately.** `Docs/current-state.md` is the
synced index and its neighbouring sections are being rewritten on
`feature/p4-appearance-follows-system`, so **two** lines there belong to the pass
that re-syncs it, not to this change: the blockers entry "🔴 intermittent …
bundle crash", and "worktrees fix it but silently skip half the secrets guard
(`HANDOFF.md` 3e)" — struck above, closed by `2d221e0`.
`Docs/gate-P3.5-checklist.md`
and `Docs/handoff-P3.5.md` describe a closed phase and are history.
`Docs/decisions.md` 2026-08-15 records the `Bundle.module` mechanism as it stood
and is append-only — it is not wrong, it is superseded.

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

## Environment gotchas that cost time

- ⚠️ **Routing is Geoapify since 2026-08-20** (`Docs/decisions.md` 2026-08-20).
  The OSRM entries below describe the parked local server (`Deploy/`), kept as
  the self-hosted fallback — they are not the shipped routing path.
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
- **Fixture shadowing is real.** `RecapTripFixtures.tripFixture` prefers
  `Tests/Fixtures/trips/local/<name>.json` (real dumps, gitignored per §0) over the
  committed fixture. Local and CI therefore test different geometry — NZ is 20
  stops locally, 3 on CI. To reproduce CI, move `local/` **outside the repo**
  (not to a dotfile inside it — only `Tests/Fixtures/trips/local/` is gitignored)
  and re-run.
- **`850a995` does not compile.** A parallel session's push swept in an
  uncommitted edit and CI died at lint before building. Harmless at the tip;
  `git bisect` across it will hit it.
- The desk render command (env-gated `RecapPilotFilmTests`, Variant A) is
  preserved in `Docs/_archive/handoff-2026-08.md` under "▶ RESUME HERE
  (2026-08-13)". Films go to `~/kamome-renders/`, never `/tmp`.

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

## Reference — Phase 4 scope, the snapshot freeze, and the camera (carried from `CLAUDE.md`, 2026-08-21)

*Current, load-bearing reference, moved here when `CLAUDE.md` became a boot
file. `Docs/eng-session-camera-arc.md` cites the freeze recorded below.*

### Phase 4 scope (Chiu 2026-08-15)

Chosen over productisation deliberately: *"方便的產品都沒有這是足夠好的作品更吸引
人"* — a good enough artefact matters more than a convenient product, so the films
come first and export convenience is discussed after. Reordered 2026-08-15 around
the first outside feedback: **nobody mentioned the map; the most common request
was to change the vehicle.**

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
   date range, and the month-reset at `ImportSheet.swift:133`.

   ⚠️ **Measured 2026-08-15 — the obvious lever is the wrong one.**
   `RecapSnapshotBudgetTests` on the real Miyakojima dump (offline, all legs
   inferred): an 88 s / 2,640-frame film costs **191 snapshots — 151 of them in
   the 9 s opening**. The opening is 10% of the film and **79% of the snapshot
   budget**, because `RecapRenderLoop` snapshots it *every frame*
   (`movingUntilFrame = openingS × fps`) while the body gets one per interval.
   `keyframe_interval_frames` 15 → 30 therefore takes 191 → 176, **−8%**, not
   half. Running the opening at the coarse interval instead would be ~58
   snapshots, ≈3.3× cheaper — *derived from the measured split, not itself
   measured*. (Refined by the 2026-08-21 findings above: cost the export as the
   number of **distinct camera values**, not frames ÷ interval — the 151 is
   5 s of motion, not 9 s of opening.)

   🔒 **Both numbers are frozen — a recorded fact, not a pending change**
   (Chiu 2026-08-15). Neither `keyframe_interval_frames` (15) nor the opening's
   every-frame interval is to be touched, and the three-way render comparison is
   not owed. They were held for a design conversation about **how the camera
   crosses large spatial gaps** — the opening's panorama-to-detail move and the
   cross-region flight are the same problem.

   ➡️ **That conversation happened on 2026-08-21. The design is
   `Docs/camera-arcs.md`** (the *contained arc*; findings above; first
   engineering session `Docs/eng-session-camera-arc.md`). **The freeze still
   stands** — the design makes both numbers *irrelevant to an arc* rather than
   tuning them, so neither gets a new value, and nothing changes until Chiu has
   judged the Pass 1 render.

**Map work is NOT in Phase 4.** Tiles, labels and the tile server all left the
roadmap with the 2026-08-15 substrate ADR. What Chiu wants from "big cute place
names" is a **Kamome-drawn overlay** — iceboxed as "Place names as narrative
rhythm", substrate-independent, and the app already geocodes every stop.

**Routing is Geoapify — CLOSED 2026-08-20** (`Docs/decisions.md` 2026-08-20
(a)–(d); `Docs/routing-provider-selection.md` is the record of what was asked,
not an open question). §0's cost was accepted 2026-08-16 and stands. The scaling
trap that forced it: a self-hosted OSRM only routes the regions it preloaded — a
friend's Tokyo trip had no routable legs at all, because the Japan extract is
Kyushu. Snap-radius history: the 500 m radius was measured to be the wrong
mechanism — read `Docs/decisions.md` 2026-08-20 (d) before citing any older
snap-radius text.

### Camera architecture (rebuilt 2026-08-01 → 2026-08-02, Chiu)

The recap camera was rebuilt after the NZ device film. `CameraPathActs` framed
each act to its own bounds while timing came from a separate clock, so motion
came from **data shape** rather than spatial continuity. What replaced it, all
of which is load-bearing:

- **`FollowCamera`** — a dead-zone dolly, pre-simulated once at build time so
  `cameraFrame(atTime:)` stays pure and random-access. Inertia is simulation
  state, never a post-process. A world-bounds clamp keeps the frame inside the
  route's extent, and **yields to the subject** when the two disagree.
- **One span per trip**, from `RecapDurationPlan.bodySpanM`. Never adaptive —
  recomputing mid-film is what produced a 97× zoom-out before the end card.
- **`body_span_padding` (0.6) sizes the body separately** from the establishing
  shot (2026-08-08, superseding the 2026-08-02 wide baseline): the establishing
  shot frames the whole trip, the body follows the vehicle inside it.
  `camera_pan_window_fraction_per_s` is **0.35 and a genuine floor** (ADR
  2026-08-09 — an older note saying "stays 0.05" was stale).
- **`CameraPathActs` keeps only discontinuity detection** — a ferry is a fact
  about the journey; framing was a decision about the camera.
- **The opening** is country → region → body, the country beat framed to fit
  *inside* the tile extent, dropped entirely when the region is no wider than
  the trip. Held beats capped at ~1 s after the title card; the closing zoom is
  skipped when the body frame already matches the regional beat.
- **The ending** pulls back past the body (`end_reveal_padding` 1.9);
  `end_card_style` selects `.full` (free) or `.minimal` (held for a paid tier).

**Two gates guard all of it** (`RecapCameraContinuityTests`, offline, every
fixture, `base_url=""` for worst-case inferred legs):
- consecutive frames share ≥50% of their ground (measured ≥97%);
- the subject never passes 80% of the half-frame (measured 43–54%).
Do not relax either — they exist because a still frame is trivially correct and
a strobing one is only wrong *between* frames.
