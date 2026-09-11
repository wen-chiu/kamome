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

⚠️ **The ideographic font family is a product choice.** `PingFang TC` follows
`CFBundleDevelopmentRegion: zh-Hant`, so **Japanese** place names render in
Chinese glyph forms. Visible on `miyakojima`. Not guessed at further.

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

## Unexplained — and it recurred

**A run reports `Testing failed:` and produces no frames, then passes on retry**
with the same command and the same binary. Round 1: `iceland`. Round 2:
`miyakojima`. **Both were the first `test-without-building` invocation of a
`for` loop after a build** — INFERRED, on two samples, and the cheapest settling
is to run the same fixture first and second in one loop. Cause **UNKNOWN**; it
has never survived a retry, so it costs a re-run, not a result.

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
