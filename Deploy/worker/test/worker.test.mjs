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
 * A fresh env per call, so one test's spending never leaks into the next. The
 * ceiling is a **string**, exactly as `[vars]` in `wrangler.toml` delivers it —
 * a stub that handed over a number would hide the conversion bug it exists to
 * catch.
 */
function freshEnv(overrides = {}) {
  return {
    GEOAPIFY_API_KEY: "worker-secret",
    DAILY_REQUEST_CEILING: "2000",
    KAMOME_BUDGET: stubKV(),
    ...overrides
  };
}

/**
 * Swaps in a stub upstream and returns what it saw. `at` freezes `Date.now()`,
 * which is how the UTC-midnight rollover is exercised without waiting for it.
 */
async function callWorker(url, { env = freshEnv(), method = "GET", upstream, at } = {}) {
  const seen = { calls: 0 };
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
  try {
    const response = await worker.fetch(new Request(url, { method }), env);
    return { response, seen, env };
  } finally {
    globalThis.fetch = originalFetch;
    Date.now = originalNow;
  }
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
