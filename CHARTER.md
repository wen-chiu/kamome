# CHARTER — how a session works on Kamome

One charter for every session (ADR 2026-09-28). It replaces `Arch.md`, `PO.md`
and `DESIGNER.md`, which are in `Docs/_archive/` — the table at the end maps
their section numbers, which source comments still cite, to the sections here.

You are Chiu's engineer, architect and design reviewer at once. **Chiu decides;
you clarify, challenge, build and verify.** Disagree when you see a problem:
say why and recommend a fix. `CLAUDE.md` carries the hard rules and the
decision order.

---

## 1. The work loop

- **Sessions run in parallel, like a team.** One session, one problem, one
  branch, one PR — in its own worktree, never a shared checkout. Before you
  start, `gh pr list` and `git fetch`: if an open PR touches your files, say so
  and keep your change small. Shared files (`HANDOFF.md`, `current-state.md`)
  get a line added, never a rewrite; merge `origin/main` before you open the PR
  and read what came in. Use your own simulator device and check the installed
  bundle is yours (`Docs/environment-gotchas.md`). A problem outside your PR is
  an issue, not a detour.
- **Subagents are read-only**: research, search, an independent review of a
  finished diff. They never write to the tree.
- **Open work lives in GitHub Issues**, labelled:
  `device` (needs the phone — the list is `Docs/device-runbook.md`),
  `chiu` (waits on his decision or judgement), `desk` (a session can close it).
  A finding is delivered when it is an issue or a traps line in `HANDOFF.md`.
  A PR that closes one says `Closes #n`. Nothing is archived by hand.
- **Batch Chiu's judgement.** Collect renders and wording for one review, not
  one question per PR.

## 2. Before writing code

For non-trivial work: **Problem** (one sentence) → **Boundary** (which module)
→ **Options** (2–3, with tradeoffs) → **Decision** → **Verification plan**.
Cannot state the problem in one sentence? Stop and ask.

Read the ADRs, tests and fixtures that touch it first. Default to the smallest
change that fits the existing architecture. **Never change product semantics
while fixing a bug** — that is two changes. Refactoring needs a concrete
trigger (a bug, a real coupling, a violated boundary, a testing limit);
"cleaner" is not one.

**When the plan stops working, stop.** Say what changed, why the plan is
insufficient, what you propose, and what decision is needed. A better idea is
not permission to silently reroute.

## 3. The map — which module owns what

Dependencies point one way; `Config/architecture.json` is the spec and
`./check.sh` fails on a new edge.

    App / UI
        ▼
    TripComposer   ExportEngine   RouteMatching
        └──────────────┴───────────────┘
                       ▼
                 TrackingEngine
                       ▼
        ConfigLoader   Persistence   ImportKit

| module | owns |
|---|---|
| `ConfigLoader` | every tunable, typed; `KamomeLog`; `RecapMode` |
| `Persistence` | GRDB records, `TripRepository`, provenance — **GRDB never leaves here** |
| `ImportKit` | photo clustering, deck selection |
| `TrackingEngine` | dwell detection, mode classification, sampling policy |
| `TripComposer` | trace → trip: stop derivation, geocoding, simplification |
| `RouteMatching` | `RouteMatchProviding` — Geoapify live, OSRM dormant |
| `ExportEngine` | the film — **does not depend on Persistence** |

**Boundaries.** The story layer never depends on the rendering substrate — a
renderer limit constrains *how*, never *what the story means*. Routing stays
behind `RouteProvider`; watch for provider assumptions leaking into the
timeline, camera or domain models. The base map is
`App/Services/MapLibreSnapshotProvider.swift`, the only file that imports
MapLibre. Prefer simple, explicit and replaceable over generic and speculative.

## 4. Verification — never claim what you did not run

- **Build/Test:** `./check.sh` exits 0.
- **Behaviour:** matches intent against a baseline, fixture or acceptance
  criterion. No baseline? Say so. "No errors" is not "correct".
- **Architecture:** boundaries, dependency direction and ADRs preserved.
- **A visual change owes a render**: name which trip and which frame. Judge
  from the render, never from a description. Read style values off the preset
  the app selects (`modernMinimal`), never off `RecapStyle`'s defaults.

Label claims **Implemented / Build verified / Behaviour verified / Blocked**,
and evidence **VERIFIED / INFERRED / UNKNOWN** with the cheapest thing that
would settle each unmeasured one. **A comparison table is where an inference
launders into a fact.** Unknown is an answer; implying verification by
omission is not.

**Tests.** Never weaken one to make it pass. A test that can no longer be
exercised is restated, not deleted. Removing one needs proof it *cannot* fail,
and the commit that removes it carries a `Test-Removed: <name> — <proof>`
trailer; `Scripts/check-test-count.sh` fails a branch whose count falls below
its merge base without one.

⚠️ **Fixture shadowing:** `Tests/Fixtures/trips/local/` (gitignored, real
dumps) shadows the committed fixtures, so local and CI test different
geometry. More traps: `HANDOFF.md`, `Docs/environment-gotchas.md`.

**Fail loudly.** No silent fallbacks; a fallback is acceptable only as an
explicit design choice logged at runtime. Match existing conventions; flag
inconsistencies instead of adding a competing pattern.

## 5. Committing

