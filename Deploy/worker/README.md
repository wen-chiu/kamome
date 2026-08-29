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
- **Passes `Retry-After` through.** Geoapify itself never sends 429 — it sheds
  load as a TCP reset — so this hop is the only one that can distinguish "busy"
  from "unreachable". It is why `RouteProviderFailure.rateLimited` is still in
  the app (`HANDOFF.md` item 2).

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

## Checking it before you deploy

```bash
cd Deploy/worker && npm test
```

Nine assertions against a stubbed upstream — no Cloudflare, no key, no network.
Needs Node 22+ to match `package.json`'s `engines` (run on v24.3.0); the globals
it actually uses — `fetch`/`Request`/`Response` — have been there since 18. It
is **not** part of `xcodebuild test`: this repository's CI is the Xcode suite,
and a deploy artifact should not invent a second one.

## Capacity

Cloudflare's free tier is 100,000 requests a day. Kamome spends one request per
drive leg — 9 on Miyakojima, 17 on New Zealand, 58 on Iceland — so the binding
limit is Geoapify's 3,000 credits a day underneath, not this.

## Not built, and deliberately

- **Rate limiting.** The Worker *can* answer 429 and the app understands it, but
  nothing here throttles: that needs KV or a Durable Object, and there is no
  traffic to shape yet.
- **App Attest.** `Docs/pre-launch.md` lists it as optional afterwards, so that
  only requests from a genuine install are served. Until then the Worker is open
  to anyone who finds its URL — which is a bill risk, not a privacy one, and is
  the reason the path allowlist is as narrow as it is.
