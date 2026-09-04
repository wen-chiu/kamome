# Release readiness — the engineering side of the bargain

**Owner: the engineering/PO sessions, not Chiu.** Created 2026-09-02 on Chiu's
instruction, which is also the division of labour this file exists to serve:

> *「你在程式端幫我把關，我就專心處理輸出影片品質。你保證程式不會壞，沒有安全性或
> 其他問題，我確保影片輸出夠好使用者願意用。」* — Chiu, 2026-09-02

So: **Chiu judges the film. This file judges everything else.** Nothing here is
for Chiu to tick. Rows reach him only in the two cases named at the bottom.

**This file supersedes `Docs/pre-launch.md` as the release gate.** `pre-launch.md`
keeps the reasoning, the dated provider research and the accepted risks, and is
cited row by row below; it is no longer the thing you read to find out where the
release stands. Nothing was deleted to make this file.

**Phase 4 does not appear here.** Its exit is Chiu's judgement of a film
(ADR 2026-09-02), and its old item 3 — "export that survives" — was half film
quality (the shake, closed by ADR 2026-08-31 (b)) and half release readiness. The
release half is now rows D1–D3 below and belongs to nobody but this file. That
overlap is what made "is item 3 done?" unanswerable for two weeks.

---

## Tier 1 — the machine already holds these

`./check.sh` is the enforcement. **VERIFIED green 2026-09-02** on
`claude/dev-progress-architecture-review-c825ce` (static half; the Xcode half
needs a machine with Xcode).

| what is guaranteed | gate |
|---|---|
| module dependency graph matches `architecture.json` (7 modules) | `check-architecture.sh` |
| `AVFoundation` confined to 1 file; `GRDB` to `Core/Persistence/`; `MapLibre` to 1 file | `check-architecture.sh` |
| every one of 57 ledger entries is findable | `check-decisions-index.sh` |
| the five charter/boot documents stay inside their byte budgets | `check-doc-budget.sh` |
| **§0** — no real trip fixture is tracked; no `KamomeLog` call carries coordinates | `check-location-data.sh` |
| `matching.base_url` is `""` or https — never a LAN address | `check-routing-endpoint.sh` |
| no routing key is committed, by either path | `check-secrets.sh` |
| the suite has not silently shrunk (baseline 404) | `check-test-count.sh` |
| **`current-state.md`'s "Last synced" line names the newest ADR and the newest merged PR** — on the branch, where the rule is satisfiable | `check-staleness.sh` **(new 2026-09-02, PR #30)** |
| **no config key loses its last consumer** — 3 known-dead are baselined, a 4th fails the build | `check-dead-config.sh` **(new 2026-09-02)** |
| **`Docs/current-state.md` is synced** to the newest ADR — offline, everywhere — and is **at most one merged PR behind**, one being the structural floor. ⚠️ Its **PR half runs locally only**: `gh` is unauthenticated on the CI runner, so CI prints `PR HALF DID NOT RUN` (VERIFIED on run 33632648596). One `GH_TOKEN` line in the workflow would close it. | `check-staleness.sh` **(new 2026-09-02)** |
| style, and the build, and the tests | `swiftlint --strict`, `xcodebuild test` |

**These need no attention from anyone.** That is the point of them, and it is the
model every row in Tier 2 should be moved into.

### Release-only gates — `./check.sh --release <artifact>`

