# Findings — the cross-region crossing beat (2026-08-30)

The engineering session that built the crossing as a beat and a camera move,
**no classifier**, plus the P0's measurement. **Nothing here is in
`Docs/decisions.md` — Chiu has not judged the film.**

⚠️ **Read findings 1 and 2 before believing anything anyone has written about
the destination's scale, including this session's own brief.** Both are
measurements that contradict a documented premise.

*Moved verbatim out of `HANDOFF.md` on 2026-08-31 when that file was put on a
budget. Nothing was edited.*

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

#### ✅ CLOSED 2026-09-02 — the gate scans both, and the span claim above is now stale

**Done, as this finding recommended:** `RecapCameraContinuityTests` runs every
fixture through **both** configurations (`region` = the synthetic extent,
`shipped` = `nil`), in the continuity scan and the safe-zone scan alike. Nothing
was swapped or relaxed; a second pass was added.

⚠️ **But the 18.6 km vs 274 km figure above no longer reproduces, and the reason
matters.** Measured across all 7 fixtures on 2026-09-02, the two configurations
now produce an **identical body span** — 6.6, 14.8, 86.3, 38.1, 122.7, 179.7 and
20.0 km respectively, the same in both. ADR **2026-08-31** ("the LAST wide beat,
not the first") is why: `establishedSpanM` returns the prologue's *final* beat,
which the title-card cut freed from `establishing` entirely. `establishing` still
shapes beat 1; it no longer sets the divisor.

**This finding was re-confirmed "still true" on 2026-08-31 — the day before PR
#26 merged the change that closed it.** A re-confirmation dated to the day of the
fix is worth nothing, and this one outlived its subject by two days.

**What the second pass actually caught is different, and it is real:** the
shipped camera frames the subject consistently looser (p95 52–53% against
43–49%; worst 58% against 44–46%), and on `ishigaki-crossing` it reaches
**79.8% of the safe zone against an 80% limit** — a pass by 0.2 points, inside
the assertion's 2-point tolerance. That was invisible for as long as only the
synthetic configuration was scanned. Whether 79.8% is acceptable is Chiu's
(`HANDOFF.md`).

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

