/**
 * The proxy's behaviour, checked without Cloudflare.
 *
 * `export default { fetch }` is a plain module, so the handler runs under any
 * Node with `fetch`/`Request`/`Response` globals (18+). The upstream is stubbed,
 * so nothing here contacts Geoapify and no key is needed.
 *
 *   node Deploy/worker/test/worker.test.mjs
 *
 * Not part of `xcodebuild test` — this repository's CI is the Xcode suite, and a
 * deploy artifact should not invent a second CI. Run it when you touch the
 * Worker.
 */
import assert from "node:assert/strict";
import worker from "../src/index.js";

const ROUTE = "https://kamome-routing.example.workers.dev/v1/routing"
  + "?waypoints=64.310400,-20.302400%7C64.327100,-20.119900&mode=drive";

/**
 * An in-memory stand-in for the KV binding — the two methods the Worker calls
 * and nothing else. `throws` makes a KV outage testable, which is the branch
 * that must fail closed rather than forward uncounted.
 */
function stubKV({ seed = {}, throws = false } = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key) {
      if (throws) throw new Error("KV unavailable");
      return store.has(key) ? store.get(key) : null;
    },
    async put(key, value, options) {
      if (throws) throw new Error("KV unavailable");
      store.set(key, value);
      this.lastPutOptions = options;
    }
  };
}

/**
 * An in-memory stand-in for the rate-limiting binding. It models the platform's
 * contract as Cloudflare documents it — `limit({ key })` answering
 * `{ success }`, one fixed-window counter per key — and nothing more, because
 * nothing more is observable from the Worker.
 *
 * ⚠️ **A stub is a model, and this one is only as good as that contract.** The
 * integration control that a stub cannot give is a `wrangler dev` run against
 * the real binding; it is in `README.md` under "The burst limit".
 *
 * `answer` forces a fixed reply, which is how the "anything but a clean success
 * refuses" branch is reached. `throws` makes a limiter outage testable — the
 * branch that must fail closed rather than forward unlimited.
 */
function stubRateLimiter({ limit = 60, throws = false, answer } = {}) {
  const counts = new Map();
  return {
    counts,
    seen: [],
    async limit(options) {
      if (throws) throw new Error("rate limiter unavailable");
      this.seen.push(options);
      if (answer !== undefined) return answer;
      const spent = (counts.get(options.key) ?? 0) + 1;
      counts.set(options.key, spent);
      return { success: spent <= limit };
    }
  };
}

/**
 * A fresh env per call, so one test's spending never leaks into the next. The
 * ceiling is a **string**, exactly as `[vars]` in `wrangler.toml` delivers it —
 * a stub that handed over a number would hide the conversion bug it exists to
 * catch, and the same goes for `BURST_RETRY_AFTER_S`.
 */
function freshEnv(overrides = {}) {
  return {
    GEOAPIFY_API_KEY: "worker-secret",
    DAILY_REQUEST_CEILING: "2000",
    BURST_RETRY_AFTER_S: "60",
    KAMOME_BUDGET: stubKV(),
    KAMOME_BURST: stubRateLimiter(),
    ...overrides
  };
}

/**
 * Swaps in a stub upstream and returns what it saw. `at` freezes `Date.now()`,
 * which is how the UTC-midnight rollover is exercised without waiting for it.
 */
async function callWorker(url, { env = freshEnv(), method = "GET", upstream, at, ip } = {}) {
  const seen = { calls: 0 };
  const restore = stubUpstream(seen, upstream, at);
  try {
    const response = await worker.fetch(request(url, method, ip), env);
    return { response, seen, env };
  } finally {
    restore();
  }
}

/**
 * The same handler, driven **concurrently** against one env — which is the only
 * way to demonstrate a burst. `callWorker` swaps globals per call and restores
 * them in `finally`, so overlapping calls would tear each other's stubs down;
 * this installs them once and takes them away when every request has landed.
 */
async function callWorkerConcurrently(url, { env = freshEnv(), count, ip } = {}) {
  const seen = { calls: 0 };
  const restore = stubUpstream(seen);
  try {
    const responses = await Promise.all(
      Array.from({ length: count }, () => worker.fetch(request(url, "GET", ip), env))
    );
    return { responses, statuses: responses.map((r) => r.status), seen, env };
  } finally {
    restore();
  }
}

