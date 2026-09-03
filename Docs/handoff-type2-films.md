# Findings — the type-2 film (home → one destination abroad), 2026-09-01

The engineering round that asked whether a long-haul frame exists before
designing an opening around one, and proposed how a film knows which of Chiu's
three types it is.

⚠️ **Nothing here is in `Docs/decisions.md`.** Task 3 is unbuilt and waits on
Chiu's answer to §3.

---

## 1. ✅ TASK 1 — MapKit **cannot** render a long-haul frame past ~109° of longitude

**The answer is not "all four are fine."** Three of the four pairs return a
genuinely beautiful frame. The fourth has **no frame at all**, and the wall is
lower and harder than the brief anticipated.

Method: one snapshot per pair per appearance, through the shipped
`MapKitSnapshotProvider`, at the shipped 1080×1920 frame, framed the way beat 2
is framed today (the span that fits both ends × `wide_span_padding` 1.5).
Harness `LongHaulFrameProbeTests`, images in `~/Kamome-wt/task1-longhaul/`,
log `~/Kamome-wt/logs/task1-probe2.log`.

| pair | great circle | **Δ longitude** | frame span | snapshot? | what it shows |
|---|---:|---:|---:|---|---|
| Taipei → Ishigaki | 272 km | 2.6° | 393 km | ✅ both | Taiwan's coast, the Yaeyamas, both cities labelled |
| Taipei → Tokyo | 2,175 km | 18.1° | 2,606 km | ✅ both | Japan, Korea, east China — both cities labelled |
| Taipei → Sydney | 7,206 km | 29.6° | 5,532 km | ✅ both | Australia, SE Asia, both cities labelled |
| **Taipei → Paris** | **12,313 km** | **119.2°** | 15,909 km | ❌ **none exists** | — |

**Both appearances are usable at every span that renders.** Light and dark differ
only in palette; neither degrades with distance. Sydney at 7,206 km is as legible
as Ishigaki at 272 km — it reads as an airline route map already.

⚠️ **The brief's ~9,800 km figure for Taipei → Paris is low; it is 12,313 km.**

### The wall, measured three ways

**(a) MapKit saturates at ~109° of longitude.** Asking the shipped provider for
8,000 / 10,000 / 11,200 km of width at the Taipei–Paris midpoint returns the same
picture — 108°, 109°, 109°. Content statistics are identical to one decimal from
8,000 km up. Taipei lands at x = 1133 and Paris at x = −53 in a 1080-wide frame:
**53 px outside each edge, symmetrically, and no span request moves them.**

**(b) The ceiling is MapKit's, not the portrait frame's.** The sweep above always
asked for a 9:16 region, so it could not tell "MapKit will not draw wider" from
"a 9:16 region that wide is not askable". Asked directly, with a deliberately
*short* latitudinal span — a region no Kamome frame would request, used only to
locate the limit:

    asked  8,000 km wide × 2,000 km tall  →  rendered  90° of longitude
    asked 12,000 km wide × 2,000 km tall  →  rendered 109°
    asked 16,000 km wide × 2,000 km tall  →  rendered 109°

**No aspect ratio, frame size or region trick gets past 109°.** It is a zoom-level
floor in the snapshotter.

⚠️ **Measured at latitude 36.94 only.** That the cap is a fixed *longitude* span
independent of latitude is INFERRED — a zoom floor is a fixed fraction of the
Mercator world width, which is a fixed longitude span — not measured. The cheapest
thing that would settle it is the same three-row sweep at a second latitude.

**(c) It is not a padding problem.** Taipei → Paris needs 119.2° of content
*unpadded*. 119.2 > 109, so removing `wide_span_padding` entirely does not
produce the frame either.

### 🔴 The shipping path will terminate the process on such a frame

