# Open — the `KamomeCore_KamomeExportEngine` subject lookup still misses

It no longer crashes; it now degrades a film silently instead. Same mechanism,
two symptoms. The rate and the trigger are still unmeasured — this entry exists
to catch the next occurrence, which is now instrumented.

*Moved verbatim out of `HANDOFF.md` on 2026-08-31 when that file was put on a
300-line budget (`Scripts/check-doc-budget.sh`). Nothing was edited; `HANDOFF.md`
carries the live summary and points here.*

---

## 🟠 Open — the `KamomeCore_KamomeExportEngine` subject lookup still misses; it no longer crashes

**Retitled and corrected 2026-08-28.** This entry stood as "🔴 intermittent bundle
crash (2026-08-13)" and described an unguarded `fatalError` reached through
`Bundle.module` in `Core/ExportEngine/RecapCarSprite.swift:75`. **That mechanism
no longer exists** — its own closing line ("the eventual fix is small and
defensive — a non-trapping bundle lookup") was carried out two days later and the
entry was never updated. Kept, not deleted: the *lookup* still misses, and the
same miss now degrades a film silently instead of crashing it.

### The history, as observed (2026-08-13)

`Fatal error: unable to find bundle named KamomeCore_KamomeExportEngine`, thrown
during map-renderer creation — after the region resolves, before any frame is
drawn. Hit **2 of 3** New Zealand render attempts; never on Miyakojima, never on
the Iceland run — so it read as trip-correlated rather than evenly random.
Cleared on retry, and again under `-retry-tests-on-failure`. The resource bundle
**is** present in the built `Kamome.app`, so it was a runtime lookup failure, not
a packaging fault. (Those are this file's own 2026-08-13 figures, kept verbatim;
no wider tally is recorded in the repository.)

### What changed the symptom — VERIFIED from the tree, 2026-08-28

| when | commit | what |
|---|---|---|
| 2026-08-15 | `b44a7fc` | "the sprite fallback stops being unreachable" — the trap is replaced by a non-trapping resolver |
| 2026-08-16 | `e2a1478` | `RecapCarSprite.swift` deleted; the resolver is generalised into `VehicleResourceBundle` (`Core/ExportEngine/SpriteDirection.swift:43`). Its message: "`Bundle.module` does not return." |

`grep -rn "Bundle.module" --include="*.swift" .` returns **only comments** — no
call site anywhere in the repository, and no `fatalError` or `try!` in
`Core/ExportEngine`. **The crash as this entry described it cannot recur.** The
generated accessor still exists in DerivedSources, as it does for every target
with resources, but nothing calls it.

### What the same lookup does now — observed 2026-08-28

`VehicleCatalog.resolve` returns nil and `VehicleSubjectRenderer.make` draws the
vector seagull. **Whether `VehicleResourceBundle.resolved` was itself nil is
UNKNOWN** — nothing recorded it, which is the gap the new log line closes. Four
`RecapStopStillTests/testRenderSubjectStill` runs differing only in
`TEST_RUNNER_KAMOME_ROUTE_COLOR` produced three cars and one gull
(`light-C-deeper`, `~/Kamome-wt/logs/render-light-C-deeper.log`); the test passed
in 25.8 s with no retry.

**VERIFIED here, not taken on report:**

- The still really is the fallback. Diffing it against the re-render at >8/255 on
  any channel gives **9,291 differing pixels of 2,073,600, all inside one
  126×131 box** — the subject and nothing else. Crops confirm gull vs car.
- **Nothing distinguished the run.** Stripped of timestamps, pids and paths, the
  two console outputs are identical **line for line**; the only differences are
  the colour, the output path and the elapsed seconds.
- The harness could not have told anyone either: `RecapReviewScene` prints
  `KAMOME_REVIEW subject <id> at <n>px` **before** calling `make`, so it reports
  what was asked for, and `KAMOME_SUBJECT_STILL … (se drawing)` derives the
  direction from the heading, not from what was drawn.
- The bundle carries `Vehicles/` and nothing else (`Package.swift`,
  `resources: [.copy("Resources/Vehicles")]`), so a whole-bundle miss would
  degrade **only** the subject. The single-box pixel diff is therefore consistent
  with a whole-bundle miss and **cannot discriminate** it from missing art.

### Same mechanism — established. Same trigger — UNKNOWN.

Same bundle name, same lookup, same code lineage, same point in the sequence
(map-renderer/compositor construction), same intermittency, both cleared by a
re-run. `b44a7fc` is exactly the commit that would turn the one symptom into the
other. That is enough to call it **one mechanism with two symptoms**.

It is **not** enough to call it one root cause. Neither occurrence was diagnosed,
and two things argue for caution: the crash tracked New Zealand and is recorded
above as never having fired on the Iceland run, while this miss *was* Iceland; and
`VehicleResourceBundle` is *stricter* than `Bundle.module` was — it accepts a
candidate only if `Vehicles/vehicles.json` is findable inside it, so a bundle
directory that exists but does not answer a resource query fails here and would
have succeeded there.

### Two hypotheses tested and weakened — 2026-08-28

**An install/launch race: WEAKENED, and it was the leading idea.** The tempting
mechanism was that the bundle being probed is a directory written moments before
the process launched. **MEASURED** on iPhone 17 Pro over four runs: a run whose
build produces a changed product installs into a **brand-new container**, taking
the old one with it (`9979C474-…` 22:24:56 → `D4A52666-…` 22:27:12 →
`E91959A1-…` 22:29:19), and the installed
`Kamome.app/KamomeCore_KamomeExportEngine.bundle` carries the install time rather
than the build time. **But a run that compiles nothing does not reinstall at
all** — a fourth run with 0 `SwiftCompile` and 0 packaging tasks left
`E91959A1-…` untouched. The four appearance renders differed only in environment
variables, so on that evidence the app was installed once and reused across them,
and no install sat next to the failing launch. INFERRED for that batch — no
install record from it survives — but it points away from the race, not towards
it.

**A build-work difference: RULED OUT.** `light-C-deeper`'s build did more than
`light-A`/`light-B`'s — two `CompileXCStrings` and four `CopyStringsFile` against
one and two. That is a real difference and it is **not** the discriminator: the
clean re-render (`render-light-C-rerender.log`) ran the *same* heavier pattern
and drew the car.

### What was done about it, and what was not

**Done (this change).** `VehicleSubjectRenderer.make` now logs the miss
(`KamomeLog.recap.error`) instead of degrading in silence, per Arch.md's no-silent-fallbacks rule, and
the doc comment that called this "a state no test can arrange" is corrected.
`KamomeLog` reaches the xcodebuild console on the simulator — the routing lines
in every render log prove it — so the next occurrence names itself in the same
file a reviewer already reads.

**Done, approved (Chiu, 2026-08-28): the lookup now says what it tried.**
`VehicleResourceBundle.resolved` logs a one-shot trace naming, per candidate, the
URL and — the fact both incidents lacked — **whether the nested bundle was on
disk**, which is what separates an install-timing fault from a packaging one.
Scope as approved: failure path only (a process that resolves logs nothing),
filesystem paths only (nothing derived from a trip, so §0 is not engaged), and
shipped rather than reached for afterwards, because an intermittent failure has
to be instrumented *before* it happens.

The walk moved into `VehicleResourceBundle.resolve(hosts:)` so the message can be
exercised — `resolved` is a lazily-initialised global with no seam, and a
diagnostic that can never be shown to fire is one nobody should trust. Order and
acceptance rule are unchanged. Two tests hold the contract in
`RecapSubjectOrientationTests`: a host with no manifest produces
`…KamomeCore_KamomeExportEngine.bundle: not on disk`, and a resolving lookup
produces an **empty** trace.

**Two lines, not one, when it next fires:** the bundle trace once per process,
and `VehicleSubjectRenderer.make`'s per-subject line naming the consequence. One
says why, the other says what the viewer will see.

**Still not measured:** the rate, and the trigger. The next occurrence is what
this exists to catch.

**Stale references left alone, deliberately.** `Docs/current-state.md` is the
synced index and its neighbouring sections are being rewritten on
`feature/p4-appearance-follows-system`, so **two** lines there belong to the pass
that re-syncs it, not to this change: the blockers entry "🔴 intermittent …
bundle crash", and "worktrees fix it but silently skip half the secrets guard
(`HANDOFF.md` 3e)" — struck above, closed by `2d221e0`.
`Docs/gate-P3.5-checklist.md`
and `Docs/handoff-P3.5.md` describe a closed phase and are history.
`Docs/decisions.md` 2026-08-15 records the `Bundle.module` mechanism as it stood
and is append-only — it is not wrong, it is superseded.

