# Why the rules in `CLAUDE.md` exist

Every hard rule in `CLAUDE.md` was paid for by an incident. The rule is short so
it can be followed; the incident is here so it can be understood.

**Read this when a rule looks arbitrary, or when you are about to work around
one — not at session start.** Splitting the two was itself a decision: the rules
and their stories used to share one file, where roughly eight lines of history
sat beside each one-line rule, and the rules a session most needed were the ones
buried deepest in what it had to read.

---

## §0 — real location data never leaves the device

The rule is the product's spine, not a privacy checkbox: Kamome asks people to
hand over where they actually went.

**The exceptions were decided, one at a time, and each cost something.** Routing
sends real trip leg coordinates to Geoapify — photo-imported trips, walks
included, and recorded traces for map-matching (`Docs/decisions.md` 2026-08-16,
2026-08-20 (b)/(c)). The trigger was a scaling trap rather than a preference: a
self-hosted OSRM only routes the regions it preloaded, and a friend's Tokyo trip
had no routable legs at all because the Japan extract was Kyushu. Honest
disclosure is the decided posture (`Docs/pre-launch.md` item 7).

**The rule's own wording was found incomplete on 2026-08-30.** It named
`Tests/Fixtures/trips/local/` as the gitignored home for real trip dumps but not
`Docs/tests/`, which holds raw device-test artifacts and had been gitignored and
in the tree all along. A standing rule that does not name one of the two places
it governs is a rule that will eventually be followed into the wrong one.

**What is mechanically checked, and what is not.**
`Scripts/check-location-data.sh` enforces two halves: nothing tracked under
either gitignored location, and no `KamomeLog` call carrying coordinates. It
deliberately does **not** flag coordinate-shaped literals — `DemoSeeder` ships
invented Western Australia coordinates and the committed fixtures ship invented
trips, so a coordinate in the source is not by itself a violation. Real versus
synthetic is not a distinction a script can make.

**Still open (`HANDOFF.md`):** two films of Chiu's real trips are committed
under `Docs/demos/`. They are phase demo artifacts, which the Rules of
Engagement require, so two rules genuinely pull against each other. This is an
owner call and has not been made — which is exactly why no check gates on it.

## The staleness check has two halves

`Docs/current-state.md` must name both the newest ADR in `Docs/decisions.md`
**and** the newest merged PR on `main`.

The one-half version — ADR only — **passed twice while the file's own blocker
list was weeks out of date.** Decisions and blockers drift on different clocks:
an ADR is written when something is decided, a blocker is closed when something
is fixed, and a check that watches only the first will certify a file whose
second half is stale.

## Confirm the branch before trusting what you read

On 2026-08-30 a PO session read a full generation of stale documents because the
checkout was sitting on an already-merged branch. Nothing about the documents
looked wrong; they were simply the previous generation of themselves.

`git status -sb` and the distance from `origin/main` cost one command.

## Never weaken a test, and removing one needs proof

**Both failure modes occurred on the same day, 2026-08-16.** A bundle-hygiene
test was shown to pass with the build step it guarded switched off — it could
not fail, and was rightly deleted. In the same pass, two catalogue tests were
swallowed by an over-wide edit and had to be restored verbatim from `HEAD`.

The rule that separates those two cases is that a deletion is justified only by
*demonstrating* the test cannot fail — disable the mechanism it guards and watch
it pass anyway. A test you merely believe is redundant is a test you have not
tested.

A related case: when shipped data makes a test's case unreachable, the
assertion is **restated** so it still holds the rule structurally. Deleting it
discards the rule along with the case.

## The test count is a signal, not an observation

The 2026-08-16 accidental deletion was caught only because the count fell from
**13 to 11**. Both suites were green with the tests missing, and every other
signal said the change was fine. A suite that loses tests does not go red.

