# Before the App Store — what has to be true first

**Kamome is not being submitted yet** (Chiu, deliberately: the artefact comes
before the convenience). This file exists so the things that block a submission
are in one place rather than scattered across ADRs, a closed gate and a handoff.

Nothing here blocks Phase 4. Everything here blocks a submission.

---

## The order to ship in (Chiu 2026-08-20)

Chiu's own sequencing, checked against the blockers below and corrected where it was
short. **Everything in 1–4 is his; 5–7 are what the list was missing** — each is
mandatory for a submission, and each is small.

| # | work | why here |
|---|---|---|
| **1** | **Routing: Geoapify integration, then a real film** | Everything downstream is judged on a film, and no film today runs on real road data. |
| **1b** | **Cloudflare Worker, key out of the binary** | Separate commit, same phase. Builds already reach other people's phones — the key is in those IPAs **today**. |
| **2** | **Cross-region: the flight/crossing beat** | `Docs/cross-region-journeys.md`. Every overseas trip hits it on device. |
| **3** | **Export survives: background, performance** | `ExportLifecycleGuard` is written and **never verified on a device**. |
| **4** | *(optional)* **Lower-quality export option** | A real feature with real design questions. Genuinely optional. |
| **5** | **Export time estimate** ⬆️ | **Promoted out of 4.** Not optional: a six-minute export with no estimate reads as broken. The loop already knows the frame count and the measured per-snapshot cost. |
| **6** | **Attribution in the app** | **Mandatory on the Geoapify free plan.** One line in an About screen. Was missing from the list. |
| **7** | **Privacy notice + Apple's App Privacy labels** | Routing sends coordinates to a third party, so Apple's privacy questionnaire must declare it. The notice is decided (2026-08-20 c) but **does not exist**, and the album path ships with it. Was missing from the list. |

**~~Also unresolved~~ RESOLVED (2026-08-21, VERIFIED):** the sprite working tree
was committed as `4ed8774` / `6cc6543` (re-centred sets, the 46 modified files) and
`c0d4583` (the two reindeer sets, with manifest entries — "choosable subjects");
`git status` is clean of PNGs. What remains from that closeout brief is the **key
verification**, whose outcome is not recorded (`Docs/eng-session-closeout.md`).

**Of the §6b six, two actually bite:** Limited Photo Library on hardware, and a
crash-free export across three trips. The souvenir-map item is moot while MapLibre is
parked.

---

## 🔴 The key has three exits, and only one of them is guarded

**Chiu's requirement (2026-08-20): there must be a complete, checkable process so the
key cannot leak at submission.** This section is that process. It is written as
checks, not as intentions.

### The three exits

| # | exit | today | closed by |
|---|---|---|---|
| 1 | **git** | ✅ **guarded** — CI step + `RoutingKeyTests`, both positive-controlled 2026-08-20 | done |
| 2 | **the build log** | ❌ **open** — `xcodebuild` echoes every build setting in clear text, and the key *is* a build setting | the Worker (nothing to echo) |
| 3 | **the IPA** | ❌ **open, and not "obfuscated"** — see below | the Worker |

### ⚠️ Exit 3, measured rather than assumed (2026-08-20)

**VERIFIED on this machine.** Two built bundles in `DerivedData` carry a **plaintext
32-hex key** in `Kamome.app/Info.plist`, read out with stock `PlistBuddy`:

```
PLAINTEXT 32-hex key found in: …/Build/Products/Debug-iphonesimulator/Kamome.app/Info.plist
```

**`Info.plist` is a separate file in the bundle, not compiled into the executable.**
App Store binary encryption (FairPlay) covers the executable, **not** resources. So
extraction from a shipped or TestFlight build is:

```
unzip the .ipa  →  plutil -p Payload/Kamome.app/Info.plist
```

Three commands, stock tools, no disassembly. **There is no "securely packaged" state
today** — do not describe it as one.

**Do not add obfuscation.** XOR-ing or splitting the string moves plaintext to
slightly-less-plaintext, buys nothing measurable, and creates exactly the false
confidence this note exists to remove. The Worker is already written (`556f828`); use
it rather than decorating the problem.

### The TestFlight position, recorded as an accepted risk

**Chiu, 2026-08-20:** TestFlight builds go to people he knows, on a free tier, so a
readable key is acceptable there. **That decision is sound** — worst case is quota use
he would notice, remedied by rotating. It is recorded as *accepted*, not as *safe*.

### ⚠️ The Worker moves the secret. It does not close the abuse surface.

The step everyone forgets: once the key is off the device, **the app ships the Worker
URL instead** — and that URL is in the same readable `Info.plist`. It is not a secret,
but it is an **open routing proxy on Kamome's quota**. Anyone who unzips the IPA gets
free routing.

