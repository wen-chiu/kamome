# HANDOFF — live findings only

**Updated 2026-09-24.** `main` carries PRs #16–#88. Everything closed has been
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
can do either**. Both gate the **App Store submission**, not TestFlight — a
TestFlight build is the vehicle for D1–D5 (→ `Docs/handoff-testflight.md`).

1. **D1–D5 — one device session, never run.** Export survives a screen lock;
   per-trip export time and memory; seconds per snapshot on current hardware;
   Limited Photo Library; the S5 UX pass. D2 feeds a mandatory submission item.
   ⚠️ **Deferred behind the substrate evaluation, not dropped** (ADR 2026-09-10);
   **step 2 did NOT settle D1** — it survives a *screen*, not a *locked device*.
   → `Docs/release-readiness.md` Tier 3, `Docs/device-test-P3.md`.
2. **The submission sequence, and it is Chiu's in both halves.** ① Run
   `./check.sh --release <.xcarchive>` — the **only** proof the built bundle
   carries no key; `check-archive.sh` needs the real key — in `KAMOME_ROUTING_API_KEY`, never a
   file (ADR 2026-09-12) — and refuses to degrade
   into a shape scan, so a session can build the archive but never run the gate.
   ② **Then rotate the Geoapify key** — S7. Every IPA already on someone's phone
   still holds the current one, and the flip cannot reach those.
   **Order matters**: rotating first would leave the check validating a bundle
   nobody ships. → `Docs/release-readiness.md` S6, S7, Tier 1.

---

## 🔵 The film carries its map credit

**ADR 2026-09-12 (b)**, amending Chiu's 2026-08-17 "never in the rendered film".
The substrate declares its attribution and the render loop draws it on every
frame. With the production switch (ADR 2026-09-16), **every shipping film now
draws a credit**. The terrain clause is region-conditional per ADR 2026-09-18 (f):
only sources whose licence requires attribution AND whose coverage intersects the
film's extent appear. Public-domain sources (USGS, NOAA, ArcticDEM) are never
credited. The desk render harness (`ReviewSubstrate`) now threads the trip extent
so rendered films show the same credit the export would.
⚠️ **The reason it is Kamome's own credit and not the snapshotter's is
measured**: crop-scaling puts `MLNMapSnapshotter`'s burned-in copy off the frame
above magnification **1.026** (shipped padding 1.03), the title band covers the
one beat that keeps it, and it renders at **2.07:1** on the dark fork.
`showsAttribution` is now **off** — if `RecapMapCreditTests` is ever removed,
that line goes back first.

⚠️ **One ACCEPTABLE KNOWN RISK, and it is Chiu's, taken 2026-09-13 with the
finding in front of him**: the shipped string does not state ODbL, and a film
cannot carry the link the OSMF guideline prefers (`AboutView` does, but whoever
receives the MP4 never opens it). **The remedy is already costed — six
characters, `, ODbL`, in one constant — and is NOT to be implemented.** The
string stands. Do not reopen this from scratch.
→ `Docs/decisions.md` 2026-09-12 (b) and 2026-09-13.

---

## ⏳ Awaiting Chiu

- **Camera areas — judge the renders** (ADR 2026-09-24). → `Docs/camera-arcs.md` §5.
- **Badge 0.60 size** — judged from a still; you reserved a film.
  → `Docs/handoff-marker-badge.md` finding 6.
- **Film length rule** — direction decided 2026-08-14, **rule not**.
  → `Docs/handoff-pacing.md`.
- **S2/S3 wording** — first-run card wording is ruled; `AboutView` is draft.
  → `Docs/release-readiness.md` S2/S3.
- **The end card's wordmark** — Chiu's layout reads `KAMOME かもめ`; the film
  ships `"Kamome"`. What the product is called, and in which scripts, is yours.
  → `Docs/decisions.md` 2026-09-05 (d) §4.
- **`privacy_intro` wording awaiting Chiu** — interim draft installed; he writes
  the final text (「給我建議的寫法我再修正」).
  → `Docs/decisions.md` 2026-09-17 §6.
