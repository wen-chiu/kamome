# The routing proxy — how the key stops shipping in the binary

**Status: deployed 2026-08-27** — `https://kamome-routing.kamome-site.workers.dev`,
from Chiu's own Cloudflare account and his authenticated shell, never from an
agent session. That hostname is **not a secret**: it ships in every IPA by design.
Preview URLs were turned off on 2026-08-28 — see "Why `preview_urls = false`".

**The app is not pointed at it yet.** Everything below is still a runbook for the
step that remains: until `matching.base_url` and `api_key_required` are flipped in
`Config/TrackingConfig.json`, builds call Geoapify directly and the key is inside
every one of them.

```
iOS app ──(no key)──▶ Cloudflare Worker ──(+ key)──▶ Geoapify ──▶ back
```

Why this exists at all is in `Docs/pre-launch.md`: the key reaches the app today
through a gitignored `.xcconfig` and lands in `Info.plist`, so it is **inside
every IPA that has ever reached another person's phone**. Provider-side key
restriction cannot fix that for a native app — Geoapify's restrictions (IP
allowlist, HTTP referrer, CORS origin) are all browser mechanisms.

## Deploy

```bash
cd Deploy/worker
npm ci                                     # pinned wrangler, right arch for this machine
npx wrangler login
npx wrangler secret put GEOAPIFY_API_KEY   # paste the key from ~/.kamome/routing.env
npm run deploy
```

**`npm ci` first is not optional, and `npm` here must be Node 22 or newer.** See
"The Node version trap" below — skipping it is what broke the 2026-08-28 deploy.

### Who may run this, and under what conditions

**An engineering session may deploy** (Chiu, 2026-08-29). The two reasons it used
to be his alone are spent: `wrangler login` is done and cached, and the secret is
set, so a session deploys under his existing authorisation and touches no
credential. The pinned wrangler above is what makes the result reproducible rather
than a function of whatever npm resolved that day.

That permission comes with conditions, each of which exists for a reason:

- **Deploy only from merged `main`, or from a branch Chiu names.** A deploy from an
  unmerged branch puts code into production that no review ever saw — the Worker
  holds the API key, so "it works on my branch" is not a standard it gets to meet.
- **The secret stays Chiu's.** `wrangler secret put` is never a session's command.
  A session that can set the key is a session that has handled the key.
- **`wrangler tail` remains forbidden**, and delegation does not soften it. It
  streams request URLs; `/v1/routing` is GET-only, so a tailed line carries a real
  trip's coordinates. §0 does not have a convenience exception.
- **Every deploy reports its Version ID and runs the probe.** A deploy without an
  after-probe is not a verified deploy — it is a deploy someone feels good about.
  The pass conditions are in "Why `preview_urls = false`" below.
- **Rollback is what makes this reversible.** Verified against the pinned 4.127.1
  by reading its own `--help`, not assumed:
  - `npx wrangler versions list` — the 10 most recent versions;
  - `npx wrangler versions view <version-id>` — one version's detail;
  - `npx wrangler deployments status` — what is live right now;
  - `npx wrangler rollback [version-id]`, with `-m` for the reason.

  Two caveats, both honest. The commands' *surface* is verified; **no rollback has
  ever been executed on this Worker**, so that it succeeds is untested. And
  ⚠️ **rolling back to a version older than `36f63def` (2026-08-29) would restore
  the configuration that had preview URLs enabled** — re-opening the door this
  setup closed. That last point is INFERRED from `preview_urls` being deploy-time
  config rather than measured, which is precisely why the rule above says *every*
  deploy runs the probe: a rollback is a deploy.
- **The GitHub Workers Builds integration stays disconnected.** Delegating to a
  session is not push-to-deploy. A session deploy is deliberate and reported; a
  push deploy is neither, and would deploy whatever landed on a branch without
  anyone choosing to. That distinction is the whole point, and it is why the
  integration was removed on 2026-08-27 rather than configured.

Then point the app at it, which is **two config values** and no code:

```jsonc
// Config/TrackingConfig.json
"matching": {
  "base_url": "https://kamome-routing.<your-subdomain>.workers.dev",
  "api_key_required": false,   // the Worker holds the key; the app carries none
  …
}
```

`api_key_required: false` is what stops the app disabling routing for want of a
key it is no longer supposed to have. With it left `true` and no key present, a
build routes nothing — which is the correct behaviour when the endpoint *is*
Geoapify, and is why the flag exists rather than the rule simply being deleted:
a keyless build must not fire coordinate-bearing requests that can only be
refused (§0 — exposure for nothing).

