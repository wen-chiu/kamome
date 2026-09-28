# HANDOFF — live findings only

**Updated 2026-09-28** against `main` at PR #110. Closed findings are in
`Docs/_archive/handoff-2026-08.md`; what is below is open.

**Rules for this file** (`Scripts/check-doc-budget.sh` enforces the size):

- Every entry is **one summary and one pointer**. The reasoning lives in the
  topic document it names, never here.
- **Closing an entry archives its document in the same PR** (ADR 2026-09-03).
- **A check that needs a phone goes in `Docs/device-runbook.md`, not here.**
  That list is the critical path; this file is for what a desk session or
  Chiu can close.

---

## 🔴 The critical path to a release

1. **`Docs/device-runbook.md`**: D1–D5, T4/T5, the phone re-exports, and every
   device number still UNKNOWN. **No Claude session can run it.** One sitting
   with a TestFlight build closes most of what is open in this repository.
2. **Chiu's submission sequence**: `./check.sh --release <.xcarchive>` with the
   real key in `KAMOME_ROUTING_API_KEY` (never a file, ADR 2026-09-12), **then**
   rotate the Geoapify key (S7). Rotating first leaves the check validating a
   bundle nobody ships. → `Docs/release-readiness.md` S6, S7, Tier 1.

---

## ⏳ Awaiting Chiu

- **Map labels: CONFLICT.** `PO.md`'s lock says labels are off the roadmap, but
  both shipped Liberty styles carry 14 visible label layers (VERIFIED). Which
  one is right? → `PO.md` §3.
- **EU-DEM credit is shortened** to `EU-DEM (Copernicus)`, while ADR 2026-09-18 (f)
  says the wording "may not shorten". The reading is INFERRED; two same-level
  sources disagree. → `Core/ExportEngine/RecapMapAttribution.swift`.
- **Camera areas + floor (e): renders.** → `Docs/handoff-camera-context-floor.md`.
- **Badge 0.60 size**: judged from a still; you reserved a film.
  → `Docs/handoff-marker-badge.md` finding 6.
- **Film length**: is Standard's 300 s right? (ADR 2026-09-27; rule history
  `Docs/handoff-pacing.md`).
- **Wording**: S2/S3 (`AboutView` is draft), `privacy_intro` (ADR 2026-09-17 §6),
  `trip_delete_recorded_confirm`, `import_error_save`, `about_export_diagnostics*`.
- **End-card wordmark**: layout `KAMOME かもめ`, the film ships `"Kamome"`.
  → ADR 2026-09-05 (d) §4.
- **TestFlight films in Application Support/Films/**: rendered on Apple Maps,
  still present. Keep or clear?
- **Map credit, ACCEPTED RISK (2026-09-13), do not reopen:** the string omits
  `ODbL`; the six-character fix is costed and deliberately not built.
  `showsAttribution` is off because Kamome draws its own credit; if
  `RecapMapCreditTests` is ever removed, that line goes back first.
  → ADRs 2026-09-12 (b), 2026-09-13.

---

## 🟠 Open at the desk — nobody is on these

- 🔴 **Built and never reached, one sweep owed.** Imported trips carry no
  `TripStats` (`Docs/handoff-audit-2026-08-30.md` finding 8, status as of ADR
  2026-09-19), and `VehicleCatalog.resolve` sometimes silently draws the fallback
  badge (`Docs/handoff-subject-lookup.md`). The question that catches the
  class: *"does the shipping path ever call this?"*
- **S2 redraws the whole recorded path every second**: INFERRED heat and lag on
  a two-week recording; decimate the display path.
  → `Docs/handoff-long-recording.md`.
- **`stop_weighting_enabled`**: the removal criterion was decided in advance; a
  removal PR must not cite "provably contained". → `Docs/handoff-stop-weighting.md`.
- **C4**: nothing asserts the end card's mark is the bird. → `Docs/release-readiness.md` C4.
- **Failure paths 4 (5xx) and 5 (mid-export drop)**: INFERRED.
  → `RecapExportJob+Render.swift`, `TileFailureTests`.

---

## ⚠️ Traps — read before you touch these

- **A worktree renders a different film**: `Tests/Fixtures/trips/local/` is
  gitignored. No checkout routes with a key (ADR 2026-09-12); the desk harness
  uses the shipped Worker, and each render spends the 2000/day quota.
  → `Docs/environment-gotchas.md`.
- **There is no render length limit.** The SIGKILLs were six `xcodebuild`
  processes on one simulator. `pgrep -fl xcodebuild` first; render one at a time.
- **A dead CI run looks like a passing one**: the tell is ~3 s and `steps=0`.
- **The production KV counter lies to your first read.** Read twice, tens of
  seconds apart (ADRs 2026-09-05, -09-08).
- **Continuity passing is not the film being right.** A wrong span that does not
  *move* scores 100% (177.3 km against 13.3 km). Read `span`, and render.
- **Do not restyle `VehicleMarker.seagull` in place**: it is also the wordmark's
  bird. → `Core/ExportEngine/Resources/Landmarks/README.md`.
- **`Docs/camera-arcs.md` §8 states an invariant no arc can satisfy.**
  `permittedCutTimesS` is what holds.
- **Read a style value off `modernMinimal`, never off `RecapStyle`'s defaults.**
- **Parallel sessions collide** on one checkout, one simulator bundle id, and
  every file each PR touches (`HANDOFF.md`, `current-state.md`, the ledger, the
  index, `test-count.baseline`). #110 merged with a baseline 12 tests low for
  exactly this reason. → `Docs/environment-gotchas.md`.
- **A merge can drop catalogue keys**: 4058b92 lost PR #91's 13 picker strings.
- **MapKit saturates at ~109° of longitude**: the frozen country card is a main
  path, not a fallback.

---

## 🐛 Known bugs and accepted costs

Import date range clips at timezone edges; `RecapMode` may be two axes; the
glacier renders flat → `Docs/handoff-known-bugs.md`. The **0.747 sharpness step
at hold boundaries** is accepted; revisit only if someone notices it in a film
(`Docs/_archive/handoff-crop-scaling.md` §10). Export cost and its levers →
`Docs/handoff-export-performance.md`.
