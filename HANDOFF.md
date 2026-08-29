# HANDOFF — current state

**Updated 2026-08-28.** Branch `feature/p4-appearance-follows-system`, off `main`
at `87d1d4e`. PR #18 (`feature/p4-visual-checks`) **merged**; PR #11 merged on
2026-08-15 (`Docs/decisions.md` 2026-08-15, Phase 3.5 close). Written so a fresh
session (or a fresh person) can pick this up without being briefed by hand.

Read `Docs/current-state.md` first for the project snapshot, then `CLAUDE.md`
for the standing rules — especially **§0, location data never leaves the device
by default**, as amended by the routing ADRs (`Docs/decisions.md` 2026-08-16 and
2026-08-20 (b)/(c)).

**This file holds only what is current**: live findings, open experiments, and
known bugs. Closed, resolved, and superseded sections were moved verbatim to
`Docs/_archive/handoff-2026-08.md` on 2026-08-21 — that file is history, never
current state.

---

## Findings — engineering session, the film follows the system appearance (2026-08-28)

**Context.** `Docs/eng-session-appearance.md` (the `Arch.md` §12 design, written
before any code), on `feature/p4-appearance-follows-system` off `main` at
`87d1d4e`. Chiu's decision of 2026-08-27: the film follows the device's system
appearance, and light mode gets an orange trail. **The first change in this series
that moves shipped behaviour.**

Both values that were Chiu's are now **closed** (2026-08-29): the orange is
candidate **B**, `RecapStyle.routeAccent` `#FF8A5B`, and the glow **stays off on
dark**. See `Docs/decisions.md` 2026-08-27.

**Stills for review** (outside the repo, §0 — renders of a real trip), all Iceland,
`car-toy` at the shipped 157.5 px, displayScale 2, the same frame the subject sweep
used: `~/Kamome-films/2026-08-28-appearance/`.

### 1. ✅ CLOSED 2026-08-29 — the orange is `#FF8A5B`, and the constraint the brief could not know

`RecapStyle.routeAccent` is **`#FF8A5B`** and its own comment calls it "the trail's
brand colour" — it is the validated web prototype's `--route`
(`Docs/prototype/recap_engine.html`), already shipped in Kamome as the active
progress dot and the stop's strap line. So "the trail is orange" is not a new
direction: it is the prototype's direction, which the dark souvenir map's cyan
overrode in 2026-07-22.

The constraint that follows: **the trail and the end card's mark are in the same
film.** `chromeAccentColor` `(0.95, 0.55, 0.32)` draws the brand mark and the
closing line (`RecapOverlayChromeDrawing:137,239–241`). The file already carries
two near-miss oranges, which is exactly what `routeAccent`'s comment says the
accent exists to prevent. Whichever candidate wins there is a case for collapsing
the pair — **that is Chiu's call and was not done here.**

Sweep candidates (`Docs/eng-session-appearance.md` §6): **A** = `chromeAccentColor`
exactly, **B** = `routeAccent` `#FF8A5B`, **C** = `(0.96, 0.42, 0.15)`, deeper, as
the hedge against a pale base. **Chiu chose B** (2026-08-29), so the film keeps one
warm accent rather than gaining a fourth. Collapsing `chromeAccentColor` into it
remains open and is still his.

### 2. 🔴 CORRECTS finding 8 — the glow was **not** "one line away"

`HANDOFF.md` finding 8 (2026-08-27) says the retired glow is "one line away
(`routeGlowColor` alpha in `RecapStyle.modernMinimal`)". It is not, and the
difference matters to the A/B it proposes.

`a58942d` did not zero the alpha on the glow's own colour. It replaced the line
with `style.routeGlowColor.copy(alpha: 0)` — the alpha of the **plain default's**
blue `(0.13, 0.45, 0.95)`. The retired pass was `(0.22, 0.62, 0.92)` at α0.32.
Raising that alpha would therefore have restored *a different blue* than the one
Chiu once accepted on the dark map, and the A/B would have been measuring two
changes while reporting one.