So "key removed" is not "problem solved". **App Attest** (already noted below as
optional) is what actually closes it, or failing that a per-IP rate limit on the
Worker. Decide which before submission — not after a quota bill.

### The submission checklist — mechanical, run on the artifact

Not a promise; a set of commands whose output is the evidence.

1. **The archive carries no key.** Unzip the `.ipa`/`.xcarchive` and grep every file
   for a key-shaped string. Zero hits is the pass condition — check the *artifact*,
   never the source.
2. **`Info.plist` carries the Worker URL and no key field**, or a key field that is
   empty.
3. **The Worker's secret is a `wrangler secret`**, never a committed file, and the
   deploy is verified to answer with the app sending none.
4. **The Worker is explicitly no-log** — no request bodies, no coordinates, no
   retention. A proxy that logs makes §0 worse while appearing to make it better.
5. **Abuse control is decided** — App Attest, or a rate limit, or an explicit written
   acceptance that the endpoint is open.
6. **Build logs.** Once the key is not a build setting, exit 2 closes by construction.
   Until then, no build log leaves the machine unscrubbed.
7. **Rotate once at submission**, after the artifact check passes, so that whatever
   any development log ever held is dead.

---

## 🔴 The routing API key must not be in the binary

**This is the one that is newly true**, because routing moved to a hosted
provider on 2026-08-16.

**Today** the key reaches the app through a gitignored `.xcconfig` and lands in
`Info.plist`. That keeps it out of git — which is the problem that actually
exists while Kamome is used by Chiu and a few friends — but **it is still inside
the IPA, and anyone who unpacks a shipped build can read it.**

**Provider-side key restriction does not save this.** Geoapify's restrictions
(IP allowlist, HTTP referrer, CORS origin) are all browser mechanisms: a phone's
IP is dynamic, a native request carries no referrer, and native apps do not do
CORS. Bundle-ID validation is a Google-specific feature that routing providers
generally do not offer, so **this is not a reason to pick a different provider —
every hosted API has the same problem with every native app.**

**Before submission, the key moves off the device entirely:**

```
iOS app ──(no key)──▶ Cloudflare Worker ──(+ key)──▶ Geoapify ──▶ back
```

- A Worker is **not** a self-hosted OSRM. It forwards an HTTP request: a few MB,
  effectively no computation, no map data, no graph rebuild. Cloudflare's free
  tier is 100,000 requests a day against Kamome's tens per film.
- The key lives in a Worker secret, never in the app.
- **The Worker must be explicitly no-log.** This is the part that is easy to get
  backwards: a proxy *adds* a party that sees every trip's coordinates. If it
  logs, §0's story gets worse while appearing to get better. No request bodies,
  no coordinates, no retention.
- **The app-side change is one base URL** — from the provider's host to the
  Worker's — which the existing release guard already accepts, since it requires
  `https` or empty.
- Optional afterwards: **Apple App Attest**, so the Worker only serves requests
  from a genuine install.

**Two reasons were added to this on 2026-08-20**, from the provider survey
(`Docs/decisions.md` 2026-08-20):

1. **`/v1/routing` is GET-only** — `POST` returns 404 — so real trip coordinates
   travel **in the URL query string, beside the key**, and a URL is the most-logged
   part of an HTTP request. Cloudflare fronts Geoapify (the survey saw `cf-ray`), and
   edge logs record URLs by default. The Worker is the only hop whose shape Kamome
   controls, which makes its **no-log requirement load-bearing rather than tidy.**
2. **Geoapify emits no 429 and no `Retry-After`** at 28.7 req/s — overload arrives as
   a TCP reset, so "the service is busy" and "we can't reach the service" are one
   event on the wire. A Worker *can* return a real 429, which is why
   `RouteProviderFailure.rateLimited` stays in the code rather than being deleted as
   dead.

## 🔴 Attribution has to be visible in the app

*(Geoapify was confirmed as the provider on 2026-08-20 — `Docs/decisions.md`. This
section was written ahead of that and is now backed rather than provisional.)*

Geoapify attribution is **mandatory on the free plan**, and OpenStreetMap
attribution is always required. Chiu's decision (2026-08-17) is that the app's
interface is where it goes, not the rendered video — nothing in the terms
requires it inside exported media, and the film draws a *line* rather than
displaying place data as data.

**One future change would reopen that:** the iceboxed "place names as narrative
rhythm" feature draws place names into the film. If those names come from
Geoapify rather than `CLGeocoder`, the condition to keep attribution *with the
returned data* starts to bite.

## ⚪ Two Geoapify terms questions — risk accepted, do NOT block on them

Read on 2026-08-20 (`Docs/decisions.md` 2026-08-20 (b)). Neither blocks Phase 4.

