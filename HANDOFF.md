# HANDOFF — live findings only

**Updated 2026-09-12.** `main` carries PRs #16–#54. Everything closed has been
moved to `Docs/_archive/handoff-2026-08.md`; what is below is open.

**Rules for this file** (`Scripts/check-doc-budget.sh` enforces the size):

- Every entry is **one summary and one pointer**. The reasoning lives in the
  topic document it names, never here.
- **Closing an entry archives its document in the same PR.** That is what kept
  the corpus growing: findings closed, files stayed (ADR 2026-09-03).
- Over budget never means delete — move detail to a `Docs/` topic document, or
  move a closed section to `Docs/_archive/handoff-2026-08.md`.

Read `Docs/current-state.md` for the snapshot and `CLAUDE.md` for the rules.

---

## 🔴 The critical path to a release — neither item is a document

Everything else on this page can wait behind these two, and **no Claude session
can do either**.

1. **D1–D5 — one device session, never run.** Export survives a screen lock;
   per-trip export time and memory; seconds per snapshot on current hardware;
   Limited Photo Library; the S5 UX pass. D2 feeds a mandatory submission item.
   ⚠️ **Deferred behind the substrate evaluation, not dropped** (ADR 2026-09-10);
   **step 2 did NOT settle D1** — it survives a *screen*, not a *locked device*.
   → `Docs/release-readiness.md` Tier 3, `Docs/device-test-P3.md`.
2. **The submission sequence, and it is Chiu's in both halves.** ① Run
   `./check.sh --release <.xcarchive>` — the **only** proof the built bundle
   carries no key; `check-archive.sh` needs the real key and refuses to degrade
   into a shape scan, so a session can build the archive but never run the gate.
   ② **Then rotate the Geoapify key** — S7. Every IPA already on someone's phone
   still holds the current one, and the flip cannot reach those.
   **Order matters**: rotating first would leave the check validating a bundle
   nobody ships. → `Docs/release-readiness.md` S6, S7, Tier 1.

---

## 🔵 Live — the export substrate evaluation

**Export left Apple Maps for OpenFreeMap + MapLibre** (ADR 2026-09-09); these
rounds only *look*. ✅ **18 annotated frames**, never in the repo (§0): 15 stock
plus **Kamome's dark Liberty fork** (減層, souvenir palette, 大地名 ×2). On the
fork the coastline and the distance readout come back; the roads are still a web,
not a skeleton. ⏳ **Awaiting Chiu.** → `Docs/handoff-openfreemap-eval.md`.

---

## 🔵 The film carries its map credit — MapLibre path only

**ADR 2026-09-12**, amending Chiu's 2026-08-17 "never in the rendered film".
The substrate declares its attribution and the render loop draws it on every
frame; `MapKitSnapshotProvider` declares **none** and must keep declaring none,
so **no shipping film draws a credit today** — the substrate switch is Chiu's.
⚠️ **The reason it is Kamome's own credit and not the snapshotter's is
measured**: crop-scaling puts `MLNMapSnapshotter`'s burned-in copy off the frame
above magnification **1.026** (shipped padding 1.03), the title band covers the
one beat that keeps it, and it renders at **2.07:1** on the dark fork.
`showsAttribution` is now **off** — if `RecapMapCreditTests` is ever removed,
that line goes back first. → `Docs/decisions.md` 2026-09-12.

---

## ⏳ Awaiting Chiu

- **Badge 0.60 size** — judged from a still; you reserved a film.
  → `Docs/handoff-marker-badge.md` finding 6.
- **Film length rule** — direction decided 2026-08-14, **rule not**.
  → `Docs/handoff-pacing.md`.
- **§0 — two real-trip films in the repo** (`Docs/demos/phase3{,_5}/`).
  Either a recorded exception or they move out.
  → `Docs/handoff-audit-2026-08-30.md` finding 7.
- **S2/S3 wording** — first-run card wording is ruled; `AboutView` is draft.
  → `Docs/release-readiness.md` S2/S3.
- **The end card's wordmark** — Chiu's layout reads `KAMOME かもめ`; the film
  ships `"Kamome"`. What the product is called, and in which scripts, is yours.
  → `Docs/decisions.md` 2026-09-05 (d) §4.

---

