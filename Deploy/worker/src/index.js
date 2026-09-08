/**
 * Kamome routing proxy — the API key's only home.
 *
 * The app ships with no routing key at all; it calls this Worker, which adds the
 * key and forwards to Geoapify. Everything about this file follows from two
 * requirements in `Docs/pre-launch.md`, and neither is decoration:
 *
 *  1. **The key never reaches a device.** A key in the IPA is readable by anyone
 *     who unpacks a build, and provider-side restriction (IP, referrer, CORS)
 *     cannot save a native app.
 *  2. **This hop must be no-log.** A proxy *adds* a party that sees every trip's
 *     coordinates. If it logs them, §0's story gets worse while appearing to get
 *     better. Nothing here writes a request line, and observability is turned off
 *     in `wrangler.toml` rather than left to whoever deploys it.
 *
 *  3. **This hop must carry a spend ceiling.** Geoapify's limits are soft on
 *     every tier with no customer-settable cap, so an uncapped proxy trades a
 *     key leak for an open quota — and the end of that road is account blocking,
 *     not a daily outage. The per-day counter below is the only place a ceiling
 *     can exist.
 *
 *  4. **A day's ceiling cannot see a burst.** KV's read cache is tens of seconds
 *     wide, so the counter can still read low while one client spends the whole
 *     day. The per-IP burst limit below closes that window. It is the ceiling's
 *     complement and never its replacement: 60 s is Cloudflare's longest period,
 *     so a burst limit cannot express a daily total, and a daily total cannot
 *     express a burst.
 *
 * A side effect worth knowing for the privacy notice: Geoapify sees Cloudflare's
 * egress address, not the device's, because this builds a fresh upstream request
 * and forwards no client headers.
 */

const UPSTREAM = "https://api.geoapify.com";

/**
 * Only what the app actually calls. `/v1/mapmatching` is deliberately absent —
 * recorded traces are not sent anywhere today (`Docs/decisions.md` 2026-08-20
 * (d)), and an open proxy is a bill someone else can run up. Adding it when
 * Capture Beta needs it is one line here plus a POST branch below.
 */
const ALLOWED_PATHS = new Set(["/v1/routing"]);

/**
 * The spend ceiling's key space. One counter per UTC day, so the budget resets
 * at a boundary that is the same everywhere and costs nobody a timezone
 * decision. The prefix exists so a second counter can be added later without
 * colliding with this one.
 */
const BUDGET_KEY_PREFIX = "routing-requests-";

/**
 * How long a day's counter outlives its own day before KV drops it. The key is
 * only ever read on the day it names, so an hour of slack is generous; it is
 * here so the namespace does not grow a key per day forever. Cloudflare's
 * minimum `expirationTtl` is 60 s and this is always well above it.
 */
const COUNTER_TTL_SLACK_S = 3600;

/**
 * The bucket a request with no `CF-Connecting-IP` falls into. Cloudflare always
 * sets that header in production, so this is reached only by something that is
 * not Cloudflare — `wrangler dev`, or a future path nobody has thought about.
 * Those share **one** bucket rather than skipping the limit: an unattributable
 * request is the one most worth rate-limiting, and a per-request fallback key
 * would hand any caller an unlimited supply of empty buckets.
 */
