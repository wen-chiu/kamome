# Before the App Store — what has to be true first

**Kamome is not being submitted yet** (Chiu, deliberately: the artefact comes
before the convenience). This file exists so the things that block a submission
are in one place rather than scattered across ADRs, a closed gate and a handoff.

Nothing here blocks Phase 4. Everything here blocks a submission.

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

Geoapify attribution is **mandatory on the free plan**, and OpenStreetMap
attribution is always required. Chiu's decision (2026-08-17) is that the app's
interface is where it goes, not the rendered video — nothing in the terms
requires it inside exported media, and the film draws a *line* rather than
displaying place data as data.

**One future change would reopen that:** the iceboxed "place names as narrative
rhythm" feature draws place names into the film. If those names come from
Geoapify rather than `CLGeocoder`, the condition to keep attribution *with the
returned data* starts to bite.

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
