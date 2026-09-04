# HANDOFF — live findings only

**Updated 2026-09-03.** `main` carries PRs #16–#32. Everything closed has been
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

Everything else on this page can wait behind these two. **`Docs/release-readiness.md`
is the gate**; these are the only rows on it that nobody has started.

1. **S5 — the Worker has no per-day budget counter, and `matching.base_url` must
   not be flipped until it does.** Consequence, stated plainly: **every build
   today still carries the routing key**, and Geoapify's limits are soft on every
   tier with no customer-settable cap, so the worst case ends in account
   blocking. Open since 2026-08-29. → `Docs/release-readiness.md` S5, S6.
2. **D1–D5 — one device session, never run.** Export survives a screen lock;
   per-trip export time and memory; seconds per snapshot on current hardware;
   Limited Photo Library; the S5 UX pass. **No Claude session can do this one.**
   D2 feeds a mandatory submission item. → `Docs/release-readiness.md` Tier 3,
   `Docs/device-test-P3.md`.

Also unguarded and nobody's: **S4** — the Worker's no-log property is asserted
nowhere, and `/v1/routing` is GET-only, so real coordinates ride in the URL.

---

## ⏳ Awaiting Chiu — a film or a judgement, not a session

- **The long-haul flight frame's 70 threshold.** The wide frame loses the viewer;
  the threshold is probably wrong. → `Docs/handoff-type2-films.md` closeout.
- **The title card still shows trip title + dates, not the country name.** The
  name is available offline; wiring it is not done. A DESIGNER question.
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
- **S2's placement and S3's wording** ship as a working draft, not a ruling. And
  still open on purpose: **whether the import flow warns at the point of import**
  — an About screen a user may never open is not a warning.
  → `Docs/release-readiness.md`.
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

- **The subject lookup still misses; it no longer crashes.** `VehicleCatalog.resolve`
  returns nil and the film silently draws the seagull instead of the car. Rate and
  trigger **UNKNOWN**; two log lines ship to name the next occurrence.
  → `Docs/handoff-subject-lookup.md`.
- **Content-derived pacing may be implemented and permanently dead.** A shipping-path
  comment in `RecapModel.swift` is wrong on its first clause; if its second clause
  holds, the feature sits behind a tile condition that can never be satisfied.
  **UNKNOWN, worth an hour.** → `Docs/handoff-audit-2026-08-30.md` finding 3.
- **`stop_weighting_enabled`** — reachable in both modes; the containment argument
  is empirical and untested on a flat photograph distribution. The removal
  criterion was decided in advance, so it is not re-litigated, and **a removal PR
  must not cite "provably contained"**. → `Docs/handoff-stop-weighting.md`.
- **The 0.747 sharpness step at hold boundaries** is *accepted as it stands*, not
  fixed. The remedy costs no extra fetches and is not built. Revisit only if
  someone notices it in a film. → `Docs/handoff-crop-scaling.md`.
- **C4 — nothing asserts the end card's brand mark**, and the badge work proved
  this failure mode is silent. → `Docs/release-readiness.md` C4.

---

## ⚠️ Traps — read before you touch these

- **A worktree renders a different film.** `Config/Secrets.xcconfig` and
  `Tests/Fixtures/trips/local/` are gitignored, so a worktree routes on straight
  lines and reads different geometry. Copy both, then count `drive/reconstructed`
  in each log before comparing two renders.
- **There is no render length limit.** The SIGKILLs were six `xcodebuild`
  processes on one simulator. `pgrep -fl xcodebuild` first; render one at a time.
- **A dead CI run looks like a passing one.** The tell is ~3 s wall clock and
  `steps=0`. Anything with steps is a real signal.
- **Continuity passing is not the film being right.** The gate measures ground
  overlap between consecutive frames, so a camera wrong in a way that does not
  *move* scores 100%: a body span from the wrong beat measured 177.3 km against
  13.3 km and scored perfectly. When a change re-derives a span, a frame or a
  padding, **read `span` on its own line, and render.**
- **Do not restyle `VehicleMarker.seagull` in place.** It is also the wordmark's
  bird on the end card. Three consumers: brand mark, fault badge, and the
  unbuilt cross-region narrator. → `Docs/handoff-marker-badge.md` 5b.
- **`Docs/camera-arcs.md` §8 states an invariant no arc can satisfy.** The gate's
  `permittedCutTimesS` is the mechanism that does hold (0 excused on all eight
  fixtures). → `Docs/handoff-cross-region-crossing.md`.
- **Read a style value off the preset the app selects, never off the defaults.**
  `RecapStyle`'s defaults are unrendered; the app selects `modernMinimal`. Got
  wrong twice, cost a ledger correction both times.
- **Two sessions sharing one checkout contaminate each other's test and lint
  counts.** Confirm your branch and your distance from `origin/main` first.
- **MapKit saturates at ~109° of longitude**, so a long-haul frame often does not
  exist — Taiwan→Iceland fails at every padding. The frozen country card is a
  **main path**, not a fallback. → `Docs/handoff-type2-films.md`.

---

## 🐛 Known bugs and accepted costs

The import date range clips at timezone edges; `RecapMode` may be two axes, not
one; the glacier renders flat. All three, in full, with workarounds:
→ `Docs/handoff-known-bugs.md`.

---

## Where the detail lives

| document | what is in it |
|---|---|
| `Docs/release-readiness.md` | **the release gate** — every obligation, sorted by who can settle it |
| `Docs/handoff-type2-films.md` | the type-2 film: what MapKit can frame, the classifier, the closeout |
| `Docs/handoff-cross-region-crossing.md` | the crossing beat, the pan-floor correction, the safe-zone margin |
| `Docs/handoff-crop-scaling.md` | crop-scaling, the budget split, the opening and the country card |
| `Docs/handoff-audit-2026-08-30.md` | the owed MapLibre sweep, dead pacing, the §0 films question |
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
