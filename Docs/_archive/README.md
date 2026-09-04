# `Docs/_archive/` — history, never a work instruction

Nothing in this directory is current. Nothing here is executable. If an archived
document disagrees with `Docs/decisions.md`, `Docs/current-state.md` or
`HANDOFF.md`, **it is wrong and they are right** — that is what being archived
means.

Archived 2026-09-03 (ADR of that date, Chiu's instruction), and added to on 2026-09-04 as the type-2 opening round closed. The corpus had grown
13 → 53 documents in seven weeks with **nothing ever retired**, and the cost was
paid by every session at boot. What moved here is work that is **finished,
superseded, or parked** — not work that was abandoned.

## Resolving a path that no longer exists

`Docs/decisions.md` is append-only and its older entries cite the original
paths; so do comments in shipping source files. **Those citations were
deliberately not rewritten** — editing the ledger's history is worse than a
path that needs one lookup, and a PO session does not edit application code.
This table is that lookup. `git log --follow` also carries every file across
its move.

| cited as | now at | why it moved |
|---|---|---|
| `Docs/eng-session-P4.md` | `_archive/eng-session-P4.md` | executed — the Geoapify migration, ADR 2026-08-20 |
| `Docs/eng-session-P4-visual.md` | `_archive/eng-session-P4-visual.md` | executed and merged, PR #18 |
| `Docs/eng-session-camera-arc.md` | `_archive/eng-session-camera-arc.md` | executed and merged, PR #26 (crop-scaling) |
| `Docs/eng-session-closeout.md` | `_archive/eng-session-closeout.md` | executed — sprite tree and the key |
| `Docs/eng-session-appearance.md` | `_archive/eng-session-appearance.md` | shipped; the decision is ADR 2026-08-27 |
| `Docs/eng-session-cross-region.md` | `_archive/eng-session-cross-region.md` | session 1 shipped (PR #24/#31); session 2, the mode classifier, is deferred by name in `Docs/current-state.md` |
| `Docs/handoff-P3.5.md` | `_archive/handoff-P3.5.md` | Phase 3.5 closed 2026-08-15. **Its §6 gate item definitions are still the definitions** anything citing them means |
| `Docs/gate-P3.5-checklist.md` | `_archive/gate-P3.5-checklist.md` | the gate it sequenced closed 2026-08-15 |
| `Docs/handoff-recap-visuals.md` | `_archive/handoff-recap-visuals.md` | historical. **§3 vehicle-sprite constraints stay authoritative** — cited by `Core/ExportEngine/Resources/Vehicles/README.md` and `DESIGNER.md` |
| `Docs/handoff-render-layers.md` | `_archive/handoff-render-layers.md` | the refactor landed with PR #11; the architecture it built is in `Docs/current-state.md` |
| `Docs/handoff-camera-arc-findings.md` | `_archive/handoff-camera-arc-findings.md` | its own header said to archive it once Pass 1 was judged; Pass 1 merged as PR #26. ⚠️ **finding 5 carries a premise measured false** — banner inside |
| `Docs/kamome-animation-vision.md` | `_archive/kamome-animation-vision.md` | parked with MapLibre (ADR 2026-08-15). The storytelling identity survives in the spec §0 rule 6 |
| `Docs/vector-tile-pipeline.md` | `_archive/vector-tile-pipeline.md` | parked with MapLibre. **Dormant and accurate** — authoritative again only if Chiu reopens the substrate |
| `Docs/osrm-setup.md` | `_archive/osrm-setup.md` | routing is Geoapify since 2026-08-20; kept as the self-hosted fallback the 2026-08-16 ADR preserves |
| `Docs/dogfood-infrastructure.md` | `_archive/dogfood-infrastructure.md` | the §6 gate it served closed; fallback infrastructure |
| `Docs/routing-provider-selection.md` | `_archive/routing-provider-selection.md` | closed 2026-08-20 — the provider is Geoapify |
| `Docs/_audit/inventory.md` | `_archive/inventory-2026-08-21.md` | a point-in-time listing of a tree that no longer exists |
| `Docs/_audit/audit-2026-08-21.md` | `_archive/audit-2026-08-21.md` | that audit ran; `Docs/_audit/` no longer exists |
| older `HANDOFF.md` sections | `_archive/handoff-2026-08.md` | closed findings, 2026-08 and 2026-09 |
| `Docs/handoff-type2-films.md` §1–§3 | `_archive/handoff-type2-films-tasks.md` | the three tasks are built and judged; the **closeout stays live** in the original file (2026-09-04) |
| `Docs/handoff-type2-opening-retime.md`'s brief | `_archive/handoff-type2-opening-brief.md` | implemented in full; ADRs 2026-09-03 (b) and 2026-09-04 (b) carry the decisions (2026-09-04) |

## What is still load-bearing inside an archived file

Three, and only three. Everything else here is record.

1. **`handoff-P3.5.md` §6** — the gate item definitions. Anything that says "§6a"
   or "§6b" means those.
2. **`handoff-recap-visuals.md` §3** — the vehicle-sprite constraints, cited from
   the sprite directory's own README.
3. **`vector-tile-pipeline.md` and `osrm-setup.md`** — dormant, accurate, and the
   only description of the parked substrate and the self-hosted fallback.

Citing one of these from live work is fine. Citing anything else here as current
is the mistake this directory exists to prevent.