/** One inbound request, carrying the connecting address Cloudflare would set. */
function request(url, method, ip) {
  return new Request(url, { method, headers: ip ? { "CF-Connecting-IP": ip } : {} });
}

/** Installs the upstream stub and the frozen clock; returns the undo. */
function stubUpstream(seen, upstream, at) {
  const originalFetch = globalThis.fetch;
  const originalNow = Date.now;
  globalThis.fetch = async (target, init) => {
    seen.calls += 1;
    seen.url = target.toString();
    seen.init = init;
    if (upstream instanceof Error) throw upstream;
    return upstream ?? new Response('{"features":[]}', {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  if (at !== undefined) Date.now = () => new Date(at).getTime();
  return () => {
    globalThis.fetch = originalFetch;
    Date.now = originalNow;
  };
}

const tests = {
  async "the secret is added and the caller's coordinates are forwarded unchanged"() {
    const { response, seen } = await callWorker(ROUTE);
    assert.equal(response.status, 200);
    const upstream = new URL(seen.url);
    assert.equal(upstream.origin + upstream.pathname, "https://api.geoapify.com/v1/routing");
    assert.equal(upstream.searchParams.get("apiKey"), "worker-secret");
    assert.equal(upstream.searchParams.get("mode"), "drive");
    assert.equal(
      upstream.searchParams.get("waypoints"),
      "64.310400,-20.302400|64.327100,-20.119900"
    );
  },

  async "a client-supplied key is dropped rather than forwarded"() {
    const { seen } = await callWorker(ROUTE + "&apiKey=someone-elses-key");
    const keys = new URL(seen.url).searchParams.getAll("apiKey");
    assert.deepEqual(keys, ["worker-secret"]);
  },

  async "no client headers reach the provider, so it never sees the device"() {
    const { seen } = await callWorker(ROUTE);
    assert.deepEqual(seen.init.headers, { accept: "application/json" });
  },

  async "only /v1/routing is proxied"() {
    const { response } = await callWorker(
      "https://kamome-routing.example.workers.dev/v1/geocode/search?text=reykjavik"
    );
    assert.equal(response.status, 404);
  },

  async "POST is refused — /v1/routing is GET-only"() {
    const { response } = await callWorker(ROUTE, { method: "POST" });
    assert.equal(response.status, 405);
  },

  // The two that matter most for honesty: broken plumbing must never arrive at
  // the app as 400, which it reads as "no road joins these places" and draws
  // dashed forever.
  async "a Worker deployed without its secret answers 503, never 400"() {
    const { response } = await callWorker(ROUTE, { env: {} });
    assert.equal(response.status, 503);
  },

  async "an upstream connection failure answers 502, never 400"() {
    const { response } = await callWorker(ROUTE, { upstream: new Error("connection reset") });
    assert.equal(response.status, 502);
  },

  async "the provider's own 400 verdict passes through untouched"() {
    const body = JSON.stringify({ statusCode: 400, message: "No suitable edges near location." });
    const { response } = await callWorker(ROUTE, {
      upstream: new Response(body, { status: 400, headers: { "content-type": "application/json" } })
    });
    assert.equal(response.status, 400);
    assert.equal((await response.json()).message, "No suitable edges near location.");
  },

  async "a 429 keeps its Retry-After, which is the only reason the app can say 'busy'"() {
    const { response } = await callWorker(ROUTE, {
      upstream: new Response(null, { status: 429, headers: { "retry-after": "30" } })
    });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("retry-after"), "30");
  },

  // ── The spend ceiling ────────────────────────────────────────────────────
  // Geoapify's limits are soft on every tier with no customer-settable cap, so
  // this counter is the only ceiling that exists anywhere. Every branch below
  // is one that must not forward an uncounted request.

  async "under the ceiling the request forwards, and the day's counter goes up by one"() {
    const { response, seen, env } = await callWorker(ROUTE, { at: "2026-09-04T12:00:00.000Z" });
    assert.equal(response.status, 200);
    assert.equal(seen.calls, 1);
    assert.equal(env.KAMOME_BUDGET.store.get("routing-requests-2026-09-04"), "1");
  },

  async "at the ceiling the Worker answers 429 itself and never calls Geoapify"() {
    const env = freshEnv({
      DAILY_REQUEST_CEILING: "2000",
      KAMOME_BUDGET: stubKV({ seed: { "routing-requests-2026-09-04": "2000" } })
    });
    const { response, seen } = await callWorker(ROUTE, { env, at: "2026-09-04T12:00:00.000Z" });
    assert.equal(response.status, 429);
    assert.equal(seen.calls, 0, "a refused request must not reach the provider");

    const retryAfter = response.headers.get("retry-after");
    assert.ok(retryAfter !== null, "a self-generated 429 without Retry-After is worthless to the app");
    assert.match(retryAfter, /^\d+$/, "Retry-After must be an integer count of seconds");
    assert.ok(Number(retryAfter) > 0, "Retry-After: 0 would tell the app to retry immediately");
  },

  async "the 429's Retry-After is the seconds remaining until UTC midnight"() {
    const env = freshEnv({
      KAMOME_BUDGET: stubKV({ seed: { "routing-requests-2026-09-04": "2000" } })
    });
    // 21:30:00Z is two and a half hours short of the roll: 9,000 seconds.
    const { response } = await callWorker(ROUTE, { env, at: "2026-09-04T21:30:00.000Z" });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("retry-after"), "9000");
  },

  async "the counter is keyed by UTC date, so a spent budget rolls at UTC midnight"() {
    const env = freshEnv({ DAILY_REQUEST_CEILING: "1" });

    const first = await callWorker(ROUTE, { env, at: "2026-09-04T23:59:00.000Z" });
    assert.equal(first.response.status, 200, "the day's first request is under the ceiling");

    const second = await callWorker(ROUTE, { env, at: "2026-09-04T23:59:30.000Z" });
    assert.equal(second.response.status, 429, "the day's budget is now spent");

    // One minute later, on the other side of the boundary, against the same KV.
    const afterMidnight = await callWorker(ROUTE, { env, at: "2026-09-05T00:01:00.000Z" });
    assert.equal(afterMidnight.response.status, 200, "a new UTC day is a new budget");
    assert.equal(env.KAMOME_BUDGET.store.get("routing-requests-2026-09-04"), "1");
    assert.equal(env.KAMOME_BUDGET.store.get("routing-requests-2026-09-05"), "1");
  },

  async "the ceiling comes from env as a string, and a lower one bites sooner"() {
    // The same assertion the wrangler dev positive control makes by hand: the
    // number is configuration, not a constant compiled into the source.
    const env = freshEnv({ DAILY_REQUEST_CEILING: "1" });
    const first = await callWorker(ROUTE, { env, at: "2026-09-04T12:00:00.000Z" });
    const second = await callWorker(ROUTE, { env, at: "2026-09-04T12:00:01.000Z" });
    assert.equal(first.response.status, 200);
    assert.equal(second.response.status, 429);
  },

  async "the day's counter is set to outlive its own day"() {
    const env = freshEnv();
    await callWorker(ROUTE, { env, at: "2026-09-04T23:00:00.000Z" });
    // An hour to the roll, plus the slack that keeps the namespace from growing
    // a key per day forever — and comfortably above Cloudflare's 60 s minimum.
    assert.equal(env.KAMOME_BUDGET.lastPutOptions.expirationTtl, 3600 + 3600);
  },

  // The three fail-closed branches. A Worker that cannot count is a Worker with
  // no ceiling, and forwarding anyway is the silent fallback that would make the
  // proxy only *look* capped.

  async "a missing KV binding fails closed at 503 and forwards nothing"() {
    const env = freshEnv({ KAMOME_BUDGET: undefined });
    const { response, seen } = await callWorker(ROUTE, { env });
    assert.equal(response.status, 503);
    assert.equal(seen.calls, 0, "an uncountable request must not be forwarded");
  },

  async "a missing or unusable ceiling fails closed at 503, never unlimited"() {
    for (const ceiling of [undefined, "", "lots", "0", "-1"]) {
      const { response, seen } = await callWorker(ROUTE, {
        env: freshEnv({ DAILY_REQUEST_CEILING: ceiling })
      });
      assert.equal(response.status, 503, `ceiling ${JSON.stringify(ceiling)} must not open the quota`);
      assert.equal(seen.calls, 0);
    }
  },

  async "a counter that does not parse fails closed, rather than reading as zero"() {
    // Only something other than this Worker writes such a value, and treating it
    // as zero is how a ceiling silently becomes no ceiling.
    for (const stored of ["", "lots", "-5"]) {
      const env = freshEnv({
        KAMOME_BUDGET: stubKV({ seed: { "routing-requests-2026-09-04": stored } })
      });
      const { response, seen } = await callWorker(ROUTE, { env, at: "2026-09-04T12:00:00.000Z" });
      assert.equal(response.status, 503, `stored ${JSON.stringify(stored)} must not read as zero`);
      assert.equal(seen.calls, 0);
    }
  },

  async "a KV outage fails closed at 503 rather than forwarding uncounted"() {
    const env = freshEnv({ KAMOME_BUDGET: stubKV({ throws: true }) });
    const { response, seen } = await callWorker(ROUTE, { env });
    assert.equal(response.status, 503);
    assert.equal(seen.calls, 0);
  },

  // ── The per-IP burst limit ───────────────────────────────────────────────
  // The day's counter cannot see a burst — KV's read cache is tens of seconds
  // wide, so one client could spend the whole day inside a single window while
  // the stored number still read low. These are the branches that close it.
  // The threshold itself lives in `wrangler.toml`, never here.

  async "under the burst limit the request forwards, keyed by the connecting address"() {
    const env = freshEnv();
    const { response } = await callWorker(ROUTE, { env, ip: "203.0.113.7" });
    assert.equal(response.status, 200);
    assert.deepEqual(env.KAMOME_BURST.seen, [{ key: "203.0.113.7" }],
      "the bucket is the caller's address, and nothing else is sent to the limiter");
  },

  // 🔴 **The positive control.** A gate nobody has watched fire is a gate nobody
  // should trust, and a burst is the one thing a sequential test cannot show.
  async "a concurrent burst above the threshold is refused, and exactly the threshold gets through"() {
    const env = freshEnv({ KAMOME_BURST: stubRateLimiter({ limit: 60 }) });
    const { statuses, seen } = await callWorkerConcurrently(ROUTE, {
      env, count: 75, ip: "203.0.113.7"
    });

    const allowed = statuses.filter((status) => status === 200).length;
    const refused = statuses.filter((status) => status === 429).length;
    assert.equal(allowed, 60, "the threshold is what gets through, no more");
    assert.equal(refused, 15, "everything above the threshold is refused");
    assert.equal(allowed + refused, 75, "and nothing lands anywhere else");
    assert.equal(seen.calls, 60, "a refused request must not reach the provider");
  },

  async "a burst refusal costs no credit and is not counted against the day"() {
    // Exhausted before the request arrives, so this one is refused outright.
    const env = freshEnv({ KAMOME_BURST: stubRateLimiter({ limit: 0 }) });
    const { response, seen } = await callWorker(ROUTE, {
      env, at: "2026-09-04T12:00:00.000Z", ip: "203.0.113.7"
    });
    assert.equal(response.status, 429);
    assert.equal(seen.calls, 0, "a refused request must not reach the provider");
    assert.equal(env.KAMOME_BUDGET.store.get("routing-requests-2026-09-04"), undefined,
      "a request that never reached Geoapify must not spend the day's budget");
  },

  async "the burst 429's Retry-After is the configured period, not a literal"() {
    // The same assertion the ceiling's tests make about its own number: this is
    // configuration in `wrangler.toml`, so a different value must show through.
    for (const [configured, expected] of [["60", "60"], ["10", "10"]]) {
      const env = freshEnv({
        BURST_RETRY_AFTER_S: configured,
        KAMOME_BURST: stubRateLimiter({ limit: 0 })
      });
      const { response } = await callWorker(ROUTE, { env, ip: "203.0.113.7" });
      assert.equal(response.status, 429);
      assert.equal(response.headers.get("retry-after"), expected);
    }
  },

  async "the burst limit is checked before the day's counter, so its Retry-After wins"() {
    // Both guards are spent. The answer must be the burst's period rather than
    // the seconds to UTC midnight — that is what proves the ordering, and the
    // ordering is what keeps a burst out of KV and off the day's budget.
    const env = freshEnv({
      KAMOME_BURST: stubRateLimiter({ limit: 0 }),
      KAMOME_BUDGET: stubKV({ seed: { "routing-requests-2026-09-04": "2000" } })
    });
    const { response } = await callWorker(ROUTE, {
      env, at: "2026-09-04T12:00:00.000Z", ip: "203.0.113.7"
    });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("retry-after"), "60");
  },

  async "one address exhausting its bucket does not refuse another"() {
    const env = freshEnv({ KAMOME_BURST: stubRateLimiter({ limit: 1 }) });
    const first = await callWorker(ROUTE, { env, ip: "203.0.113.7" });
    const second = await callWorker(ROUTE, { env, ip: "203.0.113.7" });
    const other = await callWorker(ROUTE, { env, ip: "198.51.100.4" });
    assert.equal(first.response.status, 200);
    assert.equal(second.response.status, 429, "the address has spent its bucket");
    assert.equal(other.response.status, 200, "a different address has its own");
  },

  async "a request with no connecting address shares one bucket rather than skipping the limit"() {
    const env = freshEnv({ KAMOME_BURST: stubRateLimiter({ limit: 1 }) });
    const first = await callWorker(ROUTE, { env });
    const second = await callWorker(ROUTE, { env });
    assert.deepEqual(env.KAMOME_BURST.seen, [{ key: "no-connecting-ip" }, { key: "no-connecting-ip" }],
      "an unattributable request must not get a fresh, empty bucket of its own");
    assert.equal(first.response.status, 200);
    assert.equal(second.response.status, 429);
  },

  // The three fail-closed branches, for the same reason the ceiling has three:
  // a Worker whose burst limiter is missing *looks* hardened and is not, and
  // this is the deploy whose whole purpose is making the URL safe to ship.

  async "a missing rate-limit binding fails closed at 503 and forwards nothing"() {
    const env = freshEnv({ KAMOME_BURST: undefined });
    const { response, seen } = await callWorker(ROUTE, { env, ip: "203.0.113.7" });
    assert.equal(response.status, 503);
    assert.equal(seen.calls, 0, "an unlimited request must not be forwarded");
  },

  async "a missing or unusable Retry-After period fails closed at 503"() {
    for (const period of [undefined, "", "soon", "0", "-1"]) {
      const { response, seen } = await callWorker(ROUTE, {
        env: freshEnv({ BURST_RETRY_AFTER_S: period }), ip: "203.0.113.7"
      });
      assert.equal(response.status, 503,
        `period ${JSON.stringify(period)} must not leave the burst limit unenforced`);
      assert.equal(seen.calls, 0);
    }
  },

  async "a rate limiter outage fails closed at 503 rather than forwarding unlimited"() {
    const env = freshEnv({ KAMOME_BURST: stubRateLimiter({ throws: true }) });
    const { response, seen } = await callWorker(ROUTE, { env, ip: "203.0.113.7" });
    assert.equal(response.status, 503);
    assert.equal(seen.calls, 0);
  },

  async "a limiter answering anything but a clean success refuses"() {
    // `success` is a boolean in Cloudflare's contract. Anything else is a
    // limiter this Worker does not understand, and the safe reading of "I do
    // not understand the answer" is not "let it through".
    for (const answer of [{}, { success: "yes" }, { success: 1 }, { success: null }]) {
      const env = freshEnv({ KAMOME_BURST: stubRateLimiter({ answer }) });
      const { response, seen } = await callWorker(ROUTE, { env, ip: "203.0.113.7" });
      assert.equal(response.status, 429, `answer ${JSON.stringify(answer)} must not read as success`);
      assert.equal(seen.calls, 0);
    }
  }
};

let failures = 0;
for (const [name, test] of Object.entries(tests)) {
  try {
    await test();
    console.log(`ok   ${name}`);
  } catch (error) {
    failures += 1;
    console.error(`FAIL ${name}\n     ${error.message}`);
  }
}
console.log(`\n${Object.keys(tests).length - failures}/${Object.keys(tests).length} passed`);
process.exit(failures === 0 ? 0 : 1);