`MapKitSnapshotProvider.snapshot` builds
`MKCoordinateRegion(center:latitudinalMeters:longitudinalMeters:)` with no guard.
The first probe run died on it:

    Invalid Region <center:+36.94480000, +61.95880000 span:+254.85814536, +178.60432219>
    (NSInvalidArgumentException)

254° of latitude, and the planet has 180. This is an **Objective-C** exception —
no Swift `catch` can see it, so it is not a thrown error, it is process death. For
a 1080×1920 frame the threshold is **spanM > 11,271 km**.

Nothing generates such a frame today (body spans are tens of km, country beats
hundreds), so this is not a live bug. **It becomes one the moment any opening
frames two places on opposite sides of a long flight**, which is what Task 3's
option 2 does. The probe guards its own arithmetic rather than calling MapKit;
the provider does not. **Proposed, not built** — a guard in the provider that
throws `ScaleError` rather than dying, on the `pointSize` pattern that already
refuses a canvas it cannot express.

### What this does to Task 3's option 2

The scale-dependent answer the brief told me to prepare for is real, and the
boundary is **not a distance**. Sydney at 7,206 km works and Paris at 12,313 km
does not, but the reason is not the 5,000 km between them — it is that Sydney is
a **north–south** pair (29.6° of longitude) and Paris is an **east–west** one
(119.2°). Kamome's frame is portrait, so it holds a north–south pair comfortably
and an east–west one badly.

**So the threshold, if Chiu wants option 2 with a fallback, is in degrees of
longitude, not kilometres** — and a kilometre threshold would misclassify both
directions: it would refuse Sydney (works) and accept a shorter east–west pair
that does not.

## 1b. ✅ ADDENDUM — Iceland has no frame; Finland has one and it is a bad shot

Chiu's two pairs, added to the probe 2026-09-01 and measured at **two paddings**,
because for a high-latitude east–west pair `wide_span_padding` is the difference
between a frame and no frame. Log `~/Kamome-wt/logs/task1-addendum2.log`.

⚠️ **My earlier claim that ~109° covers every `CountryExtent` row was wrong**, and
Chiu corrected it. Two of the six rows are at or past the wall, and one of them is
the Iceland film — the Geoapify acceptance trip, the most-judged film here.

| pair | Δ longitude | padded ×1.5 | unpadded ×1.0 |
|---|---:|---|---|
| Taipei → Helsinki | 96.6° | ❌ 189.7° of latitude tall | ✅ renders, both ends inside |
| Taipei → Reykjavík | 143.5° | ❌ 272.5° tall | ❌ 181.7° tall *and* 143.5° > 109 |
| Taipei → Paris | 119.2° | ❌ 254.1° tall | ❌ 119.2° > 109 |

**Iceland is impossible twice over** — it fails the aspect limit *and* the zoom
floor, at every padding. Option 1 is not a nicety for it; it is the only thing
that can render.

**Finland is the informative row, and it says the rule needs headroom, not a hard
edge.** The unpadded frame does render and does contain both ends — and it is not
a shot anyone would ship:

- **Neither city is labelled.** The nearest labels to Taipei are Hong Kong and
  Shanghai; the nearest to Helsinki are Moscow and Istanbul.
- Taipei lands at x = 1021 and Helsinki at x = 59 in a 1080-wide frame — **59 px
  from opposite bezels**, at 5% and 95% of the width. `wide_span_padding` exists
  precisely to put them at 17% and 83%, and it is what had to be thrown away to
  make the frame exist at all.
- The picture is Siberia, Africa and the Indian Ocean. It is a world map, not a
  journey.

Against Sydney at 29.6°, where both cities are labelled and sit at 24% and 76%:
**the boundary between "frames" and "is a good shot" is far below the boundary
between "frames" and "cannot be framed".**

### The threshold this argues for

Two conditions, and the second is not a number:

1. **A policy maximum in degrees of longitude**, documenting the measured 109°
   wall and deliberately sitting under it. **Proposed: 70°** — Chiu picks it.
   It is where `wide_span_padding` 1.5 stops fitting inside the wall
   (109 / 1.5 = 72.7), it keeps New Zealand's 59.3° envelope in and Finland's
   96.6° out, and the Finland render is the evidence that 96.6° is too far.
