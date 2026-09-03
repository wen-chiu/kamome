# Visual Review: the type-2 opening — the crossing beat

Judged 2026-09-02. **Direction decided by Chiu the same day**, recorded below.
Detail is deliberately left to the PO and engineering.

## Evidence

- **Film:** `~/Kamome-films/type2-2026-09-02/kamome-auckland-crossing.mp4`, 60.0 s.
- **Trip:** `Tests/Fixtures/trips/auckland-crossing.json` — **synthetic**, no §0 exposure.
- **Path:** branch `claude/kamome-cross-region-films-b2e35f` (`491e581`), not on `main`.
  Engineering findings: `Docs/handoff-type2-films.md` on that branch.

## What the render showed

Sixteen seconds pass before the road trip starts, and they are spent on a map
that has no names on it — the round's own probe records that MapKit stops
labelling the two cities somewhere between Sydney's frame and Auckland's, so at
8,891 km the picture is a texture rather than a place.

| finding | |
|---|---|
| the title card names **Auckland** over a frame centred on the Philippine Sea; New Zealand is a sliver at the edge of the card's own scrim | 1.0 s |
| both ends label as `Unnamed stop` — neither place is ever named | 3.5 s, 13.6 s |
| the crossing's dashed leg keeps being drawn for the remaining 42 s, through the end card | 16–58 s |
| the odometer reads 8,755 km before the trip starts and 9,024 km at the end — **97% of it is the flight** | throughout |
| a car crosses the Pacific at roughly the size of Taiwan | 7–13 s |

The last one is known and scoped to the crossing-mode session; do not judge the
camera by it.

## ⭐ Decided (Chiu, 2026-09-02)

### 1. The opening is retimed — 16 s becomes 11.5 s

| | |
|---|---|
| 0.0 – 3.0 s | title card over the flight frame — **unchanged** |
| 3.0 – 6.0 s | departure-airport stop, same still frame — **one or two airport photographs, not the full deck** |
| 6.0 – 10.0 s | the crossing: camera still, sprite crosses (`crossing_beat_s` 6.0 → **4.0**) |
| 10.0 – 11.5 s | the arc closes into the destination — **unchanged** |
| 11.5 s | the trip begins |

**Not changing:** the camera, the map's framing, the title card, the arrival arc.
**No place names are drawn on the map** — the icebox stays frozen, on Chiu's
ruling that the effort is not justified.

### 2. The crossing carries a boarding pass

During the crossing, the region the title card vacated carries a **Journey Card
in boarding-pass form** — perforated stub, `FROM` / `TO`, region name in English
over the local name, a dotted arc with the aircraft travelling it.

**Reference: Chiu's own mockup, supplied 2026-09-02** (the light ticket variant,
"登機證樣式（完整）"). Save it beside the film before engineering picks this up.
The mockup is the visual target; the layout details are theirs.

**Content — what Kamome actually knows, all offline:**

| field | source |
|---|---|
| region names (TAIWAN / 台灣, NEW ZEALAND / 紐西蘭) | `CountryExtent` ISO code + `Locale.localizedString(forRegionCode:)` |
| dates | last origin photograph, first destination photograph |
| distance | the crossing leg |
| flight number | **the constant `THX-9527`** (Chiu, 2026-09-02) |

**`FLIGHT TIME` is removed** (Chiu, 2026-09-02). Kamome does not know departure
or arrival times, so it cannot compute one, and printing a number it does not
have is a fabricated record. The bottom row is therefore **distance + dates** —
and distance is where the 8,755 km retired from the odometer belongs, labelled as
the flight.

⚠️ **The flight number must stay a constant.** `THX-9527` is a joke and reads as
one only while it is the same on every film; derived per trip it becomes a claim
about a real flight, which is the fault the field was flagged for. Never compute
it, never vary it.

### 3. The crossing's dashed leg appears only on the end card

Hidden from the arrival onward; drawn again for the end card, where the whole
journey is being shown.

### 4. The odometer counts the local trip only

No flight kilometres. On this film that is **269 km**, not 9,024 km. The flight's
distance belongs on the boarding pass, labelled as the flight — which is where
the retired number should go.

## Flags for the PO conversation

- **The sprite gets faster.** Chiu's own derived rule is ~16.5–17 %/s of frame
  width; at 4.0 s on this film's 98% frame share it becomes **24.5 %/s**. A
  deliberate trade — the card now carries the beat's meaning — but if it reads as
  rushed, the answer is to de-emphasise the sprite, not to re-lengthen the beat.
- **`crossing_beat_s` was chosen from a rendered sweep on 2026-09-02.** Changing
  it is a re-decision; the closeout note in `Docs/handoff-type2-films.md` should be
  amended rather than silently contradicted.
- **The long-haul threshold is still 70° and still interpolated.** This film sits
  at 53.2°, inside the policy, and was still judged too wide. Nothing here reopens
  the number — but the evidence that would has now been rendered.

## Considered and declined

- **A camera that travels with the flight** (Chiu's original instinct, and the
  external spec's Scene A→D). Declined: it is a camera translating ~9,000 km,
  which is the 2026-08-02 act-camera defect — the type-2 build hit it in practice
  (`confine` chasing the aircraft, 31 gate violations) and fixed it by holding the
  camera still. The cost objection was real but secondary; continuity is the
  reason.
- **Four camera regimes** (external spec §15) — per-act framing, on
  `Docs/camera-arcs.md` §12's list of what must not happen.
- **Place names drawn on the map** — iceboxed 2026-08-02; Chiu ruled the effort
  is not justified now.
- **Reframing the opening on the destination country**, proposed by this session:
  declined in favour of the smaller change above.
