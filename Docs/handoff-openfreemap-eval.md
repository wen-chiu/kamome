# OpenFreeMap + MapLibre — the export substrate evaluation

**Rounds of 2026-09-09/11, engineering.** The decision is ADR 2026-09-09; this is
what running it returned. **Nothing here is decided** — the shipping substrate,
light/dark handling, hillshade, place names, the notice's second item and the
pmtiles path's retirement are Chiu's.

## The pictures

**All frames live in `~/Kamome-films/openfreemap-eval/`** — outside the repo
(§0). **One camera frame per fixture**, so only the base map varies:
`miyakojima` t=45.90 s z12.34 span 14.8 km (CJK names, small island),
`iceland` t=53.93 s z8.75 span 86.5 km (coastline, terrain, large span),
`ishigaki-crossing` t=43.37 s z12.50 span 13.3 km (cross-region, dashed sea leg).

Round 1 is 15 frames. Each is `apple-light`, `openfreemap-positron`, `openfreemap-liberty` (light) and
`apple-dark`, `openfreemap-fiord` (dark) — **Apple in both appearances**, so
Fiord has a baseline of its own. Every PNG carries a caption strip **below** the
film: style, fixture, t, zoom, span km, appearance, both timings. Attribution is
on the OpenFreeMap frames only.

## What round 1 settled — the ledger owns it now

`mountain_peak` **VERIFIED present** (TileJSON z7–14, real tiles `12/1858/1092`
and `12/3473/1756`); `MLNMapSnapshotter` **does** burn attribution in; CJK
renders once `MLNIdeographicFontFamilyName` is set. The two claims the ADR got
wrong are corrected in its **`Correction, 2026-09-10` addendum** (PR #49), now
the source of truth — including that **the cause of the logo difference is
UNKNOWN and must not be asserted**.

## The number, and what kind of number it is

**Seconds per snapshot, 1080×1920, iPhone 17 Pro simulator, network tiles.**

| substrate | genuinely cold | warm |
|---|---|---|
| `openfreemap-positron`, first render of the day | **10.14 s** | 0.05–0.06 s |
| `openfreemap-liberty` / `-fiord`, tiles already cached | 0.5–1.9 s | 0.04–0.07 s |
| `apple-light` / `-dark` | 1.2–2.7 s | 0.22–0.26 s |

⚠️ **Read these three ways or not at all.**

- **10.14 s** is a **single sample** — the first snapshot of the first run, paying
  for style, glyphs, sprite and every tile at once. Every later "cold" figure is
  only *tile*-cold: all styles read one source (`tiles.openfreemap.org/planet`)
  and MapLibre's ambient cache survives runs in the app container. The simulator
  was deliberately **not** erased — another session shares that bundle id.
- **Warm, MapLibre is ~4× faster than Apple Maps** (0.05 s vs 0.24 s), and an
  export is hundreds of snapshots. **UNVERIFIED on hardware** — D1–D5's job.
- The prior MapLibre figure (0.84 s) was local `.pmtiles`, not comparable.

## Round 1's visual findings

1. **The distance readout vanishes on Liberty** — a light grey HUD value lost in
   `#f8f4f0`. *Round 2 confirms the diagnosis below.*
2. **Positron is monochrome and its coastline nearly disappears** on
   `ishigaki-crossing`. *Round 2's fork answers it.*
3. Two-line place names are **closed** — Chiu 2026-09-10 keeps them.

✅ **The ideographic font family is ruled: `PingFang TC` is accepted** (Chiu,
ADR 2026-09-09 addendum 2026-09-11). It follows `CFBundleDevelopmentRegion:
zh-Hant`, so **Japanese** place names render in Chinese glyph forms — raised in
round 1, now decided.

## What was built — the edges only

Mechanics live in the code's comments (`ReviewSubstrate.Substrate`,
`MapLibreSnapshotProvider`, `RecapSubstrateEvalTests`). What is **not** there:

- ⚠️ **Stock styles are loaded from OpenFreeMap's hosted URLs** — which
  **deviates from the plan's "add a second style resource"**, deliberately: their
  URL touches no shipping file at all. The cost is that the style is whatever
  they serve that day; the tile set here is `20260906_080001_pt`.