Closed by `RecapStyle.retiredGlowColor`, which holds the original colour so the
dark preset's alpha is genuinely the only variable. **VERIFIED from `git show
a58942d`,** not inferred.

The A/B it enabled has since been judged: **the glow stays off on dark** (Chiu,
2026-08-29). On dark the pass works exactly as designed — it lifts the terrain
beside the trail by `(8,29,29)`, compositing *lighter* than the ground, which is
the opposite of what it did on light — and he chose the trail without it anyway.

### 3. ⚠️ Three `RecapStyle` tokens have no consumer, and one test helper is a no-op

Grep-verified across `Core UI App Tests` on 2026-08-28:

| token | readers |
|---|---|
| `cardColor` | none — only `RecapAtmosphereTests` and `RecapRenderTestCase` assert/set it |
| `cardTextColor` | none — same |
| `markerColor` | **none at all**; its declaration is the only occurrence in the repository |

They belonged to the stop label's pill, removed on 2026-07-31 when the label was
restyled to the prototype's unplated `.clabel`. The comment above them still said
"still used by the stop label's pill" — corrected in place, tokens left alone.

The consequence worth knowing: **`RecapRenderTestCase.opaqueCardStyle` is
identical to `RecapStyle()`.** Its doc comment says it makes "chrome panels at
full opacity so their pixels are exactly white", and it is used by five assertions
in `RecapOverlayRendererTests` that believe they are rendering against an opaque
card. They are not — nothing reads the token. Those tests may still be sound for
other reasons; **nobody has checked**, and that check is not this change.

Removing the three tokens touches four test files and is its own change.

### 4. ⚠️ The reproducibility ADR is met in shape, **not** in persistence

`Docs/decisions.md` 2026-08-15 requires export variation to be chosen at the
composition boundary, held constant, **and persisted with the export**. The first
two are met and are the reason the design looks the way it does. The third is not:
`Core/Persistence/AppDatabase.swift` has **no export table** — the seed feature
that would create one is deferred by the same ADR.

So today: re-exporting the same trip on a device whose appearance has changed
produces a different film, and the only record of which one you have is the
`KamomeLog.recap.notice("film: …")` line, which now names the appearance.
**Stated, not solved.** When the export record lands it has exactly one obvious
field to carry. Do not read the design doc's §4.1 as a claim that the ADR is
satisfied.

### 5. The souvenir map would have got the light palette — closed before it shipped

`RecapModel.snapshotProvider` still returns `MapLibreSnapshotProvider` when a
`.pmtiles` region covers the trip. Nothing installs one today, so it never fires —
but with the film following the device, a light-mode phone with tiles installed
would have drawn an orange trail and a light-tuned grade over a **near-black**
map. That is the halo defect's mechanism (`a58942d`) running the other way.

`MapRendererCapabilities.fixedAppearance` closes it: the souvenir map declares
`.dark`, `RecapModel` resolves `fixedAppearance ?? requested`, and a new always-on
test holds both halves. The MapLibre half of that test **does compile and run** in
this build — verified by its positive control failing, not assumed from the
`#if canImport`.

### 6. ℹ️ `Docs/current-state.md` passes its staleness check and is still behind

Its "Last synced" line names 2026-08-21, which **is** the newest ADR in
`Docs/decisions.md`, so the protocol in `CLAUDE.md` reports it fresh. But its
*Active work* section still says the three visual checks are "NOT YET RUN" and
lists PRs #16/#17 as open; #18 has since merged and those checks are done.

The staleness protocol keys on the ADR ledger alone, so a session that only ran
the check would trust a stale Active-work section. Not fixed here — this is a
governance-session edit, and the file says as much.

### 7. MEASURED — Chiu's fjord, in numbers, and the trail against the sea

Every figure below is a pixel probe of the rendered stills at **row y = 657**, the
north-coast trail west of Sauðárkrókur, after the grade and vignette
(`~/Kamome-wt/pixel`, source `~/Kamome-wt/pixel.swift`). Same frame (t=114.3 s),
same camera, displayScale 2. **VERIFIED by measurement, not by looking.**

| appearance · trail | solid, composited | dashed (α0.55) | the sea beside it |
|---|---|---|---|
| light · cyan `#6BDEFA` *(today)* | `(92,190,218)` | `(102,188,217)` | `(115,184,216)` |
| light · **A** `#F28C52` | `(205,121,77)` | `(164,149,140)` | `(115,184,216)` |
| light · **B** `#FF8A5B` | `(216,120,84)` | `(170,148,144)` | `(115,184,216)` |
| light · **C** `#F56B26` | `(208,94,40)` | `(166,134,120)` | `(115,184,216)` |
| dark · cyan, glow 0 | `(92,190,218)` | `(62,126,169)` | `(26,49,113)` |
| dark · cyan, glow 0.32 | `(92,190,218)` | `(61,138,189)` | `(34,78,142)` |

**The fjord, quantified.** On today's light base the solid trail differs from the
ocean beside it by **(23, 6, 2)** — one channel, by 9%. That is the measured form
of "not distinguishable from a fjord". Every orange candidate separates it by more
than 100 on two channels.

### 8. 🔴 On the light base the dashed leg is indistinguishable from the solid one

**The finding this session did not go looking for.** Today, light base: solid
`(92,190,218)`, dashed `(102,188,217)`. **Δ = (10, −2, −1).** The two are the same
colour to any viewer. Honest provenance (PD-1, spec §0) is *not reaching the
viewer* in a shipped light film — the distinction survives only in the dash gaps
and the stroke width, and see finding 9 for what happens to the gaps.

Why: α0.55 over a **bright** background lands almost on top of the full-alpha
colour, because the backdrop is already near the trail's own luminance. Over
near-black it lands well below it — dark, dashed `(62,126,169)` against solid
`(92,190,218)`, clearly the weaker claim. **This is the halo inversion again**, in
a second token: an alpha-derived treatment tuned on a dark base behaves oppositely
on a light one. Worth stating as a rule, because it will keep happening.

**What the oranges do to it.** All three fix the invisibility and are clearly
weaker than their solid. Chroma (max−min channel) at *this* sample point:

