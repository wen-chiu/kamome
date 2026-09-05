/**
 * S4 — the no-log property, as an assertion instead of a memory.
 *
 * `/v1/routing` is GET-only, so a real trip's coordinates travel **in the URL**,
 * which is the most-logged part of an HTTP request. Two things keep them out of
 * a log, and until now both were kept by whoever remembered them: no `console.`
 * anywhere in `src/`, and `[observability] enabled = false` in the deployed
 * config. `Docs/release-readiness.md` S4 asks for exactly this — *"a deploy-time
 * assertion in the Worker's own repo path"* — and `npm run deploy` runs it.
 *
 *   node Deploy/worker/test/deploy-config.test.mjs
 *
 * **Every rule below is exercised in both directions.** The scan runs against
 * this Worker and must find nothing, and it runs against a synthetic tree that
 * breaks each rule and must find it. A gate nobody has watched go red is a gate
 * nobody should trust, so this one goes red on every run, against a fixture.
 *
 * It is a line scanner, not a TOML parser, and deliberately so: the alternative
 * is a dependency in the one directory that holds an API key. The cost is that
 * it is conservative — a `#` inside a quoted value would truncate that line, and
 * the forbidden strings are forbidden in comments too. Both err toward failing.
 */
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";

const WORKER_DIR = join(dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE_DIR = join(WORKER_DIR, "src");
const CONFIG = join(WORKER_DIR, "wrangler.toml");

/** Kamome's own legitimate burst: Iceland's 58 legs inside `matching.trip_budget_s` 120. */
const KAMOME_BURST_PER_MINUTE = 58 / (120 / 60);

// ── The scan ───────────────────────────────────────────────────────────────

/**
 * Every way this Worker could start writing a request line, as a list of
 * findings. Empty means clean; the strings are diagnostics, so a failure says
 * which rule and where rather than only that something is wrong.
 */
export function scan({ sourceDir, configPath }) {
  return [...scanSource(sourceDir), ...scanConfig(configPath)];
}

function scanSource(sourceDir) {
  const found = [];
  const files = sourceFiles(sourceDir);
  if (files.length === 0) {
    // A scanner that scans nothing reports success and measures nothing, which
    // is the failure shape this project has already been bitten by twice
    // (`Arch.md` §6). An empty tree is a finding, never a pass.
    return [`${sourceDir}: no source file was scanned`];
  }
  for (const file of files) {
    readFileSync(file, "utf8").split("\n").forEach((line, index) => {
      // The string is forbidden outright — in code and in comments alike. A
      // rule that has to decide what is "really" a call needs a parser, and a
      // parser is a dependency in the directory that holds the API key.
      const sink = line.match(/\bconsole\s*\.\s*(\w+)/);
      if (sink) {
        found.push(`${relative(sourceDir, file)}:${index + 1}: console.${sink[1]} — this hop must not log`);
      }
    });
  }
  return found;
}

function sourceFiles(dir) {
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return [];
  }
  return entries.flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.(js|mjs|cjs|ts)$/.test(entry) ? [path] : [];
  });
}