That is why `Scripts/check-test-count.sh` counts statically and fails on any
drift from `Scripts/test-count.baseline`, in either direction. Adding tests is
deliberately a two-line change: write the test, raise the baseline in the same
commit. The cost of that second line is what makes a silent deletion impossible.

## Never write an assumption as though it were established

**This rule exists because it was broken.** On 2026-08-20 a PO session wrote
into three documents that a snap radius "can tell a wrong road from an indirect
one, because it acts before a route exists." That was reasoning, never measured.
Measurement said the opposite — wrong-road routes snap 44–132 m away, benign
ones 465–477 m — and `radiuses=500` had never guarded that band on OSRM either,
so the regression described did not exist (`Docs/decisions.md` 2026-08-20 (d)).

⚠️ **A comparison table is where an inference launders into a fact.** The error
happened because measured numbers and an unmeasured claim sat in one table at
the same visual weight. Mark the column, or split the table.

Where a claim is unmeasured, name the cheapest thing that would settle it,
in the document, beside the claim.

## A superseded lock is a governance hazard, not clutter

Twice, `PO.md` held a "do not reopen" lock that a later ADR had already amended:
the OSRM + MapLibre substrate lock (superseded 2026-08-15) and the "the routing
provider is not selected" lock (superseded 2026-08-20). Either would have had a
PO session defending a dead decision against the current ledger.

If you find yourself enforcing a lock that an ADR has amended, **the ADR wins
and the lock is the bug.**

## The document budgets are enforced because discipline did not hold

`HANDOFF.md` was trimmed by hand from **1,961 to about 915 lines** on
2026-08-29. Within days it was back over **1,400**. Nobody was careless; the
file is where live findings go, and live findings arrive faster than anyone
remembers to archive dead ones.

`Scripts/check-doc-budget.sh` caps `CLAUDE.md` at 80 lines and `HANDOFF.md` at
300. Over budget never means delete: move the detail to a topic document under
`Docs/` and leave a pointer, or move a closed section to `Docs/_archive/`.

## Why there is no magic-number gate

The no-magic-numbers rule is real and stays in `CLAUDE.md`, but it is enforced
by review rather than by a script, and that is a measured decision rather than
an omission.

A detector for decimal literals outside constant declarations was written and
run over `App`, `Core` and `UI` on 2026-08-31: **50 hits, of which the large
majority are epsilon comparisons** — `> 0.001`, `< 0.01` — which are not
tunables and never will be. A gate at that false-positive rate is a gate
somebody disables in its first week, and a disabled gate is worse than none
because the rule then looks covered.

If this is revisited, the promising shape is the inverse: assert that every key
in `Config/TrackingConfig.json` has a typed mirror and a `ConfigLoaderTests`
assertion, which is a closed set and checkable exactly.

## `TEST_RUNNER_` harness variables must be declared in `project.yml`

Fixed 2026-08-15, after every env-gated desk harness had been skipping silently
— which is the worst way for a measurement tool to fail, because it reports
success and measures nothing.

On this toolchain `xcodebuild` turns `TEST_RUNNER_FOO=bar` into a **build
setting**, and scheme environment values expand build settings. So `project.yml`
declares each harness variable as `$(TEST_RUNNER_<VAR>)`. Two consequences:

- An unset variable arrives as a **defined empty string**, so harnesses must
  read it through `HarnessEnv.value`, which collapses empty to nil.
- Adding a harness variable means adding a line to `project.yml`, or it can
  never be set.

With no `environmentVariables` at all, XcodeGen emits the test action with
`shouldUseLaunchSchemeArgsEnv = "YES"` and the test action takes the *Launch*
action's environment; declaring anything flips it to `"NO"`.

## SwiftLint needs a toolchain override locally

Rosetta swiftlint cannot load Xcode 26's arm64-only SourceKit, so local runs
need `XCODE_DEFAULT_TOOLCHAIN_OVERRIDE=/Library/Developer/CommandLineTools`.
`check.sh` sets it when it is not already set; CI does not need it.