## 🟠 Open — nobody is on these

- **Dismissing the first-run notice backgrounds the app.** The §0 path every user
  walks once (PR #45). Simulator-reproducible; **UNKNOWN on device** — joins D1–D5.

- 🟠 **No desk render can validate `matching.base_url`** — `RecapDemoFilmTests`
  never reads the shipped config, and making it would spend real quota.
  → `Docs/decisions.md` 2026-09-08.

- 🔴 **Three features built and never reached — one class, one sweep owed.**
  Imported trips carry no `TripStats`, so the title card's subtitle, Home and Trip
  Detail print **no kilometres** (found 2026-09-09,
  → `Docs/handoff-audit-2026-08-30.md` finding 8); content-derived pacing may sit
  behind a tile condition that can never hold (**UNKNOWN**, → finding 3); and
  `VehicleCatalog.resolve` still returns nil and silently draws the seagull
  instead of the car (rate **UNKNOWN**, → `Docs/handoff-subject-lookup.md`).
  The question that catches the class: *"does the shipping path ever call this?"*
- **`stop_weighting_enabled`** — reachable in both modes; the containment argument
  is empirical and untested on a flat distribution. The removal criterion was
  decided in advance, and **a removal PR must not cite "provably contained"**.
  → `Docs/handoff-stop-weighting.md`.
- **C4 — nothing asserts the end card's brand mark**, and the badge work proved
  this failure mode is silent. → `Docs/release-readiness.md` C4.
- 🔴 **Two left by the type-2 opening round**: `Geo.distanceM` is **121 km short**
  over Taipei → Auckland with no sweep of who reads it, and a **ferry gets a
  boarding pass and a plane**. → `Docs/handoff-type2-opening-retime.md`.

---

## ⚠️ Traps — read before you touch these

- **A worktree renders a different film**: `Tests/Fixtures/trips/local/` is
  gitignored, so it reads different geometry. ⚠️ Routing needs a key the flip
  **removed**. → `Docs/handoff-crop-scaling.md` §3.
- **There is no render length limit.** The SIGKILLs were six `xcodebuild`
  processes on one simulator. `pgrep -fl xcodebuild` first; render one at a time.
- **A dead CI run looks like a passing one** — the tell is ~3 s and `steps=0`.
- **The production KV counter lies to your first read.** A day's key returned
  **404 while holding 4**, and a read straight after a render shows the pre-render
  value. Read twice, tens of seconds apart, believe the second. Same cache is why
  `wrangler dev` at ceiling 1 measures **zero** overshoot — miniflare's KV has no
  read cache, so that test is **retired, not pending** (ADRs 2026-09-05, -09-08).
- **Continuity passing is not the film being right.** A camera wrong in a way that
  does not *move* scores 100%: a body span from the wrong beat measured 177.3 km
  against 13.3 km and scored perfectly. When a change re-derives a span, a frame
  or a padding, **read `span` on its own line, and render.**
- **Do not restyle `VehicleMarker.seagull` in place** — it is also the wordmark's
  bird. **Four** gull objects now; the table naming them is in
  `Core/ExportEngine/Resources/Landmarks/README.md`.
- **`Docs/camera-arcs.md` §8 states an invariant no arc can satisfy.**
  `permittedCutTimesS` is what does hold — 0 excused on all eight fixtures.
- **Read a style value off the preset the app selects, never off the defaults.**
  `RecapStyle`'s defaults are unrendered; the app selects `modernMinimal`. Got
  wrong twice, cost a ledger correction both times.
- **Two sessions contaminate each other's counts** (one checkout) **and each
  other's simulator** (one bundle id — a screenshot can show *their* build's
  wording). Confirm your branch. → `Docs/environment-gotchas.md`.
- **MapKit saturates at ~109° of longitude** — Taiwan→Iceland has no frame at any
  padding, so the frozen country card is a **main path**, not a fallback.

---

## 🐛 Known bugs and accepted costs

The import date range clips at timezone edges; `RecapMode` may be two axes, not
one; the glacier renders flat. All three, in full, with workarounds:
→ `Docs/handoff-known-bugs.md`. And the **0.747 sharpness step at hold
boundaries**, accepted as it stands — revisit only if someone notices it in a
film (`Docs/handoff-crop-scaling.md`).