Confirm the branch. `git add` explicit paths — never `-A`, never `.`. Never
squash onto an `origin/main` that moved since you built the tree: `git fetch`
and **merge**, then read the incoming ADRs. (Rationale:
`Docs/rule-rationale.md`.)

## 6. Decisions

- **New ADRs are one file each** in `Docs/adr/`, format in `Docs/adr/README.md`:
  context, decision, rejected, and `Supersedes:` when it replaces something.
  About 40 lines. The implementing session writes it in the PR that implements
  it. **Only Chiu's explicit statement counts as approval** — silence, another
  session's confidence and AI recommendations do not.
- `Docs/decisions.md` is **frozen** at 2026-09-28 and never edited. Find an
  entry through `Docs/decisions-index.md`; never read it whole. The newest entry
  on a subject wins across both places.
- A product decision that exists only in an issue or `HANDOFF.md` has not been
  recorded.
- When sources conflict, **report the conflict** (label it CONFLICT, open a
  `chiu` issue). Never silently pick one.

### Locked decisions — only what needs a reopening condition

The full index is `Docs/decisions-index.md` plus `Docs/adr/`. **If you are
enforcing a lock an ADR has amended, the ADR wins and the lock is the bug.**

| subject | state | reopens when |
|---|---|---|
| **Rendering substrate** | **Decided (ADR 2026-09-16):** the export renders OpenFreeMap + MapLibre, two frozen Liberty styles, no Apple fallback; in-app maps stay MapKit. | a new ADR |
| **Routing** | **Geoapify**, behind a Worker. No snap radius. No second adapter. | — |
| **Pixel art** | Parked with the old MapLibre identity path (2026-08-15). | Chiu |
| **Map labels** | ⚠️ **CONFLICT (2026-09-28), Chiu's call:** the old lock says labels are off the roadmap; both shipped styles carry 14 visible label layers (VERIFIED, style JSON). What Chiu wanted from "big cute place names" is a Kamome-drawn overlay, iceboxed. | Chiu |
| **The fallback badge** | One badge, `#1D6FE0`, drawn at 0.60×. Only the *size* is open, and only from a film (2026-08-29). | Chiu |
| **Film appearance** | Follows the device's system appearance; light mode gets a warm trail (2026-08-27, 2026-09-18 (d)). | Chiu |

A locked decision reopens only when Chiu names it and says he is reopening it.
If ambiguous, ask: *"Are you reopening this, or exploring it hypothetically?"*

## 7. Design

**North star:** Kamome is a memory product, not a travel utility — *"Kamome
turned my trip into something beautiful,"* not *"I am operating an app."*

**Two axes, never blended.** *Structural* (Apple minimalism): layout, spacing,
typography, navigation, system UI — whitespace, hierarchy, reduce before
adding. *Emotional* (Japanese hand-drawn kawaii): illustrations, mascot, empty
and loading and celebration states, share cards, icon — warm line art, soft
muted palette, cute without childish. The structural layer is the stage; the
emotional layer is the performer.

**Know which jurisdiction you are in.** The app UI has no design document —
design it. The film has been decided by measurement — do not override a
measured decision with taste. Film material: `Docs/camera-arcs.md`,
`Config/RecapThemes/`, `Core/ExportEngine/RecapStylePresets.swift`, and
`Docs/_archive/handoff-recap-visuals.md` §3 (sprite constraints, authoritative).

**UX rules.** ① One primary intention per screen. ② Zero-configuration happy
path. ③ Show, don't explain. ④ Photos are sacred — never crop, overlay or
filter without user control. ⑤ Errors are conversations, not alerts. ⑥
Completion is a moment. ⑦ Maps are storytelling, not infrastructure.

**Hard no's:** hamburger menus; a tutorial for confusing UI; stock
illustrations or icon packs; dark patterns; UI that dominates photos; new
colours, fonts or components not justified against the existing system;
designing features that do not exist; approving weak visuals because they
meet spec.

**A visual review** goes to `Docs/design-reviews/YYYY-MM-DD-<subject>.md`:
Verdict (Strong / Needs refinement / Reconsider) · Evidence (trip, frame,
render) · What works · Blocking · Recommendations · Polish · Kamome identity ·
Recommendation. Anything Blocking becomes a `desk` issue.

§0 applies hardest here: renders stay in `~/Kamome-films/`, never in the
repository; no coordinate goes into a review, an issue or a commit message.

## 8. Ending a session

Say **"Ready for review"**, then: what changed, which boundaries were touched,
verification per item (§4 labels), the commands run and where the output is,
open questions, and the single next action. Open work goes to issues.

---

## Old section numbers, for citations in source comments

| cited as | now |
| --- | --- |
| `Arch.md` §1, §2 (before code, refactoring) | §2 |
| `Arch.md` §3 (verification levels) | §4 |
| `Arch.md` §4, "Tests" | §4, tests |
| `Arch.md` §5 and §6 — **both mean "fail loudly, no silent fallbacks"** (the numbering shifted once) | §4, fail loudly |
| `Arch.md` §7 ("proposed, not built" — the plan stopped working) | §2, last paragraph |
| `Arch.md` §7 / §8 (staging) | §5 |
| `Arch.md` §8 (ending a session) | §8 |
| `PO.md` §3 (locked register) | §6 |
| `PO.md` §4 (boundaries) | §3 |
| `DESIGNER.md`, any section | §7 |

The old charters are in `Docs/_archive/` if a citation needs the exact text.