2. **The padded frame must actually be expressible** — the same latitude-aware
   arithmetic the provider now enforces, evaluated as pure maths before any
   snapshot. A degree threshold alone cannot capture this: the aspect limit binds
   at low latitudes and the zoom floor at high ones, so which one fails first
   depends on where the pair is.

## 1c. The threshold: 70 ships, and it is interpolated

Chiu: take 70 and move on. **Be clear what it is: interpolated from a gap with no
data in it.** Sydney at 29.6° is a good shot and Helsinki at 96.6° is framed and
useless; nothing between them had been rendered, and 70 sat in the middle of that
67° gap. Two more pairs were measured on 2026-09-02 to fill it:

| pair | Δ longitude | padded ×1.5 | where the ends land |
|---|---:|---|---|
| Taipei → Auckland | 53.2° | ✅ frames | 25% and 75% of the width |
| Taipei → Moscow | 83.9° | ❌ zoom floor | unpadded only: 56 px from opposite bezels |

So the transition sits between **53.2° and 83.9°**, and 70 is inside it. Auckland
keeps `wide_span_padding` intact and puts both ends where padding is meant to put
them; Moscow behaves exactly like Helsinki.

⚠️ **One honest caveat on Auckland**: MapKit stops labelling the two cities
somewhere between Sydney's frame (5,532 km) and Auckland's (8,836 km), so at 53.2°
the base map names neither end. Kamome draws its own pins and labels over the top,
so this is a backdrop question rather than an information one — but it is the
reason the "good shot" boundary could be argued lower than 70.

⚠️ **The policy is not the binding constraint everywhere.** Near the equator the
portrait aspect refuses a padded frame at ~60°, below the policy; at mid latitudes
the policy binds first. That is why `CrossingFraming` checks both and neither
number alone is the rule.

## 2. ✅ TASK 2 — built, and the first rule was wrong

### The monotonic correction (Chiu, 2026-09-02)

The rule as first built returned `unknown` whenever **any** leg was NULL. That
sounded careful and was not: routing ships disabled and the offline gate
establishes nothing, so **every fixture classified `unknown`, fell back to the
local film, and the type-2 form would have had no test coverage at all** — the
fifth instance in this project of a property that only exists on the shipping path
being guarded only where the shipping path is not.

**An unrouted leg can only ever *add* a local journey, never remove one.** So the
journey count over confirmed crossings is a **lower bound**, and a lower bound of 2
is a fact whatever the unknowns turn out to be. `classify` now reads:

    >= 3          -> multiRegion
    == 2          -> oneDestination
    <= 1          -> local if nothing is outstanding, else unknown

`ishigaki-crossing` classifies **`oneDestination` offline**, which is what gives
the new form its coverage.

⚠️ **`>= 2` maps to the type-2 form, and that is sound only while type 3 is
deferred.** A lower bound of 2 could still resolve to 3; today both render the same
way, so nothing is claimed that could be wrong. **Revisit the day the multi-region
film is built.**

### Derived, never stored

`RecapTrip.everyLegRoutabilityEstablished` + a computed `filmType`. Two consequences
recorded rather than solved: the same trip yields different films on different days,
which sharpens ADR 2026-08-15's unmet third requirement (no export record exists);
and nothing tells a user that re-exporting later would give a better film.

## 3. ✅ TASK 3 — the type-2 film form, built

    title card over the flight frame -> the aircraft crosses, camera still
      -> the arc closes into the destination -> the destination's local trip
      -> end card

**The origin's drive is not in the film.** `RecapTypeTwoFilm.trimmedToTheDestination`
drops every leg before the crossing and every stop before the departure, keeping the
departure airport and its photographs. What that produces is a trip that *begins*
with its crossing — exactly `Docs/camera-arcs.md` §4 **Case C**, which that document
predicted and left unbuilt, and whose rule it already stated: *when the first local
journey is degenerate, the opening arc **is** the first crossing arc.*

