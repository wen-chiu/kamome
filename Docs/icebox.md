# Icebox — ideas deliberately not in the current sprint (spec §1.4/§9)

Entries move out of here only via a spec version bump.

## Creator b-roll export (post-v1 wedge candidate)
Travel creators pay for tools and their shares self-advertise. But they want
**material control, not finished TikToks**: 4K, transparent-background,
speed-adjustable map-animation b-roll that drops into their own edit. Higher
price point than consumer per-trip export (§1.6). Do not build a template
library for them.

## Group trips (v2 at the earliest)
Merging several phones' tracks into one recap is genuinely viral, but sync +
merge + everyone-must-install is a cold-start and infra trap for a solo dev.
Revisit only after fork loop (Phase 6) proves organic sharing.

## Auto trip detection (arm-nothing capture)
Passive tier v2: detect trip start with zero user action (first SLC fix far
from home region → "looks like you're on a trip — recording?" notification).
Needs the Capture Beta tier proven first; also raises the App Review bar (§6 —
current posture is "only between explicit Start/End").

## Google Timeline importer — dropped as redundant (owner 2026-07-20)
Was Phase 4 scope; cut. Photo-EXIF import already reconstructs *past* trips and
in-app capture (Capture Beta) covers *new* ones, so a Timeline parser adds
Google-export format-drift maintenance for little unique value. The
`imported_timeline` `trip.source` value stays reserved for forward-compat only.
Thaw only if real user demand for Timeline import appears. (`decisions.md`
2026-07-20 Replay MVP repositioning.)

## Subscription vs. transactional — decided, kept for the record
$4.99/mo subscription dies of churn at 2–4 trips/year usage. Transactional
per-trip export + yearly unlock-all + creator tier is the model (§1.6).

## Premium video styles / fork-count analytics
From spec v1.2 §1.6 — still parked.

## Video clips in the recap (post-P3-gate candidate)
Auto-excerpt short clips from videos the user shot mid-trip and play them at
their stop's hold (the clip replaces the photo card; the hold stretches to
clip length, still counted inside `export.max_hold_fraction`). Fits the
minimum-effort vision — zero editing by the user. Hard constraints when
thawed: **deterministic** excerpt selection (seed by trip id; §4.5 is a
deterministic frame pipeline with golden-frame tests, and re-exporting must
reproduce the same video), 2–3 s per clip (tunable), muted (consistent with
the no-music call), cap clip count. Blocked on: §4.5 steps 2–5 landed and the
<90 s render budget measured — per-frame video decode + composite is the
single biggest render-cost risk in the whole pipeline. (Decision record:
`decisions.md` 2026-07-17.)
