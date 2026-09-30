# Kamome — current state

The snapshot of the project TODAY. **An index, not a source of truth**: every
claim carries a pointer and the pointed-at document wins on detail. Keep it that
way — this file rotted twice by growing its own reasoning.

## Staleness

Last synced: 2026-09-29 against ADR **2026-09-29-the-opening-zooms-and-the-route-holds**
(the opening zooms out of the title card instead of cutting, reopening
2026-08-31; the revealed route holds before the end card). Before it:
2026-09-28-a-drive-is-never-framed-at-town-scale (Draft: a trip is framed by
its own towns, and travel is earned by windows); 2026-09-28-sample-trip (an
empty Home offers a sample trip, Hualien to Taitung, with its road shipped and
drawings for photographs); 2026-09-28, governance v2, the ledger's last entry.

**This file is the snapshot of what is true, not a list of what is open.** Open
work is GitHub Issues (`device`, `chiu`, `desk`); phone-only checks are
`Docs/device-runbook.md`; traps are `HANDOFF.md`. Update this file in the PR
that lands an ADR, and name that ADR in the line above —
`Scripts/check-staleness.sh` fails if a newer one exists. Never bump the name
without re-reading what the ADR changes here.

## Product

Kamome (卡摸咩) is a **memory engine for road trips** (`CLAUDE.md` carries the
sentence). Not a GPS visualizer. North star in `CHARTER.md` §7; the original spec is
archived (`Docs/_archive/kamome-poc-spec.md`).

**No release is in flight.** The current work proves the *artefact* ahead of
productisation (Chiu 2026-08-15). The next release target is Phase 2 (App Store),
gated by `Docs/release-readiness.md`; nothing there blocks Phase 4.

## Current phase

**Phase 4 — films worth keeping** (opened 2026-08-15):

1. ✅ Vehicle sprites — PR #15.
2. ✅ Cross-region crossing — PRs #24/#31.
3. ~~Export that survives~~ — **dissolved 2026-09-02**: film half in ADR
   2026-08-31 (b), release half in `Docs/release-readiness.md` D1–D3.
4. **Closeout** — four steps, named 2026-09-10. ① ✅ film record (ADR
   2026-09-08). ② ✅ export outlives the screen (ADR 2026-09-10). ③ ⏸ D1–D5 and
   ④ ⏸ performance — the substrate evaluation is concluded and the production
   switch has landed (ADR 2026-09-16); performance now prices `MLNMapSnapshotter`, not
   `MKMapSnapshotter`. Deferred, not dropped; **② does not settle D1**. Music is
   outside the closeout.

⚠️ **Phase 4 has no hard gate and none is to be written** (ADR 2026-09-02,
amending `CLAUDE.md` rule 7 **for Phase 4 only**). It closes when Chiu judges a
film good enough to release. Do not propose a checklist for it.

**Closed:** Phase 3.5 (Replay MVP) 2026-08-15 — §6a passed, §6b did not; its six
unmet items are on the release gate. Phases 0–3 done. P5 Capture Beta / P6 Plans /
P7 backend deferred.

## Where the work actually stands

