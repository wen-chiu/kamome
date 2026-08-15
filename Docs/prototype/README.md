# Recap visual prototype — findings & spec reference

**Date:** 2026-07-20 · **Owner sign-off:** Chiu ("prototype 蠻成功的，收斂回 app")
**Status:** exploration complete → feeds spec §4.5 / §7 (Phase 3.5) and §4.7 (import).

This folder is a **throwaway web prototype** (HTML/JS) built to de-risk the
recap *visual system* on real data before committing the Swift implementation.
The language is different from the app on purpose — it let us iterate the
*feel* in hours instead of days. Everything here is a spec reference for the
app; nothing here ships. Read this doc, then skim `recap_engine.html`
(the animation logic) and `recap_data_pipeline.py` (the data flow).

Built and reviewed live with Chiu over one session. Real input: **170 geotagged
iPhone photos from Chiu's actual 13-day Iceland ring-road trip (Oct 2023)** —
not synthetic fixtures. The whole thing was generated from those photos alone,
which is itself the key import finding (below).

---

## 0. Positioning (this is the north star — put it above every feature call)

> **"Kamome turns your road trips into stories you can relive and share."**

Founder motivation, in Chiu's words (keep this verbatim — it is the product's
soul and the tie-breaker for scope decisions):

> 對我來說，最開始的開發動機就是為了自己。我喜歡出去玩，但懶得整理。我可以不用
> 寫旅行日誌，旅程結束後 Kamome 自動幫你做成一部旅行電影。

Translation for the record: *built first for myself — I love travelling but
can't be bothered to organize. No travel journal. The trip ends and Kamome has
already made the movie.* This reframes the whole product as a **storytelling /
memory** product, not a GPS or planning tool. Consistent with spec §1.8 (zero
mid-trip effort) and the v1.5 pivot (`kamome-animation-vision.md`). The recap
film is **differentiator #1's payoff** — over-invest there.

---

## 1. What we tried (three iterations, all still viewable as artifacts)

| Ver | Idea | Verdict |
|-----|------|---------|
| v1  | Fully **abstract** illustrated island + glowing route + photo cards; "don't render a real map at all" | ❌ Over-rotated. An abstract blob is unrecognizable — a person who's been there can't tell where it is. |
| v2  | **Real photos** woven in as "beads on a thread"; side-view car marker; camera zooms to each stop | ✅ Photo-as-bead confirmed. ❌ Side-view car + still-generic map. |
| v3  | **Souvenir map** (real Iceland coastline + glaciers, subtractive style) + real GPS route + top-down car + photo deck | ✅ Direction locked. One requirement still unmet (follow-cam — see §2.3). |

