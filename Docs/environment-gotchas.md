# Environment gotchas that cost time

Operational reference for anyone rendering, routing or reproducing CI on this
machine. Not findings — things that have already cost somebody an afternoon.

*Moved verbatim out of `HANDOFF.md` on 2026-08-31 when that file was put on a
300-line budget (`Scripts/check-doc-budget.sh`). Nothing was edited; `HANDOFF.md`
carries the live summary and points here.*

---

## Environment gotchas that cost time

- ⚠️ **Routing is Geoapify since 2026-08-20** (`Docs/decisions.md` 2026-08-20).
  The OSRM entries below describe the parked local server (`Deploy/`), kept as
  the self-hosted fallback — they are not the shipped routing path.
- **The desk render path and the app disagree about routing.** `matching.base_url`
  ships `""`, so the shipped app reconstructs **no** legs and draws everything
  dashed; the desk harness defaults to `http://127.0.0.1:5100` and reconstructs
  most of them. A film that is dashed everywhere is almost certainly an app-config
  artifact, not a regression.
- **`RouteMatchService` logs the wrong base URL** when a reconstructor is injected
  (which every desk harness does): it prints `config.matching.baseURL`, so the log
  says `"(none — matching disabled)"` in the same run where legs reconstruct
  against a live OSRM. `App/Services/RouteMatchService.swift:39`. Unfixed; it is
  the line you would otherwise trust to answer "which server did this build ask?".
- **Agent shells here are sandboxed.** `curl` to localhost and `docker ps` fail
  with what look like "server is down" errors even when the server is running.
  Confirm through a test run, not through curl.
- **OSRM on `:5100` is compose-managed and restart-safe** — corrected 2026-08-09.
  It is the `osrm` service in **`Deploy/docker-compose.yml`** (container
  `kamome-osrm`, `restart: unless-stopped`, healthcheck green), so it comes back
  on its own provided Docker Desktop starts at login. Start it with
  `cd Deploy && docker compose up -d`.

  The stale claim this replaces — "started ad hoc, will not come back" — was
  reading `~/kamome-osrm/docker-compose.yml`, a **legacy file** carrying only
  taiwan:5002 and australia:5001. Nothing runs from it; the per-region servers
  were replaced by the single merged extract when `Deploy/` landed (`0924eca`).
  It is outside the repo and harmless, but it is what to ignore when checking
  whether routing is up. `docker ps` is the answer, not that file.
- Tiles/terrain: `~/kamome-osrm/tiles`, `~/kamome-osrm/terrain`.
- `simctl addmedia` fails with LaunchdSimError 133 unless the device is actually
  booted — boot it first, the error does not say so.
- **Fixture shadowing is real.** `RecapTripFixtures.tripFixture` prefers
  `Tests/Fixtures/trips/local/<name>.json` (real dumps, gitignored per §0) over the
  committed fixture. Local and CI therefore test different geometry — NZ is 20
  stops locally, 3 on CI. To reproduce CI, move `local/` **outside the repo**
  (not to a dotfile inside it — only `Tests/Fixtures/trips/local/` is gitignored)
  and re-run.
- **`850a995` does not compile.** A parallel session's push swept in an
  uncommitted edit and CI died at lint before building. Harmless at the tip;
  `git bisect` across it will hit it.
- The desk render command (env-gated `RecapPilotFilmTests`, Variant A) is
  preserved in `Docs/_archive/handoff-2026-08.md` under "▶ RESUME HERE
  (2026-08-13)". Films go to `~/kamome-renders/`, never `/tmp`.

## Capture the whole run, or a flake is unattributable

**2026-09-02.** A `./check.sh` run reported `** TEST FAILED **` while the suite
itself printed **247 tests, 0 failures** — so the failure was outside the summary
the console filter showed. The immediate re-run passed, and **three further clean
runs did not reproduce it**. The output of the failing run had not been kept, so
there is nothing to attribute it to and no honest claim to make beyond this
paragraph. Classified **UNKNOWN**.

It is *tempting* to file this under the known intermittent subject lookup
(`Docs/handoff-subject-lookup.md`) — same profile: rare, clears on retry, never
diagnosed. **Do not.** That entry already records how much damage one unfounded
attribution does, and the whole reason two log lines ship there is to catch an
occurrence *with its evidence attached*.

**So: redirect the whole run to a file, always.** The console filter you use to
read a run is not the run.

    ./check.sh > /tmp/check-$(date +%H%M%S).log 2>&1; echo "exit=$?"

Then grep the file. A flake you did not capture costs the same time as the
incident and buys nothing.

## The seam is bounded by the collapse rule, not by taste

`FollowCameraRestingFrameTests.testTheOpeningHandsOverWithoutAJump` asserts the
one-frame step at the opening→body seam is within
`export.opening_collapse_drift_fraction` (15%) of the frame. That is not a chosen
number: when the closing zoom plays it ends exactly on the live track and the seam
is ~0, and when it is *collapsed*, `isEffectivelyTheSame` is what permitted the
collapse — so its drift allowance is precisely the largest cut the design allows.
Margaret River sits at 8.6% of that 15%.

An earlier version asserted a flat "under 5% of the frame", which was fine while
the seam was always a cut and started failing the moment `body_span_padding` made
the closing zoom a real 2.5× move.