| | solid chroma | dashed chroma, at y=657 | terrain there, for scale |
|---|---:|---:|---:|
| A `#F28C52` | 128 | 24 | 54 |
| B `#FF8A5B` | 132 | 26 | 54 |
| C `#F56B26` | 168 | 46 | 54 |

⚠️ **Do not read that column as a property of the alpha rule — it is a property of
what the leg crosses**, and I nearly recorded it as the former. At α0.55 the
backdrop shows through, and this particular leg crosses a pale **blue-grey**
terrain patch `(210,212,216)`, which pulls a warm stroke toward grey. Measured on
the same shipped preset (candidate B) where a dashed leg crosses **green/beige**
instead — the south coast near Vík in `stop-light` — the dashed stroke is
`(198,158,112)`, chroma **86**, unmistakably orange. So the honest range for B's
dashed leg is roughly **26–86 depending on terrain**, not 26.

What survives as a genuine input to the choice: C's deeper start gives its dashed
variant more colour to lose, so it holds hue on the worst backdrop where A and B
do not. ⏳ Chiu's call, and it need not be a straight pick of the three — keeping A
or B and raising `routeInferredAlpha` on light gets to the same place. Nothing was
changed on this.

### 9. 🟠 The dashes read at the stop camera and **not** at the travelling one

Printed by the harness on every subject still: **43 legs revealed, 8 dashed ·
longest 17.5 km = 4.0% of the frame width (span 432 km).**

4.0% of 1080 px is **≈43 px**. The dash cycle is `routeInferredDashPx` 26 +
`routeInferredGapPx` 22 = **48 px**. So at the wide travelling camera the *longest*
inferred leg in this film is shorter than one on-off cycle, and the other seven are
shorter still: it renders as **one stub**, not as a dashed line.

⚠️ **I first wrote this as "the dashed convention does not work", and that was
wrong** — the stop stills falsified it before it was committed. During a stop beat
the camera is far closer, and in `stop-light` the inferred stretch on the south
coast near Vík resolves into **unmistakable dashes** beside the solid trail, in a
clearly lighter orange. So the honest statement is about *where in the film*, not
about the convention:

- **Travelling shots (span ~432 km):** provenance is carried only by the stroke
  being thinner and paler. The dashes are not visible as dashes.
- **Stop beats:** the dashes read exactly as designed.

Whether that matters is a product question — a viewer sees both, and the stop beat
is where the film asks to be read closely. **Nothing changed.** The dash lengths
are style, not config, and stated at the 1080 reference width; resizing them
against the camera span is Chiu's call, not the appearance change's.

The 17.5 km leg is the detour-gate rejection — 61.6 km routed against 17.5 km
straight, the same one the 2026-08-21 and 2026-08-22 runs named. Routing was
byte-identical again this session: **50/58 legs reconstructed, 8 with no road
route, 0 unreachable, 0 rate-limited.**

### 10. ⚠️ A render silently drew the fallback marker instead of the car

Four light stills, identical but for `KAMOME_ROUTE_COLOR`. Three drew the car
sprite; the **`light-C-deeper`** run drew the **vector seagull fallback** — white,
on a light base, close to invisible. The test passed in 25.8 s with no retry and
**nothing in the console said the sprite set had not loaded.**

`VehicleSubjectRenderer.make` falls back to `.marker` when `VehicleCatalog.resolve`
returns nil, and its doc comment says that "only fires when the app's own resource
bundle cannot be found — a state no test can arrange". **That claim is now false by
observation.** Whether it is the same resource-bundle problem as the intermittent
`KamomeCore_KamomeExportEngine` crash below is *suggestive, not established*.

Three consequences:

1. A review still can be materially wrong while looking fine, and a reviewer would
   have no way to know. `KamomeLog` is in `KamomeConfig`, which `KamomeExportEngine`
   already depends on, so the diagnostic is about one line — **not added here**,
   because this change does not touch that file. Spawned as its own task.
2. `fallbackMarkerColor` (white) joins the list of tokens that arguably must differ
   by appearance — §5 of the design doc had it as "fallback-only"; this render is
   the counter-example. Product call.
3. `light-C-deeper` was **re-rendered** into `light-C-deeper-rerender/` so the
   sweep Chiu judges is clean. The affected still is kept beside it as the
   evidence. The trail pixels are byte-identical between the two runs — only the
   subject differed.

### 11. The chrome and the deck, on a light base — reported, not judged

`title-{light,dark}` and `stop-{light,dark}`. The brief's point stands: these
survived on light, but "survived" was not "was judged", and now there is a pair.

- **The title card works in both, differently.** The dark scrim
  (`chromeScrimColor`, α0.55 + centre boost) fades seamlessly into a dark base and
  reads as a deliberate letterbox band on a light one. Neither is broken; the dark
  one is the more elegant of the two. **No change made.**
- **`labelTextColor` is white type** and on the light base it is close to its
  limit over pale terrain — `labelShadowColor` is what is holding it up, which is
  what its comment says it is for ("a bright photograph or a pale glacier"). Worth
  Chiu's eye.
