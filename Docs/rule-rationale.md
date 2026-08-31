# Why the rules in `CLAUDE.md` exist

Read this when a rule looks arbitrary, or when you are about to work around
one — not at session start.

**Most of what was here has been deleted, deliberately.** The first draft
retold seven incidents that `Docs/decisions.md` already records. That ledger is
append-only and authoritative, and nothing kept this file in sync with it: a
second, weaker account of a decision is exactly the failure `PO.md` warns about,
where the later-dated entry wins while being the worse one. What survives is
what has **no other home**, plus pointers.

---

## Where each rule's story actually lives

| `CLAUDE.md` rule | the incident behind it |
|---|---|
| §0 exceptions (Geoapify, one share) | `Docs/decisions.md` 2026-08-16, 2026-08-20 (b)/(c) — the trigger was a scaling trap: self-hosted OSRM only routes preloaded regions, and a friend's Tokyo trip had no routable legs because the Japan extract was Kyushu |
| Mark VERIFIED / INFERRED / UNKNOWN | `Docs/decisions.md` 2026-08-20 (d) — a snap-radius claim written as fact, measured, and found backwards. `PO.md` carries the rule it produced, including that **a comparison table is where an inference launders into a fact** |
| Never weaken or delete a test | `Arch.md` §7.1–§7.3 — both failure modes, 2026-08-16 |
| A locked decision reopens only when Chiu names it | `PO.md`, *"a superseded lock is a governance hazard"* — twice a lock outlived the ADR that amended it |
| The staleness check has two halves | `PO.md` — the ADR-only version **passed twice** while the file's blockers were weeks stale |
| `TEST_RUNNER_<VAR>` must be declared | `project.yml`, the comment above `environmentVariables` — `xcodebuild` turns it into a *build setting*, so an undeclared variable silently reaches nothing and every env-gated harness skips while reporting success |
| SwiftLint's toolchain override | `check.sh` sets it — Rosetta swiftlint cannot load Xcode 26's arm64-only SourceKit |

---

## The test count is a signal, not an observation

**No other document records this.** On 2026-08-16 an accidental deletion was
caught only because the count fell from **13 to 11**. Both suites were green
with the tests missing, and every other signal said the change was fine. A suite
that loses tests does not go red.

`Scripts/check-test-count.sh` therefore fails on drift in **either** direction.
Adding tests is deliberately a two-line change — write the test, raise
`Scripts/test-count.baseline` in the same commit. That second line is the whole
mechanism: it is what makes a silent deletion impossible.

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