⚠️ **This supersedes §4 Case B's reasoning for a type-2 film.** Case B says the film
opens on the departure because "you cannot arrive somewhere if the film never showed
you leaving". Still true — it is now the departure airport's photographs and the
flight frame that show it, rather than a drive across the origin city. The document
is stale on that point rather than wrong about the principle.

### Three defects the gate caught on the way, and what each taught

1. **71 violations from 4.33 s.** The arc began after the departure airport's stop
   hold, so the frame jumped from the flight frame to a 13 km frame on the terminal
   and back. Fixed by starting the opening arc at the opening's end, so the airport's
   photographs play over the frame the aircraft is about to cross.
2. **Body span 177.3 km, frame-to-frame overlap 100% — a still film.** The flight
   frame is the prologue's last beat, so `establishedSpanM` derived the body span
   from it and undid the whole 2026-08-31 chain-break. Fixed with an explicit
   override: a type-2 film keeps beat 2's *meaning* (the destination's own local
   journey) without having a beat 2 on screen.
3. **31 violations, the camera moving 24 km per snapshot step against
   `containedLerp`'s 7 km containment bound.** Not the zoom: `CameraPath.confine`
   keeps the subject inside the safe zone and was **chasing the aircraft across the
   sea while the frame shrank**. Fixed by giving `Arc` an explicit `holdUntilS` —
   the camera holds until the aircraft *lands*, then closes with a stationary
   subject, so `confine` does nothing and the move is a pure zoom.

**Every one of those was caught by the gate, not by looking.** The second is the
one worth remembering: it *passed* the gate (100% overlap is perfect continuity)
and was still wrong. Continuity passing is not the film being right.

### The gate now asserts the beat rather than trusting it

`assertTheFlightBeatIsStill` — every frame from 0 until the aircraft lands must
have ground overlap 1.0 with the frame at t=0. Same pattern as
`assertTheCardBeatIsStill`: **assert that there is no motion to be continuous
with, never forgive a window.** A slow drift keeps 99% frame-to-frame overlap and
would pass the continuity scan while being exactly what this beat must not do.

    ishigaki-crossing 60.0s · span 13.3 km · worst overlap 70% · 0 violations
                      · 2 permitted cuts · 0 excused · 1 arcs
                      · type oneDestination · opens on the flight ✅

No exemption was added or widened. The other six fixtures are unchanged.

### What the film does, measured

| | `main` | now |
|---|---:|---:|
| length | 69.0 s | **60.0 s** |
| body span | 20.0 km | **13.3 km** |
| snapshots | 178 | **135** |
| of which the opening | 14 | **1** |

**The opening costs one snapshot** — a still camera at any span, which is the whole
reason the flight can be drawn at all. Net against what ships today: 367 → 135.

Wall clock, one render at a time on this Mac: **type-2 87 s** (1800 frames, 36.4 MB),
**type-1 `miyakojima` 109 s** (2640 frames, 54.1 MB). The type-1 control is
unchanged — it classifies `unknown`, renders the local film, and is the evidence
that this round's change is confined to type-2 films.

### 4. The beat length: rendered at 4 / 6 / 9, and at two scales

⚠️ **SUPERSEDED ON THE NUMBER, NOT ON THE METHOD — read ADR 2026-09-03 first.**
Everything below was written while the beat's job was *"give the sprite a legible
traverse"*. Since the 2026-09-02 review the crossing carries a **Journey Card**,
and the beat is **4.0 s** because that is how long the card takes to read. The
screen-speed finding is still true and is still not to be re-swept; it simply
stopped being the quantity the constant chooses. Read `6.0` below as *what was
shipped on 2026-09-02*.