- **`labelPinColor` is cyan** `(0.35, 0.85, 0.95)` — the same colour family as the
  water, on the light base, exactly the trap the trail was in. In `stop-light` the
  pin sits on the coast at Reykjavík. Not in the brief's list, and not changed.
- **`deckMatteColor`** (the white photo keyline) reads on both. The deck itself
  was rendered with the gradient stand-ins — `KAMOME_STOP_PHOTOS` was not set, and
  the harness says so on the console — so this is a **layout** check, not a check
  of how a photograph sits on a light base.
- Stop names read "Unnamed stop": `RecapReviewGeocoder` is opt-in and was off.
  Expected, not a regression.

**Verification worth noting.** `stop-light` and `stop-dark` used **no colour
override at all** — only `KAMOME_MAP_APPEARANCE`. One value selected the light
Apple Maps base *and* the orange trail, and its solid stroke measures
`(216,120,84)`, matching candidate B exactly. That is the shipped path working end
to end, not a harness-only result.

### 12. ✅ 2026-08-29 — two more tokens were in the water, and the enumeration was wrong twice

Chiu approved the direction; the **values are candidates** for him, rendered into
`~/Kamome-films/2026-08-29-tokens/`.

**`fallbackMarkerColor` → ink `(0.11, 0.13, 0.19)` on light.** Finding 10 is the
reason this is not cosmetic: the marker only appears when the vehicle artwork
cannot be loaded, and *the wrong still survived review because a white gull on a
light base is hard to see*. So the token's job now includes being noticed.
Measured, with the sprite path deliberately bypassed:

| | marker, composited | terrain beside it | luminance gap |
|---|---|---|---:|
| light, **white** (what happened by accident) | `(216,218,222)` | `(211,213,217)` | **~5** |
| light, **ink** (the candidate) | `(25,32,48)` | `(212,213,218)` | **~180** |
| dark, white (unchanged) | `(216,218,222)` | `(91,115,152)` | ~105 |

Ink rather than the trail's orange, deliberately: a warm gull would sit on the warm
trail it is travelling along and read as styling rather than as a fault. The value
is `markerOutlineColor`'s, reused so the film gains no new colour, and only `fill`
matters — the shipped `.seagull` is a single stroked arc that reads neither
`accent` nor `outline`.

**`labelPinColor` → the trail's own hue on light.** Not a new rule: the dark preset
had followed it silently all along — `(0.35,0.85,0.95)` is within **0.07** of
`trailOnDark` on every channel. Left cyan on Apple Maps it is a water-coloured dot
sitting on a coastline. Dark is deliberately untouched, so the change is one
appearance wide.

⚠️ **The part worth carrying forward is how the enumeration failed.** The design
doc's palette table (§5) got two answers wrong, both the same way: I judged each
token by *where it is drawn* rather than by *what it is drawn on*.
`fallbackMarkerColor` was written off as "fallback-only" and the fallback fired by
itself the same day. `labelPinColor` was never enumerated at all — the brief did
not list it and it is not part of the trail. The question that catches both is not
"does this token matter?" but **"what does this colour sit on, on each base?"**
Anyone auditing the remaining tokens should ask it that way.

Both are held by new always-on guards, each shown red by a positive control — as
*rules*, not values: the pin must sit in the trail's hue family (not equality, since
the dark pin is deliberately a shade off), and the fallback marker must contrast
with its base by luminance (not "must be this ink", since what has to be true is
that it is visible).

**The pin, measured** (stop beat, light base): the cyan pin composited to
`(77,186,211)` beside a sea of `(100,179,218)` — **Δ = (23, 7, 7)**, which is the
*same margin* that made the trail read as a fjord. The trail's hue puts it at
`(216,120,84)`, Δ from that sea `(116, 59, 134)`.

### 13. ⏳ OPEN — solid versus dashed, asked as its own question

Chiu asked for this to be judged separately rather than absorbed into the colour
pick, because it is a **product rule** (PD-1, spec §0): recorded versus
reconstructed-from-photos has to reach the viewer.

**First, what the orange already did.** The defect in finding 8 was cyan-specific.
On light, cyan solid `(92,190,218)` vs cyan dashed `(102,188,217)` — Δ `(10,−2,−1)`,
the same colour. With the chosen `#FF8A5B` the two are plainly different at every
alpha tried. **The provenance defect this session measured is closed by the trail
change**; what is left is a preference about how much weaker a guess should look.

**The sweep** — stop beat, light base, `routeInferredAlpha` the only variable, all
sampled at one pixel over the same terrain (`~/Kamome-films/2026-08-29-tokens/`).
Solid is `(216,120,84)` in every row:

| `routeInferredAlpha` | dashed, composited | Δ from the solid | chroma |
|---|---|---|---:|
| 0.40 | `(192,170,121)` | `(24, 50, 37)` | 71 |
| **0.55** — ships today | `(198,158,112)` | `(18, 38, 28)` | 86 |
| 0.70 | `(203,145,103)` | `(13, 25, 19)` | 100 |

