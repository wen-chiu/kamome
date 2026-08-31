# Kamome — session boot

Kamome (卡摸咩) is a **memory engine for road trips**: import or capture a
journey once, then turn it into a cinematic recap film worth keeping and
sharing. What Kamome *is*: `Docs/kamome-poc-spec.md` (later ADRs override its
stale status text).

**Phase 4 — films worth keeping**: vehicle sprites → cross-region crossing →
export that survives. Phase 3.5 closed 2026-08-15. Later: P5 Capture Beta,
P6 Plans, P7 backend.

## Read at session start

1. `Docs/current-state.md` — the snapshot. **Run its staleness check first**:
   its "Last synced" line must name **both** the newest ADR in
   `Docs/decisions.md` **and** the newest merged PR on `main`. If either is
   behind, report the staleness before proceeding — `decisions.md` wins on
   decisions, `HANDOFF.md` wins on live findings and blockers.
2. `git status -sb` — confirm which branch you are on and your distance from
   `origin/main` before trusting anything you read.
3. Your charter: `Arch.md` (engineering) or `PO.md` (product owner / governance).
4. `HANDOFF.md` — live findings, open experiments, known bugs, each pointing at
   its detail document.
5. The task document your work names.

`Docs/decisions.md` is append-only: the newest entry on a subject wins over any
older entry, any handoff, and this file. `Docs/_archive/` is history and is
never a work instruction.

## Hard rules — a violation stops the work

1. **§0 — real location data never leaves the device.** Never logged
   off-device, synced, sent to analytics or crash reporting, or committed to
   this repository. Real dumps live only in `Tests/Fixtures/trips/local/` and
   `Docs/tests/`, both gitignored. `KamomeLog` may name *which* stop failed,
   never where it is. Decided exceptions, and only these: routing sends real leg
   coordinates to Geoapify, and one user-initiated share of one trip. Anything
   further is a product decision for Chiu, never an implementation detail.
2. **Stop and confirm** before changing product behaviour, the Story/Rendering
   separation, the `RouteProvider` boundary, a public interface, what ships in
   MVP, or before adding a dependency.
3. **Never weaken a test to make it pass.** If you believe a test is wrong, say
   so and stop. Removing one needs proof it *cannot fail*, not an argument that
   it is redundant.
4. **Never write an assumption as though it were established.** Mark claims in
   documents VERIFIED / INFERRED / UNKNOWN, and name the cheapest thing that
   would settle each unmeasured one.
5. **Honest provenance.** Never "Verified Trip". Recorded and
   reconstructed-from-photos are different things, and a wrong road is never
   drawn as fact.
6. **A locked decision reopens only when Chiu names it** and says he is
   reopening it. Register: `Docs/current-state.md`. Procedure: `PO.md`.
7. **No magic numbers** — every tunable lives in `Config/TrackingConfig.json`.
   **Phase gates are hard gates**, each owing a demo artifact. **Boring
   technology.** Flag anything that needs the physical device.

## Done means `./check.sh` is green

    ./check.sh            # gates, lint, build, tests
    ./check.sh --static   # gates only, no Xcode required

Never report "done", "fixed" or "ready for review" from a partial run. A visual
change owes a render as well: `./check.sh` cannot see the film.

The `.xcodeproj` is generated — change `project.yml` and re-run
`xcodegen generate`, never hand-edit it. Desk harnesses read
`TEST_RUNNER_<VAR>`, and each variable must be declared in `project.yml` or it
can never be set:

    xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -only-testing:KamomeTests/RecapTimelineReportTests TEST_RUNNER_KAMOME_TIMELINE_REPORT=miyakojima

## Why these rules exist

Every rule above was paid for by an incident. Those are in
`Docs/rule-rationale.md` — read it when a rule looks arbitrary or when you are
about to work around one. Not at session start.