Chiu's method, not one fixture. `crossing_beat_s` was 6.0 and **reasoned, never
measured**, and `Docs/cross-region-journeys.md` warns in advance against a constant
reverse-derived from one trip — how `body_span_padding` and `tier_skip_share` were
both built and both removed.

**The measurement that decides whether a constant is even the right shape** — the
share of the *frame* the aircraft crosses, not the ground distance, because the
frame is fitted to the crossing (`RecapOpeningFramingTests`):

| fixture | crossing | frame | of the width | at 6.0 s | at 4.0 s (ships) |
|---|---:|---:|---:|---:|---:|
| `ishigaki-crossing` | 306 km | 443 km | **69%** | 11.5% / s | **17.3% / s** |
| `auckland-crossing` | 8,755 km | 8,891 km | **98%** | 16.4% / s | **24.6% / s** |

⚠️ **The 8,755 km is the *equirectangular* length and is 121 km short** (VERIFIED
2026-09-03). `Geo.distanceM` scales longitude by the cosine of the first
latitude alone, which degrades over a Taipei → Auckland diagonal; the great
circle is **8,876 km**. Harmless here — this table is about the *share of the
frame*, and both numerator and denominator ride the same axis — and **not**
harmless on the Journey Card, which prints the figure. The card uses
`Geo.greatCircleM`; see `HANDOFF.md`.

**A constant is far closer to right than the distances suggest.** 8,755 km is 29×
306 km, but the frame scales with it, so the perceived travel differs by **1.4×**,
not 29×. The worry that one number makes the sprite crawl on one film and tear
across the other is mostly answered by the framing itself.

**The residual is real and has a cause.** The frame is fitted to the crossing's
*bounding box* and padded on the dominant axis, so an axis-aligned crossing
(Ishigaki, mostly east–west) leaves slack the diagonal one (Auckland) does not.

So the two candidate rules are:

- **a constant** — 6.0 s gives 11.5% / s and 16.4% / s;
- **constant screen speed** — pick a % / s and derive the seconds. At Ishigaki's
  current 11.5% / s, Auckland would want **8.5 s**.

**Chiu picks from the films**, which is why all four were rendered:
`ishigaki-beat{4,6,9}s.mp4` and `kamome-auckland-crossing.mp4`.

⚠️ **Context, not to be solved here.** 13.4 s is 22% of a 60 s film, films cap at
90 s, and **"duration must scale with trip size" is direction-decided and
rule-undecided** (2026-08-14). Whether this beat is too long partly depends on a
rule that does not exist.

### 5. 🔴 The long-haul film found a bug the short one could not

`auckland-crossing`'s first render **failed**, and correctly: the **end reveal** was
fitted to the whole route including the flight, which asks for an 11,907 km frame —
190.2° of latitude tall, refused by the guard built earlier this round.

That is requirement 5's failure arriving in the *last* beat instead of the first,
and `ishigaki-crossing` could never have found it: its union is 443 km and
perfectly expressible. **The end reveal now opens out to the destination's local
journey**, like the body span and beat 2 before it.

This is the argument for the long-haul fixture existing at all, and it is now in
the continuity gate's list — eight fixtures, `0 excused`.

### 🔴 The most visible thing left: a car drives across the sea

The crossing subject is still the **car sprite**. The mode classifier
(plane / ship / seagull) is explicitly session 2 of the crossing work and was out of
scope, so this is not a regression — but it is far more visible now, because the
crossing is the *opening beat* of every type-2 film rather than something in the
middle of one. Judge the camera from this film; the sprite is the next session's.

⚠️ **And on a long-haul frame it is the size of Taiwan** — `subject_length_px` is
fixed in pixels, so the sprite reads correctly at 443 km and absurdly at 8,891 km.
A second argument for doing session 2 soon.

### 🔴 CONFLICT — `ishigaki-crossing` is a **type 2**, not a type 3

The brief states it "renders a type 3 today" and asks for a new type-2 fixture.
By the brief's **own** counting rule it is a type 2, and the tree therefore
already has one.