Two more gates exist and are **not** in the run above. They were separated because
they failed on work that was scheduled rather than broken, and a permanently red
`main` teaches everyone to ignore it (`HANDOFF.md`, *"a red check means something
now"*). **`check-attribution.sh` no longer fails** — S2 and S3 are built — but it
stays here rather than moving up: it is a release obligation, it belongs beside
the artifact scan, and moving a gate because it went green is how a gate stops
being read.

| what is guaranteed | gate |
|---|---|
| the routing key is not in the built artifact — exact match across every file, binaries included; `KamomeRoutingAPIKey` absent or empty; the **shipped** `TrackingConfig.json` is distributable; no 32-hex string in any bundled text resource | `release/check-archive.sh` |
| the app carries Geoapify + OpenStreetMap attribution and a privacy notice string — **passing since 2026-09-02**, and the only one of the two that can be run without an artifact | `release/check-attribution.sh` |

An ordinary `./check.sh` **prints that these did not run**, so a release gate
cannot be silently forgotten. Both are runnable on their own for a quick check
without a full test cycle.

⚠️ **`check-archive.sh` refuses to run without the real key** rather than falling
back to a shape scan. A shape scan alone would pass a key of another shape, and a
check that silently measures less than it claims is the failure mode `check.sh`
exists to avoid.

**All four gates were positive-controlled on the day they were written** — a
planted key in both an `.xcarchive` and an `.ipa`, a config key stripped of its
last consumer, and a baselined key given one back. A gate never shown to fire is
one nobody should trust.

---

## Tier 2 — claimed somewhere, enforced by nobody

**This is where "程式會壞" actually comes from.** Each row is a property some
document already asserts, which no gate checks, so it stays true only while
someone remembers it. Each names the check that would end that.

**Four of these are now gates, not prose** (Chiu authorised the 2026-09-02 PO
session to write them, lifting `PO.md`'s no-code rule for `Scripts/` only). Rows
closed that way are struck through and name their gate.

**S2 and S3 closed differently, later the same day, and the difference matters:**
their gate already existed and *failed* — what closed them is application code
that makes it pass. A struck row therefore means one of two things, and it says
which: the property is now checked by a machine (S1, C1), or the obligation is
now met and the machine confirms it (S2, S3). The rest remain specifications for
an engineering session.

### Security and release

| # | what is unguarded | evidence | the check that ends it |
|---|---|---|---|
| ~~**S1**~~ | ✅ **CLOSED 2026-09-02 — `release/check-archive.sh`.** The paragraph below is why it exists; it is now a command, not an instruction to remember. ~~**The built artifact is never checked for the key.**~~ `check-secrets.sh` greps *tracked source*. The submission checklist's "unzip the `.ipa`, grep for a key-shaped string" is prose, run by hand, at the moment of highest pressure. | **VERIFIED 2026-08-20** (`pre-launch.md`): two built bundles carried a **plaintext 32-hex key** in `Kamome.app/Info.plist`, read out with stock `PlistBuddy`. FairPlay covers the executable, not resources. | `check-archive.sh <path>` — walk every file in an `.xcarchive`/`.ipa`, fail on a 32-hex match; assert `Info.plist` carries the Worker URL and no key field. Must run **on the artifact**, never the source. |
| ~~**S2**~~ | ✅ **CLOSED 2026-09-02 — the app now carries the attribution, and a user can reach it.** `Powered by Geoapify` (the format the free plan requires, untranslated in both languages) and `Map data © OpenStreetMap contributors`, each with its link, on `UI/About/AboutView.swift`, reached from an `info.circle` button in Home's toolbar. **In the interface, never in the film** (Chiu 2026-08-17). ~~Attribution does not exist in the app.~~ | **VERIFIED 2026-09-02:** `release/check-attribution.sh` exits 0; `LocalizationTests.testAttributionCarriesBothLicenceObligations` asserts the Geoapify format is byte-identical in `en` and `zh-Hant`, because a translation pass would break the obligation while looking like an improvement. **And visible to a user** — `Docs/demos/release/` holds the simulator captures in both languages, because the gate proves the strings are in the catalogue and cannot prove anyone can see them. | `release/check-attribution.sh` (the catalogue) + the localization test (the format). ⏳ **The placement is still Chiu's**: the toolbar button is the anchor that already existed, not a chosen design, and visual craft is `DESIGNER.md`'s. |
| ~~**S3**~~ | ✅ **CLOSED 2026-09-02 as a shipping draft — the notice exists and describes both payloads.** Imported legs: stop centres **plus photo positions**, thinned and capped, in the request's URL — and the two numbers are read from `TrackingConfig` rather than typed into the copy, so tuning cannot make the notice untrue. Recorded legs: **nothing is sent**, which is what the code does (see the correction in the row below). "Start and end coordinates" appears nowhere and a test forbids its return. The album control it names **ships** (`ImportSheet.albumSection`). ~~The privacy notice does not exist.~~ | **VERIFIED 2026-09-02:** gate green; three localization tests hold the payload split, the ≤24 h retention *with* its failures exception, and the promise-only-what-ships rule, in both languages. | ⏳ **The wording is Chiu's and is not ruled on** — this ships so the obligation is met rather than deferred. ⚠️ **Still open and deliberately untouched:** whether the import flow warns *at the point of import* (`pre-launch.md`, 🟡, explicitly §0 and explicitly Chiu's). An About screen is not that decision. |
| **S3b** | 🟡 **`pre-launch.md`'s payload table is STALE about recorded trips — it describes a state that never arrived, and on the current endpoint cannot.** Its own shape row says "POST — in the body **(after migration)**": the migration was to Geoapify, and **Geoapify has no map-matching endpoint**, so no matcher can be constructed and the recorded column has never described a live payload. The code says exactly this itself at `RouteMatchService.swift:325-327`. **The underlying question — whether a recorded trace is ever sent — is still OPEN and deferred to Capture Beta** (ADR 2026-08-20 (d)'s addendum: *"Deferred to Capture Beta, not decided now"*, *"Nothing to build now"* — it records Chiu's lean, it does **not** decide). | **VERIFIED 2026-09-02:** `provider:` defaults to `nil` and none of the three shipping call sites passes one — `TrackingSession.swift:113`, `ImportFlowModel.swift:155`, `RecapModel.swift:142`; `RouteMatchService.swift:331` is `case .gpsHifi, .gpsPassive: return matcher != nil`. A recorded leg is therefore never offered to routing. | ✅ **Now gated — `RouteMatchRecordedLegTests` (2026-09-02).** The notice promises that if a future version sends the recorded path it will say so, and nothing enforced that: the day Capture Beta wires a matcher on a shipping path, `shouldReconstruct` flips and the notice becomes a lie with no test failing. The test fails on that day and names the notice. **The table itself is Chiu's** — relabel or delete, but it is not an equal claim in conflict with the code. |
| **S4** | 🟠 **The Worker's no-log property is asserted nowhere**, and it is load-bearing rather than tidy: `/v1/routing` is GET-only, so real coordinates travel **in the URL**, the most-logged part of an HTTP request. | `pre-launch.md`, `Deploy/worker/README.md`. Deployed 2026-08-27. | a deploy-time assertion in the Worker's own repo path. A proxy that logs makes §0 worse while appearing to make it better. |
| **S5** | 🟠 **The counter is BUILT and tested; it is not DEPLOYED, so the ceiling does not yet exist in production.** ~~No per-day budget counter exists in the Worker~~ — `Deploy/worker/src/index.js` refuses above `DAILY_REQUEST_CEILING` (2000/day, Chiu's number) with 429 + `Retry-After` to UTC midnight, and fails closed at 503 when it cannot count. **`matching.base_url` still must not be flipped**, because the deployed Worker is still the uncapped 2026-08-27 version. | **VERIFIED from Geoapify's own pages, 2026-08-29:** limits are **soft on every tier**, there is no customer-settable cap, and escalation ends in **account blocking**. There is no provider-side ceiling to fall back on. **VERIFIED 2026-09-04:** `npm test` 19/19 in `Deploy/worker/`, four of which fail when the ceiling is neutered; a `wrangler dev` positive control at ceiling 1 answers the second request 429 / `Retry-After: 65312`. | **the deploy, and its after-probe** (`Deploy/worker/README.md` §"Why `preview_urls = false`"). Blocked on merge: this session may deploy only from merged `main` or a branch Chiu names. Then S5 closes and `matching.base_url` may be proposed. |
| **S6** | 🟡 **Build logs echo the key in clear text** — it is a build setting, and `xcodebuild` prints every one. | `pre-launch.md` exit 2. | closes **by construction** when S5's wiring lands — the key stops being a build setting, so there is nothing left to echo. **Still open**: the wiring is the config flip, which is Chiu's to approve (`CLAUDE.md` rule 2) and was deliberately not made in the counter's PR. Until then: no build log leaves the machine unscrubbed. |

### Code quality

| # | what is unguarded | evidence | the check that ends it |
|---|---|---|---|
| ~~**C1**~~ | ✅ **CLOSED 2026-09-02 — `check-dead-config.sh`**, with the three baselined in `Scripts/dead-config.baseline`. A fourth now fails the build. ~~**Config keys that look live and control nothing — there are three, not two.**~~ All decode, all pass through six copy-constructors, all are asserted by tests, and none has a consumer outside `Core/ConfigLoader/`. | **VERIFIED 2026-09-02, this session**, over all 121 keys: `matching.route_waypoint_radius_m`, `export.keyframe_interval_frames`, and **`export.total_duration_max_s`** — the third was not previously named anywhere. Its own code says so: `RecapDurationPlan.swift:221` ("deliberately does **not** apply here any more") and `RecapComposer.swift:237` ("This used to pass `totalDurationMaxS`"). | `check-dead-config.sh` — flag any key in `TrackingConfig.json` with no reference outside `Core/ConfigLoader/`. Comments and decode plumbing must not count as readers; both fooled this session's first attempt at the same query. |
| ~~**C2**~~ | ✅ **CLOSED 2026-09-02** — priced off `RecapRenderLoop.stations`, which is documented pure for exactly this. **Measured on running it:** `0.79 s per snapshot → ~42 s for 53 stations` (30 s film, 900 frames). ⚠️ **Honest note on the size of the error:** the old formula would have said ~60 keyframes / ~47 s here, so on a *uniform synthetic* trip it was only ~13% out and looked fine. It was wrong in principle, and it diverges on real films, where stations cluster at stop beats and arcs — `ishigaki-crossing` moved 367 → 178 snapshots under crop-scaling while `frameCount / 15` would not have moved at all. ~~**The one benchmark that feeds the export-time estimate measures a quantity the renderer no longer has.**~~ `RecapBudgetAndDemoTests` prints `KAMOME_BENCH … ~Xs for Y keyframes`, computed as `frameCount / config.keyframeIntervalFrames`. | **VERIFIED 2026-09-02, this session.** After crop-scaling, snapshots are planned by `RecapSnapshotStations`; the interval has no shipping reader (C1). **The export-time estimate is a mandatory submission item** (`pre-launch.md` item 5, promoted out of optional) and this is the number it would be built from. | re-derive the benchmark from the station count. Until then the printed figure is not evidence of anything. |
| ~~**C3**~~ | ✅ **CLOSED 2026-09-02** — both gates now scan both cameras, and doing so **found something**: the shipped camera reaches **79.8% of the safe zone on `ishigaki-crossing`** against an 80% limit, invisible while only the synthetic configuration was scanned. It also retired the row's own premise — body span is identical in both since ADR 2026-08-31. `HANDOFF.md`. ~~**The two continuity gates have never measured the shipped camera.**~~ They pass a synthetic `establishing` extent; the app has passed `nil` since 2026-08-15 — **18.6 km vs 274 km** of body span on one fixture. | `HANDOFF.md`, re-confirmed 2026-08-31. Deliberately unchanged: `nil` is more forgiving, so swapping weakens the gate. | scan **both** configurations. This is the cheap fix and it does not lower the bar; it adds one. |
| **C4** | 🟠 **Nothing asserts post-grade output, and nothing asserts the end card's brand mark.** `RecapMarkerDeckStillsTests` writes stills and asserts nothing, so "the end card still shows a bird" rests on a human noticing. The bare gull now has three consumers. | `HANDOFF.md` traps; `Docs/handoff-marker-badge.md` 6c/6d/7. | one assertion on the end card's mark. The badge work already proved the failure mode is silent. |
| **C5** | 🟠 **The subject lookup misses, and the miss is indistinguishable from correct fallback output.** See the note below — this is the row Chiu asked about. | `Docs/handoff-subject-lookup.md`. Instrumented 2026-08-29; **rate and trigger UNKNOWN**. | a render-time assertion that the resolved subject id equals the requested one, failing the run rather than the film. |

---

## Tier 3 — only a device or a person can answer these

Nothing here can be mechanised, so this file's job is only to stop them being
forgotten. All five are the **same device session**, and it has never been run.

| # | what | why it is not optional |
|---|---|---|
| **D1** | `ExportLifecycleGuard` — start an export, **lock the screen**, wait, see whether it survives | implemented and never verified; a simulator cannot answer it |
| **D2** | record the **per-trip export time** and the memory reading at full frame count | the input to S-item 5 (the export estimate); missed on the 2026-08-30 runs |
| **D3** | re-measure **seconds per snapshot** on current hardware | last figure is 0.72–1.55 s, taken before crop-scaling changed the count 367 → 178 |
| **D4** | **Limited Photo Library** on hardware | the last of the §6b pair still open |
| **D5** | the **S5 UX pass** (`Docs/device-test-P3.md` item G) | never done |

**The standing rule that survives all of this** (`pre-launch.md`): anyone
proposing a rendering change that *raises* the snapshot count has not solved D3,
they have traded it — and the trade is priced in device seconds. The one
sanctioned exception is framing.

---

## What reaches Chiu, and nothing else

Two cases only. Everything else is this file's problem.

1. **A licence, privacy or §0 obligation that needs a product decision.** Three
   are open right now, and none of them blocks the obligation being *met*:
   **S2's placement** and **S3's wording** — both now ship as a working draft, so
   what reaches Chiu is a revision, not a blank page; **S3b**, what to do with a
   payload table that describes a state that never arrived; and
   whether the user is told that importing contacts a third party
   (`pre-launch.md`, still 🟡 undecided and explicitly §0's) — **untouched by the
   About screen on purpose**, because a notice a user may never open is not a
   warning at the point of import.
2. **A gate that would have to be weakened** to ship. `CLAUDE.md` rule 3 makes
   that a stop-and-ask, always.

**Submission order is unchanged and stays Chiu's** (`pre-launch.md` 2026-08-20).
This file does not sequence a release; it says whether one is safe.
