# HANDOFF — live findings only

**Updated 2026-09-10.** `main` carries PRs #16–#47. Everything closed has been
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

**Export left Apple Maps for OpenFreeMap + MapLibre** (ADR 2026-09-09); this
round only *looks*. ✅ **The pictures exist** — 15 annotated frames in
`~/Kamome-films/openfreemap-eval/`, never in the repo (§0). Three unknowns are
settled, **two ADR statements need correcting** (one is Apple's logo), three
visual findings are for judgement. ⏳ **Awaiting Chiu.**
→ `Docs/handoff-openfreemap-eval.md`.

---

## ⏳ Awaiting Chiu — a film or a judgement, not a session

- **The long-haul 70 threshold is untouched and still probably wrong.** Its
  *"the wide frame loses the viewer"* half is answered (ADR 2026-09-04 (b)).
  → `Docs/handoff-type2-films.md` closeout.
- **Five questions from the retimed type-2 opening** — four visual, one semantic
  (its DATE row is the **trip's** range, not the flight's).
  → `Docs/design-reviews/2026-09-04-open-questions-type2-opening.md`.
- **The title card still shows trip title + dates, not the country name** —
  re-VERIFIED 2026-09-04, and a DESIGNER question.
  → `Docs/handoff-crop-scaling.md` §11, §14.
- **The badge's 0.60 size** — judged from a still; you reserved a film.
  → `Docs/handoff-marker-badge.md` finding 6.
- **79.8% against the 80% safe-zone limit** on `ishigaki-crossing`, on the camera
  that actually ships. A pass by 0.2 points, with nothing relaxed to get it.
  Whether that is acceptable is a bar question.
  → `Docs/handoff-cross-region-crossing.md` finding 2.
- **The crossing beat's three defaults**: the seagull ships `selectable: true`;
  whether the apex wants a hold. → same document, finding 9.
- **Film length, two questions in order** — the duration rule (direction decided
  2026-08-14, **rule not**), then travel pacing (`travel_max_s` names a thing
  that does not exist). → `Docs/handoff-pacing.md`.
- **§0 — two films of real trips are committed to this repository**
  (`Docs/demos/phase3/`, `Docs/demos/phase3_5/`). They are gate artifacts, and
  they are not in §0's decided-exceptions list. Either a recorded exception or
  they move out. **Deliberately not gated** — a gate would pre-empt your call.
  → `Docs/handoff-audit-2026-08-30.md` finding 7.
- **S2's placement and `AboutView`'s wording** are still a draft, not a ruling;
  the first-run card's wording is ruled. **Whether a user may refuse** stays
  deferred. → `Docs/release-readiness.md` S2/S3.
- **S3b — `pre-launch.md`'s recorded-leg payload row describes a state that never
  arrived.** Relabel or delete; it is not an equal claim in conflict with the
  code. → `Docs/release-readiness.md` S3b.
- **A staging rule for `Arch.md`** — confirm the branch before committing, stage
  explicit paths, never `-A`. A branch ref picked up another session's commits
  three times. Recommended, **not in force** until you say so.
- **The MapLibre-era sweep.** Five defects share one shape: a value tuned while
  MapLibre was the substrate that silently degraded when Apple Maps became what
  ships. Each was found one film at a time, by accident. The question that
  catches the class is *"what was this value tuned against?"* Not scheduled.
  → `Docs/handoff-audit-2026-08-30.md` finding 4.

---

## 🟠 Open — nobody is on these

- **Dismissing the first-run notice backgrounds the app.** The §0 path every user
  walks once (PR #45). Simulator-reproducible; **UNKNOWN on device** — joins D1–D5.

- 🟠 **No desk render can validate `matching.base_url`** — `RecapDemoFilmTests`
  never reads the shipped config, and making it would spend real quota.
  → `Docs/decisions.md` 2026-09-08.

- **The subject lookup still misses; it no longer crashes.** `VehicleCatalog.resolve`
  returns nil and the film silently draws the seagull instead of the car. Rate and
  trigger **UNKNOWN**; two log lines ship to name the next occurrence.
  → `Docs/handoff-subject-lookup.md`.
- **Content-derived pacing may be implemented and permanently dead.** A shipping-path
  comment in `RecapModel.swift` is wrong on its first clause; if its second clause
  holds, the feature sits behind a tile condition that can never be satisfied.
  **UNKNOWN, worth an hour.** → `Docs/handoff-audit-2026-08-30.md` finding 3.
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

- **A worktree renders a different film.** `Config/Secrets.xcconfig` and
  `Tests/Fixtures/trips/local/` are gitignored, so it routes on straight lines and
  reads different geometry. Copy both, then compare `drive/reconstructed` counts.
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

---

## Where the detail lives

| document | what is in it |
|---|---|
| `Docs/release-readiness.md` | **the release gate** — every obligation, sorted by who can settle it |
| `Docs/handoff-type2-films.md` | the type-2 film: what MapKit can frame, the classifier, the closeout |
| `Docs/handoff-type2-opening-retime.md` | the retimed opening, the pass, the plane, the two marks |
| `Docs/handoff-cross-region-crossing.md` | the crossing beat, the pan-floor correction, the safe-zone margin |
| `Docs/handoff-crop-scaling.md` | crop-scaling, the budget split, the opening and the country card |
| `Docs/handoff-audit-2026-08-30.md` | the owed MapLibre sweep, dead pacing, the §0 films question |
| `Docs/handoff-openfreemap-eval.md` | the substrate evaluation: the frames, the number, the corrections |
| `Docs/handoff-marker-badge.md` | the fallback badge and the gaps it left |
| `Docs/handoff-pacing.md` | film duration and travel pacing |
| `Docs/handoff-subject-lookup.md` | the silent subject fallback |
| `Docs/handoff-stop-weighting.md` | the removal criterion |
| `Docs/handoff-known-bugs.md` | the three above, in full |
| `Docs/camera-arcs.md` | the arc design — live, and §5 carries a correction |
| `Docs/cross-region-journeys.md` | cross-region requirements (Chiu 2026-08-14) |
| `Docs/phase4-reference.md` | Phase 4 scope and the camera architecture |
| `Docs/environment-gotchas.md` | routing, simulators, fixture shadowing |
| `Docs/rule-rationale.md` | why each rule in `CLAUDE.md` exists |
| `Docs/_archive/README.md` | **what was archived and where it went** — history, never a work instruction |