**Every Phase 4 film that was in flight has landed and been judged**, the type-2
opening included — retimed, with a boarding pass, a plane and two marked flight
ends (ADRs 2026-09-03 (b), 2026-09-04 (b)). What is open is Chiu's judgement, in
`HANDOFF.md`, which wins on findings and blockers. ✅ **The production switch has
landed** (ADR 2026-09-16, PRs #71–#72): OpenFreeMap + MapLibre replaces Apple Maps
in the export, with no Apple fallback, and Apple geocoding is a §0 exception
scoped to **stop points** (#72). **Journey Discovery ships as an added feature
in beta, not the home** (ADRs 2026-09-17 → 2026-09-18 (c)): S1 and S3 are
restored untouched, the feature lives behind one toolbar button, and home is
never looked up. Discovery's thresholds ship INFERRED and its lookup timing is accepted
(2026-09-18 (e)); a photo at home ends a journey (2026-09-25). S1's dark override is lifted and the light style approved
(2026-09-18 (d) and addendum) — films follow the device. The terrain credit is
owed only where a licence requires it (2026-09-18 (f)).

What is between Kamome and a submission is **neither a document nor a session**:
**D1–D5**, one device run nobody has done — then Chiu's submission sequence, the
artifact check (`./check.sh --release`, needs the real key) and **then** the key
rotation, in that order. **TestFlight is not behind these** — it is how
D1–D5 get run (`Docs/handoff-testflight.md`). → `Docs/release-readiness.md`, `HANDOFF.md` 🔴.

## Architecture

- **Story ↔ Rendering separation** (`CHARTER.md` §3): the story layer never depends on the
  rendering substrate.
- **Rendering:** `RecapSnapshotProviding` is the boundary; each renderer confined
  to one file. **The export renders OpenFreeMap + MapLibre** (two frozen Liberty
  styles, dark and light); in-app maps stay MapKit. Apple fallback removed.
- **Routing:** `RouteProvider`-shaped boundary; **Geoapify**, key behind a
  Cloudflare Worker. Detour-ratio gate 2.5. **No snap radius exists or is needed**
  (ADR 2026-08-20 (d) — read it before citing any older snap-radius text).
  Bounded, cancellable, and it reports which of four causes dashed a film.
- **Camera:** `FollowCamera` dead-zone dolly, pre-simulated, one span per **area**
  (`CameraPathAreas`, ADR 2026-09-24); scale changes only in a reframe beat;
  a trip's scale comes from its own town density (two nearest towns in view),
  a zoom-in is earned only by days driven around one town, and travel lasts only
  as long as its windows need at `travel_pacing.windows_per_s` (ADR file 2026-09-28, Draft).
  Snapshots planned by `RecapSnapshotStations` (crop-scaling, PR #26). Two
  continuity gates scan **both** cameras — never relax them.
- **Export:** one film at a time, app-wide; `RecapExportCoordinator` outlives
  every screen (ADR 2026-09-10). **The substrate declares its own attribution**
  (`MapRendererCapabilities.attribution`) and the render loop draws it on every
  frame — MapLibre credits OSM, **MapKit credits nothing and must not** (ADR
  2026-09-12).
- **Config:** no magic numbers; every tunable in `Config/TrackingConfig.json`.
  ⚠️ **Two keys are dead** — tuning them does nothing
  (`Scripts/dead-config.baseline`). `total_duration_max_s` is Short's ceiling.
- **Infrastructure:** `.xcodeproj` generated by `xcodegen` from `project.yml`;
  env-gated harnesses via `TEST_RUNNER_` settings declared there; `Deploy/`
  (self-hosted OSRM + tiles) dormant as fallback.

## Locked decisions

`Docs/decisions-index.md` (frozen ledger) and `Docs/adr/` are the lookup;
`CHARTER.md` §6 carries the reopening conditions. Newest entry on a subject wins.

Two standing constraints that are **not** decisions: **film duration must scale
with trip size — direction decided (Chiu 2026-08-14), rule NOT**; and **Variant B
is not to be tuned** — Variant A is harness-only env overrides.

## Deferred — do not implement opportunistically

MapLibre substrate work beyond the frozen styles (custom tiles, tile server, map
labels, pixel art) — the production switch landed (ADR 2026-09-16) · Story
Director's remaining content (chapters, music, video beads — hero photos
reopened, ADR 2026-09-24) ·
transit routing as a road profile · walk-narrowing for recorded trips · the
crossing **mode classifier** (plane / ship / seagull) · **type 3** multi-region
films · the duration rule's candidate formula and the travel-pacing tunable ·
per-act camera framing (rejected 2026-08-02; per-**area** framing built 2026-09-24) · "Place names as narrative rhythm" (`Docs/_archive/icebox.md`).

## Authoritative sources — higher wins; newest wins within a level

| what | where |
|---|---|
| Product intent & rules | `Docs/_archive/kamome-poc-spec.md` (v1.8 — §0 rules and §4 provenance still authoritative) |
| Decisions | `Docs/adr/` (one file each, from 2026-09-28); before that `Docs/decisions.md`, frozen, via `Docs/decisions-index.md` |
| Open work | GitHub Issues — **win over this file on anything open**; traps in `HANDOFF.md` |
| Current state | this file; `CLAUDE.md` is the boot file |
| Release gate | `Docs/release-readiness.md` |
| Governance / conduct | `CHARTER.md` — one for every session |
| Rule rationale | `Docs/rule-rationale.md` |
| History | `Docs/_archive/` — and `Docs/_archive/README.md` resolves any path that moved there |