Monotonic and exactly the trade you would expect: **lower alpha separates it from
the solid, higher alpha keeps more of the trail's own hue.** There is no value that
maximises both, so it is a judgement, not a calculation.

**Two things that constrain the judgement, and neither is alpha.**

1. At the **travelling camera** the dashes do not resolve at all (finding 9 — a
   43 px leg against a 48 px cycle), so colour is the *only* provenance cue there,
   and no alpha changes that. If Chiu wants the guess legible during travelling
   shots, the lever is dash geometry against camera span, which is a separate
   question with its own render.
2. **This cannot be gated.** The separation that matters is the *composited*
   difference, which depends on the terrain the leg crosses — the whole point of
   finding 8's correction. At style level the only expressible rules are the ones
   `testInferredLegsStayDerivedFromTheTrailInEveryAppearance` already holds (same
   hue, weaker alpha, thinner, actually dashed). A rendered gate over
   `FlatSnapshotProvider` would *pass on the exact defect this session found*,
   because a flat synthetic background is not Apple Maps' terrain — so it would
   buy confidence rather than coverage, and is deliberately not added.

**Nothing changed.** `routeInferredAlpha` stays 0.55 until Chiu says otherwise.

---

## Findings — engineering session, three visual checks (2026-08-22)

**Context.** `Docs/eng-session-P4-visual.md`, run on `feature/p4-visual-checks`
off `main`. Three cheap visual changes Chiu judges by looking, plus the stale
`XCTFail`. Ordered by what can go wrong silently.

**Films for review** (outside the repo, §0 — renders of a real trip). All three
are the same Iceland dump, `car-toy`, 21 stops, 64 legs, 211.5 s:

| | `~/Kamome-films/` | what varies |
|---|---|---|
| A | `2026-08-22-cartoy-light/kamome-iceland.mp4` | today's shipping look, halo removed · 472 s |
| B | `2026-08-22-cartoy-dark-x2/kamome-iceland.mp4` | dark, displayScale 2 · 491 s |
| C | `2026-08-22-cartoy-dark-x3/kamome-iceland.mp4` | dark, displayScale 3 · 475 s |

**Stills** (seconds each, since finding 6 was fixed), same frame t=114.3 s:
`2026-08-27-subject-stills/` — the 225/180/157.5 sweep plus the seagull;
`2026-08-27-appearance/{light,dark}/` — the light-vs-dark pair at displayScale 2,
which is the only place that axis has been compared on equal terms.

---

### 1. The halo was the configured glow, and the brief's premise was wrong

**Decision.** `RecapStyle.modernMinimal` no longer sets a glow alpha
(`a58942d`). The pass and its style properties stay.

**Why.** `RecapStyle()` has `routeGlowColor` alpha 0 — but nothing renders the
neutral default. Both the app (`UI/Recap/RecapModel.swift:202`) and the desk
harness (`Tests/AppTests/RecapDemoFilmTests.swift:63`) select
`RecapStyle.modernMinimal`, which set **alpha 0.32** with
`routeGlowWidthMultiple` **3.0**. The glow pass ran on every frame of the
2026-08-21 film.

**Evidence.** Measured on frame t=120 s of that film, against the preset's own
numbers — VERIFIED, not inferred:

| | measured in the film | the preset says |
|---|---:|---:|
| core stroke width, min over the curve | 17 px | `routeWidthPx` 17 |
| band ÷ core, median of 917 columns | 3.12 | multiple 3.0 |
| halo colour over terrain | (150, 183, 186) | (150, 184, 187) |

The colour figure is the glow at alpha 0.32 composited over the de-graded
terrain sample and re-graded; it lands within 1/255 on all three channels. After
the fix, the same measurement on film A gives band ÷ core **1.14** — a single
stroke plus its antialiased edge.

**Why it inverted.** The preset's comment says it was tuned against the dark
subtractive souvenir map, where translucent light-blue over near-black reads as
*light*. MapLibre was parked 2026-08-15 and films render on Apple Maps' light
base, where the same mid-blue composites **darker** than the terrain. Same code,
opposite effect — a consequence of the substrate ADR, the same class as finding
6 of 2026-08-21, **not** a defect in `RecapOverlayRouteDrawing`.

**Risk.** The glow is the right treatment again the day a dark base returns, and
film B shows a dark base is now one parameter away. Whoever turns that on must
re-judge the trail, not assume the glow should come back with it.

### 2. ⚠️ The golden-frame and continuity gates cannot see `MapKitSnapshotProvider` at all

**Decision.** `MapKitSnapshotScaleTests` was written because the brief's
proposed verification could not have worked.

**Why.** The golden-frame gates render on `FlatSnapshotProvider`, which carries
its own projection and its own `RecapStyle()`. `RecapCameraContinuityTests` runs
offline over `CameraFrame`s and never renders. **Neither touches the shipping
base-map provider.** Every other `MapKitSnapshotProvider` reference in the suite
is an env-gated bench.

