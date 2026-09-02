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
| the suite has not silently shrunk (baseline 371) | `check-test-count.sh` |
| **no config key loses its last consumer** — 3 known-dead are baselined, a 4th fails the build | `check-dead-config.sh` **(new 2026-09-02)** |
| style, and the build, and the tests | `swiftlint --strict`, `xcodebuild test` |

**These need no attention from anyone.** That is the point of them, and it is the
model every row in Tier 2 should be moved into.

### Release-only gates — `./check.sh --release <artifact>`

Two more gates exist and are **not** in the run above, because they fail today on
work that is scheduled rather than broken, and a permanently red `main` teaches
everyone to ignore it (`HANDOFF.md`, *"a red check means something now"*).

| what is guaranteed | gate |
|---|---|
| the routing key is not in the built artifact — exact match across every file, binaries included; `KamomeRoutingAPIKey` absent or empty; the **shipped** `TrackingConfig.json` is distributable; no 32-hex string in any bundled text resource | `release/check-archive.sh` |
| the app carries Geoapify + OpenStreetMap attribution and a privacy notice string | `release/check-attribution.sh` |

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

**Four of these are now gates, not prose** (Chiu authorised this session to write
them, 2026-09-02, lifting `PO.md`'s no-code rule for `Scripts/` only — application
code is untouched). Rows that were closed this way are struck through and name
their gate. The rest remain specifications for an engineering session.

### Security and release

| # | what is unguarded | evidence | the check that ends it |
|---|---|---|---|
| ~~**S1**~~ | ✅ **CLOSED 2026-09-02 — `release/check-archive.sh`.** The paragraph below is why it exists; it is now a command, not an instruction to remember. ~~**The built artifact is never checked for the key.**~~ `check-secrets.sh` greps *tracked source*. The submission checklist's "unzip the `.ipa`, grep for a key-shaped string" is prose, run by hand, at the moment of highest pressure. | **VERIFIED 2026-08-20** (`pre-launch.md`): two built bundles carried a **plaintext 32-hex key** in `Kamome.app/Info.plist`, read out with stock `PlistBuddy`. FairPlay covers the executable, not resources. | `check-archive.sh <path>` — walk every file in an `.xcarchive`/`.ipa`, fail on a 32-hex match; assert `Info.plist` carries the Worker URL and no key field. Must run **on the artifact**, never the source. |
| **S2** | 🔴 **Attribution does not exist in the app** — now *gated* by `release/check-attribution.sh`, which fails today. The string itself is still missing; the gate makes shipping without it impossible rather than unlikely. Geoapify attribution is **mandatory on the free plan**; OSM attribution is always required. Chiu decided 2026-08-17 it lives in the interface. | **VERIFIED 2026-09-02, this session:** zero occurrences of `Geoapify`, `OpenStreetMap` or `Powered by` in `App/Resources/Localizable.xcstrings` or `InfoPlist.xcstrings`. The only hits in the tree are Swift type names. | assert the strings catalog contains the attribution key. One line, and it is a licence condition, not a nicety. |
| **S3** | 🔴 **Gated by the same script.** **The privacy notice does not exist**, and it gates Apple's App Privacy questionnaire. Decided 2026-08-20 (c); never built. Must describe **two different payloads** (`pre-launch.md`) — "start and end coordinates" is untrue of both. | **VERIFIED 2026-09-02:** no privacy/about string in either catalog. | same catalog assertion; the wording is a writing job, and the album control must ship with it or the notice may not mention it. |
| **S4** | 🟠 **The Worker's no-log property is asserted nowhere**, and it is load-bearing rather than tidy: `/v1/routing` is GET-only, so real coordinates travel **in the URL**, the most-logged part of an HTTP request. | `pre-launch.md`, `Deploy/worker/README.md`. Deployed 2026-08-27. | a deploy-time assertion in the Worker's own repo path. A proxy that logs makes §0 worse while appearing to make it better. |
| **S5** | 🟠 **No per-day budget counter exists in the Worker**, and it was decided mandatory *before* the app-side wiring. | **VERIFIED from Geoapify's own pages, 2026-08-29:** limits are **soft on every tier**, there is no customer-settable cap, and escalation ends in **account blocking**. There is no provider-side ceiling to fall back on. | the counter itself (`Deploy/worker/README.md` costs it). Until it exists, `matching.base_url` must not be flipped. |
| **S6** | 🟡 **Build logs echo the key in clear text** — it is a build setting, and `xcodebuild` prints every one. | `pre-launch.md` exit 2. | closes **by construction** when S5's wiring lands. Until then: no build log leaves the machine unscrubbed. |

### Code quality

| # | what is unguarded | evidence | the check that ends it |
|---|---|---|---|
| ~~**C1**~~ | ✅ **CLOSED 2026-09-02 — `check-dead-config.sh`**, with the three baselined in `Scripts/dead-config.baseline`. A fourth now fails the build. ~~**Config keys that look live and control nothing — there are three, not two.**~~ All decode, all pass through six copy-constructors, all are asserted by tests, and none has a consumer outside `Core/ConfigLoader/`. | **VERIFIED 2026-09-02, this session**, over all 121 keys: `matching.route_waypoint_radius_m`, `export.keyframe_interval_frames`, and **`export.total_duration_max_s`** — the third was not previously named anywhere. Its own code says so: `RecapDurationPlan.swift:221` ("deliberately does **not** apply here any more") and `RecapComposer.swift:237` ("This used to pass `totalDurationMaxS`"). | `check-dead-config.sh` — flag any key in `TrackingConfig.json` with no reference outside `Core/ConfigLoader/`. Comments and decode plumbing must not count as readers; both fooled this session's first attempt at the same query. |
| **C2** | 🟠 **The one benchmark that feeds the export-time estimate measures a quantity the renderer no longer has.** `RecapBudgetAndDemoTests` prints `KAMOME_BENCH … ~Xs for Y keyframes`, computed as `frameCount / config.keyframeIntervalFrames`. | **VERIFIED 2026-09-02, this session.** After crop-scaling, snapshots are planned by `RecapSnapshotStations`; the interval has no shipping reader (C1). **The export-time estimate is a mandatory submission item** (`pre-launch.md` item 5, promoted out of optional) and this is the number it would be built from. | re-derive the benchmark from the station count. Until then the printed figure is not evidence of anything. |
| **C3** | 🟠 **The two continuity gates have never measured the shipped camera.** They pass a synthetic `establishing` extent; the app has passed `nil` since 2026-08-15 — **18.6 km vs 274 km** of body span on one fixture. | `HANDOFF.md`, re-confirmed 2026-08-31. Deliberately unchanged: `nil` is more forgiving, so swapping weakens the gate. | scan **both** configurations. This is the cheap fix and it does not lower the bar; it adds one. |
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

1. **A licence, privacy or §0 obligation that needs a product decision** — S2's
   placement, S3's wording, and whether the user is told that importing contacts
   a third party (`pre-launch.md`, still 🟡 undecided and explicitly §0's).
2. **A gate that would have to be weakened** to ship. `CLAUDE.md` rule 3 makes
   that a stop-and-ask, always.

**Submission order is unchanged and stays Chiu's** (`pre-launch.md` 2026-08-20).
This file does not sequence a release; it says whether one is safe.
