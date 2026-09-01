# Findings — crop-scaling and the opening (2026-08-31 → 2026-09-01)

The engineering session that replaced the render loop's cross-fade with
reprojection (`Docs/camera-arcs.md` §7, camera-arc Pass 1), and measured the
opening ahead of the Task B design.

⚠️ **Nothing here is in `Docs/decisions.md`.** Chiu has not judged the films.
Two design questions are open and are his (§4).

---

## 1. ✅ The P0 is fixed by reprojection, and it is measured against interval 1

`RecapRenderLoop` no longer alpha-blends two snapshots taken at two different
cameras. It plans **stations** (`RecapSnapshotStations`) — one snapshot per run
of frames — and reprojects each station onto each frame: translate, and scale
when the span changes. A reprojected frame is *geometrically exact*, so there is
no mismatch to bound and nothing to fine-sample against.

**Method.** Identical to the 2026-08-30 falsification pair so the numbers are
comparable: `miyakojima` (the local dump), 10 s of **body** at 20.0–30.0 s,
rendered through the shipped loop, frames extracted and compared per frame in
greyscale, mean absolute difference on 0–255. The reference is `main`'s
`keyframe_interval_frames: 1`, rendered from a worktree at `dde9d5b`.

Both runs are the same film — `9 × drive/reconstructed`, holds at 20.00–23.86 s
and 26.06–30.00 s. ⚠️ **That took a correction** — see §3.

| configuration | hold 1 | **travelling** | hold 2 | whole | peak | **frame-to-frame swing** | snapshots |
|---|---:|---:|---:|---:|---:|---:|---:|
| shipped cross-fade (interval 15) | 0.038 | **2.005** | 0.121 | 0.503 | **3.415** | mean 0.078 / **max 1.402** | 191 |
| crop-scale, magnification 1.00 | 0.035 | 0.094 | 0.036 | 0.048 | 0.329 | 0.010 / 0.324 | 583 |
| crop-scale, **1.10 — shipped** | 0.585 | **0.818** | 0.640 | 0.658 | 0.850 | 0.008 / **0.077** | **42** |
| crop-scale, 1.20 | 0.916 | 1.194 | 0.733 | 0.905 | 1.339 | 0.010 / 0.360 | 18 |
| crop-scale, 1.05 | 0.423 | 0.615 | 0.423 | 0.465 | 0.681 | 0.009 / 0.129 | 124 |

The magnification-1.00 row is the **reference agreeing with itself**: 0.048 mean
against `main`'s interval 1, which is the codec noise floor (2026-08-30 measured
0.07 at blend 0, where the two clips are the same picture). Crop-scaling at
magnification 1.0 *is* interval 1 — same pixels, identity transform. That row is
the control, and without it none of the others mean anything.

**The column that answers Chiu's 晃動 is the swing**, not the mean. 晃動 is a
*change* frame to frame; a level of error that never changes is softness, which
is a different complaint. The cross-fade swings by up to **1.402** per frame —
that is the sawtooth locked to `RecapBackground.blend`, snapping twice a second.
Crop-scaling's worst swing is **0.077**, eighteen times smaller, and it has no
periodic structure because there is no blend.

Every crop-scaling row beats the cross-fade on travelling error *and* on peak
*and* on swing. The cost of that is a uniformly slightly softer map, which the
holds column prices: the cross-fade was pixel-exact during a parked camera
(0.038) and crop-scaling is not (0.585 at 1.10). **That trade is a look and it is
Chiu's to judge** (`Docs/camera-arcs.md` §7 says so in advance). The dial is one
config key and one env override:

    TEST_RUNNER_KAMOME_STATION_MAX_MAGNIFICATION=1.05

## 2. The snapshot budget, split three ways, before and after

Measured through the shipped loop by `RecapSnapshotBudgetTests`, offline.

| fixture | before | after | opening | arc | body |
|---|---:|---:|---:|---:|---:|
| `ishigaki-crossing` | **367** = 151 + 182 + 34 | **51** | 14 | 25 | 12 |
| `miyakojima` (local dump) | **191** | **42** | 14 | — | 28 |