function scanConfig(configPath) {
  const found = [];
  let raw;
  try {
    raw = readFileSync(configPath, "utf8");
  } catch {
    return [`${configPath}: the deployed configuration is missing`];
  }

  // wrangler reads wrangler.jsonc, then wrangler.json, then wrangler.toml. A
  // second config file would silently become the deployed one while this gate
  // went on reading the other — a gate measuring a file nobody deploys.
  for (const sibling of ["wrangler.jsonc", "wrangler.json", "wrangler.toml"]) {
    const path = join(dirname(configPath), sibling);
    if (path !== configPath && exists(path)) {
      found.push(`${sibling}: a second wrangler config would take precedence over the scanned one`);
    }
  }

  const lines = raw.split("\n").map(uncommented);

  // Workers Logs. Absent is not off — the platform's default is on, which is
  // why this must be written down in the deployed config rather than assumed.
  const observability = section(lines, "observability");
  if (observability === null) {
    found.push("[observability]: absent, and the platform default is on");
  } else if (!observability.some((line) => /^\s*enabled\s*=\s*false\s*$/.test(line))) {
    found.push("[observability]: enabled is not false");
  }
  // Anywhere in the file, so a named environment cannot switch it back on.
  lines.forEach((line, index) => {
    if (/^\s*enabled\s*=\s*true\s*$/.test(line)) {
      found.push(`wrangler.toml:${index + 1}: enabled = true re-opens observability`);
    }
    if (/^\s*logpush\s*=\s*true\s*$/.test(line)) {
      found.push(`wrangler.toml:${index + 1}: logpush records request URLs, which here means coordinates`);
    }
    if (/^\s*\[?\[?tail_consumers/.test(line)) {
      found.push(`wrangler.toml:${index + 1}: a tail consumer receives every request line`);
    }
    if (/^\s*\[?\[?analytics_engine_datasets/.test(line)) {
      found.push(`wrangler.toml:${index + 1}: an analytics dataset is a place to write a request line`);
    }
  });

  // Not a logging property, and included on purpose: a preview URL is a second
  // public door onto the same key (`README.md`, "Why preview_urls = false"), it
  // is `true` by default, and it is the other thing here kept true only by
  // whoever remembers it.
  if (!lines.some((line) => /^\s*preview_urls\s*=\s*false\s*$/.test(line))) {
    found.push("preview_urls: not pinned to false, and the platform default is on");
  }

  return found;
}

/** A TOML line with its comment removed, so the prose above a key never matches. */
function uncommented(line) {
  return line.split("#")[0].replace(/\s+$/, "");
}

/** The lines belonging to `[name]`, or null when the section is absent. */
function section(lines, name) {
  const start = lines.findIndex((line) => line.trim() === `[${name}]`);
  if (start === -1) return null;
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => /^\s*\[/.test(line));
  return end === -1 ? rest : rest.slice(0, end);
}

function exists(path) {
  try {
    statSync(path);
    return true;
  } catch {
    return false;
  }
}

// ── Fixtures for the positive controls ─────────────────────────────────────

/**
 * A synthetic worker directory that is clean unless a test breaks it. Written
 * to a temp dir, never beside the real one: a fixture that lived in `src/`
 * would be scanned by the gate it exists to test.
 */
function fixture({ source, config } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "kamome-worker-gate-"));
  mkdirSync(join(dir, "src"));
  writeFileSync(join(dir, "src", "index.js"), source ?? "export default { async fetch() {} };\n");
  writeFileSync(join(dir, "wrangler.toml"), config ?? CLEAN_CONFIG);
  return { sourceDir: join(dir, "src"), configPath: join(dir, "wrangler.toml") };
}

const CLEAN_CONFIG = `name = "kamome-routing"
preview_urls = false

[observability]
enabled = false
`;

// ── The tests ──────────────────────────────────────────────────────────────

const tests = {
  // The one that matters: this Worker, as it is about to be deployed.
  async "this Worker's source and deployed config carry no way to log a request"() {
    assert.deepEqual(scan({ sourceDir: SOURCE_DIR, configPath: CONFIG }), []);
  },

  async "the scan actually reads this Worker, rather than passing on an empty tree"() {
    // The failure this project has twice: a check that reports success and
    // measures nothing. If `src/` ever moves, this goes red instead of green.
    assert.ok(sourceFiles(SOURCE_DIR).length > 0, "src/ must contain something to scan");
    assert.deepEqual(scan({ sourceDir: join(WORKER_DIR, "does-not-exist"), configPath: CONFIG }),
      [`${join(WORKER_DIR, "does-not-exist")}: no source file was scanned`]);
  },

  // 🔴 The positive controls. Each breaks one rule and must be caught by name.

  async "a log call added back to the source is caught"() {
    const broken = fixture({
      source: "export default { async fetch(request) {\n  console" + ".log(request.url);\n} };\n"
    });
    const found = scan(broken);
    assert.equal(found.length, 1, `expected exactly one finding, got ${JSON.stringify(found)}`);
    assert.match(found[0], /^index\.js:2: console\.log — this hop must not log$/);
  },

  async "every console method is caught, not only log"() {
    for (const method of ["log", "info", "warn", "error", "debug", "trace"]) {
      const broken = fixture({ source: `console` + `.${method}("x");\n` });
      assert.equal(scan(broken).length, 1, `console.${method} must be caught`);
    }
  },

  async "observability switched on is caught, and so is its absence"() {
    const on = scan(fixture({ config: 'preview_urls = false\n\n[observability]\nenabled = true\n' }));
    assert.ok(on.some((f) => /\[observability\]: enabled is not false/.test(f)),
      `expected the section finding, got ${JSON.stringify(on)}`);
    assert.ok(on.some((f) => /enabled = true re-opens observability/.test(f)),
      "and the file-wide finding, so a named environment cannot switch it back on");

    const absent = scan(fixture({ config: "preview_urls = false\n" }));
    assert.deepEqual(absent, ["[observability]: absent, and the platform default is on"]);
  },

  async "a named environment re-enabling observability is caught"() {
    const found = scan(fixture({
      config: CLEAN_CONFIG + "\n[env.staging.observability]\nenabled = true\n"
    }));
    assert.equal(found.length, 1, `expected exactly one finding, got ${JSON.stringify(found)}`);
    assert.match(found[0], /enabled = true re-opens observability/);
  },

  async "the other three log sinks are caught"() {
    const cases = [
      ["logpush = true\n", /logpush records request URLs/],
      ['tail_consumers = [{ service = "logger" }]\n', /a tail consumer receives every request line/],
      ['[[analytics_engine_datasets]]\nbinding = "AE"\n', /an analytics dataset is a place to write/]
    ];
    for (const [snippet, expected] of cases) {
      const found = scan(fixture({ config: CLEAN_CONFIG + "\n" + snippet }));
      assert.ok(found.some((f) => expected.test(f)),
        `${JSON.stringify(snippet)} must be caught, got ${JSON.stringify(found)}`);
    }
  },

  async "preview URLs switched back on are caught"() {
    for (const config of ["[observability]\nenabled = false\n",
                          "preview_urls = true\n\n[observability]\nenabled = false\n"]) {
      const found = scan(fixture({ config }));
      assert.deepEqual(found, ["preview_urls: not pinned to false, and the platform default is on"]);
    }
  },

  async "a second wrangler config that would take precedence is caught"() {
    const clean = fixture();
    writeFileSync(join(dirname(clean.configPath), "wrangler.jsonc"), "{}\n");
    const found = scan(clean);
    assert.equal(found.length, 1, `expected exactly one finding, got ${JSON.stringify(found)}`);
    assert.match(found[0], /^wrangler\.jsonc: a second wrangler config/);
  },

  async "prose is not a violation — the rules read values, not the comments above them"() {
    // This file's own `wrangler.toml` explains `preview_urls` and observability
    // at length. A scanner that matched inside comments would be unfixable.
    const found = scan(fixture({
      config: "# preview_urls = true is what we must never do\n"
        + "# logpush = true would record coordinates\n" + CLEAN_CONFIG
    }));
    assert.deepEqual(found, []);
  },

  // ── The burst limit's numbers, which live in the config and nowhere else ──

  async "the burst Retry-After equals the binding's period, so the two cannot drift"() {
    // The Worker cannot read its own period — the binding exposes only
    // `.limit()` — so `Retry-After` has to come from a second value. This is
    // what stops the pair drifting, and it is why the source carries no literal.
    const raw = readFileSync(CONFIG, "utf8");
    const period = Number(raw.match(/simple\s*=\s*\{[^}]*\bperiod\s*=\s*(\d+)/)?.[1]);
    const retryAfter = Number(raw.match(/^\s*BURST_RETRY_AFTER_S\s*=\s*"(\d+)"/m)?.[1]);
    assert.ok(Number.isFinite(period), "the [[ratelimits]] binding must declare a period");
    assert.ok([10, 60].includes(period), "Cloudflare accepts a period of 10 or 60 seconds only");
    assert.equal(retryAfter, period, "BURST_RETRY_AFTER_S must equal the binding's period");
  },

  async "the burst threshold stays above Kamome's own legitimate burst"() {
    // Iceland is 58 legs inside `matching.trip_budget_s` 120 — ~29 requests a
    // minute. A limit at or below that throttles a genuine import, which is a
    // worse failure than the one this guard exists to prevent.
    const raw = readFileSync(CONFIG, "utf8");
    const limit = Number(raw.match(/simple\s*=\s*\{[^}]*\blimit\s*=\s*(\d+)/)?.[1]);
    assert.ok(Number.isFinite(limit), "the [[ratelimits]] binding must declare a limit");
    assert.ok(limit > KAMOME_BURST_PER_MINUTE,
      `a burst limit of ${limit}/min would throttle Iceland's own ${KAMOME_BURST_PER_MINUTE}/min import`);
  },

  async "the day's ceiling is still a positive number in the config, not the source"() {
    const raw = readFileSync(CONFIG, "utf8");
    const ceiling = Number(raw.match(/^\s*DAILY_REQUEST_CEILING\s*=\s*"(\d+)"/m)?.[1]);
    assert.ok(Number.isFinite(ceiling) && ceiling > 0, "DAILY_REQUEST_CEILING must be a positive number");
    assert.equal(readFileSync(join(SOURCE_DIR, "index.js"), "utf8").includes(String(ceiling)), false,
      "the ceiling must not also appear as a literal in the source");
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
