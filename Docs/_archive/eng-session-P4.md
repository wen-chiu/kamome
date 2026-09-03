# Engineering session — Phase 4, task 1: routing goes live

**Status: EXECUTED (as of 2026-08-21).** The migration is committed on
`feature/geoapify-routing` (`e366df2`, `556f828`, `1cedbd2`). Do not paste this
brief into a new session — the follow-up is `Docs/eng-session-P4-visual.md`.
Kept as the record of what was asked.

**Paste the block below as the first message of a fresh Claude Code session.**
It is written to be self-contained: it names the reading order, the one task, the
constraints that are already decided, and what counts as done.

Scope is **one task**. Do not hand this session cross-region or export work — those
are separate sessions, in the order set by `Docs/pre-launch.md`.

---

```
You are the engineering session for Kamome, operating under `Arch.md`. Read it
first — it is your charter, and §7/§8 (verification is mandatory, three levels)
and §12 (communicate before implementing) are the parts I will hold you to.

Read in this order before proposing anything:
- `CLAUDE.md` — current state, Phase 4 scope, and §0 (location data never leaves
  the device by default). §0 has been amended by an explicit owner decision; read
  the ADRs below for what it now permits.
- `Docs/decisions.md`, entries **2026-08-20**, **2026-08-20 (b)** and
  **2026-08-20 (c)** — the routing provider is decided, the terms are read, and
  the privacy line is drawn. The most recent entry on a subject wins.
- `HANDOFF.md`, "Findings — PO/Architecture session (2026-08-20)" — nine numbered
  items. Items 0b, 1, 2, 3 and 4 constrain this task directly.
- `Docs/pre-launch.md` — what blocks an App Store submission, and the order.

Where a `Docs/handoff-*.md` file contradicts an ADR, the ADR wins and the handoff
is stale. Say so rather than resolving it quietly; this repository has lost real
time to stale documents read as current thinking.

## The task

Migrate routing from the self-hosted OSRM on a LAN to **Geoapify**, and then
render one real film on it. The film is the deliverable, not the integration —
Chiu decides from rendered output, and nothing published so far has ever run on
real road data from a hosted provider.

Ship it as two reviewable changes, not one:
1. The provider migration.
2. The Cloudflare Worker that takes the API key out of the binary
   (`Docs/pre-launch.md`). Builds already reach other people's phones, so the key
   is in those IPAs today. Separate commit, same session.

## What is already decided — do not redesign these

- **Geoapify is the provider.** Closed on Chiu's own survey. Do not evaluate
  alternatives, and do not build a provider registry, factory or second adapter.
  The boundary already passes the real test: OSRM's wire format lives only in the
  two provider files and everything downstream consumes a domain-level
  `RouteMatchOutcome`, so a differently-shaped provider is one new file.
- **`/v1/routing` is GET-only** (`POST` returns 404) and takes
  `?waypoints=lat,lon|lat,lon&mode=drive`. `/v1/mapmatching` is POST.
- **Three things move with the migration, not two** — `HANDOFF.md` item 1:
  1. Lift the detour-ratio gate out of `OSRMRouteProvider`; it is Kamome's
     honest-provenance policy, not an OSRM fact.
  2. **Carry `matching.route_waypoint_radius_m` (500 m) across.** Today it is sent
     as OSRM's `radiuses=` and it is what makes a photo taken 1 km from a road
     draw **dashed**. Chiu's survey measured Geoapify without it: that photo
     returns 200 and a 20.33 km route for an 11.29 km leg (ratio 2.247), which
     **passes** the 2.5 detour gate and draws as solid road the traveller never
     took.
     ⚠️ **Whether Geoapify accepts any snap-radius parameter is untested.** Report
     what you find. **If it does not, STOP and ask** — "dashed" versus "a road
     that was not taken" is a product decision for Chiu, and it is explicitly not
     to be solved by tightening the detour ratio (a fjord drive is legitimately
     2–4×, so the ratio cannot tell a wrong road from an indirect one).
  3. **Keep `RouteProviderFailure.rateLimited`** even though Geoapify never emits
     a 429 — the Worker can, and will.
- **No user-facing string is edited.** Chiu confirmed this on 2026-08-20:
  `recap_routing_budget_detail` keeps its retry promise (verified true —
  `shouldReconstruct` skips already-matched legs, so a second run really does
  resume), and `recap_routing_unreachable_detail` stands as written.
- **§0 — never log the request URL.** GET-only means the URL carries the API key
  *and* real coordinates. The existing logs are the pattern: `OSRMRouteProvider`
  logs `config.baseURL` (host only), never the built URL. Keep it that way.
- **Frozen, and not oversights:** `export.keyframe_interval_frames` and the
  opening's per-frame snapshotting. They wait on a camera-transition design
  conversation. Do not touch them, do not "improve" them, and do not benchmark
  around them.
- **Walks route on a walking profile and draw solid** (spec v1.8 §4.4.1). That is
  *scope*, not this task — car ships first. Do not build it here; just do not
  design anything that makes it harder.

## `matching.trip_budget_s` — measure it, do not pick a number

It is 60 s, chosen against a healthy LAN server at ~1 s a leg. Survey latency was
0.48–2.53 s cold and 440–840 ms with connection reuse; Iceland is 58 legs, so the
sequential trip lands somewhere between ~35 s and ~88 s — **derived arithmetic,
not a measurement.** `matchTrip` already logs `STOPPED after N legs —
trip_budget_s exhausted`. Read that line from a real run, then set the number, and
say in the commit which run it came from.

## What counts as done

Per `Arch.md` §8, and be explicit about which level each claim reaches:

- **Level 1** — build and suite green, with the exact commands and full output.
  Report the test count and flag any change in it (§7.4).
- **Level 2** — **one real trip rendered end to end on Geoapify**, with: how many
  legs routed versus stayed dashed, the `matchTrip` log line, and the film itself.
  This is the deliverable Chiu judges.
- **Level 3** — state plainly that OSRM's wire format has not leaked outside the
  provider file, and that the three carried policies are where you put them.

Do not say "done". `Arch.md` §14: say "Ready for review", and name what is still
unverified.

## Before you write code

`Arch.md` §12: first response is Problem → Boundary → Options (2–3) → Decision →
Verification plan. Do not start until that is stated.

One more thing worth knowing: 45 shipped vehicle sprite PNGs are modified but
uncommitted in the working tree — same dimensions, different decoded pixels,
consistent with an uncommitted `Tools/center-sprites.py` run. Not your task; do not
commit them as a side effect of yours.
```