**Chiu decided 2026-08-20 (c): proceed without asking.** Both are ambiguous edges
with no realistic legal exposure, and the remedy in either case is to upgrade the
plan or stop. Kept on this page as *known accepted risk*, not as a blocker.

- **Permanent storage of routing results** — the Terms are **silent**, which favours
  us: no clause to breach. The fallback if it ever changes is already built — route
  at export time instead of reading `matched_polyline`; offline re-export degrades,
  nothing breaks.
- **"Limited commercial use" is undefined**, and a publicly distributed app is the
  case the terms never address. Volume is not the issue (3,000 credits/day against
  ~58 requests per Iceland film).

The mitigation is the **dated record** in `Docs/decisions.md` 2026-08-20 (b) — the
URLs and what each document said on the day.

Attribution, now confirmed: OSM attribution **always**, Geoapify attribution
**mandatory on Free**, format `Powered by Geoapify` with a link. **Where** it appears
is unspecified, which leaves the 2026-08-17 in-app decision intact.

## 🟠 The privacy policy has to exist, and has to be true

Chiu's §0 line (2026-08-20): recorded trips are the user's own; **photo-imported
trips send their coordinates to the routing provider, walks included**, and that gets
declared honestly rather than hidden.

What a truthful notice has to say, from Geoapify's own Privacy Policy: they retain
**request body, headers, IP address and timestamp**, for **no longer than 24 hours**
for *successful* requests — failures are not covered by that sentence — and
`/v1/routing` is **GET-only**, so the coordinates sit in the URL.

**Both open questions were closed on 2026-08-20 (c).** Recorded traces **are** sent —
without them there is no route data — and the answer is honest declaration. And the
notice must describe the **two different payloads**, because they are not the same:

| | photo-imported leg | recorded leg |
|---|---|---|
| what is sent | the leg's waypoints — stop centroids **plus photo positions**, thinned to ≥250 m, ≤100 per leg | **the full recorded trace**, in chunks of ≤100 points |
| shape | GET — **in the URL** | POST — in the body (after migration) |

⚠️ **"Start and end coordinates" is not a truthful description of either.** A notice
that understates what is sent is worse than no notice.

⚠️ **The album path ships with the notice, or the notice does not mention it.**
Selecting an album (`Docs/cross-region-journeys.md` requirement 1, the cheap half) is
now the control the privacy story rests on — a notice may not promise a control the
app does not offer.

## 🟠 The six items §6b did not pass

Phase 3.5 closed on 2026-08-15 with §6a passed and §6b explicitly not
(`Docs/decisions.md`). These moved here rather than being waived:

- Only **two of three trips** ever ran on a device.
- **Limited Photo Library** path never exercised on hardware.
- **S5 UX pass** (`Docs/device-test-P3.md` item G) never done.
- **Per-trip export time** never recorded from the S5 readout.
- **Memory behaviour** at full frame count never observed.
- **The souvenir map has never rendered on a phone** — both device films fell
  back to Apple Maps. Moot while MapLibre is parked; it returns if that reopens.

## 🟠 Export has to survive an ordinary phone

Measured on device: **0.72–1.55 seconds per map snapshot**, one snapshot per
`keyframe_interval_frames`, so a 3.5-minute film costs around six minutes and the
phone gets warm enough that thermal throttling makes longer films worse than
linear.

- `ExportLifecycleGuard` holds the idle timer and a background assertion, and is
  **implemented but never verified on a device** — a locked screen mid-export is
  exactly what a simulator cannot tell you. **Verify it in the first device
  session**: start an export, lock the screen, wait, see whether it survives.
- Resumable export is deliberately **not** built. `AVAssetWriter` cannot resume
  across process death; that is a project, not a fix.
- The largest available saving — the opening's per-frame snapshotting, worth
  roughly 3.3× — is **frozen pending a camera-transition design conversation**,
  not forgotten.

## 🟡 The user is never told that importing contacts a third party

Routing sends real trip coordinates to a hosted API. The failure copy tells
someone when routing *fails*; nothing tells them it happens at all. **§0 makes
this Chiu's decision, and it has not been made** — whether it needs saying, and
where.

## 🟡 Two date-selection edges, recorded not fixed

Photo `creationDate` is absolute time while `Calendar.current` is the device's
zone, so importing an Iceland trip from Taiwan shifts the day boundary by eight
hours and can clip photographs at either end. Fixing it needs per-photo timezone.

---

## What is *not* on this list, on purpose

Tiles, map labels and the tile server left the roadmap with the 2026-08-15
substrate ADR. Pixel Art is parked with MapLibre. Capture Beta, Story Director
and trip sharing are later phases, not submission blockers.
