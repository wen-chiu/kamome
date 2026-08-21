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

/** An empty-bodied status. No message, because a message is a place to leak one. */
function refuse(status) {
  return new Response(null, { status });
}
