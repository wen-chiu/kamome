# Desk renders route direct to Geoapify, on their own key

**Status:** Decided (Chiu, 2026-10-03)
**Supersedes:** ledger entry "2026-09-19", its last clause only (`RecapDemoFilmTests` defaults to the shipped Worker)

## Context

Since 2026-09-19 every desk harness routed through the shipped Worker, which
holds the only key, and so spent the daily ceiling it shares with every user.
On 2026-10-02 about twenty desk films helped exhaust it, and from 14:47 UTC
every user's routing failed closed at 503 (#204; PR #215 moves the counter to a
Durable Object, which fixes the miscount but not the sharing). VERIFIED: #204,
PR #215. INFERRED: the desk's share of that day's requests — 10/02's count had
expired before anyone read it.

## Decision

Chiu, asked whether desk renders may go direct to Geoapify as a new §0
exception, and whether the desk uses a separate Geoapify key: *「2 3 是」*.

- **§0 exception, desk only.** A desk harness — the XCTest renders and reports
  on the Mac, over Chiu's own trips — may send routing positions **directly** to
  `api.geoapify.com`. The shipped app is unchanged: no key, routes through the
  Worker.
- **Its own key**, in `~/.kamome/desk-routing.env` on the Mac: one line, the key
  alone. The Worker's key (`~/.kamome/routing.env`) is never used by a desk
  render.
- **The key never travels through the environment.** `xcodebuild` echoes
  `TEST_RUNNER_` values into its log, so the test process reads the file
  itself, through `SIMULATOR_HOST_HOME` (`Tests/AppTests/DeskRouting.swift`).
  It is never logged, printed, committed, or put in a bundle or fixture.
- **The desk refuses the Worker.** `KAMOME_ROUTING_BASE_URL` set to the shipped
  Worker host is a harness error; unset means Geoapify direct; `""` routes
  nothing and reads no key (the offline gates, CI).

## Rejected

- Keep desk renders on the Worker and ration them — the users' budget stays one
  careless loop away from zero.
- A second Worker for the desk — more infrastructure to deploy and keep
  log-free, for a relay the desk does not need.
- The desk key in a `TEST_RUNNER_` variable — it would land in clear text in
  every build log (the known trap).

## Consequences

- `RecapDemoFilmTests.importedRecap` routes through `DeskRouting.matching`;
  `DeskRoutingTests` holds the rules, and proves on a Mac with the key that a
  simulator test reads it (CI skips that one test — it has no key).
- No privacy-notice change: no user's data takes this path.
- UNKNOWN: whether Geoapify meters the free tier per key, per project or per
  account. If the desk key shares the account's daily credits, desk renders can
  still starve users — at Geoapify instead of at the Worker. Settled by reading
  the Geoapify dashboard (#218).
- `CLAUDE.md` hard rule 1 lists the §0 exceptions "and only these"; adding this
  one there waits on Chiu's wording (proposed in the PR).