`Config/Secrets.xcconfig` becomes unnecessary at that point. Leaving a key in it
is harmless — the app just stops sending one — but delete it from any machine
that builds for distribution.

## The Node version trap

**This cost a deploy on 2026-08-28.** `npx wrangler deploy` died with:

```
Error: You installed workerd on another platform than the one you're currently
using. The "@cloudflare/workerd-darwin-64" package is present but this platform
needs "@cloudflare/workerd-darwin-arm64".
```

The error names neither Node nor a version, so here is what it means. wrangler
pulls `workerd` as a set of platform-specific optional dependencies, each
declaring `cpu` and `os`; npm installs whichever matches `process.arch` **at
install time**. A login shell on this machine defaulted to **Node 17, which is an
x64 build running under Rosetta**, so npm resolved the Intel `workerd` into the
shared `~/.npm/_npx/` cache — and `npx` reuses that cache afterwards even once an
arm64 Node is active.

Purging the cache unblocks it once. It comes back the next time a shell defaults
to 17, which is why the fix is in this directory instead:

- **`package.json` pins `wrangler` exactly** (not `^`), so a deploy tool that
  holds an API key resolves to a known version rather than whatever was latest
  that day.
- **`package-lock.json` carries every platform's `workerd`** with its `cpu`/`os`
  constraints, so one committed lockfile still resolves correctly per machine —
  `npm ci` picks arm64 here and x64 elsewhere.
- **`node_modules/` is local to this directory**, so `npx wrangler` finds it
  before it ever consults the shared npx cache.
- **`.npmrc` sets `engine-strict=true`**, so running this under Node 17 now fails
  with `EBADENGINE … Required: {"node":">=22.0.0"} Actual: v17.0.0` rather than
  the workerd message above. A clear failure instead of a puzzling one.

If `npm ci` reports `EBADENGINE`, switch Node (`nvm use 24.3.0`) — do not work
around it by deleting `.npmrc`. wrangler 4.127.1 genuinely requires Node ≥ 22.

## What this Worker will and will not do

- **Forwards only `GET /v1/routing`.** Anything else is 404. `/v1/mapmatching`
  is absent on purpose: recorded traces are not sent anywhere today
  (`Docs/decisions.md` 2026-08-20 (d)), and an open proxy is somebody else's
  bill. Capture Beta adds it deliberately or not at all.
- **Never logs.** No `console.log`, and `[observability] enabled = false` in
  `wrangler.toml`. Two things stay off after deploy, and they are easy to switch
  on by accident:
  - **Logpush** — records request URLs, which here means coordinates.
  - **`wrangler tail`** — streams live requests to your terminal, and here a
    request line *is* a trip's coordinates. Do not run it against production.
    **This used to say "reproduce on a preview deployment". That path is gone on
    purpose** — see below. Debug against something that holds no production
    secret: `npx wrangler dev` locally with your own key in `Deploy/worker/.dev.vars`
    (gitignored since 2026-08-28 — it is a plaintext key, and Wrangler does not
    ignore it for you), or a throwaway Worker under a different `name =`.
- **Has no preview URLs.** `preview_urls = false` in `wrangler.toml`, explicitly
  rather than by default. See the next section — it is the reason the debugging
  advice above changed.
- **Forwards no client headers**, so Geoapify sees Cloudflare's egress address
  rather than the device's. That is a genuine improvement to what
  `Docs/pre-launch.md`'s privacy notice has to say, and it should be said only
  once the Worker is actually deployed.
- **Never answers 400 for its own problems.** A missing secret is 503 and an
  upstream connection failure is 502, because the app reads 400 as "no road
  joins these places" and would draw that leg dashed permanently. Broken
  plumbing has to arrive as "nobody answered", which is retryable.
- **Refuses above a per-day ceiling.** A KV counter keyed by UTC date; above
  `DAILY_REQUEST_CEILING` the Worker answers **429 with `Retry-After` set to the
  seconds until UTC midnight**, and does not call Geoapify. See "The spend
  ceiling" below.
- **Fails closed when it cannot count.** No KV binding, no usable ceiling, or a
  KV error is **503**, not a forwarded request. A Worker that cannot count is a
  Worker with no ceiling, and forwarding anyway is the silent fallback that would
  make the proxy only *look* capped.