Established by inspection of the fixture and `UnroutableSeaProvider` (VERIFIED at
the file level, to be confirmed by measurement when the classifier is built): the
fixture has six stop clusters, and the provider calls a leg `noRoadHere` exactly
when its ends straddle 122.5°E.

    taipei         3 photos  121.561..121.567   west
    taoyuan        3 photos  121.230..121.236   west
    ishigaki-port  2 photos  124.153..124.156   east
    kabira         3 photos  124.143..124.148   east
    hirakubo       2 photos  124.311..124.313   east
    taketomi       3 photos  124.091..124.095   east

**One** leg straddles the meridian → **one** crossing → **two** local journeys →
type 2. The fixture's own `_comment` describes it as "a short drive across Taipei
to Taoyuan airport, an unroutable crossing of open sea, then four stops on
Ishigaki", which is Chiu's type 2 exactly.

What is true of it, and is probably what the brief meant: its **film** shows the
origin's drive, and the type-2 film form says the origin's drive is not in the
film. That is a difference in the *film*, not in the *classification*.

**Consequence:** the tree has a type-2 fixture and **no type-3 fixture**. Type 3
is out of scope this round, so nothing needs authoring for the gate to cover a
type-2 film — `ishigaki-crossing` already does, and it is already in
`RecapCameraContinuityTests`' list. Reported rather than resolved
(`CLAUDE.md`: state the conflict).

## 3. ⏳ The question for Chiu

Unchanged in shape from the brief, sharpened by §1:

- **Option 1 — the flight is not drawn.** Title card over a frozen frame of the
  destination country, cutting straight into the local trip. Works at every
  distance, costs one snapshot, and is what the opening already does.
- **Option 2 — the flight is drawn** over a frame holding both places, camera
  still, plane moving. **Available only when Δ longitude ≤ ~109°**, and
  comfortable well below that. Beyond it there is no frame, so option 2 needs
  option 1 as its fallback and a threshold to switch on.

If Chiu takes option 2, the number he is picking is **degrees of longitude**, and
the honest default is the measured ceiling with room under it.

---

# Closeout — 2026-09-02. Read this first if you are picking up cross-region.

🔴 **CORRECTED 2026-09-03. `crossing_beat_s` is 4.0, and the ADR is written**
(`Docs/decisions.md` 2026-09-03, which wins over this closeout). This section said
it *stays 6.0*; that held for one day. The 2026-09-02 visual review retimed the
type-2 opening and gave the crossing a **Journey Card** to read, so the beat stopped
being a screen-speed choice and became *as long as the boarding pass needs*. At 4.0 s
the sprite runs **24.5 %/s** on Auckland, knowingly.

⚠️ **If that reads rushed, de-emphasise the sprite — do not re-lengthen the beat.**
That lever is handed-over item 3 below (`subject_length_px`), and it is one decision
with the sprite's size, not two.

## ⭐ The beat's derivation is already validated — do not run another sweep

**Still true, and still the answer to the question it answers.** What follows
derives the *screen-speed* rule. Since 2026-09-03 the constant is not chosen from
screen speed, so this is the standing answer to *"how fast does the sprite cross?"*
rather than to *"how long is the beat?"* — and it is why no sweep is owed either way.

Chiu judged **Ishigaki best at 4 s and Auckland best at 6 s**, then accepted 6.0 for
both as a working constant. His two picks are **the same screen speed to within 5%**:

    Ishigaki   69% of frame width ÷ 4 s = 17.25 %/s
    Auckland   98% of frame width ÷ 6 s = 16.33 %/s

That is `frameShare / target_screen_speed` — the rule proposed from the arithmetic —
**confirmed independently by his eye**, on two films 29× apart in distance. So when
this is revisited, the answer is already derived and already measured: a target of
**~16.5–17 %/s** reproduces both picks. **No new sweep is needed** — and since ADR
2026-09-03 none is *owed*, because the constant is no longer picked from this rule.