Artifacts (private, Chiu's account): v1 abstract, v2 real-photos, v3 souvenir-map.
The v3 engine source is `recap_engine.html` (data stripped out, `__KDATA__`
placeholder — no personal photos are committed).

---

## 2. Validated design decisions (with Chiu's responses)

These are the concrete answers the app should implement. Each maps to an
existing spec component so nothing here requires new architecture — it
*constrains* the existing one.

### 2.1 Base map = real geometry + hand-written subtractive style ✅ LOCKED

**Finding:** the base map must use **real geographic geometry** (users must
recognize the place — "去過的人一看就懂") but a **subtractive, hand-authored
style** (only coastline + glaciers + the route; **no POI, no road labels**;
deliberately chosen land/water/glacier colors). Chiu's formula:

> **真幾何 ＋ 手寫減法樣式 = 紀念品地圖** (real geometry + subtractive styling = a souvenir map)

This is exactly the **MapLibre substrate ADR** (`decisions.md` 2026-07-19,
`vector-tile-pipeline.md`) — and the prototype validates *why* it's non-negotiable:
the abstract v1 was rejected as unrecognizable; the real coastline was instantly
"that's Iceland." Route precision comes later from **OSRM road-snapping (§4.4)**
and does not block the look.

- **Prototype:** Natural Earth 10m coastline + glaciated areas, Douglas–Peucker
  simplified, equirectangular projection with `cos(lat)` x-scaling.
- **App:** MapLibre renders the same real classes (coastline, water, glacier,
  terrain) from self-hosted PMTiles; **the Kamome style JSON does the
  subtraction and coloring.** `MapLibreSnapshotProvider` behind
  `RecapSnapshotProviding` (handoff §2). Colours are a `RecapTheme` concern
  (Modern Minimal first). Land colour is still open — see §4.
- **Reaffirms:** the substrate ADR. The prototype is the "before" evidence for
  the Phase 3.5 quality-bar side-by-side.

### 2.2 Photos = fan + rotating deck at the stop location ✅ (timing revised)

**Finding:** photos should appear **at the place**, not in a fixed lower slot.
When the vehicle reaches a stop, the camera eases in and that stop's photos
bloom **on that point**: a 3-card fan (peek-left / hero / peek-right) with the
**hero cross-fading through ALL of the stop's photos** — 3 to 8 of them
depending on how many exist at that location. A dots indicator shows progress;
dwell length scales with the photo count.

**Chiu's revision:** 1.0 s per photo was **too slow → use 0.8 s.** Fan format
is good; a location may show 3–8 photos ("端看景點照片多不多"). *Not* a full-screen
takeover — the "bead floating on the map" reading is right.

- **App:** this is the **OverlayTimeline / stop-card** work in §4.5 — but richer
  than "one photo card per stop." Each stop becomes a **timed photo deck** event
  (photo count → per-photo hold 0.8 s → dwell duration). Photos come from
  `photo_ref` rows already matched to the stop (§4.3). `is_highlight` photos lead
  the deck.

### 2.3 Vehicle = top-down car (default), follow-cam ⚠️ REQUIREMENT, NOT YET MET

**Chiu's ask:** the marker should be a **top-down car** (default), seagull
swappable, "更像 TravelBoast 那種俯視小車但更好看." And the camera must be a
**TravelBoast-style follow camera**.

**Status — the one thing the prototype did NOT nail.** Chiu's verdict on v3:

> 還是沒有做出像 TravelBoast 跟隨鏡頭的動畫，影片畫面只有路線移動而已沒有帶入車子。
> *(Still not the TravelBoast follow-cam — the shot is just the route moving, the car isn't brought in.)*

Even with a zoom-and-follow transform, the car read as a small dot at the tip of
a growing line rather than the subject of the shot. **The requirement for the app:**

- The **vehicle is the focal point**, large and roughly centered — not a marker
  on a wide map.
- **Close, consistent zoom** locked on the vehicle; the map + route **translate
  (and preferably rotate heading-up) underneath**, so you feel it *driving
  forward through terrain*.
- This needs the **near-terrain detail that vector tiles give at zoom** — the
  prototype's sparse coastline made the close shot feel empty, which is part of
  why "only the route moves." Real tiles fix this.
- Wide establishing shots are reserved for the **title / end / day-transitions**.
- **App owner:** this is `CameraPath` (§4.5 step 1). Today it interpolates along
  the full polyline at a fixed frame; it must instead produce a **vehicle-locked
  follow trajectory** (position + heading + zoom per frame), with wide shots as
  explicit keyframes. Treat "the vehicle is the subject" as the acceptance test.

Top-down car + swappable marker (car / seagull / scooter / bike) is a small
`RecapTheme` / overlay asset concern — the seagull stays the brand mascot but is
no longer forced as the moving marker.

---

## 3. Forward directions Chiu wants captured (import · video · music)

### 3.1 Import — the prototype already IS the EXIF importer (§4.7)

The entire prototype was generated from Chiu's real photos with zero manual
tagging — see `recap_data_pipeline.py`. That pipeline (EXIF GPS+time → cluster
into stops → time-ordered route → name → road-snap → recap) is **exactly the
photo-EXIF importer** in §4.7, proven end-to-end on a real 13-day trip.

**Recommendation (unchanged from the session):** build **photo-EXIF import
first**, before Google Timeline. Reasons: (a) it's the only way Chiu can dogfood
the recap quality on *past* trips (Iceland/NZ/Finland) before the next drive —
"the emotional bar can only be set on your own real memories"; (b) date-range
selection is trivial (pick an album/range), which sidesteps Google Timeline's
export-everything friction; (c) photos are the emotional payload anyway. Timeline
import → backlog. This is the cold-start hook **and** the dogfooding tool.

Key proof: **sparse geotagged photos are enough** to reconstruct a recognizable
trip once snapped to roads and drawn on real-geometry map. Load-bearing on §4.4.

### 3.2 Video clips as beads — v2 feature, tame the length

Chiu wants road/scenery **video clips** in the recap but flagged the
variable-length problem. Answer: **auto-trim each clip to 2–3 s, muted, hard cap
the duration**, and play it inline as a motion "bead" alongside the photo deck —
never let the user hand-edit length. Deterministic excerpts only (fixed
in-point) so golden-frame CI stays stable (spec §4.5 / icebox note). Sequence:
**ship the photo version first, add video beads after** — clips are a
multiplier, not the foundation.

### 3.3 Music — royalty-free + beat-sync (Chiu: "如果技術上做得到，我也很想玩玩看")

Technically very doable, and it's ~half the emotional payload of a recap:

1. **Bundle a small royalty-free / licensed library** (start free: Uppbeat,
   Pixabay Music; commercial tier later: Artlist / Epidemic Sound), a few tracks
   across moods (epic / calm / playful / nostalgic).
2. **Pre-analyze each track's beat map offline** (BPM + beat timestamps), store
   as track metadata. Deterministic → safe for golden-frame CI, no live audio
   analysis.
3. **Quantize recap events to the beat grid**: `CameraPath` / `OverlayTimeline`
   snap stop arrivals, photo reveals, and transitions to the nearest beat. That
   "cuts land on the beat" is what makes a travel edit hit — background music the
   user adds *after* export on IG loses this, because the timing won't match.
4. **Two export paths:** free = **silent export** (clean, user adds platform
   music on IG/TikTok — legal, matches platform norms); premium = **in-app
   licensed track with beat-sync**. Good paid-tier candidate (§1.6 transactional).
5. **Muxing:** `AVAssetWriter` already writes the video; add an audio track.

---

## 4. Open questions for the app phase

- **Land / palette warmth** (§2.1): prototype is cool slate-blue minimal. Chiu
  OK'd the *direction*; warm/hand-drawn-paper vs. cool-minimal is a **Modern
  Minimal `RecapTheme` decision** (`handoff-P3.5` §3, Chiu in the loop).
- **Follow-cam acceptance** (§2.3): needs a device/tile pass to judge — the
  prototype can't fully demonstrate it without real terrain at zoom.
- **Heading-up rotation** of the map during follow: nice-to-have that strongly
  sells "driving"; decide during CameraPath work.

---

## 5. Files here

- `README.md` — this doc.
- `recap_engine.html` — the v3 prototype animation engine (souvenir map, route
  draw, follow-cam attempt, top-down car ↔ seagull toggle, photo deck). Data
  stripped (`__KDATA__` placeholder); no personal photos committed.
- `recap_data_pipeline.py` — EXIF → stops → route → base geometry → recap data.
  The executable spec of §4.7 import + §4.2 stops + §4.4 route + §7 base map.

To regenerate locally: `python3 recap_data_pipeline.py <photo_dir> out/`, then
inline `out/kamome_data.json` into `recap_engine.html` at `__KDATA__` and open
it (serve over http with `charset=utf-8`).