- ⚠️ **One line reaches the shipped bundle** — `MLNIdeographicFontFamilyName` in
  `App/Info.plist`. MapLibre reads it from the main bundle at startup and has no
  runtime API, so there is nowhere else. Inert in a shipping build, which never
  constructs the MapLibre renderer. Named rather than hidden.

## The "flake" — a stale test bundle, and probably not this worktree's

**Four occurrences** — round 1 `iceland`, round 2 `miyakojima`, and twice in
round 3: `miyakojima`, then the `apple-dark` re-render of that same fixture.
**Round 3 kept the whole log, and it settles what ran:** the failure printed
`…which is not one of positron, liberty, fiord, liberty-fork`, the error text of
the harness *before* round 3 (round 3's reads `not apple-light, apple-dark or one
of …`). VERIFIED: pre-round-3 test code executed under a round-3 command.

- **Not "the first run after a build".** A controlled repeat — build, then the
  identical run twice — drew fresh code on the first pass (VERIFIED,
  `r3-logs/probe/`).
- **Probably another session's bundle.** At that moment two other sessions were
  mid-`xcodebuild test` (`~/Kamome-wt/rb3-localnet`, `~/Kamome-wt/rb2-verdicts`),
  both on `main` + #53 — exactly the harness that error text belongs to (VERIFIED
  by reading their files). This worktree's own pre-round-3 build cannot have been
  it: round-3 unit tests had already run green on this worktree's build before
  the failure. They targeted other simulator devices, so **how** their bundle
  reached this run is UNKNOWN — INFERRED, not asserted.
- 🔴 **The fourth occurrence rendered instead of failing — the case the first
  three only threatened.** The `apple-dark` re-render of `miyakojima` **exited 0,
  wrote a plausible PNG, and printed `Apple Maps (light …)`**: pre-fix code
  producing exactly the mislabelled baseline this round exists to correct. It was
  thrown away only because the run was **gated on a console line that only the
  fixed build prints** (`substrate Apple Maps (dark`); the retry passed. **A green
  exit code is not evidence about whose code ran** — gate every desk render.

Rounds 1 and 2 kept no logs; their cause is UNKNOWN and consistent with the above.

---

# Round 2 — the Liberty fork (2026-09-10/11)

**Chiu forked Liberty, dark only, no hillshade.** ⚠️ **Dark-only is sequencing,
not a decision** — his words, *"先一個一個來"* — and **ADR 2026-08-27 is
untouched**; the light path is not removed and nothing here records otherwise.

Three changes, no fourth: **減層** (16 furniture layers out — POI, shields, road
names, buildings, aeroway, airport), **色票** (`modern-minimal.json`'s palette,
verbatim), **大地名** (country/city/town `text-size` ×2, nothing else).
`Tests/AppTests/LibertyFork.swift` builds it into a temp file at render time —
**no shipping file gains an asset** — and `LibertyForkTests` asserts all three
with no network and no render. Forked against `20260906_080001_pt`.

`substrate-<fixture>-openfreemap-liberty-fork.png`, same three camera frames.
s/snapshot **2.7–7.8 s cold, 0.06–0.07 s warm** — cold here is style/glyph/sprite
cold but tile-*warm*, the stock rounds having filled that cache. Attribution
**still in the output** (VERIFIED by eye).

## What the fork answers, and what it does not

- ✅ **The distance readout comes back** — "72 km", "245 km", "61 km" all read.
  That confirms round 1's diagnosis: the HUD is **coupled to the substrate's
  value**, tuned against Apple Maps, and it fails on a light ground rather than
  on MapLibre. **Not fixed here** — it is chrome, and the fix is a DESIGNER call.
- ✅ **The coastline reads on `ishigaki-crossing`** — `#1e2b33` land against
  `#060d15` sea separates the island cleanly. This was round 1's substantive
  complaint about Positron and it is gone.
- ⚠️ **The road network is a fine dense web, not a skeleton.** The palette's road
  colour and width ramp are on **all** ~40 of Liberty's transportation layers, so
  a town reads as a hairball of uniform hairlines; the souvenir map draws only
  motorway/trunk/primary. Keeping every class was the literal reading of "keep
  the road geometry" — **cutting to three classes is the obvious next
  increment**, and Chiu's call.
- ⚠️ **Two palette rows have no Liberty layer to land on and were NOT applied**:
  the **water edge line** (`#4d7f86`) and the **peak accent** (`#9fd8e8`).
  Applying either means *adding* a layer, which is a fourth change. Consequence:
  inland water has no edge, and no peak is drawn even though `mountain_peak` is
  in the tiles. Stated rather than silently dropped.
- ⚠️ **大地名 does nothing on `ishigaki-crossing`** — its only place label is
  `ISHIGAKI ISLAND ⏎ 石垣島`, a `label_other`, correctly excluded by the spec.
- ⚠️ **Doubled labels now collide with the trail** — on `iceland`, `Hella` and
  `Hvolsvöllur` are partly under the cyan route. Bigger labels made an existing
  overlap visible.
- **Three things were left at their light-map values on purpose** and none showed
  in these frames: `boundary_2/3`, `road_area_pattern`, and `natural_earth` —
  ⚠️ that last one is a *light* shaded-relief raster with `maxzoom` 7, inert at
  z8.75–12.50 but **not at a country-wide establishing shot**.

**`options.scale` stays 1** — raising it to 2 doubles every label in pixels and
would undo the selectivity. Reported as an option, **not adopted**.

---

# Round 3 — the prototype's linework, and an orange trail (2026-09-11/12)

**Rulings:** ADR 2026-09-09, `Addendum, 2026-09-11` — Liberty is the base, the web
prototype is the reference, roads reduce, layers may be added, `PingFang TC` is
accepted, and an orange trail + glow set is authorised **for evaluation only**.
Dark-first is still sequencing; ADR 2026-08-27 is untouched.

**Built** in `Tests/AppTests/LibertyForkRound3.swift`, **on top of** round 2 so
round 2 still reproduces; `LibertyForkRound3Tests` asserts each change with no
network and no render. (a) all 61 `transportation` layers → `road-major`
(motorway/trunk/primary, minzoom 8) + `road-secondary` (minzoom 11); (b)
`mountain-peak-dot` + `-name`, `ele ≥ 600` and `rank ≤ 2` (**first guesses**), the
name copied from `label_town`'s two-line expression; (c) `island` leaves
`label_other` for `label_island` at `label_town`'s doubled size; (d) the souvenir
`inland-water-edge` (`class != ocean`); (e) glacier `#55646b`, opaque; (f) coast
A / B / C. Harness: `KAMOME_ROUTE_GLOW_COLOR`, `KAMOME_SUBSTRATE_EVAL_TAG`, and
`apple-light` / `apple-dark` as names in `KAMOME_SUBSTRATE_EVAL_STYLES`.

**Frames:** `substrate-{frame}-liberty-fork-r3-coast{A,B,C}.png` (12) and
`r3-orange-glow/substrate-{frame}-liberty-fork-r3-coastA.png` (4) — the 16 asked
for — plus re-rendered `apple-dark` baselines (see the harness bug below). **The
three cameras match rounds 1–2 exactly** (same z and span), so they compare like
for like although `main` moved underneath. The fourth frame is **`iceland-wide`,
t = 2.50 s — inside the title card's country beat**, z6.08, span 528.9 km; the
title card covers its lower quarter.

## The seam table

**Measured, not eyeballed:** B and C differ from A only in their coast layer, so a
pixel diff against A isolates exactly that layer. Masks and a lake crop are in
`r3-logs/seams/` beside the frames; the script is `r3-logs/seams.swift`.

| frame | A — contrast only | B — ocean fill outline | C — 1 px ocean line |
|---|---|---|---|
| `miyakojima` | no sea stroke, so no sea seam | **seams**: single straight lines across open sea (y≈94, y≈742, x≈615) | **seams**: the same tile edges |
| `iceland` | 🔴 **lake seam** (below) | **seams**: y≈1399 across the sea | **seams, doubled**: y≈1398/1425, x≈69/96, x≈930/957 |
| `iceland-wide` | lakes not inspected | **seams**: a full-width line at y≈30 | **seams, doubled**: a full grid — three horizontal and two vertical pairs across the whole sea |
| `ishigaki-crossing` | no sea stroke, so no sea seam | **seams**: x≈407 the full height of the sea, y≈547 | **seams**: the same, doubled |

- **B seams on every frame, and so does C.** B draws each tile edge once, C draws
  it as a pair ~17–27 px apart (measured on `iceland` and `iceland-wide`). That the
  pair is the tile buffer — each neighbouring tile stroking its own clipped
  polygon — is INFERRED.
- 🔴 **A is not seam-free either.** The souvenir lake edge strokes tile-clipped
  lakes: `crop-iceland-coastA-lake-x3.png` shows a straight 2 × 2 grid across
  Þingvallavatn. It is in all three variants, because (d) is.
- **Not picking.** The table says only that "contrast only" is the one variant
  without a sea seam, and that no variant is without a lake seam.

## What the map does now

- ✅ **The island-name fix works** — `Ishigaki Island ⏎ 石垣島` at town size.
  ⚠️ Two side effects: `miyakojima` now shows **two near-identical big names side
  by side** (city `Miyakojima ⏎ 宮古島市`, island `Miyako-jima ⏎ 宮古島`), and
  Iceland's river island **Árnes** is promoted from small caps to town size.
- ✅ **Peaks read on `iceland`** — eight named, with dots. None on the islands (no
  peak there reaches 600 m) or on the wide frame (below minzoom 7). ⚠️ **Hekla,
  1,491 m, is on Apple's frame and not the fork's** — `rank > 2` or collision with
  Öxl beside it, UNKNOWN; cheapest settling is reading its `rank` from the tile.
- ✅ **The skeleton reads on both islands** — neither is roadless, so `tertiary`
  was never in question. ⚠️ At `iceland` z8.75 the skeleton is **nearly invisible**
  (its own ramp puts it at ~0.26 opacity, ~0.6 px), so the trail loses its road
  context at wide zooms.
- ✅ **Glaciers read, and no pale cross** over Vatnajökull on the wide frame.
- **The wide frame** shows `natural_earth` as relief texture on the land — it reads
  as terrain rather than as a defect at z6.08 — no visible admin boundary lines,
  and **low-zoom landcover drawn as rectangular blocks** in the interior.
- The distance readout reads on every fork frame.

## Labels under the trail, and the orange set

- **Still under it:** `Hella` and `Hvolsvöllur` on `iceland`; `Miyako-jima` is
  clipped on `miyakojima`. MapLibre's collision cannot see a trail drawn later.
- **The orange glow makes it worse** — at ×3.0 width it covers `Hella`'s H and
  `Miyakojima`'s M and 宮. Evidence for the still-locked question of where names
  belong; not acted on.
- ⚠️ **The glow compounds where the trail overlaps itself** — α 0.55 double-blends
  into darker blobs at leg joins on `iceland`.
- ⚠️ **No glow on dashed legs — by design, not a bug.** `drawRouteLeg` returns
  before the glow pass for an inferred leg, because a glowing line would claim a
  road nobody proved. Every visible leg on `ishigaki-crossing` is dashed, so its
  orange frame has no glow at all.
- ⚠️ **The orange `iceland-wide` frame is identical to the cyan one** — 0 differing
  pixels outside the caption. No trail is revealed at t = 2.50, so one of the four
  orange frames cannot show orange.

## 🔴 A harness bug this evaluation shipped, found and fixed this round

**Every `apple-dark` baseline delivered so far was a light Apple map under the dark
palette, captioned dark** — round 1's three (PR #51) and round 3's first orange
four. `RecapReviewScene.make(fixture:appearance:)` gave its override to the
palette only; `ReviewSubstrate.appleMaps` kept reading `KAMOME_MAP_APPEARANCE`,
whose default is light. Nothing failed, and the console printed
`Apple Maps (light …)` for the dark scene the whole time. Found by looking at a
still. **Fixed** — the override now reaches the Apple provider, and
`testAnAppearanceAskedOfTheSubstrateReachesTheAppleMap` holds it. The wrong files
are kept, renamed `*-apple-dark-MISLABELLED-light-map.png`, and the dark baselines
are re-rendered. ⚠️ One of those eight re-renders came back stale and was
rejected by that gate before it could be delivered; its retry passed.

