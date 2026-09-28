# Kamome — session boot

Kamome (卡摸咩) is a **memory engine for road trips**: import or capture a
journey once, then turn it into a cinematic recap film worth keeping and
sharing. The spec (`Docs/_archive/kamome-poc-spec.md`) is the historical
reference; ADRs and `Docs/current-state.md` are current.

**Phase 4 — films worth keeping**, in closeout: what remains is the device
runbook, Chiu's judgement queue and bug fixes, all as issues. Phase 3.5 closed
2026-08-15. Later: P5 Capture Beta, P6 Plans, P7 backend.

## Read at session start

1. `git status -sb` — your branch and distance from `origin/main`. **One
   session implements at a time**; if another branch is mid-flight, say so.
2. `CHARTER.md` — the one charter: work loop, verification, design rules.
3. `Docs/current-state.md` — the snapshot. Its "Last synced" line must name the
   newest ADR (`./check.sh --static` checks it); if not, report it first.
4. `HANDOFF.md` (traps) and the open issues: `gh issue list` — labels
   `device`, `chiu`, `desk`. Phone-only checks: `Docs/device-runbook.md`.
5. The issue or task your work names.

New ADRs are one file each in `Docs/adr/`. `Docs/decisions.md` is frozen
history (to 2026-09-28), found through `Docs/decisions-index.md`. The newest
entry on a subject wins over any older one, any issue, and this file.
`Docs/_archive/` is history, never a work instruction.

## Hard rules — a violation stops the work

1. **§0 — real location data never leaves the device.** Never logged
   off-device, synced, sent to analytics or crash reporting, committed to
   this repository, or written into an issue or PR (the repository is public). Real dumps live only in `Tests/Fixtures/trips/local/` and
   `Docs/tests/`, both gitignored. `KamomeLog` may name *which* stop failed,
   never where it is. Decided exceptions, and only these: routing positions to
   Geoapify through Kamome's relay; map tiles to OpenFreeMap; terrain tiles to
   AWS (ADR 2026-09-16, addendum 2026-09-17); stop names to Apple (Chiu
   2026-09-17, subject to Apple's terms — see Part D); and one user-initiated
   share of one trip. CLGeocoder output is not Map Data under DPLA Attachment 6
   on the plain reading (ADR 2026-09-16 §6, Part D analysis). Anything further
   is a product decision for Chiu, never an implementation detail.
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
   reopening it. Register and procedure: `CHARTER.md` §6.
7. **No magic numbers** — every tunable lives in `Config/TrackingConfig.json`.
   **Phase gates are hard gates**, each owing a demo artifact. **Boring
   technology.** Flag anything that needs the physical device.

## Decision authority — every session, every role

Higher overrides lower:

1. Explicit product decisions by Chiu
2. Approved ADRs — `Docs/decisions.md`, newest entry on a subject wins
3. Locked decisions — the register is in `CHARTER.md` §6
4. Existing tested behaviour and established conventions
5. Your engineering or design judgement

Existing code is **evidence, not truth**: where it contradicts a higher
authority, treat the implementation as potentially stale. Where two sources at
the same level conflict, state the conflict — never silently pick one.

**A finding that exists only in a conversation has not been delivered.** It
becomes a GitHub issue (or a traps line in `HANDOFF.md`), or it did not happen.

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
