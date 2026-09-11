# OpenFreeMap + MapLibre — the export substrate evaluation

**Round of 2026-09-09/10, engineering.** The decision is ADR 2026-09-09; this is
what running it returned. **Nothing here is decided** — the shipping substrate, a
Kamome style, place names, the notice's second item and the pmtiles path's
retirement are Chiu's, and the ADR says so.

## The pictures

**15 frames, in `~/Kamome-films/openfreemap-eval/`** — outside the repo (§0).
Three fixtures × five substrates, **one camera frame per fixture**, so only the
base map varies:

| fixture | t | z | span | what it tests |
|---|---|---|---|---|
| `miyakojima` | 45.90 s | 12.34 | 14.8 km | CJK names, small island, town detail |
| `iceland` | 53.93 s | 8.75 | 86.5 km | coastline, terrain, large span |
| `ishigaki-crossing` | 43.37 s | 12.50 | 13.3 km | cross-region framing, dashed sea leg |

Each is `apple-light`, `openfreemap-positron`, `openfreemap-liberty` (light
palette) and `apple-dark`, `openfreemap-fiord` (dark) — **Apple in both
appearances**, so Fiord has a baseline of its own. Every PNG carries a caption
strip **below** the film, never over it: style, fixture, t, zoom, span km,
appearance, both timings. Attribution is on the OpenFreeMap frames only.

## What the round settles

| the ADR's open row | now |
|---|---|
| `mountain_peak` in the tiles | **VERIFIED present** — in the planet TileJSON (z7–14) **and** in real tiles `12/1858/1092` (Iceland) and `12/3473/1756` (Miyakojima). No stock style draws it; Apple does, with elevations. |
| does `MLNMapSnapshotter` burn attribution in | **It does.** `MLNMapSnapshotOptions.showsAttribution` defaults to `YES`; the output carries the obliged string bottom-right and a MapLibre logo bottom-left, without us drawing either. |
| Latin-only glyphs → CJK needs `MLNIdeographicFontFamilyName` | **Confirmed, and it works.** 宮古島市 / 宮古空港 / 石垣島 all render. |

### ⚠️ Two corrections the ADR is owed

1. **`MKMapSnapshotter` DOES draw the Apple Maps logo.** Every `apple-*` frame
   carries "&#63743; Maps" bottom-left and Kamome composites no such thing
   (`MapKitSnapshotProvider` has no logo code), so the ADR's *"…with no Apple logo
   and no legal link"* is not what the snapshotter produces today — the legal link
   is absent, the logo is not. **This changes nothing about the decision**: §2.5
   and §2.3 are not cured by attribution, and Chiu's reasoning turned on those.
   Recorded because the ADR offered that still as a measurement.
2. **All six of Kamome's source-layers are served.** "5 of 6 in positron's style"
   is about *positron*, not the tiles.

## The number, and what kind of number it is

**Seconds per snapshot, 1080×1920, iPhone 17 Pro simulator, network tiles.**

| substrate | genuinely cold | warm |
|---|---|---|
| `openfreemap-positron`, first render of the day | **10.14 s** | 0.05–0.06 s |
| `openfreemap-liberty` / `-fiord`, tiles already cached | 0.5–1.9 s | 0.04–0.07 s |
| `apple-light` / `-dark` | 1.2–2.7 s | 0.22–0.26 s |

⚠️ **Read these four ways or not at all.**

- **10.14 s** is a **single sample** — the first snapshot of the first run, paying
  for style, glyphs, sprite and every tile at once.
- Every later "cold" figure is only *tile*-cold: all three styles read one source
  (`tiles.openfreemap.org/planet`) and MapLibre's ambient cache lives in the app
  container, which survives runs. The simulator was deliberately **not** erased —
  another session shares that bundle id.
- **Warm, MapLibre is ~4× faster than Apple Maps** (0.05 s vs 0.24 s), and an
  export is hundreds of snapshots. **UNVERIFIED on hardware** — D1–D5's job.
- The prior MapLibre figure (0.84 s) was local `.pmtiles`, not comparable.

## Three visual findings, all for judgement, none fixed here

1. **The distance readout vanishes on Liberty.** `iceland` reads "245 km" on Apple
   and Fiord; on `openfreemap-liberty` only "km" survives — a light grey lost in
   Liberty's `#f8f4f0` ground. The MapLibre-era sweep's shape exactly: a value
   tuned against one base, silently wrong on another.
2. **Positron reads as monochrome and its coastline nearly disappears.** On
   `ishigaki-crossing` the sea and the island are almost the same value under
   Kamome's vignette; Apple's blue-sea/green-land frame is unambiguous at a
   glance. For a film about islands that is the substantive comparison.
3. **Positron's place labels print two lines** — `Miyakojima ⏎ 宮古島市`, from the
   stock style's `["case", ["has", "name:nonlatin"], …]` text-field. Possibly too
   noisy for `DESIGNER.md`'s restraint. Reported, not changed.

⚠️ **The ideographic font family is a product choice.**
`MLNIdeographicFontFamilyName` is `PingFang TC`, following
`CFBundleDevelopmentRegion: zh-Hant` — which renders **Japanese** place names in
Chinese glyph forms. Visible on `miyakojima`. Not guessed at further.

## What was built — the edges only

The mechanics are in the code's own comments (`ReviewSubstrate.Substrate`,
`MapLibreSnapshotProvider`, `RecapSubstrateEvalTests`). What is **not** there:

- ⚠️ **The styles are OpenFreeMap's hosted ones, loaded by URL** — which
  **deviates from the plan's "add a second style resource"**, deliberately: their
  URL touches no shipping file at all, and no style JSON is authored or
  committed. The cost is that the style is whatever they serve that day; the tile
  set rendered here is `20260906_080001_pt`.
- ⚠️ **One line reaches the shipped bundle** — `MLNIdeographicFontFamilyName` in
  `App/Info.plist`. MapLibre reads it from the main bundle at startup and has no
  runtime API, so there is nowhere else. Inert in a shipping build, which never
  constructs the MapLibre renderer. Named rather than hidden.

## Unexplained

**One `iceland` run reported `Testing failed:` and produced no frames**, then
passed on retry with the same command and binary. **UNKNOWN**; not reproduced in
four later runs. Recorded so a second occurrence is a pattern.