const NO_CONNECTING_IP = "no-connecting-ip";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method !== "GET") {
      return refuse(405);
    }
    if (!ALLOWED_PATHS.has(url.pathname)) {
      return refuse(404);
    }
    if (!env.GEOAPIFY_API_KEY) {
      // A Worker deployed without its secret is broken plumbing, not a verdict
      // about the geography. 502/503 reaches the app as `.refused`, which it
      // reports as "we can't reach the routing service" and treats as
      // retryable. Answering 400 here would make the leg draw dashed *forever*
      // as though no road existed — the one mistake this proxy must not make.
      return refuse(503);
    }

    // ── The per-IP burst limit ──────────────────────────────────────────────
    //
    // Checked **before** the per-day counter, because it is the cheaper guard
    // and because the burst it stops is the one the counter provably cannot see:
    // KV's read cache is tens of seconds wide (measured 2026-09-04), so a client
    // could spend the whole day inside a single window while the stored number
    // still read low. A refusal here never reaches KV and never reaches
    // Geoapify, so it costs no credit and is not counted against the day.
    //
    // The threshold is `simple.limit` on the `[[ratelimits]]` binding in
    // `wrangler.toml` — 60/min — and it is not visible from here at all: the
    // binding exposes `.limit()` and nothing else. That is deliberate. There is
    // no number in this file to drift from the deployed one.
    //
    // ⚠️ The limit is **per Cloudflare location**, VERIFIED from their docs
    // 2026-09-05, so this half bounds one address in one place and the per-day
    // ceiling below bounds the total. Complements, not substitutes — the daily
    // ceiling cannot express a burst and this cannot express a day.
    const burstRetryAfterS = Number(env.BURST_RETRY_AFTER_S);
    if (typeof env.KAMOME_BURST?.limit !== "function"
      || !Number.isFinite(burstRetryAfterS) || burstRetryAfterS <= 0) {
      // Fail closed, exactly as the ceiling does, and for a sharper reason: a
      // Worker whose burst limiter is missing looks hardened and is not, and
      // this is the deploy whose whole purpose is to make the URL safe to ship.
      // It also makes the after-probe worth more — every fault here is a 503,
      // so a production 200 now proves *both* guards are wired, not just one.
      return refuse(503);
    }

    let withinBurst;
    try {
      // Keyed by the connecting address. That address never reaches a log, a
      // body or a header — `refuse()` answers empty — and Cloudflare already
      // holds it by virtue of terminating the connection, so this moves nothing
      // that was not already there.
      ({ success: withinBurst } = await env.KAMOME_BURST.limit({ key: burstKey(request) }));
    } catch {
      return refuse(503); // Fail closed, for the reason above.
    }
    if (withinBurst !== true) {
      // Strict `!== true`: a limiter that answers anything other than a clean
      // success refuses. `Retry-After` is one whole period, which is an upper
      // bound on the wall-clock-aligned window rather than a guess at it.
      return refuse(429, { "retry-after": String(Math.ceil(burstRetryAfterS)) });
    }

    // ── The spend ceiling ───────────────────────────────────────────────────
    //
    // 🔴 This Worker is the only place a ceiling can exist. VERIFIED from
    // Geoapify's own pricing pages, 2026-08-29: their limits are *soft on every
    // tier*, there is no customer-settable cap, and escalation ends in account
    // blocking. So the failure this guards is not a daily outage that clears at
    // midnight — it is every user losing routing until Chiu resolves it with the
    // provider by hand.
    //
    // The number is `DAILY_REQUEST_CEILING` in `wrangler.toml`, never a literal
    // here. It arrives from `env` as a **string**, so it is converted once, at
    // the top, rather than at the comparison.
    const ceiling = Number(env.DAILY_REQUEST_CEILING);
    if (!env.KAMOME_BUDGET || !Number.isFinite(ceiling) || ceiling <= 0) {
      // Fail closed. A Worker that cannot count is a Worker with no ceiling,
      // which is the exact condition this guard exists to prevent — forwarding
      // anyway would be the silent fallback that makes the proxy *look* capped.
      // 503 for the same reason as the missing secret above: broken plumbing
      // the app retries, never a 400 that draws the leg dashed forever.
      return refuse(503);
    }

    // Read through `Date.now()` rather than the system clock directly, so a test
    // can move the clock and prove the counter rolls at UTC midnight.
    const now = new Date(Date.now());
    const budgetKey = BUDGET_KEY_PREFIX + utcDayKey(now);
    const secondsLeftToday = secondsUntilUtcMidnight(now);

    let spentToday;
    try {
      const stored = await env.KAMOME_BUDGET.get(budgetKey);
      // `null` is the day's first request, not a fault. Anything else that does
      // not parse means something other than this Worker wrote to the namespace,
      // and treating it as zero is how a ceiling silently becomes no ceiling.
      // `Number("")` is 0, not NaN, so a blank value is rejected explicitly
      // rather than left to read as an unspent day.
      spentToday = stored === null ? 0
        : stored.trim() === "" ? NaN
        : Number(stored);
      if (!Number.isFinite(spentToday) || spentToday < 0) {
        return refuse(503); // Fail closed, for the reason above.
      }
    } catch {
      return refuse(503); // Fail closed, for the reason above.
    }

    if (spentToday >= ceiling) {
      // The one status this Worker generates itself instead of passing through.
      // `Retry-After` is the seconds to UTC midnight, which is exactly when the
      // key rolls — so the app's `RouteProviderFailure.rateLimited` back-off
      // matches the real reset instead of guessing at it.
      return refuse(429, { "retry-after": String(secondsLeftToday) });
    }

    // Counted *before* the fetch, not after. This is the only ordering in which
    // the stored number bounds what actually gets forwarded. It over-counts the
    // requests that end at 502 — those never reached Geoapify and cost no credit
    // — and over-counting is the safe direction for a ceiling.
    //
    // ⚠️ KV is eventually consistent, so concurrent requests can read the same
    // value and the count can overshoot slightly. **That is acceptable for a
    // ceiling**, and it is a deliberate choice over a Durable Object, which is
    // exact but adds a class, a migration, and a round trip to one object on
    // every request. A ceiling set well below the provider's soft limit does not
    // need to be exact; it needs to exist. Do not silently switch to a DO.
    try {
      await env.KAMOME_BUDGET.put(budgetKey, String(spentToday + 1), {
        expirationTtl: secondsLeftToday + COUNTER_TTL_SLACK_S
      });
    } catch {
      return refuse(503); // Fail closed: an uncounted request is an uncapped one.
    }

    const upstream = new URL(UPSTREAM + url.pathname);
    for (const [name, value] of url.searchParams) {
      // A client-supplied key is ignored rather than forwarded: the app sends
      // none, and anything calling this Worker with one is not the app.
      if (name.toLowerCase() === "apikey") continue;
      upstream.searchParams.append(name, value);
    }
    upstream.searchParams.set("apiKey", env.GEOAPIFY_API_KEY);

    let response;
    try {
      // A fresh request: no client headers travel onward, so nothing about the
      // device — user agent, language, connecting IP — reaches the provider.
      response = await fetch(upstream, {
        method: "GET",
        headers: { accept: "application/json" }
      });
    } catch {
      // Deliberately not logged, and deliberately not 400.
      return refuse(502);
    }

    const headers = { "content-type": response.headers.get("content-type") ?? "application/json" };
    // The app tells "busy, try later" apart from "no road here", and this is the
    // only hop that can say so: Geoapify sheds load as a TCP reset and never
    // sends 429. Passing the header through keeps `RouteProviderFailure
    // .rateLimited` meaningful rather than dead code.
    const retryAfter = response.headers.get("retry-after");
    if (retryAfter) headers["retry-after"] = retryAfter;

    return new Response(response.body, { status: response.status, headers });
  }
};

/**
 * An empty-bodied status. No message, because a message is a place to leak one.
 * `headers` is optional and exists for exactly one caller: the self-generated
 * 429 above, which must carry `Retry-After` to be worth anything to the app.
 */
function refuse(status, headers) {
  return new Response(null, { status, headers });
}

/**
 * The burst limit's bucket for one request: the connecting address, or the
 * shared fallback when Cloudflare did not set one. `||` rather than `??` on
 * purpose — an empty header is as absent as a missing one.
 */
function burstKey(request) {
  return request.headers.get("CF-Connecting-IP") || NO_CONNECTING_IP;
}

/** `YYYY-MM-DD` in UTC — the counter's day, and the only timezone in this file. */
function utcDayKey(now) {
  return now.toISOString().slice(0, 10);
}

/**
 * Whole seconds until the next UTC midnight, floored at 1. Always a positive
 * integer: `Retry-After: 0` tells a client to retry immediately, which is the
 * opposite of what a spent budget means.
 */
function secondsUntilUtcMidnight(now) {
  const midnight = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(1, Math.ceil((midnight - now.getTime()) / 1000));
}