Measure the frame share with `RecapOpeningFramingTests.testHowFarTheAircraftTravelsAcrossItsOwnFrame`.

## 🔴 Four items handed over, not solved

**1. The wide flight frame loses the viewer.** Chiu on the Auckland film: 地圖放太遠
會失去焦點, 一開始的畫面會無法明確知道出發地跟目的地. This is the **mirror of a defect
already recorded**: `Docs/handoff-P3.5.md` §"Map reference labels" (2026-08-02),
*"once zoomed in I lose all sense of geographic orientation"*, whose remedy was **a
recognisable country silhouette**. At Auckland's scale neither end is a silhouette,
so the flight frame violates a principle this project had already written down.
Two candidate answers — lower the threshold so the frozen destination card takes
long-haul, or draw Kamome's own labels at the two ends. **Chiu is deciding.
`crossing_flight_max_longitude_deg` stays 70 and is probably wrong; do not change
it here.**

**2. The union-derived sweep is owed.** The end reveal was the **third** camera
quantity found deriving from the whole route's union instead of a local journey,
after the body span and beat 2. Each of the three cost a render or a gate failure to
find. Reading the rest of the camera and pacing code for the same shape is cheap and
nobody has done it. **What I already know, not fixed:**

- `CameraPath.bodyFrame(route:spanM:config:)` passes the **whole route** to
  `FollowCamera.restingFrame`, whose `routeBounds` clamp is therefore the union. On a
  type-2 film that clamp is drawn around two countries. It is only the dolly's
  *starting* position, so it is probably harmless — but it is the same shape and it
  is unverified.
- `RecapDurationPlan` receives `localDistanceM` (crossings already excluded) — this
  one is **correct**, and is the precedent for what the others should look like.
- The odometer counts the flight: 120 km mid-crossing, 306 km on landing, on a trip
  whose driven distance is far less. Whether a Kamome odometer should include a
  flown leg is a **product** question, not a camera one.

**3. `subject_length_px` is absolute while the frame span moves 20×** (443 km →
8,891 km). **This is not session 2's**: swapping a car for a plane still leaves the
sprite 157.5 px on a Pacific-wide frame. It is a judgement — a map symbol need not be
to scale — and it needs Chiu's eye on the Auckland film. **The same cause hits the
trail**: the dash pattern is fixed in pixels, so each dash is ~50 km of ground on the
Ishigaki flight frame. Sprite and dashes are one decision, not two.

**4. The mode classifier** — crossing session 2, unchanged, still not this round's.

## What I fixed in the closeout, and what I deliberately did not

Bounds were: nothing needing a new config key, a new subsystem, a change to the
camera's shared machinery, or a Chiu decision.

**Fixed (both one-liners, both latent traps rather than live bugs):**

- `CameraPath.openingS` / `journeyStartS` now say what they do **not** mean. On a
  type-2 film the crossing arc owns the frame for ~10 s past both, so a reader
  treating either as "the body camera is live" is wrong — and nothing in the tree
  would have caught it.
- `LinearTimeline.opensOnTheFlight` derived from the frame alone while `CameraPath`
  derived it from the frame **and** a non-zero opening. They agree today only because
  no path has both a crossing and `openingS == 0`; the reporter now uses the same
  condition as the thing it reports on.

**Deliberately not fixed, inside the bounds, because each needs a judgement:**

- The **departure airport's stop scene plays at 443 km**, so its pin and name are
  drawn on a frame where the airport is sub-pixel. The deck reads fine; the *place*
  does not.
- The **subject is parked and visible on a country-scale frame for ~4.5 s** before
  the flight starts (measured: still at the airport from 0 → 7.5 s). Whether it
  should fade in later on a type-2 film is a look.

Both are overlay/subject timing rather than the type-2 form, and both would have
needed Chiu's eye, so they are named here instead.
