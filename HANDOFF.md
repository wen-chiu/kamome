# HANDOFF — traps, and where the open work lives

**Updated 2026-09-28** (ADR 2026-09-28). This file no longer lists open work.

| what | where |
|---|---|
| Open work | **GitHub Issues**: `gh issue list` — labels `device`, `chiu`, `desk` |
| Phone-only checks | `Docs/device-runbook.md`, tracked by #112 |
| Waiting on Chiu | `gh issue list --label chiu` |
| The snapshot | `Docs/current-state.md` |
| Closed findings, history | `Docs/_archive/` |

**The critical path to a release:** #112 (the device run), then Chiu's
submission sequence — `./check.sh --release <.xcarchive>` with the real key in
`KAMOME_ROUTING_API_KEY` (never a file, ADR 2026-09-12), **then** rotate the
Geoapify key (S7). Never the other way round. → `Docs/release-readiness.md`.
Before submitting, the App Store prerequisites A1–A7 are Chiu's (#126,
`Docs/handoff-release-review-2026-09-28.md`).

**Accepted risk, do not reopen (Chiu 2026-09-13):** the film's map credit omits
`ODbL`; the six-character fix is costed and deliberately not built.
`showsAttribution` is off because Kamome draws its own credit — if
`RecapMapCreditTests` is ever removed, that line goes back first.
→ ADRs 2026-09-12 (b), 2026-09-13.

This file holds only what an issue cannot: **traps** — things that will cost
the next session an afternoon if nobody says them first. Add one when it has
cost somebody time; keep each to a summary and a pointer.

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
- **Two sessions share one checkout family and one simulator bundle id** — a
  screenshot can show *their* build. Use your own device (`CHARTER.md` §1).
  → `Docs/environment-gotchas.md`.
- **A merge can drop catalogue keys**: 4058b92 lost PR #91's 13 picker strings.
- **MapKit saturates at ~109° of longitude**: the frozen country card is a main
  path, not a fallback.
- **Never set the version in Xcode's General tab** — xcodegen discards it. Use
  `Scripts/set-version.sh minor|patch|major`; the build fails on a mismatch.
  The build number is the commit count, stamped by every build. `Scripts/install-git-hooks.sh` once per clone regenerates the
  project after every checkout, merge, pull and rebase.
- **Never set the Team in Xcode's Signing pane either** — same discard. It is
  `DEVELOPMENT_TEAM` in `project.yml`; a wrong one (B9U326WRA4, until
  2026-09-30) fails a CLI archive with "No Account for Team", and `archive.sh`
  now stops first if no valid signing certificate belongs to the team.

---

## 🐛 Known bugs and accepted costs

Import date range clips at timezone edges; `RecapMode` may be two axes; the
glacier renders flat → `Docs/handoff-known-bugs.md`. The **0.747 sharpness step
at hold boundaries** is accepted; revisit only if someone notices it in a film
(`Docs/_archive/handoff-crop-scaling.md` §10). Export cost and its levers →
`Docs/handoff-export-performance.md`.
