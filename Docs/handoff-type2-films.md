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

## 2. ⏳ TASK 2 — the rule is proposed, not built

See `HANDOFF.md` and §3 below. Proposal: count distinct local journeys by folding
the `SegmentRoutability.noRoad` partition, **derive it rather than store it**, and
make "unknown" the answer whenever any segment's routability is NULL.

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