**Risk, and it is wider than this task.** Apple Maps has been the shipping
substrate since 2026-08-08, and the type that produces it has no always-on test.
A projection error there is invisible to CI, and invisible in a still frame.

### 3. 🔴 MapKit may raster at a scale nobody asked for — measured, cause UNKNOWN

**What happened.** The first scale-2 render was refused by the provider's own
guard: MapKit returned a **1620x2880px image for a 540x960pt canvas — 3x**, the
simulator device's native scale.

**What was then measured** (`MapKitSnapshotProbeTests`, live SDK):

- `point(for:)` answers in the **point canvas the snapshotter was given** — a
  540x960pt canvas puts the region's centre at (270, 480). VERIFIED across
  scales 1/2/3. This is what the correction rests on, and it means the factor is
  `widthPx / canvasWidth` — the *requested* scale — never the raster scale.
- Scales 1/2/3 × spans 20/200/900 km × 8 concurrent requests: **every one
  honoured the request exactly.** The deviation did not reproduce.

**So the trigger is UNKNOWN** and is treated as something MapKit may do rather
than something Kamome can prevent. The guard now refuses only a **non-uniform**
raster, where no single factor maps canvas to frame; a uniform one at any scale
is resampled into the frame and the labels still arrive at the requested size
(`f995b13`).

**Cheapest thing that would settle it:** re-run the scale-2 film and watch for a
second occurrence. One deviation in three renders is not a rate.

### 4. The keyed path works — the 2026-08-21 UNKNOWN is closed

**VERIFIED.** All three renders routed against Geoapify with the key in
`Config/Secrets.xcconfig`, through the app's own configuration. No 401, no
locally-run Worker:

    matchTrip: 58/64 legs routable, budget 120s
    matchTrip: 50/58 legs reconstructed; 8 have no road route, 0 unreachable,
               0 rate-limited, 0 never asked

**Better than the reference run**, which reported 49/58 and 1 unreachable. The
1 unreachable was the timeout it named as retryable, and it routed this time —
so 50 solid legs, and the reference film's own reading of it was right. The 8
without a road route are identical, and the detour-gate rejection is
byte-identical (61.6 km routed vs 17.5 km straight, 3.5×), which is a good
cross-check that this is the same trip through the same policies.

Reproduced on all three renders. Nothing here reopens ADR 2026-08-20 (d).

### 5. displayScale changes label *density*, not only label size

**Reported, not decided — this is Chiu's judgement.**

Labels roughly double from scale 1 to scale 2, as predicted. But MapKit also
chooses **fewer** of them, and the effect is strong by scale 3:

| | scale 1 | scale 2 | scale 3 |
|---|---|---|---|
| Sauðárkrókur | present, small | present, ~2× | **absent** |
| Blönduós | present | absent | absent |
| Akureyri | present | present | large, **collides with the route line** |

Scale 2 reads as the balance; scale 3 buys size by spending the place names the
souvenir map is partly made of. Road-network detail thins at 3 as well. Both
knobs are env overrides (`KAMOME_MAP_APPEARANCE`, `KAMOME_MAP_DISPLAY_SCALE`),
**not** config keys — nothing is shipped until Chiu picks one.

### 6. ✅ FIXED 2026-08-27 — `RecapPilotFilmTests` and `RecapStopStillTests` could not run at all

**Was:** `RecapReviewScene.make` threw `SetupError.noRegion` when no `.pmtiles`
region covered the trip, so since 2026-08-15 both harnesses depending on it were
dead — the one that limits a render to N seconds, and the only one that writes
stills. Every review render this session had to be a full 211.5 s film, ~8
minutes each, which is why `KAMOME_SUBJECT` was wired into `RecapDemoFilmTests`
(`cad1dba`) rather than reused.

**Fixed in `78a910e`**, and the rule now has **one** implementation
(`ReviewSubstrate`) because two copies had already proved they get corrected
separately: `77b71b4` fixed the `RecapDemoFilmTests` copy and did nothing for
this one. Stills now render in under a minute, which is what made the
subject-size sweep (`57a5692`) cheap enough to do properly.

**The lesson worth keeping:** a rule stated twice is a rule that will be fixed
once. Both copies here were wrong, in different directions — one `XCTFail`ed and
carried on, the other threw.

### 7. ✅ DECIDED 2026-08-27 — the subject shrinks 30%, the mark does not follow

`export.subject_length_px` **225 → 157.5** (Chiu, from a 225/180/157.5 still
sweep on the film he had just watched), and the seagull's `length_fraction`
**0.7 → 1.0** so the mark holds its current 157.5 px rendered size. `57a5692`.

**Why the mark was asked about rather than left to follow:** at 0.7 of the new
base it would render at 110.25 px, and 112.5 px (0.5 of the old base) is the size
rejected on 2026-08-18 for reading too small.

⚠️ **Carry this forward:** pinning at 1.0 discards the relational intent
`cb14ae8` built the fraction for. The mark is now the same length as a vehicle
and **will** follow the base fully next time it moves — today's size survives
only because the base fell by the reciprocal. If `subject_length_px` changes
again, the mark's size is a fresh judgement, not something this value protects.

