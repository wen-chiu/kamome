# Why the rules in `CLAUDE.md` exist

Read this when a rule looks arbitrary, or when you are about to work around
one — not at session start.

**Most of what was here has been deleted, deliberately.** The first draft
retold seven incidents that `Docs/decisions.md` already records. That ledger is
append-only and authoritative, and nothing kept this file in sync with it: a
second, weaker account of a decision is exactly the failure `CHARTER.md` §6 warns about,
where the later-dated entry wins while being the worse one. What survives is
what has **no other home**, plus pointers.

---

## Where each rule's story actually lives

| `CLAUDE.md` rule | the incident behind it |
|---|---|
| §0 exceptions (Geoapify, one share) | `Docs/decisions.md` 2026-08-16, 2026-08-20 (b)/(c) — the trigger was a scaling trap: self-hosted OSRM only routes preloaded regions, and a friend's Tokyo trip had no routable legs because the Japan extract was Kyushu |
| Mark VERIFIED / INFERRED / UNKNOWN | `Docs/decisions.md` 2026-08-20 (d) — a snap-radius claim written as fact, measured, and found backwards. `CHARTER.md` §4 carries the rule it produced, including that **a comparison table is where an inference launders into a fact** |
| Never weaken or delete a test | `CHARTER.md` §4, "Tests", and `CLAUDE.md` rule 3 — both failure modes, 2026-08-16 |
| A locked decision reopens only when Chiu names it | `CHARTER.md` §6 — twice a lock outlived the ADR that amended it, and on 2026-09-28 the substrate row still said "Apple Maps still ships" twelve days after ADR 2026-09-16 |
| The staleness check names the newest ADR only | ADR 2026-09-28. The ADR-only version once **passed twice** while the file's blockers were weeks stale — so a PR half was added. It is gone because the blockers left the file: open work is issues now, and the PR half made every PR edit one line |
| `TEST_RUNNER_<VAR>` must be declared | `project.yml`, the comment above `environmentVariables` — `xcodebuild` turns it into a *build setting*, so an undeclared variable silently reaches nothing and every env-gated harness skips while reporting success |
| SwiftLint's toolchain override | `check.sh` sets it — Rosetta swiftlint cannot load Xcode 26's arm64-only SourceKit |

---

## The test count is a signal, not an observation

**No other document records this.** On 2026-08-16 an accidental deletion was
caught only because the count fell from **13 to 11**. Both suites were green
with the tests missing, and every other signal said the change was fine. A suite
that loses tests does not go red.

`Scripts/check-test-count.sh` therefore fails when the count **falls**.

Until 2026-09-28 it compared against a committed baseline and failed on drift
in *either* direction, so every test-adding PR edited `Scripts/test-count.baseline`.
Parallel branches collided on that one number: #110 merged its branch's 771 over
the 783 that #106/#108/#109 had brought, and `main` went red with no test
missing. Now the reference is the count at the merge base with `origin/main`,
adding a test needs no second edit, and a deliberate removal carries a
`Test-Removed: <name> — <proof>` trailer per test (ADR 2026-09-28). The signal
the 2026-08-16 incident needed — a fall — is exactly what is still caught.

## The document budgets exist because discipline did not hold

`HANDOFF.md` was trimmed by hand from **1,961 to about 915 lines** on
2026-08-29. **Within two days it was back over 1,400** — nobody was careless;
live findings simply arrive faster than anyone remembers to archive dead ones.

`Scripts/check-doc-budget.sh` caps the files a session must read at start.
Over budget never means delete: move detail into a `Docs/` topic document and
leave a pointer, or move a closed section to `Docs/_archive/`.

## Why there is no magic-number gate

The no-magic-numbers rule is real and stays in `CLAUDE.md`, but it is enforced
by review, and that is a **measured decision rather than an omission**.

A detector for decimal literals outside constant declarations was run over
`App`, `Core` and `UI` on 2026-08-31: **50 hits, mostly epsilon comparisons**
(`> 0.001`, `< 0.01`) which are not tunables and never will be. A gate at that
false-positive rate is one somebody disables in its first week, and a disabled
gate is worse than none because the rule then looks covered.

The promising alternative, if this is revisited: assert that every key in
`Config/TrackingConfig.json` has a typed mirror and a `ConfigLoaderTests`
assertion. That is a closed set, and checkable exactly.

## Why staging is a rule (`CHARTER.md` §5)

Four incidents, and the fourth is a different kind from the first three.

Three times a branch ref picked up another session's commits — sessions here
share a checkout family, `main` moves under you mid-task, and a wildcard stage
cannot tell your change from someone else's. The cost each time was rework.

The fourth, **2026-09-09**, cost someone else's work. A squash rebased a tree
built against PR #46 onto a `main` that had reached #47; git reported no
conflict, because a soft reset keeps your index and asks no questions. **Five
documents of an already-merged PR came back as silent reverts** — an ADR, its
index row, `HANDOFF.md`, `PO.md` and `current-state.md` — and nothing failed. It
was caught by diffing the commit against the new head *afterwards*, which is not
a control anyone had asked for.

That is why the rule names three separate acts — confirm the branch, name the
paths, do not squash onto a moved `main`. Each of them turns a silent overwrite
into either a conflict or a diff you have to read.


## Why one session implements at a time (ADR 2026-09-28)

From 2026-09-01 to 2026-09-28, 488 of ~1,600 file touches on `main` were
documents: `HANDOFF.md` changed 90 times, `current-state.md` 81, the ledger 77,
its index 58. Every parallel PR edited the same five files, so parallel sessions
bought merge conflicts and silent reverts (the staging incidents above, #110's
baseline), not speed. The bottleneck of the remaining work is the phone and
Chiu's judgement, which more sessions cannot widen. Subagents stay useful for
read-only work, where they touch no shared file.