**7.2× on the crossing film.** At the 0.72–1.55 s per snapshot device figure that
is 4.4–9.5 minutes becoming **37–79 seconds** for a 69-second film.

⚠️ **Task A and Task B overlap; they are not additive.** The brief predicted the
opening's country→region ease was worth ~75 snapshots *on its own, additive to
crop-scaling*. It is not: crop-scaling already collapsed that ease from 148
moving frames to part of 14 stations. Cutting the beat now saves a handful, not
75. **The 75-snapshot argument for the cut is spent** — the cut has to be argued
on what it does for the *viewer*, which is what Chiu decided it on anyway.

## 3. 🔴 A worktree renders a different film — `Config/Secrets.xcconfig` is gitignored

The first before/after comparison was **invalid and looked plausible**: 4.08 mean
difference where the answer had to be ~0. Cause: `git worktree add` does not
carry gitignored files, so the `main` worktree had no `Config/Secrets.xcconfig`
and therefore no routing key. Its legs came back `9 × drive/inferred` against the
branch's `9 × drive/reconstructed` — straight lines versus real roads, 24 km
versus 31 km on the odometer at the same second. A dashed trail against a solid
one, and a genuinely different film.

`Tests/Fixtures/trips/local/` has the same property, and is the shadowing trap
`Arch.md` §5 already names — this is the second file with it.

> **Before comparing renders across worktrees, copy both `Config/Secrets.xcconfig`
> and `Tests/Fixtures/trips/local/`, then check the leg provenance line in each
> log.** `KAMOME_FIXTURE` already announces the local dump; routing does not
> announce itself, and the difference is only visible if you count
> `drive/reconstructed` against `drive/inferred`.

Caught only because a control was measured. **Any render comparison without a
"these two should be identical" row is not evidence.**

## 4. 🔴 THE OPENING: the destination-framing inference is right in outcome, wrong in mechanism

Step 0 of the brief asked for `bodySpanM` with `establishing` derived from the
destination segment's bounds. Measured on `ishigaki-crossing`:

| `establishing` | established span | body span | ratio |
|---|---:|---:|---:|
| `nil` — **what ships** | 685.0 km | **274.0 km** | 2.50× |
| whole trip bounds | 46.6 km | 18.6 km | 2.50× |
| **destination segment bounds** | 46.6 km | **18.6 km** | 2.50× |
| origin segment bounds | 46.6 km | 18.6 km | 2.50× |
| an extent wider than the trip | 1001.9 km | 400.8 km | 2.50× |
| wider still | 2817.8 km | 1127.1 km | 2.50× |

**The number moves — 274 → 18.6 km, 14.7× tighter — but not because of the
destination.** Rows 2–4 are identical: `buildWideOpening` takes
`countryBounds = union(establishing, tripBounds)`, so every extent *inside* the
trip is the same input. The improvement comes from flipping the country beat off
the `nil` branch (`tripBounds × country_view_padding`, padding **out**) onto the
`containedSpanM` branch (largest portrait frame fitting **inside**). Rows 5–6
isolate it: only an extent wider than the trip changes the answer.

That contain-branch is a **tiles-era rule** — its own comment says it exists so
the tiles' edge never shows. With Apple Maps global it has no reason to exist,
and 46.6 km is not a country, it is a city.

**Two further measurements:**

**(a) The ratio is 2.50× in every row.** `target_zoom_ratio` sets the body span in
every configuration; the pan floor never binds anywhere, not only on the shipped
path. `Docs/handoff-cross-region-crossing.md` finding 1 generalises.

**(b) The opening has never had a country beat *and* a region beat — it has one
picture shown twice.** Walking the opening frame by frame
(`RecapOpeningFramingTests`):

    ishigaki-crossing · opening 9.00s (270 frames) · 150 distinct camera values
      HELD  0.00–3.00s at span 685.0 km
      HELD  5.50–6.50s at span 467.1 km
      2 held runs · 148 moving frames