- **Passes `Retry-After` through.** Geoapify itself never sends 429 — it sheds
  load as a TCP reset — so this hop is the only one that can distinguish "busy"
  from "unreachable". It is why `RouteProviderFailure.rateLimited` is still in
  the app (`HANDOFF.md` item 2).

## The spend ceiling

**Built 2026-09-04.** The counter sits in `src/index.js` after the secret check
and before the upstream fetch — 🔴 **the only place a ceiling can exist for
Kamome.** VERIFIED from Geoapify's own pricing pages, 2026-08-29: their limits
are *soft on every tier*, there is **no customer-settable cap**, and escalation
ends in **account blocking**. The failure it guards is not a daily outage that
clears at midnight; it is every user losing routing until Chiu resolves it with
the provider by hand.

| what | where |
|---|---|
| the number | `DAILY_REQUEST_CEILING` in `wrangler.toml` — **2000/day, Chiu's number**, arithmetic beside it. Never a literal in the source, and **never** in `Config/TrackingConfig.json`: that is the app's config and the app never sees this value. |
| the storage | `KAMOME_BUDGET`, one key per UTC day, `routing-requests-YYYY-MM-DD`, expiring an hour after its day. |
| over the ceiling | **429**, `Retry-After` = seconds to UTC midnight, empty body, upstream never called. |
| cannot count | **503** — fail closed. |

Two choices worth knowing before you change anything here:

- ⚠️ **The count can overshoot slightly under concurrency, and that is
  accepted.** KV is eventually consistent, so simultaneous requests can read the
  same value. A Durable Object would be exact, and it costs a class, a migration
  and a round trip to one object on every request. A ceiling set well below the
  provider's soft limit does not need to be exact; it needs to exist. **Do not
  silently switch to a DO.**
- **The request is counted before the fetch, not after.** That is the only
  ordering in which the stored number bounds what is actually forwarded. It
  over-counts requests that end at 502 — those never reached Geoapify and cost no
  credit — and over-counting is the safe direction for a ceiling.

**Positive control, and re-run it after any change here**, because a gate nobody
has seen fire is a gate nobody should trust:

```bash
cd Deploy/worker && npx wrangler dev --port 8799 --var DAILY_REQUEST_CEILING:1
```

Then two requests to `/v1/routing` with **public landmark coordinates only** (§0
— never a real trip). The second must be `429` with a positive integer
`Retry-After`. Measured 2026-09-04 with a placeholder key in `.dev.vars`, which
is why the first line is Geoapify's own 401 rather than a 200 — the point is that
it reached the provider and was counted, and the second never did:

```
=== request 1 ===
HTTP/1.1 401 Unauthorized
=== request 2 ===
HTTP/1.1 429 Too Many Requests
Retry-After: 65312
```

`wrangler dev` binds KV **locally** (its startup banner says `local`), so this
touches no namespace in Chiu's account.

**In production, the cheap check is the 200.** Every KV fault fails closed at
503, so a successful `/v1/routing` proves the binding is attached, the ceiling
parsed and the counter read and wrote. Read the day's key directly with:

```bash
npx wrangler kv key get "routing-requests-$(date -u +%Y-%m-%d)" \
  --namespace-id d533d7ee1b7d4a3c8ffcf51fe8701b33 --remote
```

⚠️ **Expect a stale read for tens of seconds.** Measured 2026-09-04: a read 2 s
after a write still returned the pre-write value; the same key 30 s later
returned the new one. That is KV's read cache, it is the mechanism behind the
accepted overshoot, and **it means a counter that "did not increment" is usually
a cache, not a bug — wait a minute before concluding anything.**

## Why `preview_urls = false`

**Measured 2026-08-27, not assumed.** With preview URLs on, Cloudflare gives every
deployed version its own permanent public hostname —
`<first-8-of-version-id>-kamome-routing.<subdomain>.workers.dev` — running the same
code with the same `GEOAPIFY_API_KEY` binding. The preview host of version
`75c481ad` answered a keyless `GET /v1/routing` with **HTTP 200 and 9,842 bytes of
route**, byte-identical to what production returned for the same public landmark
coordinates. The hostname was derived from the Version ID at the first attempt, so
it costs an attacker nothing to find, and `x-robots-tag: noindex` — which
Cloudflare sets on these — stops indexing, not access.

So every deploy was leaving a permanent extra public door onto Kamome's Geoapify
quota. Kamome does not use versioned or gradual deploys, so turning it off costs
nothing.

**Do not turn it back on to get a debugging endpoint.** That trades a guessable
public copy of the production secret for convenience `wrangler dev` already
provides. If you ever genuinely need a deployed preview, deploy it as a separate
Worker that holds no production secret.