- **TestFlight films in Application Support/Films/** — rendered on Apple Maps,
  still present (§2.5). Chiu's call.

---

## 🟠 Open — nobody is on these

- 🟠 **Crash-safe recording and trip merge (ADR 2026-09-24 (b)); device checks owed.**
  → `Docs/handoff-long-recording.md`.
- 🟠 **Arch review 2026-09-24: to verify.** → `Docs/handoff-arch-review-2026-09-24.md`.
- 🟠 **TestFlight: the code is done (PRs #76, #77); two verifications are owed.**
  T4's captures — S3, recap screen, Discovery beta, repeat-import prompt, light + dark, one film per
  mode — and T5, the first-run notice that backgrounds the app, which did not
  reproduce on the simulator and needs a device. → `Docs/handoff-testflight.md`.
- ⚠️ **The film's EU-DEM credit is shortened, and ADR 2026-09-18 (f) says the
  Copernicus wording "may not shorten".** PR #77 ships `EU-DEM (Copernicus)`
  (Iceland, Europe) on a reading of Delegated Regulation 1159/2013 Art. 3 that
  is **INFERRED**. Two same-level sources disagree; a PO call, not an
  implementation detail. → `Core/ExportEngine/RecapMapAttribution.swift`.
- 🔴 **Two features built and never reached — one class, one sweep owed.**
  Imported trips carry no `TripStats` (`ImportService` writes no `stats_json`,
  → `Docs/handoff-audit-2026-08-30.md` finding 8). **The title card now measures
  the drawn journey itself (ADR 2026-09-19); Home and Trip Detail stay empty by
  Chiu's choice** — showing them needs a distance-only field (an interface
  change, rule 2), and Trip Detail's other three stats cannot honestly be claimed.
  And `VehicleCatalog.resolve`
  still misses now and then and silently draws the fallback badge instead of the
  car (1 render in 5 on 2026-09-16; device rate **UNKNOWN**,
  → `Docs/handoff-subject-lookup.md`).
  The question that catches the class: *"does the shipping path ever call this?"*
- **`stop_weighting_enabled`** — reachable in both modes; the containment argument
  is empirical and untested on a flat distribution. The removal criterion was
  decided in advance, and **a removal PR must not cite "provably contained"**.
  → `Docs/handoff-stop-weighting.md`.
- **C4 — nothing asserts the end card's mark is the bird.** Only weakly held:
  `RecapChromeTests` counts lit pixels on the end card, which the wordmark alone
  would satisfy. → `Docs/release-readiness.md` C4.
- 🟠 **Miyakojima film fixed in code, owed on the phone** (ADR 2026-09-23 (b)):
  re-export + three crash-free exports.
  → `Docs/handoff-type2-round-trip.md`.
- **Simulator s/snapshot with terrain** — cold/warm timing SIMULATOR only.
  VERIFIED 2026-09-18: terrain-only host failure also errors (path 3c).
  Device timing joins D1–D5. → `RecapExportJob+Render.swift`, `TileFailureTests`.
- **Failure paths 4 (5xx) and 5 (mid-export drop)** — INFERRED. → same file.
- ⚠️ `provenance_recorded` is defined twice in the string catalogue → ADR 2026-09-23 (e).

---

## ⚠️ Traps — read before you touch these

- **A worktree renders a different film**: `Tests/Fixtures/trips/local/` is
  gitignored, so it reads different geometry. ⚠️ **No checkout routes with a key**
  (ADR 2026-09-12): the desk harness defaults to the shipped Worker (ADR
  2026-09-19); each render spends the 2000/day quota.
  → `Docs/handoff-crop-scaling.md` §3.
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

## ⏱ Export time is measured now, and a crossing arc is half the bill

A film with a transit stop took **1,859 s**. The export logs its plan up front
and its cost by stage at the end. Measured offline: `auckland-crossing` spends
**54 of 102 stations on ~4 s of arc**; magnification 1.10 → 1.25 halves the
budget and costs sharpness — Chiu's call, judged against renders.
→ `Docs/handoff-export-performance.md`.

## 🐛 Known bugs and accepted costs

The import date range clips at timezone edges; `RecapMode` may be two axes, not
one; the glacier renders flat. All three, in full, with workarounds:
→ `Docs/handoff-known-bugs.md`. And the **0.747 sharpness step at hold
boundaries**, accepted as it stands — revisit only if someone notices it in a
film (`Docs/handoff-crop-scaling.md`).

## iCloud photo download — code done, never run against iCloud

iCloud-only photos are fetched before the render. **Unmeasured:**
derivative-vs-original transfer size, peak memory of a full-mode film, cellular
cost of previews. One device, Optimize Storage on, Instruments.
→ ADR 2026-09-19 (b).