This **confirms `Docs/camera-arcs.md` §2's model by measurement** — 148 + 2 = 150
against a predicted 151, previously arithmetic only. And 685.0 / 467.1 =
**1.4667**, which is exactly `country_view_padding / wide_span_padding` = 2.2 /
1.5. `miyakojima` gives the same 1.4667 (69.5 → 47.4 km). **On every trip, the
"country" and "region" beats are the same framing at two paddings**, and the film
spent 2.5 s easing between two pictures a viewer cannot tell apart. That is
"看不到整個澳洲… 不知道在哪裡" in one line.

### The structural finding underneath both faces

`RecapDurationPlan.bodySpanM` divides the span of the opening's **first beat**.
One number does two incompatible jobs: it is the "where in the world"
establishing shot **and** the divisor that sets how tightly the destination is
framed, chained by `target_zoom_ratio`. **You cannot widen the country without
smudging the destination.**

Chiu's 2026-08-31 decision breaks exactly that chain: once beat 1 **cuts** to
beat 2, beat 1's span no longer has to be continuous with anything, and the
divisor should become **beat 2's** span. The decision and the measurement agree.

## 5. ⏳ Two things for Chiu — proposed, not built (`Arch.md` §7)

**Neither was implemented.** The opening is unchanged on this branch.

### (a) Where the country's extent comes from

The constraint that decides it: **every Apple API that returns a country extent
needs the network.** `CLGeocoder` and `MKLocalSearch` are round trips;
`CLPlacemark.region` only exists on a response. Against "a film must still render
with no network", no Apple-only option stands alone.

| | A. built-in table | B. MapKit behind a seam | C. table + MapKit refinement |
|---|---|---|---|
| offline | **always** | **cannot** | works, degraded to A |
| dependency | none (a data file) | `import MapKit` gains a 2nd consumer | as B |
| boundary | a JSON in `ConfigLoader` | a protocol in `App/Services` on the `StopGeocoding` pattern | both |
| accuracy | crude — one box per country; the US, Russia and France are badly served | exact | exact when online |
| §0 | clean — a static table is not location data | sends **one real coordinate** off-device to draw a wider opening: a **new exception**, so Chiu's, not an implementation detail | as B |

⚠️ **The §0 point was not foreseen in the brief.** `CLGeocoder` already runs for
stop *naming*, but that is a decided exception for naming, not for framing, and
`CLAUDE.md` rule 1 says extending it is a product decision.

True whichever wins: **the country name is not persisted** — `StopDisplayName`
uses `country` only to *reject* coarse names and discards it — so the title
card's text needs a small persistence change either way.

**Recommendation: A.** The only one that satisfies the hard requirement alone, no
dependency, no §0 exception, and C remains reachable without moving the seam.

### (b) How beat 2's frame is defined

Beat 2 is load-bearing twice: the first frame of the film proper, and (after the
chain-break) the divisor that sets the body span.

