# The routing ceiling counts in one Durable Object, not in KV

**Status:** Decided (Chiu, 2026-10-03)
**Supersedes:** ledger entry "2026-09-04" point 1 (`Docs/decisions.md`): "a deliberate choice over a Durable Object"

## Context

From 2026-10-02 14:47 UTC every request to the routing Worker returned 503 (#204).
It answered 200 again after 00:00 UTC, and nothing had been deployed: the live version
was still `09e248ee` from 2026-09-05 (VERIFIED, `wrangler deployments list`).

The cause: the counter wrote one KV key per request. Cloudflare's free plan allows
**1,000 KV writes a day** and **one write a second to the same key** (VERIFIED, KV
limits page, 2026-10-03). So the real ceiling was 1,000, not `DAILY_REQUEST_CEILING`
2000. Past 1,000 every write failed, and the Worker refused every request with 503
until UTC midnight. The fail-closed behaviour itself worked: a request it could not
count was never forwarded to Geoapify. The 2026-09-04 entry weighed a Durable Object
against KV's eventual consistency. It never looked at KV's write limits. Whether
10/02's write count actually reached 1,000 is INFERRED; the dashboard's KV metrics
would settle it.

## Decision

Chiu: *「如果DO是不花錢的方法能讓我打到一天兩千次的免費路由請求 那就做吧 但我要你完整分析我的系統架構不能犧牲品質穩定度跟效能」*

- The count lives in **one** SQLite-backed Durable Object, `RoutingBudget`, named
  `routing-budget`, with one row per UTC day. On the free plan a Durable Object gets
  100,000 requests and 100,000 rows written a day (VERIFIED, DO pricing page,
  2026-10-03), and each routing request uses one of each.
- The count is **exact**: the object handles one request at a time, and its read,
  compare and increment run with no `await` between them. The object keeps 31 days
  of counts, so the dashboard's Data Studio can show what a past day spent.
- What the app sees does not change: 429 with `Retry-After` to UTC midnight above
  the ceiling, 503 when the Worker cannot count, counting before forwarding, and the
  per-IP burst limit checked first.
- `BUDGET_LOCATION_HINT = "apac"`: the region where the object is first
  created, never moved afterwards. VERIFIED 2026-10-03, in Taiwan, with
  `/cdn-cgi/trace`: Chiu's iPhone on cellular is served from SIN and this Mac
  from SJC. The app's requests come from phones.

## Rejected

- **Workers Paid.** Chiu: paying is not an option now. It also would not lift KV's
  limit of one write a second to the same key.
- **Lowering the ceiling to 900.** Turns the 503 into an honest 429, but the day
  still holds fewer than 1,000 requests, and the one-write-a-second limit remains.
- **Sampled or sharded KV counting.** Rebuilds by hand what a Durable Object
  already provides, and the count becomes an estimate.
- **Starting the Geoapify fetch in parallel with the count to hide latency.** A
  refused request would still spend a credit, which defeats the ceiling.

## Consequences

- Code: `Deploy/worker/src/index.js` (the class and `spendOne`), `wrangler.toml`
  (the binding, migration `v1-routing-budget` and the hint). The KV namespace is
  unbound, not deleted; deleting it is Chiu's call.
- ⚠️ **`wrangler rollback` cannot cross this migration** (VERIFIED, Cloudflare
  rollback docs). A bad deploy can only be fixed forward, so `npm test` and the
  `wrangler dev` control must pass before the deploy, and the probe runs after it.
- Performance: before the change, 10 requests from Taiwan took 1.35–5.50 s each
  (median 3.4 s), and the Worker's own path without an upstream takes about 0.5 s
  (VERIFIED, 2026-10-03). The extra Worker-to-object round trip is UNKNOWN until
  measured: run the same 10 requests after the deploy. Legs are routed one after
  another inside `trip_budget_s` 120, so every 100 ms added per leg is about 3% of
  the budget.
