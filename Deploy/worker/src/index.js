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
 *     can exist. It lives in one Durable Object, `RoutingBudget`, at the bottom
 *     of this file (ADR 2026-10-03, which replaced the KV counter).
 *
 *  4. **A day's ceiling cannot see a burst.** One address could still spend the
 *     whole day's ceiling inside a minute, and every other user would be refused
 *     until UTC midnight. The per-IP burst limit below stops that. It is the
 *     ceiling's complement and never its replacement: 60 s is Cloudflare's
 *     longest period, so a burst limit cannot express a daily total, and a daily
 *     total cannot express a burst.
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
 * The one counter object's name. **One object for the whole Worker, never one
 * per day**: an object is placed near whoever first asks for it and never moves
 * (VERIFIED from Cloudflare's docs, 2026-10-03), so a per-day object would land
 * somewhere different every day. The day is a row inside it instead.
 *
 * Renaming this starts a fresh, empty counter in a new place — the way to move
 * the object if `BUDGET_LOCATION_HINT` turns out wrong. It also resets the
 * current day's count, so the day it changes can spend up to twice the ceiling.
 */
const BUDGET_OBJECT_NAME = "routing-budget";

/**
 * How many UTC days of counts the object keeps. Only today's row is ever
 * consulted; the rest are there so that "what did yesterday spend?" has an
 * answer in the dashboard's Data Studio — the question #204 could not answer,
 * because the KV key had already expired. The rows hold a date and a count and
 * nothing else.
 */
const BUDGET_HISTORY_DAYS = 31;

/** The counter's internal address. Never public: a Durable Object is reachable only through its binding. */
const BUDGET_SPEND_URL = "https://routing-budget.internal/spend";

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
    // and because the day's counter cannot tell one greedy address from many
    // users: without this, one client could spend the whole day's ceiling in a
    // minute and leave everyone else refused until UTC midnight. A refusal here
    // never reaches the counter and never reaches Geoapify, so it costs no
    // credit and is not counted against the day.
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
    //
    // The count lives in one Durable Object (ADR 2026-10-03). It replaced a KV
    // counter, which on the free plan allows 1,000 writes a day and one write a
    // second to a key — so it failed at half the ceiling it was meant to hold
    // (#204). The object answers one question per request, "count this one if
    // the day has room", and answers it exactly: it handles one request at a
    // time and the check and the increment run with no `await` between them.
    const ceiling = Number(env.DAILY_REQUEST_CEILING);
    if (typeof env.KAMOME_BUDGET?.idFromName !== "function"
      || typeof env.KAMOME_BUDGET?.get !== "function"
      || !Number.isFinite(ceiling) || ceiling <= 0) {
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
    const secondsLeftToday = secondsUntilUtcMidnight(now);

    // Counted *before* the fetch, not after. This is the only ordering in which
    // the stored number bounds what actually gets forwarded. It over-counts the
    // requests that end at 502 — those never reached Geoapify and cost no credit
    // — and over-counting is the safe direction for a ceiling.
    let allowed;
    try {
      allowed = await spendOne(env, now, ceiling);
    } catch {
      return refuse(503); // Fail closed, for the reason above.
    }
    if (allowed === false) {
      // The one status this Worker generates itself instead of passing through.
      // `Retry-After` is the seconds to UTC midnight, which is exactly when the
      // day rolls — so the app's `RouteProviderFailure.rateLimited` back-off
      // matches the real reset instead of guessing at it.
      return refuse(429, { "retry-after": String(secondsLeftToday) });
    }
    if (allowed !== true) {
      // Strict, like the burst limiter's answer: a counter that says anything
      // but a clean yes or no is a counter this Worker does not understand.
      return refuse(503);
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

/**
 * Asks the counter object to count one request for `now`'s UTC day. Answers
 * `true` (counted, forward it), `false` (the day is spent), or anything else,
 * which the caller treats as a fault. Throws on any transport failure.
 *
 * What crosses to the object is a date, the ceiling and a cut-off date —
 * never a coordinate, never an address.
 */
async function spendOne(env, now, ceiling) {
  const id = env.KAMOME_BUDGET.idFromName(BUDGET_OBJECT_NAME);
  // The hint only shapes where the object is first created; afterwards it is
  // ignored (VERIFIED, Cloudflare docs 2026-10-03). Absent means "near the first
  // caller", which is the platform's default.
  const hint = env.BUDGET_LOCATION_HINT;
  const counter = hint ? env.KAMOME_BUDGET.get(id, { locationHint: hint }) : env.KAMOME_BUDGET.get(id);

  const spend = new URL(BUDGET_SPEND_URL);
  spend.searchParams.set("day", utcDayKey(now));
  spend.searchParams.set("ceiling", String(ceiling));
  spend.searchParams.set("keep_from", utcDayKey(new Date(now.getTime() - BUDGET_HISTORY_DAYS * 86_400_000)));

  const response = await counter.fetch(spend.toString(), { method: "POST" });
  if (response.status !== 200) return undefined;
  const answer = await response.json();
  return answer?.allowed;
}

/** A UTC day key, and nothing else, is what the counter accepts as a day. */
const DAY_KEY = /^\d{4}-\d{2}-\d{2}$/;

/**
 * The spend ceiling's counter: one SQLite-backed Durable Object holding one row
 * per UTC day (ADR 2026-10-03).
 *
 * **Why this is exact, which KV never was.** An object runs one request at a
 * time, and `ctx.storage.sql` is synchronous, so the read, the comparison and
 * the increment below happen with no `await` between them — no second request
 * can read the same count. Concurrent requests queue for milliseconds instead of
 * overshooting.
 *
 * A plain class with `fetch()`, not `extends DurableObject` with RPC, on
 * purpose: RPC needs `import … from "cloudflare:workers"`, which Node cannot
 * resolve, and then this class could not run under `npm test` against a real
 * SQLite. `fetch()` is the older call style and the one that needs nothing.
 */
export class RoutingBudget {
  constructor(ctx) {
    this.sql = ctx.storage.sql;
    this.sql.exec("CREATE TABLE IF NOT EXISTS spend (day TEXT PRIMARY KEY, count INTEGER NOT NULL)");
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/spend") return refuse(404);

    const day = url.searchParams.get("day");
    const keepFrom = url.searchParams.get("keep_from");
    const ceiling = Number(url.searchParams.get("ceiling"));
    if (!DAY_KEY.test(day ?? "") || !DAY_KEY.test(keepFrom ?? "")
      || !Number.isInteger(ceiling) || ceiling <= 0) {
      return refuse(400); // Only the Worker calls this; the Worker reads any non-200 as a fault.
    }

    const row = this.sql.exec("SELECT count FROM spend WHERE day = ?", day).toArray()[0];
    const spent = row === undefined ? 0 : row.count;
    if (!Number.isInteger(spent) || spent < 0) {
      // Something other than this class wrote the row. Treating it as zero is
      // how a ceiling silently becomes no ceiling.
      return refuse(500);
    }
    if (spent >= ceiling) {
      return Response.json({ allowed: false });
    }

    this.sql.exec(
      "INSERT INTO spend (day, count) VALUES (?, 1) ON CONFLICT(day) DO UPDATE SET count = count + 1",
      day
    );
    if (row === undefined) {
      // The day's first request: drop what is older than the history window.
      // Once a day, so it costs nothing worth counting.
      this.sql.exec("DELETE FROM spend WHERE day < ?", keepFrom);
    }
    return Response.json({ allowed: true });
  }
}
