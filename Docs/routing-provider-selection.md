# Choosing the routing provider — what to compare

**The decision to use a hosted third-party API on a free tier is made**
(`Docs/decisions.md` 2026-08-16, including its §0 consequence: real trip
coordinates now leave the device to a third party). **Which provider is not.**

This is the checklist for closing that. It is ordered by what can disqualify a
provider outright, not by price — price is nearly irrelevant here, because one
film is one request per drive leg (9 on Miyakojima, 17 on New Zealand, 58 on
Iceland) and a person makes a handful of films. **Any free tier absorbs the
volume. The terms are what decide it.**

## 🔴 Two questions that can disqualify outright — ask these first

### 1. May the returned route be stored permanently?

Kamome writes `matched_polyline` into the database and keeps it. That is not an
optimisation, it is the product: a trip is saved, re-exported offline months
later, and draws the same roads.

**Some providers forbid retaining results beyond a session or a fixed window.**
That conflicts with the architecture, not with a setting — such a provider is
unusable at any price. Ask this before reading anything else; it may remove half
the candidates.

### 2. Does it do map-matching, or only routing?

Kamome needs two different things, and they are two protocols in the code for
that reason:

| protocol | the question | used by |
|---|---|---|
| `RouteReconstructing` | sparse points → a plausible route through them | **photo import — today's path** |
| `RouteMatchProviding` | a dense GPS trace → which road it was on | passive capture — Capture Beta |

A routing-only provider **covers today and fails later.** That may be an
acceptable trade, but make it knowingly rather than discovering it in Capture
Beta.

## 🟠 One that changes the product rather than the engineering

### 3. Attribution — is it required, and does it have to be visible?

If a provider requires a credit, the real question is **whether it has to appear
in the rendered film.** Attribution inside the app is ordinary. A line burned
into every MP4 is a change to the artefact, and §6a's whole standard is whether
a film is worth publishing.

Read where the attribution has to sit, not just that it exists.

## 🟡 Four that change cost or feasibility

### 4. Does the free tier permit this use, and how is "commercial" defined?

An app given to friends, which may later reach the App Store, sits in the
ambiguous middle of most definitions. **Read the definition, not the heading.**

### 5. The shape of the rate limit — per second, not per month

Kamome is **bursty**: one Iceland film is 58 sequential requests. A plan with a
generous monthly quota and a low per-second cap will stall on that burst, and
`matching.trip_budget_s` (60 s) will spend itself waiting. The monthly number is
almost certainly fine; **the per-second or per-minute number is the one that
binds.**

### 6. Are failures distinguishable?

The user-facing copy deliberately separates "the routing service is busy" from
"we can't reach the routing service", and only the time-budget case promises that
exporting again will help — because that budget is ours and the other failures
are not (`Docs/decisions.md` 2026-08-15, and the rule: **Kamome only promises
what Kamome controls**).

A provider that returns opaque 500s for everything makes that distinction
unachievable, and the copy becomes a guess. Look for a real 429 and a
`Retry-After`.

### 7. §0 — what does the provider log, and for how long?

Real trip coordinates go there now. **Their retention policy becomes part of
Kamome's privacy story**, and the product's central claim is that this data is
safe here. There is no correct answer to weigh against; the point is to know what
was agreed to rather than to find out later.

### 8. Response shape — a cost, not a gate

OSRM-compatible means roughly a URL change. A different shape means one new file
conforming to the two protocols. **The boundary survives either** — OSRM's wire
format lives only in the two provider files and everything downstream consumes a
domain-level `RouteMatchOutcome`, verified by architecture review 2026-08-15 — so
this changes the estimate by days, and decides nothing.

## When a provider is chosen

Three things land together, and none of them before:

- **Lift the detour-ratio plausibility gate out of `OSRMRouteProvider`.** It is
  Kamome's honest-provenance policy rather than an OSRM fact, and a new provider
  file would silently drop it. This is the one seam the migration actually needs.
- **Re-measure `matching.trip_budget_s`.** Its 60 s was chosen against a healthy
  local server at roughly a second a leg, never against a rate-limited tier.
- **Decide whether the user is told that importing contacts a third party.** No
  disclosure surface exists. The failure copy says when routing *fails*, not that
  it happens at all.

## Explicitly ruled out

**The OSRM demo server** (`router.project-osrm.org`). It is a demonstration
service, not infrastructure, and building an app that other people install on top
of it is a licensing question rather than a reliability one. Cheap is not the
same as free.
