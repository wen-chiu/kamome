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

const ENV = { GEOAPIFY_API_KEY: "worker-secret" };
const ROUTE = "https://kamome-routing.example.workers.dev/v1/routing"
  + "?waypoints=64.310400,-20.302400%7C64.327100,-20.119900&mode=drive";

/** Swaps in a stub upstream and returns what it saw. */
async function callWorker(url, { env = ENV, method = "GET", upstream } = {}) {
  const seen = {};
  const original = globalThis.fetch;
  globalThis.fetch = async (target, init) => {
    seen.url = target.toString();
    seen.init = init;
    if (upstream instanceof Error) throw upstream;
    return upstream ?? new Response('{"features":[]}', {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    const response = await worker.fetch(new Request(url, { method }), env);
    return { response, seen };
  } finally {
    globalThis.fetch = original;
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