The film sprite is `seagull/omni.png`; `logo.png` beside it is only the S3 picker
thumbnail.

---
### 8. 🔴 IF DARK SHIPS, `a58942d` REOPENS — the halo verdict is light-only

**Not acted on. Do not touch `RecapStyle` on this.**

`a58942d` turned the glow off **because the base was light**, and its own message
says the pass "is the right treatment again the day a dark base returns". Chiu
accepted "the halo is gone" from film A, which was rendered **light**. That
acceptance is therefore not a settled result on a dark base — the glow was
designed for one and inverted only on the other.

So the appearance choice is not just a look decision: **picking dark reopens a
closed one.** The mechanism is intact and one line away (`routeGlowColor` alpha
in `RecapStyle.modernMinimal`), which is why it was kept rather than deleted.

**Evidence for the choice, rendered 2026-08-27:** two stills, light and dark, both
at displayScale 2, same frame (t=114.3 s), same subject size — one variable.
`~/Kamome-films/2026-08-27-appearance/{light,dark}/`. Chiu had never compared the
axis on equal terms: film A was light *and* scale 1, while B and C were both dark.

**Cheapest thing that would settle the glow question if dark is chosen:** render
that same still twice on the dark base, glow alpha 0 vs 0.32. Minutes, now that
`RecapStopStillTests` runs.

### 9. ⚠️ PROCESS — a wide `git add` committed a wrangler cache file

`Deploy/worker/.wrangler/cache/wrangler-account.json` was swept into `78a910e` (pre-rewrite `bbf08c4`), a
commit about substrate fallback. The Cloudflare account id in it is **not a
secret** — it is in dashboard URLs and authenticates nothing.

**Why it still mattered:** it is a 32-hex string, and this project's key-leak
check is "zero 32-hex hits over the pushed range" — used three times since
2026-08-21. One permanent false positive there teaches people to skip the check.
CI never would have caught it and was **not** widened: its guard greps
`*.xcconfig` for the routing key specifically, and that narrowness is deliberate.

Chiu chose to rewrite the branch (nothing had reached `main`);
`backup/p4-visual-prerewrite` at `0d7de54` is the pre-rewrite tip, his to delete
after the PR merges. `.wrangler/` is now gitignored (`834b0fc`).

**The habit worth changing:** `git add -A` was used for every commit this session.
It is why an unrelated file rode along in a commit whose message says nothing
about it.


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

## Findings — PO/Architecture session (2026-08-20)

**Context.** Chiu ran the Geoapify survey on 2026-08-19 and selected the provider.
ADR: `Docs/decisions.md` 2026-08-20. These are the items the survey did not close,
or closed differently from how it reported them. Ordered by what can go wrong
silently.

---

### 1. ⚠️ SUPERSEDED 2026-08-20 (d) — the mechanism below was measured and does not hold

**Read `Docs/decisions.md` 2026-08-20 (d) first.** Geoapify accepts no snap-radius
parameter, and measurement shows a 500 m radius would have accepted every wrong-road
case (they snap 44–132 m away) while the benign ones snap 465–477 m away. `radiuses=500`
was not guarding this band on OSRM either. The class it *did* guard — no road anywhere
near the waypoint — Geoapify rejects natively with `400 No suitable edges`.

**Standing instruction: the detour gate stays at 2.5, nothing new is built for this in
the migration PR, and the Iceland film is the test.** The rest of this item stands —
the gate still moves out of the provider file, and `.rateLimited` still stays.

### 1 (as originally written). The migration PR carries **two** policies out of `OSRMRouteProvider`

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

### 3d. ✅ DECIDED 2026-08-20 — the reindeer sets are **choosable subjects**

Chiu's decision: option **(a)**. `reindeer-cute` and `reindeer-deer` become
user-selectable subjects, like `car-toy`, not crossing art like `plane` / `boat` /
`seagull`.

**Reason, so it is not re-litigated:** the crossing set exists to describe honestly
*how a crossing was actually made*, and Kamome would never infer a reindeer. A
reindeer is a decorative choice, and changing the vehicle is the most common
community request.

Work: a `vehicles.json` entry each with `"selectable": true` and both locale names,
then the two pinned tests — `testTheSubjectsAUserMayChooseAreExactlyThese` and
`testEligibilityIsTheFlagAloneAndArtCannotNarrowIt` — updated. Per `Arch.md` §7.5 the
rule genuinely moved, so the reason goes in the commit message. The 18 PNGs commit
with it, not before.

---

### 3e. 🔴 PROCESS — two sessions shared one working tree, and a verification claim was contaminated (2026-08-20)

**What happened.** The sprite/key session reported `KamomeCoreTests 222 → 229 (+7)`
and attributed it to *"parametric tests now iterating 12 subjects instead of 10"*.

**That is impossible as stated, and it is checkable in one line.**
`VehicleCatalogTests.swift` is **XCTest** (`import XCTest`, zero `@Test`
annotations). **XCTest counts test methods, not loop iterations** — adding two
subjects to a suite that loops over subjects internally cannot change the count at
all. And `git show c0d4583 -- Tests/ | grep -c '^+.*func test'` returns **0**: that
commit added no test methods; it changed three lines of one pinned expectation.