### Closed, and measured closed — 2026-08-29

Chiu redeployed as version `36f63def`. The door is shut, and the discriminator is
the body: a Cloudflare miss returns a 17-byte `text/plain` page, while this
Worker's own `refuse(404)` returns nothing at all.

| host | before | after |
|---|---|---|
| `kamome-routing` `/v1/routing` | 200, 9,842 B of route | **200, 9,842 B — unchanged** |
| `kamome-routing` `/` | 404, **empty** (the Worker) | 404, **empty** — still the Worker |
| `75c481ad-…` `/` | 404, empty, `noindex` | **404, 17 B `error code: 1042`** |
| `75c481ad-…` `/v1/routing` | **200, 9,842 B of route** | **404, 17 B `error code: 1042`** |
| `36f63def-…` `/` and `/v1/routing` | — | **404, 17 B `error code: 1042`** |
| control, never deployed | 404, 17 B `error code: 1042` | unchanged |

Production staying an empty-bodied 404 on `/` is the positive control in the same
run: the Worker is still there, and the preview hostnames are no longer it. The new
version opened no door of its own.

### Re-measured 2026-09-04 — the ceiling's deploy opened no door

Version `5b33922c` (from merged `main` `07fdd14`). Same discriminator, same
result: production unchanged, both new preview hostnames are Cloudflare misses.

| host | result |
|---|---|
| `kamome-routing` `/v1/routing` | **200, 9,842 B** — byte-identical to 2026-08-29 |
| `kamome-routing` `/` | **404, empty** — still the Worker |
| `5b33922c-…` `/` and `/v1/routing` | **404, 17 B `error code: 1042`** |
| control, never deployed | **404, 17 B** — unchanged |

That first row does double duty now: **it is also the proof the spend counter is
live**, because every KV fault fails closed at 503. See "The spend ceiling".

**These are the pass conditions for every future deploy.** Re-run
`~/Kamome-wt/probe.sh <first-8-of-Version-ID>` — public landmark coordinates only
(§0), never a real trip.

## Checking it before you deploy

```bash
cd Deploy/worker && npm test
```

Nineteen assertions against a stubbed upstream — no Cloudflare, no key, no network.
Needs Node 22+ to match `package.json`'s `engines` (run on v24.3.0); the globals
it actually uses — `fetch`/`Request`/`Response` — have been there since 18. It
is **not** part of `xcodebuild test`: this repository's CI is the Xcode suite,
and a deploy artifact should not invent a second one.

## Capacity

Cloudflare's free tier is 100,000 requests a day. Kamome spends one request per
drive leg — 9 on Miyakojima, 17 on New Zealand, 58 on Iceland — so the binding
limit is Geoapify's 3,000 credits a day underneath, not this.

## Not built, and deliberately

- ~~**A per-day budget counter.**~~ ✅ **BUILT 2026-09-04** — see "The spend
  ceiling" above. This bullet is kept as a stub because the reasoning that made it
  mandatory is now in that section and in `Docs/decisions.md` 2026-09-04.
- **A burst rate limit — a speed bump, not the answer.** Cloudflare's rate-limiting
  binding caps requests per 10 or 60 seconds; **60 seconds is its maximum period**,
  so it cannot express a daily total, which is the thing actually at risk. Kamome's
  own legitimate burst is ~29 requests/minute (Iceland's 58 legs inside
  `matching.trip_budget_s` 120), so any per-IP limit must sit above ~30/min or it
  throttles a genuine import — at which point a single-IP attacker still exhausts a
  3,000-credit day in under an hour. Worth having eventually; never worth mistaking
  for the ceiling.
- **App Attest.** `Docs/pre-launch.md` lists it as optional afterwards, so that
  only requests from a genuine install are served. Until then the Worker is open
  to anyone who finds its URL. **That was described here as "a bill risk, not a
  privacy one"; the soft-limits finding above makes it an availability risk too** —
  no card means no bill, but it never meant no harm. It remains the reason the path
  allowlist is as narrow as it is.

  Both this and the budget counter are **additive to the current handler**, checked
  by reading it: `fetch` is a flat sequence of early-return guards that all read
  from `env`, so a counter slots in after the secret check and an attestation check
  after the path allowlist. Neither needs a router or a restructure. The only edit
  to existing code either implies is `refuse()` taking optional headers, so a
  self-generated 429 can carry `Retry-After`.