| | Iceland (a country) | Miyakojima (an island) | compact trip in a large country |
|---|---|---|---|
| A. destination local-journey bounds × padding | frames the driven part, not the island | frames the drive; island edges may fall outside | correct and tight — the motivating case |
| B. geocoded `administrativeArea` | "Suðurland" — arbitrary extent | Okinawa Prefecture — 1,000 km of ocean | anything from a city to a US state |
| C. **largest** local journey × padding (§5's own recommendation) | as A | as A | as A |

**Argue against B**: it makes the film's scale a function of how a country draws
its administrative units — the class of defect "no magic numbers" exists to
prevent, except the number comes from a foreign government.

A and C differ only on a cross-region trip, where A frames the *destination* and
C the *biggest* journey. For Taiwan→Ishigaki those are very different. **Which
one the film opens on is narrative, not engineering.**

### (c) Reported, not decided: should a local trip's opening change too?

The cut is *more* defensible on a local trip, because there the country→region
ease is provably the 1.4667× non-move above — motion that buys nothing. But Chiu
specified only the cross-region case, and silence is not permission.

## 6. The gates, and one thing deliberately not fixed

`RecapCameraContinuityTests`, all seven fixtures, **0 violations and 0 excused**.
No exemption was added or widened.

    finland            60.0s · span  9.8 km · worst overlap 68% ·  1 permitted cuts · 0 excused · 0 arcs ✅
    iceland           211.5s · span 57.8 km · worst overlap 70% · 20 permitted cuts · 0 excused · 0 arcs ✅
    ishigaki-crossing  69.0s · span 18.6 km · worst overlap 70% ·  3 permitted cuts · 0 excused · 1 arcs ✅
    margaret-river     60.0s · span  3.4 km · worst overlap 70% ·  0 permitted cuts · 0 excused · 0 arcs ✅
    miyakojima         88.0s · span 10.5 km · worst overlap 69% ·  0 permitted cuts · 0 excused · 0 arcs ✅
    new-zealand       154.5s · span 49.5 km · worst overlap 70% · 14 permitted cuts · 0 excused · 0 arcs ✅
    nz-real            88.0s · span 60.7 km · worst overlap 69% ·  9 permitted cuts · 0 excused · 0 arcs ✅

**This closes `Docs/camera-arcs.md` §8's "Unknown, and cheap to close":** five of
seven fixtures do exercise `permittedCutTimesS` (1, 20, 3, 14, 9), and **0 are
excused on any of them** — the mechanism is reachable and has never been needed.

⚠️ **Still true, and deliberately not fixed: the gate has never measured the
shipped camera.** It passes a synthetic `establishing` extent; the shipped app
passes `nil`, which takes the other branch and gives 18.6 km of body span against
274 km. Reported, not moved — `nil` is the *more forgiving* configuration, so
scanning it instead would weaken the gate, and that is a bar move for Chiu
(`Docs/handoff-cross-region-crossing.md` finding 2). The cheap fix is to scan
both.

## 7. `keyframe_interval_frames` is now read by nothing

It was **not changed** — it is frozen, and it still holds 15. The reprojected loop
simply does not consult it: the interval bounded *geometric mismatch in a
cross-fade*, and a reprojected frame has none. `Docs/camera-arcs.md` §7 predicted
exactly this ("the interval stops being a quality knob at all"). Station length is
set by `snapshot_station_max_magnification`.

Left in the config rather than removed: whether the cross-fade path goes for good
is Chiu's call from these renders. `RecapBackground`'s cross-fade form is still
there and still used by the still harnesses, and `RecapFrameTests` still asserts
its arithmetic — nothing in the shipping path constructs it with two cameras any
more.

## 8. Verification

`./check.sh` exits **0** — gates, xcodegen, swiftlint --strict, build, and the
full suite (343 test cases). Log: `~/Kamome-wt/logs/checkfull2.log`.

⚠️ **CI is still dead account-wide** (Actions spending limit, from 2026-08-29).
Confirmed on 2026-08-31: the latest run on `main` is `conclusion: failure` with
**0 steps executed** in 3 seconds. Local `./check.sh` is the only verification
there is.

One test was **restated, not deleted** (`Arch.md` §4):
`testMovingCameraFetchesOneSnapshotPerDistinctView` asserted one snapshot per
distinct camera value, which measured the *value cache* rather than the rule.
Under stations one snapshot deliberately serves many cameras. It is now
`RecapSnapshotStationsTests.testMovingCameraIsCarriedByStationsThatContainEveryFrame`
and asserts the rule structurally and more strongly: the plan partitions the film,
every frame's magnification is ≥ 1 (its station contains it) and ≤ the budget
(no station "contains everything" by being enormous). Both bounds are checked on
the snapshots the provider actually produced.

---

# Round 2 — 2026-09-01

Chiu accepted round 1's crop-scaling, answered both proposals, and pushed back on
one claim. §§9–12 are that round.

## 9. 🔴 I WAS WRONG: there is no render length limit, and the "control" was confounded

Round 1 reported that a 70-second `RecapPilotFilmTests` render is SIGKILLed on
this Mac, "reproduced identically on `main`, so it is not crop-scaling." Chiu
pushed back from direct experience — he has watched 3-, 5- and 10-minute films
render here. **He is right and the claim was wrong, not merely over-broad.**

Re-run with nothing else running, whole `ishigaki-crossing`, 2,070 frames:

| path | result |
|---|---|
| `RecapPilotFilmTests` → `RecapRenderLoop` | **2070/2070 frames · 96 s** |
| `RecapDemoFilmTests` → `RecapExporter` (what the app uses) | **2070 frames · 38.9 MB · 99 s** |

**What actually happened.** All six failures fall in one five-minute window
(22:51–22:56) in which **six xcodebuild processes were competing for one
simulator**: a background script running four renders — which was still alive —
plus two foreground runs launched in the belief it had died. Every one failed,
with `Executed 0 tests` or `Test crashed with signal kill`. The log timestamps
interleave exactly.

**The part worth keeping is the reasoning, not the number.** A control run on
`main` reproduced the failure, and that was read as proof the defect was
pre-existing. It was not a control — it was confounded in precisely the same way,
because it ran inside the same collision. **A control that shares the confound
manufactures confidence instead of removing it**, which is worse than having no
control at all. `pgrep -fl xcodebuild` before trusting any render result.

Round 1's *other* control — the `establishing`/`Secrets.xcconfig` one in §3 —
worked correctly and caught a real error, so the technique is sound; the mistake
was not checking that the control was clean.

`HANDOFF.md` is corrected. **A whole film is renderable, so judgement no longer
has to be made from disconnected windows** — which was Chiu's actual point:
"沒有銜接", pacing and length cannot be judged from clips that are by
construction discontinuous.

## 10. ✅ Stop beats are pixel-exact again — stations split at hold boundaries

Round 1 measured the cross-fade as pixel-exact during a parked camera (0.038) and
crop-scaling as not (0.585), and offered a tighter global magnification at 3× the
cost. Chiu asked whether there is a trade to make at all, since a parked frame's
station should be the frame itself.

**There is not — it is fixable, and cheaply.** The cause was that a station sized
to contain a run of frames spanning *both* a travelling stretch and a parked one
is wider than the parked frames need. `RecapSnapshotStations.splitFrames` now
forces a station to begin at each hold's first frame, at the frame after its last,
and **at the frame where the camera settles inside the hold** — the dead-zone
dolly is still coasting when a beat opens. Everything after that settle point is
one camera value, so its station is that value at magnification 1.0: the identity.

Threshold-free on purpose. The holds are a fact the story layer already states
(`CameraPath.holds`), and the settle point is *the last frame at which the camera
changes* — measured, not chosen. "A parked run longer than N frames earns a
station" would have been a number nobody could later justify.

Measured against the interval-1 reference, `miyakojima` body 20–30 s:

| | hold 1 | travelling | hold 2 | whole | swing (max) | snapshots |
|---|---:|---:|---:|---:|---:|---:|
| shipped cross-fade | 0.038 | 2.005 | 0.121 | 0.503 | **1.402** | 191 |
| 1.10, no hold splits | 0.585 | 0.818 | 0.640 | 0.658 | 0.077 | 42 |
| **1.10 + hold splits** | **0.046** | 1.061 | **0.142** | **0.307** | 0.747 | 55 |
| 1.05 + hold splits | 0.035 | 0.617 | 0.127 | 0.199 | 0.448 | 161 |

Holds go 0.585 → **0.046** and 0.640 → **0.142**, matching the cross-fade's
0.038/0.121. Cost: **+10 snapshots** on `ishigaki-crossing`, +13 on `miyakojima`.

⚠️ **One new artifact, and Chiu should know before he picks.** The worst
frame-to-frame swing rose from 0.077 to 0.747, and it is localised exactly at
**23.87 s and 26.07 s** — the two hold boundaries. It is a *sharpness* step, not a
double image: a pixel-exact parked station now abuts a magnified travelling one.
Still half the cross-fade's 1.402, and it lands where the car pulls away rather
than twice a second throughout. `Docs/camera-arcs.md` §7 anticipated it and
prescribes the remedy — cross-fade *at a station boundary*, where the two images
are the same framing and differ only in resolution, which costs **no extra
fetches** because both stations are already in the cache. **Not built**; it is
~30 lines and a blend-length tunable, and it should be judged from the render
first.

## 11. The opening, built — and one deviation from proposal 2A, with its reason

Chiu's answers: **proposal 1 → A** (built-in table), **proposal 2 → A** (the
destination's local-journey bounds), and apply it to local trips too.

### What was built

- `CountryExtent` — a built-in table, ISO 3166-1 alpha-2 → bounding box, **six
  countries**, the ones Kamome renders. Point-in-box, no network, no coordinate
  leaves the process, so **no new §0 exception**. The country *name* comes from
  `Locale.localizedString(forRegionCode:)`, so it is the viewer's own language
  offline — **the persistence change turned out not to be needed**, which is why
  it was not made.
- **Beat 1 is the country, held for `title_card_s`, and it CUTS to beat 2.** The
  beat's length *is* the card's length — written as `titleCardS` rather than
  checked against `opening_country_s`, so "the cut lands as the title leaves"
  cannot drift apart. `opening_country_s` is now read by nothing.
- **Beat 2 is one local journey × `wide_span_padding`**, and `bodySpanM` divides
  **beat 2** rather than beat 1 — the chain-break.
- The closing zoom is now `containedLerp`, not `lerp`.

⚠️ **A country whose single bounding box would be a lie is left out, not
approximated.** One box for the United States spans Alaska to Florida; a trip in
California would be established by a frame in which California is a speck. France
and Norway have the same problem. Those need more than one box per country, and
an unknown country **falls back loudly** (a `KamomeLog` line) to the previous
trip-bounds behaviour. Extending it is adding a row.

### The deviation, and why (`Arch.md` §7)

Proposal 2A says beat 2 frames the **destination's** local journey. Chiu's reason
was that in the film he wants, *the origin's drive is not in the recap at all*.

**That premise is not true of the film that exists today**, and building to it
early produces an incoherent opening rather than an early version of the right
one. Measured on `ishigaki-crossing` (`RecapOpeningFramingTests`):

    beat 2 fitted to the destination sits 275 km from where the body camera starts
    → the closing zoom must travel 273 km across a 33.3 km frame — 8.2 frame-widths

`RecapCameraContinuityTests` failed it as **69 violations**, correctly: it is the
2026-08-08 pre-pan defect at eight times the scale, and it is "多餘畫面" of exactly
the kind the cut was decided to remove — the film would show the destination, jump
back 275 km to the origin, drive, then fly to the destination it had already shown.

So beat 2 frames **the local journey the body camera actually starts in**:

- on a **local** trip — the case Chiu also asked to change — first and last are the
  same journey, so this **is** proposal 2A, with no difference of any kind;
- on a **cross-region** trip it is the origin today, and it becomes the destination
  **on its own** the moment the next session drops the origin from the recap,
  because the destination will then be the only local journey. No further change
  is needed in the camera when that lands.

`CameraPath.openingRoute` carries this reasoning; it is one function to flip if
Chiu wants the literal reading instead, and the gate says what that costs.

### What the opening now does

`ishigaki-crossing`, shipped path (`establishing: nil`):

| | before | after |
|---|---:|---:|
| opening length | 9.0 s | **6.5 s** |
| beat 1 | 685.0 km (trip × 2.2) | **285.6 km — Taiwan** |
| beat 2 | 467.1 km (trip × 1.5) | **50.1 km — the drive itself** |
| body span | **274.0 km** | **20.0 km** (13.7× tighter) |
| moving frames in the opening | 148 | **74** |

The 1.4667× non-move is gone: beat 1 and beat 2 are now 5.7× apart on this film
and 44× apart on `miyakojima` (2111.6 km of Japan → 47.4 km), instead of being the
same picture at two paddings.

## 12. ⚠️ The cost went UP, and the reason is the point

| | `ishigaki-crossing` | `miyakojima` |
|---|---:|---:|
| shipped, before this session | 367 | 191 |
| + crop-scaling (§1) | 51 | 42 |
| + hold splits (§10) | 61 | 55 |
| **+ the opening and body span (§11)** | **178** | **80** |

**Round 1's 51 was cheap because the destination was a smudge.** A 274 km body
span barely moves relative to its own window, so stations lasted hundreds of
frames. At 20.0 km the camera crosses far more of its window per second and
stations expire faster. **The smudge was free; framing the destination properly
costs snapshots**, and no amount of rendering cleverness changes that — it is the
camera moving relative to its frame.

Net against what ships today: **367 → 178, still 2.1× cheaper** (191 → 80, 2.4×),
with the ghosting gone, stop beats pixel-exact, a real country establishing shot,
a 13.7× tighter destination and 2.5 s less opening. On device that is 4.4–9.5
minutes of export becoming **2.1–4.6 minutes**.

If 178 is too many, the dial is `snapshot_station_max_magnification` and §10's
table prices it. This is the number to watch when the next session removes the
origin from the recap: a shorter film with one local journey should fall again.

## 13. The gates

`RecapCameraContinuityTests`, all seven fixtures, **0 violations and 0 excused**,
with the title-card cut in place and **no exemption added or widened**.

**How the gate stays honest about the cut.** It does not excuse a frame range. It
asserts that **the card beat is a still frame** — every frame from 0 to the cut
must have ground overlap 1.0 with the frame at t=0 — and then scans everything
from the cut onward with nothing forgiven. If the card beat ever moved, the gate
fails rather than skips, which is the whole difference between this and an
exemption. A cut out of a held picture under a title is a film convention; a cut
out of a *shot* would be the bug, and that is what is now checked.

Three tests were **restated, not deleted** (`Arch.md` §4), each because its case
became unreachable:

- `testARegionNoWiderThanTheBodyOpensOnTheJourneyWithoutPanning` asserted "the span
  never changes and the centre never moves 10% of a frame", both of which encoded
  the tiles-era `cappedToRegion` as the mechanism. Now: the card beat is still,
  and every frame of the closing zoom **lies inside the establishing frame** —
  strictly stronger, since a small translate that also zoomed *out* would pass the
  old budget and fail this.
- `testOpeningCollapsesBeatsThatDoNotMoveTheCamera` reached `collapse` through a
  fixture whose country and regional beats could be made near-duplicates. A whole
  country against one trip's bounds cannot be. `collapse` is now driven directly.
- `RecapDeckBudgetTests` re-baselined [2,6,6,6] → [2,5,5,5], and the arithmetic
  points the *other* way, which is why it is worth stating: that test passes a
  synthetic extent under which the opening used to collapse to **3.0 s with no
  establishing shot at all**. It now gets a real 6.5 s one. Holds 8.61 s → 8.02 s,
  which is one photo of deck. The shipped path went the other way, 9.0 s → 6.5 s.

## 14. Still open

- **The station-boundary sharpness step** (§10) — 0.747 at hold boundaries. §7's
  cross-fade remedy costs no extra fetches. Not built; judge the render first.
- **`opening_country_s` is now read by nothing**, like `keyframe_interval_frames`.
  Both left in config deliberately.
- **The country table has six rows.** Every trip outside them falls back loudly to
  trip bounds × `country_view_padding`.
- **The title card's text** still shows trip title + dates·km. The country name is
  now available offline via `CountryExtent.Country.localizedName`, but **wiring it
  into the card was not done** — that is `App/Services/RecapComposer.titleSubtitle`
  and a `RecapTrip` field, and it is chrome layout, which is DESIGNER territory.
- **The continuity gate still never measures the shipped `establishing: nil`
  camera.** Unchanged deliberately; re-confirmed still true.