**Where the +7 actually came from.** The **routing session's** uncommitted
`Tests/CoreTests/RouteReconstructionTests.swift` was sitting untracked in the same
working tree and growing while the sprite session measured. `Tests/CoreTests/` is a
directory glob in `project.yml`, so an untracked `.swift` file there is compiled into
the test target. It now carries 14 test methods. The same contamination explains
`swiftlint` going 160 → 163 files.

**Why this matters more than the number.** The sprite session's Level 1 evidence —
"338 tests, 0 failures", "0 violations, 163 files" — is partly a claim about **code
it did not write, did not review, and which was changing under it.** None of it is
wrong; none of it is attributable either.

**The rule this needs.** `Arch.md` §7.4 requires reporting the test count and
flagging any change. Add to it in practice: **before quoting a count, state whether
the tree contains uncommitted work from another session, and exclude it or say you
could not.** §9 already says a fixture that is local, uncommitted or divergent is a
red flag to stop and report — the same applies to sources.

**For Chiu, not the implementer:** two sessions in one checkout will keep producing
this. A git worktree per session removes it entirely and costs nothing.

#### ⚠️ But the worktree fix silently disables half the new key guard — **VERIFIED**

Two independent lines of evidence, and they agree:

- **Code:** `testTheSecretsFileIsNotTracked` reads `<repoRoot>/.git/index` directly.
  **In a worktree `.git` is a *file*, not a directory**, so the read fails and the
  test throws `XCTSkip`. The test's own comment names this case.
- **Measurement, from the isolating session's own table:** main tree reported
  `109 (16 skipped)`; both worktrees reported `109 (**17** skipped)`. One extra skip,
  in exactly the run where the index is unreachable.

**Not a defect anyone introduced** — the fallback was documented and points at the CI
step, which is unaffected (CI clones normally, so `.git` is a directory). It is an
interaction between two decisions made hours apart: the guard was written for a
normal checkout, and worktrees are now recommended.

**Consequence if left:** in the setup being adopted, the local half of the guard never
runs. Protection still exists, but only at PR time.

**Fix, small:** when `.git` is a file, read its `gitdir: <path>` line and resolve the
index there. ~5 lines, and it restores the local half. Low priority — CI covers the
actual risk — but do it before anyone concludes the local test is protecting them.

---

### 4. ✅ DONE — `matching.trip_budget_s` — measure it, do not pick a number

**Resolved (doc note 2026-08-21):** the measurement happened. Commit `1cedbd2`
("fix(routing): trip_budget_s 60 -> 120, from a measured 58-leg run") set the
budget exactly as this item asked, and `Config/TrackingConfig.json` now carries
**120**. The original item follows as the record.

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

### 7. ✅ RESOLVED 2026-08-21 (was: ⚠️ CORRECTED 2026-08-20 — the sprite tree holds three different things, not one)

**Resolution (VERIFIED 2026-08-21):** the three things landed as separate commits —
`6cc6543` (the 46 re-centred files) and `c0d4583` (the reindeer sets as choosable
subjects, per decision 3d, with manifest entries). `git status` is clean of PNGs.
The correction below stands as the record of why one commit would have been wrong.

**A merge session reported these as landed in `4ed8774`. They were not** — that commit
carried an *earlier* pass. Verified on `main` at `7b563d7`, the working tree still holds:

| | what | why it is its own commit |
|---|---|---|
| **46 modified** | boat, car-toy, car-white, drone, plane-3d re-runs | pixels only, sets already declared — same shape as `4ed8774` |
| **1 of those** | **`car-red/logo.png`** | car-red is the **reference proportion** the whole catalogue is sized against (`Vehicles/README.md`) **and** the default subject (NULL ⇒ car). Not a routine re-encode. |
| **18 untracked** | **`reindeer-cute/`, `reindeer-deer/`** — two entirely new sets | **`vehicles.json` does not mention reindeer.** Art with no manifest entry is bytes nothing can select, and which subjects a user may choose is pinned by a test on purpose. A new subject is a product decision, not an asset drop. |

So: **not committable as one change.** `./Tools/center-sprites.py --check` first.

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

**Cheapest thing that would settle the trigger.** A one-shot diagnostic in
`VehicleResourceBundle.resolved` naming, per candidate, the URL tried and whether
it existed on disk. It fires once per process and would turn the next occurrence
from "bundle NOT FOUND" into a diagnosis. **Not built** — it is investigation
instrumentation on shipped code and belongs to its own decision.

**Still not measured:** the rate. One miss in four renders is not a rate, and no
recurrence has been attempted since the diagnostic landed.

**Stale references left alone, deliberately.** `Docs/current-state.md` (blockers,
"🔴 intermittent … bundle crash") is the synced index and its neighbouring
section is being rewritten on `feature/p4-appearance-follows-system`; the
correction belongs to the pass that re-syncs it. `Docs/gate-P3.5-checklist.md`
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
