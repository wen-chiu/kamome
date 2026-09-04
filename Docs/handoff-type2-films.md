# The type-2 film — the closeout, and what it handed over

The three tasks that built this form are closed and archived
(`Docs/_archive/handoff-type2-films-tasks.md`), which also carries the three facts
worth knowing without reading them: the **~109°** MapKit wall, the **70°**
threshold and its interpolation, and that `ishigaki-crossing` is a type 2.

Decisions win over both: `Docs/decisions.md` 2026-09-01, 2026-09-03 (b),
2026-09-04 (b).


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

## 🔴 Five items handed over, not solved

**1. ✅ ANSWERED 2026-09-04 — the wide flight frame loses the viewer.** Chiu took
the **second** candidate below: Kamome draws its own wordless mark on each end of
the flight, from t=0 until the aircraft lands (ADR 2026-09-04). The threshold
**stays 70** and the map place-names icebox **stays frozen** — the marks carry no
text. What follows is the finding as it stood.

Chiu on the Auckland film: 地圖放太遠
會失去焦點, 一開始的畫面會無法明確知道出發地跟目的地. This is the **mirror of a defect
already recorded**: `Docs/_archive/handoff-P3.5.md` §"Map reference labels" (2026-08-02),
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
⚠️ **Sharper since ADR 2026-09-04**: a crossing that carries a boarding pass now
also flies a **plane**, and with no classifier a **ferry** gets both. The card and
the airframe never disagree with each other; neither is a claim about the world.

**5. ⚠️ The Journey Card reads ONE beat and sums ALL crossings** (added 2026-09-03,
with the boarding pass). `LinearTimeline.journeyCardContent` takes
`path.crossingBeatWindowsS.**first**` — the beat the pass is drawn over — while
`journeyCard(trip:locale:)`'s `crossingDistanceM` totals **every** leg with
`isCrossing`. On a type-2 film those are the same crossing, so the two are exactly
equivalent today and nothing is wrong.

**On a type 3 they are not.** A multi-region trip has two or more crossings, and
the first card would print the sum of all of them — a Taipei→Auckland pass
claiming the length of Taipei→Auckland→Sydney. **This is the same footnote as
"`>= 2 ⇒ the type-2 form` holds only while type 3 is deferred"** (§2), and it is
written here so type 3 inherits it rather than rediscovering it in a render: when
the multi-region film is built, the card's distance has to be scoped to the beat
it is drawn over, and there has to be one card per crossing.

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
