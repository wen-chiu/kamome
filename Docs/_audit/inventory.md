# Inventory — 2026-08-21

Stage 1 of the documentation audit (PO.md governance). Mechanical inventory only —
no document was read in full; data below is line counts, `git log -1`, H1/H2
headings, self-declared status lines from the first 30 lines, and verbatim grep
hits. No interpretation has been applied.

Working-tree note (branch `feature/geoapify-routing`): five files are **modified,
uncommitted** — `CLAUDE.md`, `HANDOFF.md`, `PO.md`, `Docs/decisions.md`,
`Docs/pre-launch.md`. Five files are **untracked** (blank "last commit" below):
`Docs/camera-arcs.md`, `Docs/eng-session-P4.md`, `Docs/eng-session-P4-visual.md`,
`Docs/eng-session-camera-arc.md`, `Docs/eng-session-closeout.md`.

## File table

| path | lines | last commit | declared status (first 30 lines) |
|---|---:|---|---|
| Arch.md | 157 | 2026-08-18 docs(arch): when removing a test is right… | none; title says "(Final)" |
| CLAUDE.md | 469 | 2026-08-20 docs(adr): Geoapify is the routing provider… **+ uncommitted edits** | none explicit; header declares spec "v1.7" authoritative; L127 heading declares "Current phase: 4 … Phase 3.5 CLOSED 2026-08-15" |
| HANDOFF.md | 1717 | 2026-08-20 docs(spec): v1.8 — journeys are multi-modal… **+ uncommitted edits** | "**Updated 2026-08-08.** Branch `feature/typed-legs-routing`…" (header date/branch predate later sections) |
| PO.md | 439 | 2026-08-15 docs(po): the charter stops defending a decision… **+ uncommitted edits** | charter; "This session never edits application code" |
| Docs/camera-arcs.md | 407 | (untracked) | "**Status: design recommended by the PO/architecture session (2026-08-21), NOT decided, nothing built.**" |
| Docs/cross-region-journeys.md | 262 | 2026-08-14 docs(cross-region): a crossing is a beat… | "**Status: requirements decided by Chiu (2026-08-14), design NOT decided, nothing built.** … Supersedes the two deferred stubs in `Docs/handoff-P3.5.md`" |
| Docs/decisions.md | 1897 | 2026-08-20 docs(spec): v1.8… **+ uncommitted edits** | "Append-only." |
| Docs/demos/phase0/gate-output.md | 35 | 2026-07-12 fix(project): generate Info.plist… | dated gate record (title carries date) |
| Docs/demos/phase2/README.md | 28 | 2026-07-14 feat(demo): Phase 2 gate artifacts… | none |
| Docs/demos/phase3/README.md | 32 | 2026-07-19 feat(matching): §4.4 validated end-to-end… | none; "Rendered 2026-07-19" |
| Docs/demos/phase3_5/import/README.md | 50 | 2026-07-21 feat(import): Replay MVP §1… | none; "Captured 2026-07-21" |
| Docs/demos/phase3_5/matching/README.md | 42 | 2026-07-19 feat(matching): §4.4 validated… | none |
| Docs/demos/phase3_5/modern-minimal/README.md | 113 | 2026-07-22 feat(recap): §3 draft v2… | "`modern-minimal.json` — **DRAFT v2, NOT signed off.**" |
| Docs/demos/phase3_5/substrate/README.md | 60 | 2026-07-21 feat(recap): Replay MVP §2… | "Landed 2026-07-21… **functional substrate**, not the shipping look" |
| Docs/device-test-P1.md | 51 | 2026-07-15 fix(location): arm dwell resume region… | none; "Chiu signs off; spec §7 Phase 1 gate" |
| Docs/device-test-P3.md | 97 | 2026-07-21 feat(import): Replay MVP §1… | "⚠️ Redistribution 2026-07-20 … history preserved, nothing marked passed" |
| Docs/dogfood-infrastructure.md | 191 | 2026-08-01 fix(tiles): terrain survives a plain Finder drag… | "**Local first** (Chiu 2026-07-29)" |
| Docs/eng-session-P4-visual.md | 112 | (untracked) | session paste-prompt; "Chiu rotated the key. The previous session was blocked by a key returning 401" (L19) |
| Docs/eng-session-P4.md | 118 | (untracked) | session paste-prompt; "Scope is **one task**" |
| Docs/eng-session-camera-arc.md | 111 | (untracked) | session paste-prompt; "…opening's every-frame interval are FROZEN for a design conversation" (L24) |
| Docs/eng-session-closeout.md | 123 | (untracked) | session paste-prompt; "Two closing tasks" |
| Docs/gate-P3.5-checklist.md | 510 | 2026-08-14 docs(gate): the §6b pre-flight, reordered… | "Consolidated 2026-07-31; … **revised 2026-08-13 for the §6a / §6b split**. Gate items live in `Docs/handoff-P3.5.md` §6 and stay authoritative" |
| Docs/handoff-P3.5.md | 669 | 2026-08-14 docs(cross-region): a crossing is a beat… | "(rewritten 2026-07-20)" — the Replay MVP work order in mandatory sequence |
| Docs/handoff-recap-visuals.md | 283 | 2026-07-26 docs(recap): close out the visuals phase… | "**This closes the recap-visuals phase.** … **Not merged — PR #11 holds until the §6 three-real-trip gate.**" |
| Docs/handoff-render-layers.md | 119 | 2026-07-24 docs(recap): mark RecapOverlayRenderer landed… | "**Not merged** — PR #11 holds until the §6 three-trip gate." |
| Docs/icebox.md | 232 | 2026-08-15 Merge origin/main into phase-3-recap… | "Entries move out of here only via a spec version bump." |
| Docs/kamome-animation-vision.md | 138 | 2026-07-21 feat(import): Replay MVP §1… | "**Status:** Product direction from Chiu, 2026-07-19… Scope note: long-term visual north star; not the MVP checklist" |
| Docs/kamome-poc-spec.md | 573 | 2026-08-20 docs(spec): v1.8 — journeys are multi-modal… | "**Doc version:** 1.8 (2026-08-20)"; changelog line also says "Routing provider closed as **Geoapify** the same day" |
| Docs/osrm-setup.md | 132 | 2026-07-21 feat(import): Replay MVP §1… | none; describes self-hosted OSRM backing §4.4 |
| Docs/pre-launch.md | 284 | 2026-08-20 docs(adr): Geoapify is the routing provider… **+ uncommitted edits** | "**Kamome is not being submitted yet**… Nothing here blocks Phase 4. Everything here blocks a submission." |
| Docs/prototype/README.md | 211 | 2026-07-20 docs: recap prototype findings + spec v1.6… | "**Status:** exploration complete → feeds spec §4.5 / §7 … nothing here ships" |
| Docs/routing-provider-selection.md | 121 | 2026-08-20 docs(adr): Geoapify is the routing provider… | "> ## ✅ CLOSED 2026-08-20 — the provider is **Geoapify**" |
| Docs/vector-tile-pipeline.md | 248 | 2026-07-22 feat(recap): render harness for §3… | "**Status:** authoritative implementer guide for the MapLibre substrate" |

## Heading map

H1 at margin, H2 indented; (Lnn) = line number for targeted reads. decisions.md's H2 entries are in the ledger index below.

### Arch.md
- (L1) Engineering Agent Operating Rules (Final)
  - (L11) 0. Decision Authority
  - (L27) 1. Repository Context Before Design
  - (L37) 2. Before Writing Any Code
  - (L53) 3. Product and Architecture Governance
  - (L63) 4. Refactoring Needs a Reason
  - (L73) 5. Code Quality Bar
  - (L83) 6. Abstraction Discipline
  - (L91) 7. Verification Is Mandatory
  - (L107) 8. Three Levels of Verification
  - (L117) 9. Baseline and Fixture Discipline
  - (L125) 10. When Verification Is Blocked
  - (L131) 11. Plan Deviation
  - (L137) 12. Communication Before Implementation
  - (L145) 13. Session Handoff
  - (L153) 14. Final Report

### CLAUDE.md
- (L1) Kamome — working memory for Claude Code
  - (L15) §0 · Location data never leaves the device by default (Chiu 2026-08-03)
  - (L45) Replay MVP repositioning (spec v1.7, 2026-07-20, Chiu) — READ FIRST
  - (L80) Recap visual pivot (spec v1.5, 2026-07-19, Chiu)
  - (L127) Current phase: **4 — films worth keeping.** Phase 3.5 CLOSED 2026-08-15
  - (L346) Phase 3 history (recap pipeline, spec §4.5/§7) — started 2026-07-16
  - (L456) Verification commands (run from repo root)

### HANDOFF.md
- (L1) HANDOFF — current state
  - (L17) Findings — PO/Architecture session (2026-08-21)
  - (L213) Findings — PO/Architecture session (2026-08-20)
  - (L512) 🐛 Known and not fixed — the import date range clips at timezone edges (2026-08-18)
  - (L539) ▶ RESUME HERE — MVP desk renders, 3 of 3 rendered, review in progress (2026-08-13)
  - (L641) ✅ §6a — CLOSED by owner (Chiu 2026-08-14)
  - (L668) ✅ §6a film review — all three judged (Chiu 2026-08-13)
  - (L764) ⏳ Pending decision — film duration must scale with trip size (2026-08-14)
  - (L872) ⏳ Pending experiment — travel pacing in Variant A (2026-08-13) — NOTHING DECIDED
  - (L956) 🔴 Open — intermittent `KamomeCore_KamomeExportEngine` bundle crash (2026-08-13)
  - (L988) ✅ REVIEWED AND APPROVED — recap camera (2026-08-09)
  - (L1149) ▶ Substrate decision — OSRM + MapLibre, behind swappable boundaries (2026-08-08)
  - (L1198) ▶ Pre-Phase-2 blocker — OSRM hosted-endpoint TOS unverified (2026-08-08)
  - (L1208) ✅ CLOSED — lint split (2026-08-07, landed as `4460d8d` / `850a995` / `6ae62a7`)
  - (L1313) Committed on this branch
  - (L1343) "Unnamed stop" — CLOSED 2026-08-04
  - (L1373) Deck budget — RESOLVED 2026-08-06 (`ea32ce9`, ADR in `Docs/decisions.md`)
  - (L1419) `stop_weighting_enabled` — reachable in BOTH modes, containment only empirical
  - (L1499) Open question — RecapMode may be two axes, not one (Chiu 2026-08-06)
  - (L1521) Known cosmetic tradeoff — flat glacier (Chiu 2026-08-06: leave it)
  - (L1534) Phase 2 (real app release) — parked, not blockers for Phase 1
  - (L1551) Base map — MapLibre is the substrate; MapKit is the uncovered-trip fallback
  - (L1579) Fixtures and the §6 gate — Stage 0
  - (L1620) Environment gotchas that cost time
  - (L1651) Tile regions need establishing headroom, not just coverage (2026-08-08)
  - (L1705) The seam is bounded by the collapse rule, not by taste

### PO.md
- (L1) Kamome — Product Owner & Architecture Governor
  - (L3) Role
  - (L15) Session Access & Scope
  - (L28) Current Situation
  - (L44) Product North Star
  - (L52) Locked Product Decisions
  - (L119) Core Product / Architecture Principle
  - (L149) Routing Boundary
  - (L169) Product Coherence Responsibilities
  - (L194) Architecture Coherence Responsibilities
  - (L220) Documentation Coherence
  - (L243) Decision Classification
  - (L284) Change Discipline
  - (L313) Verification Rule
  - (L331) Communication Style
  - (L360) Coordination with the Active Claude Code Session
- (L415) Initial Recovery Audit

### Docs/camera-arcs.md
- (L1) The contained arc — how the camera crosses a gap
  - (L26) 1 · The premise this corrects
  - (L48) 2 · The cost model this design is built on
  - (L74) 3 · The primitive: a contained arc
  - (L109) 4 · What the arc is fitted to: the local journey
  - (L165) 5 · Body span, and the per-act-framing line
  - (L198) 6 · What is NOT unified
  - (L239) 7 · The rendering rule: an arc is scaled, never cross-faded
  - (L273) 8 · The two gates: **no exemption, none at all**
  - (L321) 9 · What it costs
  - (L348) 10 · How to build and judge it — two passes, one thing at a time
  - (L382) 11 · Open questions — none decided
  - (L394) 12 · What must not happen

### Docs/cross-region-journeys.md
- (L1) Cross-region journeys — requirements and design space
  - (L15) Why this is open now
  - (L59) What Chiu decided (requirements, 2026-08-14)
  - (L93) The reframing this suggests
  - (L144) Classifying a crossing
  - (L179) Pacing a crossing
  - (L204) Choosing the photographs (requirement 1)
  - (L234) Open questions — none decided
  - (L251) What must not happen

### Docs/demos/phase0/gate-output.md
- (L1) Phase 0 gate run — 2026-07-12, dev Mac (Xcode 15.4, iPhone 15 simulator, iOS 17.5)
  - (L5) 1. `xcodegen generate`
  - (L12) 2. `xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 15'`
  - (L30) 3. `swiftlint`

### Docs/demos/phase2/README.md
- (L1) Phase 2 demo artifacts (spec §7 gate)
  - (L3) s3-demo-trip.png
  - (L19) photo-permission-priming.png

### Docs/demos/phase3/README.md
- (L1) Phase 3 demo — recap video (§4.5)

### Docs/demos/phase3_5/import/README.md
- (L1) Replay MVP §1 — Photo EXIF Import: S1 UI + honest provenance
  - (L8) What these show
  - (L16) How they were produced (deterministic, no faked pass)
  - (L31) ⚠️ Needs the physical device — NOT faked here (flagged per §0)

### Docs/demos/phase3_5/matching/README.md
- (L1) Phase 3.5 §1 — map matching before/after (handoff §1 item 3)

### Docs/demos/phase3_5/modern-minimal/README.md
- (L1) §3 Modern Minimal — design review harness (needs Chiu + a real render)
  - (L9) Status
  - (L24) What Chiu judges (the quality bar — vector-tile-pipeline §1)
  - (L43) How to check it (one command)
  - (L62) First-look stills (committed, 2026-07-22 — DRAFT v2 dark souvenir)
  - (L81) Findings from the in-sim render (2026-07-22)
  - (L94) Follow-ups gated on sign-off (all land in the switch-over PR)

### Docs/demos/phase3_5/substrate/README.md
- (L1) Replay MVP §2 — MapLibre souvenir-map substrate (demo artifact)
  - (L7) What landed (verified in-repo, CI-green)
  - (L26) What is NOT self-certified here (needs sim/device — flagged, not faked)
  - (L37) Reproduce a real frame locally (sim/device)
  - (L56) Attribution

### Docs/device-test-P1.md
- (L1) Phase 1 device test — checklist (Chiu signs off; spec §7 Phase 1 gate)
  - (L6) Build preconditions (decisions.md 2026-07-12: must land before this drive)
  - (L14) Setup
  - (L23) Drive (~2 h, mixed route)
  - (L35) Verify afterwards
  - (L45) Sign-off

### Docs/device-test-P3.md
- (L1) Phase 3 device validation — stop semantics + battery (next real drives)
  - (L7) ⚠️ Redistribution 2026-07-20 (Replay MVP repositioning — history preserved, nothing marked passed)
  - (L25) A. Park → walk ~20 min loop → return → drive  · **→ Capture Beta**
  - (L30) B. Park → sit in car ≥ 3 min → then walk  *(known edge, expected to fail)*  · **→ Capture Beta**
  - (L35) C. Park with GPS silence ~10 min → drive away  · **→ Capture Beta** (region-resume re-validation)
  - (L50) D. Traffic jam / true standstill ≥ 3 min  · **→ Capture Beta**
  - (L56) E. Battery  · **→ Capture Beta**
  - (L63) F. §4.5 render budget  · **→ Replay MVP gate (reframed 2026-07-20)**
  - (L80) G. S5 user-experience validation  · **→ Replay MVP gate**
  - (L91) H. Former Phase 3 hard gates — **split 2026-07-20**

### Docs/dogfood-infrastructure.md
- (L1) Dogfood infrastructure — routing + map regions for the Replay MVP gate
  - (L27) Regions
  - (L34) 1. Build and run it locally
  - (L78) 2. Later: moving to a VPS
  - (L105) 3. Map regions — build and side-load
  - (L171) 4. Gate checklist
  - (L187) Cost, when the VPS happens

### Docs/eng-session-P4-visual.md
- (L1) Engineering session — confirm the API, then look at the film
  - (L17) 0 — Before anything else: confirm routing actually works
  - (L29) 1 — The route line has a shadow around it. Find out why.
  - (L45) 2 — One map experiment, two dimensions at once
  - (L67) 3 — Render with `car-toy`, not the seagull
  - (L77) Not in this session — named so you do not pick them up
  - (L89) One thing you may fix, as its own commit
  - (L98) Verification and reporting

### Docs/eng-session-P4.md
- (L1) Engineering session — Phase 4, task 1: routing goes live
  - (L32) The task
  - (L45) What is already decided — do not redesign these
  - (L85) `matching.trip_budget_s` — measure it, do not pick a number
  - (L94) What counts as done
  - (L109) Before you write code

### Docs/eng-session-camera-arc.md
- (L1) Engineering session — the contained arc, Pass 1 (rendering only)
  - (L40) The task
  - (L67) Start with the throwaway
  - (L77) What is already decided — do not redesign these
  - (L96) What counts as done

### Docs/eng-session-closeout.md
- (L1) Engineering session — close out sprites and the API key
  - (L22) 🔴 Read this before your first command
  - (L36) Task 1 — the sprite tree: work out what it is, then commit it correctly
  - (L80) Task 2 — close out the API key, by verifying rather than trusting
  - (L114) Reporting

### Docs/gate-P3.5-checklist.md
- (L1) §6 Replay MVP gate — owner runbook
  - (L8) The split, and how these stages map onto it
  - (L25) Status — §6a is judged (2026-08-13)
  - (L43) Known defects — #1 fixed, #2 mitigated, neither blocking now
  - (L116) Stage 0 — real data (desk, ~30 min, do this first) — §6a ✅ DONE
  - (L155) Stage 1 — judge each trip at the desk — §6a ✅ DONE, kept as the procedure
  - (L234) Stage 2 — the iPhone (one sitting, the expensive part) — §6b, NOT STARTED
  - (L361) Stage 3 — sign-off (spans both gates)
  - (L380) Appendix — first device install (going straight to the phone)
  - (L449) Appendix — reading the log when a film comes out wrong
  - (L496) Not on this list, on purpose

### Docs/handoff-P3.5.md
- (L1) Handoff — Phase 3.5 = **Replay MVP** work order (rewritten 2026-07-20)
  - (L18) What the Replay MVP is
  - (L27) State at handoff
  - (L45) 1. Photo EXIF Import  ← START HERE (spec §4.7, schema v2 §3)
  - (L134) 2. MapLibre souvenir-map substrate (spec §4.5, `Docs/vector-tile-pipeline.md`)
  - (L196) 3. Modern Minimal theme — the ONE MVP theme (spec §4.5, Chiu in the loop)
  - (L236) 4. Vehicle-focused follow-cam (spec §4.5 step 1; prototype §2.3)
  - (L304) 5. Basic photo deck @ ~0.8 s (OverlayTimeline; prototype §2.2)
  - (L329) 6. Three-trip dogfood + Replay MVP release gate (needs Chiu + iPhone + real photos)
  - (L640) Not in the Replay MVP (do not build here)
  - (L652) Standing rules (unchanged, restated because they get violated under pressure)

### Docs/handoff-recap-visuals.md
- (L1) Handoff — Recap Layer 3 + visual redesign (2026-07-25)
  - (L13) 0. The camera is static — read this before the rest
  - (L50) 1. Layer 3 is wired — the render-layers refactor is complete
  - (L70) 2. North-up map — heading-up abandoned (Chiu 2026-07-25)
  - (L91) 3. Car = 8-direction sprite set, not one rotatable image
  - (L126) 4. Stop scene — zoom-in reveal + two beats
  - (L146) 5. Tests worth knowing about
  - (L164) 6. Carried forward from this work
  - (L176) 7. Base map, theme atmosphere, and stop layout (`f294883`)
  - (L245) 8. What is left before PR #11 can go up

### Docs/handoff-render-layers.md
- (L1) Handoff — Recap render-layers refactor (2026-07-24)
  - (L13) The architecture (the one rule)
  - (L30) 1. What landed (committed `c933121`, 115 tests green, swiftlint --strict clean)
  - (L71) 2. What's next — Layer 3 wiring (the visual-changing chunk)
  - (L104) 3. Key constraints (do not violate)

### Docs/icebox.md
- (L1) Icebox — ideas deliberately not in the current sprint (spec §1.4/§9)
  - (L5) Creator b-roll export (post-v1 wedge candidate)
  - (L12) Group trips (v2 at the earliest)
  - (L17) Auto trip detection (arm-nothing capture)
  - (L23) Google Timeline importer — dropped as redundant (owner 2026-07-20)
  - (L31) Subscription vs. transactional — decided, kept for the record
  - (L35) Premium video styles / fork-count analytics
  - (L38) Video clips in the recap (post-P3-gate candidate)
  - (L66) Flight legs — airport-to-airport journey framing (owner idea, 2026-07-21)
  - (L96) Beyond road trips — multi-modal journeys + per-segment mode icons (owner idea, 2026-07-21)

### Docs/kamome-animation-vision.md
- (L1) Kamome Animation Vision
  - (L37) Inspiration and core difference
  - (L52) MVP goal
  - (L65) Design direction
  - (L72) Route rendering
  - (L79) Visual quality vs. TravelBoast
  - (L86) Multiple art styles
  - (L102) Camera
  - (L109) Binding principles (Chiu's 2026-07-19 refinements)
  - (L126) Long-term vision & priorities

### Docs/kamome-poc-spec.md
- (L1) Kamome 卡摸咩 — POC Design Spec & Build Plan
  - (L25) 0. Rules of Engagement for Claude Code
  - (L38) 1. Product Definition
  - (L111) 2. Architecture
  - (L177) 3. Data Model (GRDB schema v1)
  - (L276) 4. Core Algorithms (spec level)
  - (L352) 5. UI Spec (SwiftUI screens)
  - (L369) 6. Permissions & App Store Compliance
  - (L381) 7. Build Plan — Phases & Hard Gates
  - (L482) 8. Repo Structure
  - (L505) 9. Risks & Mitigations
  - (L523) 10. Success Criteria (staged to the phase map, §7)
  - (L546) 11. Handoff Checklist & Kickoff (added v1.2)

### Docs/osrm-setup.md
- (L1) OSRM map-matching server — setup & validation
  - (L14) 1. Get extracts
  - (L36) 2. Preprocess (once per extract, car profile)
  - (L51) 3. Serve
  - (L87) 4. Point the app at it
  - (L98) 5. Validate
  - (L115) Troubleshooting

### Docs/pre-launch.md
- (L1) Before the App Store — what has to be true first
  - (L11) The order to ship in (Chiu 2026-08-20)
  - (L39) 🔴 The key has three exits, and only one of them is guarded
  - (L117) 🔴 The routing API key must not be in the binary
  - (L168) 🔴 Attribution has to be visible in the app
  - (L184) ⚪ Two Geoapify terms questions — risk accepted, do NOT block on them
  - (L207) 🟠 The privacy policy has to exist, and has to be true
  - (L235) 🟠 The six items §6b did not pass
  - (L248) 🟠 Export has to survive an ordinary phone
  - (L265) 🟡 The user is never told that importing contacts a third party
  - (L272) 🟡 Two date-selection edges, recorded not fixed
  - (L280) What is *not* on this list, on purpose

### Docs/prototype/README.md
- (L1) Recap visual prototype — findings & spec reference
  - (L20) 0. Positioning (this is the north star — put it above every feature call)
  - (L39) 1. What we tried (three iterations, all still viewable as artifacts)
  - (L53) 2. Validated design decisions (with Chiu's responses)
  - (L137) 3. Forward directions Chiu wants captured (import · video · music)
  - (L188) 4. Open questions for the app phase
  - (L200) 5. Files here

### Docs/routing-provider-selection.md
- (L1) Choosing the routing provider — what to compare
  - (L23) 🔴 Two questions that can disqualify outright — ask these first
  - (L50) 🟠 One that changes the product rather than the engineering
  - (L61) 🟡 Four that change cost or feasibility
  - (L103) When a provider is chosen
  - (L116) Explicitly ruled out

### Docs/vector-tile-pipeline.md
- (L1) Vector-tile pipeline — recap base maps (Phase 3.5 = Replay MVP)
  - (L12) 1. Why this exists (and when to abandon it)
  - (L47) 2. Architecture at a glance
  - (L68) 3. Data source
  - (L83) 4. Tile generation — Planetiler → PMTiles
- (L92) one-time per region; output committed to a data location, not the repo
  - (L113) 5. Hosting & distribution
  - (L137) 6. Style-sheet authoring (theme = MapLibre style JSON)
  - (L175) 7. iOS integration
  - (L198) 8. Determinism & CI
  - (L211) 9. Deliverables checklist (Phase 3.5, substrate portion)
  - (L240) Changelog

## decisions.md ledger index

ADRs carry no numeric identifiers; the identifier is the date heading (with
letter suffixes where one day has several). Line numbers are from the current
working tree (uncommitted edits included). "Status markers" are the only
status-like lines grep found inside the file — bodies were not read.

| ADR (line) | title | date | status markers found |
|---|---|---|---|
| L7 | GRDB 6.x, not 7.x | 2026-07-12 | — |
| L16 | Core code lives in a root SwiftPM package (KamomeCore) | 2026-07-12 | — |
| L26 | `kamome-smoke` executable mirrors the Phase 0 gate tests | 2026-07-12 | — |
| L36 | Generated `.xcodeproj` is gitignored | 2026-07-12 | — |
| L44 | postGenCommand downgrades project format for Xcode 15.4 | 2026-07-12 | — |
| L58 | Phase 1 device-test gate deferred (owner decision) | 2026-07-12 | — |
| L73 | Xcode 26.6 upgrade: objectVersion workaround removed | 2026-07-14 | contains "superseded" note at L78 |
| L84 | S4 photo reorder deferred (needs schema v2) | 2026-07-12 | — |
| L94 | Walk threshold raised to 6 km/h; mid band is non-evidence | 2026-07-12 | — |
| L106 | Derived speeds use a 30 s displacement baseline | 2026-07-12 | — |
| L118 | Dwell resume via CLLocationManager region monitoring, not CLMonitor | 2026-07-15 | — |
| L136 | Config loader module is `Core/ConfigLoader`, not `App/` | 2026-07-12 | — |
| L146 | Spec v1.3: battery-moat pivot (passive tier, import; fork deferred) | 2026-07-15 | — |
| L166 | Phase 3 starts now; device drive + photo-access check become P3 gate items | 2026-07-16 | — |
| L195 | Speed evidence gated by accuracy; geocoded names need address context | 2026-07-18 | — |
| L222 | Recap video: route photos in, export gets a photos toggle, video clips parked | 2026-07-17 | — |
| L256 | Fork demoted from positioning language to mechanism | 2026-07-18 | — |
| L285 | Stop detection redesigned around real stops: streaks, walk visits, silence gaps | 2026-07-18 | — |
| L323 | Recap chrome: photos toggle gates stop cards only; title/end cards always render | 2026-07-18 | — |
| L345 | stop.kind = what happened, never how it was detected | 2026-07-18 | — |
| L366 | Recap visual pivot: P3 frozen as pipeline milestone, Phase 3.5 opened | 2026-07-19 | — |
| L398 | ADR: recap substrate = MapLibre Native + self-hosted vector tiles | 2026-07-19 | amended by L1312 entry ("Amends the 2026-08-08 substrate ADR" chain — see L1090, L1314) |
| L448 | Drive finding: region-resume died after wake; recovery watchdog added | 2026-07-19 | — |
| L497 | Owner call: continue into Phase 3.5 while P3's device items stay open | 2026-07-19 | — |
| L519 | §4.4 map matching: app side landed, server-side deferred to setup doc | 2026-07-19 | — |
| L551 | Recap visual system validated on real data via a web prototype | 2026-07-20 | — |
| L608 | Replay MVP repositioning: photo-import recap ships first; capture → Capture Beta; Story Director & Plans deferred; honest provenance | 2026-07-20 | — |
| L721 | Replay MVP §2: MapLibre substrate landed (provider in app target, pmtiles ingestion, MapKit kept alive) | 2026-07-21 | — |
| L800 | §3 Modern Minimal: kicked off as a DRAFT (visual sign-off is Chiu's, on a real render) | 2026-07-21 | — |
| L824 | pmtiles ingestion CONFIRMED in-sim: `pmtiles://file://`, MapLibre renders in the simulator | 2026-07-22 | — |
| L856 | §3 visual direction corrected: dark atmospheric souvenir map (not pale "Modern Minimal") | 2026-07-22 | title itself is a correction |
| L889 | §3 signed off as the substrate; recap-output redesign moved to its own session | 2026-07-22 | — |
| L914 | Follow-cam camera core: wide-to-close framing, camera ≠ vehicle | 2026-07-23 | — |
| L955 | Stop presentation ported from the prototype's CSS, and the stop group flips as one cluster | 2026-07-31 | — |
| L1007 | Day and distance become persistent HUD, not stop chrome | 2026-07-31 | — |
| L1038 | Stop presentation is budget-constrained — derive the count, never assume one | 2026-08-06 | "**Status:** accepted" (L1040) |
| L1090 | MVP substrate is OSRM + MapLibre, behind swappable boundaries | 2026-08-08 | "reopened" (L1095); "**superseded by this entry**" (L1130); amended by L1312 entry (L1314) |
| L1138 | The recap camera: a configured zoom, and a wider establishing shot | 2026-08-09 | — |
| L1179 | The Replay MVP gate splits: §6a the film (desk, Variant A), §6b the product (phone, Variant B) | 2026-08-13 | — |
| L1251 | Phase 3.5 closes: §6a passed, §6b did not, and the phase map catches up | 2026-08-15 | "The phase map is not rewritten; it is corrected" (L1272); "Tile provisioning is reopened as a performance question" (L1294); "reopened" (L1305) |
| L1312 | MapLibre is parked, Apple Maps is what ships, and routing moves behind an API | 2026-08-15 | "**Amends the 2026-08-08 substrate ADR.** Reopened and closed by Chiu on the same…" (L1314) |
| L1385 | Routing is bounded, cancellable, and says which of four things went wrong | 2026-08-15 | — |
| L1439 | Export variation enters as a seed, never as randomness | 2026-08-15 | — |
| L1473 | Routing moves to a commercial API's free tier, and real coordinates leave the device | 2026-08-16 | "Self-hosted OSRM stays viable behind the same boundary if this is ever reversed" (L1516) |
| L1519 | 2026-08-20 (a) — Geoapify is the provider, and **two** policies must survive the migration | 2026-08-20 | sub-heads: "🔴 The consequence that is not in the survey…" (L1545), "Corrections to what the survey concluded" (L1593), "Open, and deliberately not guessed" (L1605), "§0 — GET-only changes the shape of the exposure, not the decision" (L1619), "What this does NOT decide" (L1632) |
| L1642 | 2026-08-20 (b) — Geoapify's terms, read; and what Kamome now commits to on privacy | 2026-08-20 | sub-heads: "Verdict: **not disqualifying, and the provider decision stands.**" (L1661), "⚠️ The retention clause has an edge…" (L1673), "Chiu's decisions, 2026-08-20" (L1686), "🔴 Item 3 needs one clarification before anything is built" (L1705), "🔴 The justification for item 3 describes a product that does not exist yet" (L1720) |
| L1731 | 2026-08-20 (c) — The terms risk is accepted; traces are sent; the notice must say what is actually sent | 2026-08-20 | sub-heads: "accepted, do not ask" (L1735); "⚠️ The approved wording understates what is sent — corrected here" (L1764); "The album path is now load-bearing for the privacy story" (L1785) |
| L1797 | 2026-08-20 (d) — The snap radius was the wrong mechanism, and it was never guarding what I said | 2026-08-20 | sub-heads: "What was claimed" (L1803), "What was measured" (L1810), "The correction, and it goes further than the engineering session claimed" (L1837), "Decision: the detour gate stays at 2.5, nothing new is built in this PR" (L1855), "Two items closed for free by the same probe" (L1876), "Addendum (Chiu, 2026-08-20) — recorded trips: the lean, parked" (L1883) |

## Conflict candidate hits

Verbatim grep hits (case-sensitive substring match, exactly the terms as given). Recorded, not interpreted. Per-term totals: MapLibre 183 · OSRM 130 · routing provider 4 · rendering substrate 1 · Phase 3.5 37 · Phase 4 34 · current phase 2 · release target 1 · location data 3 · privacy 17 · telemetry 2 · API 33 · Key 11 · single source of truth 1 · LOCKED 2 · SUPERSEDED 3 · DEPRECATED 0 · TODO 0 · TBD 1 · leg 176 · stop 371 · sprite 48 · export 149. Note for Stage 2: 'leg', 'stop', 'export', 'MapLibre', 'OSRM' are core domain vocabulary — their sections are lookup tables, not shortlists.

### MapLibre
- CLAUDE.md:57:  **Photo EXIF Import first** → MapLibre souvenir map → Modern Minimal (the
- CLAUDE.md:97:  between GPS points) → MapLibre substrate → Modern Minimal theme.
- CLAUDE.md:98:- **Substrate ADR** (decisions.md 2026-07-19): MapLibre Native +
- CLAUDE.md:107:  MapLibre types get the same one-file confinement). Deferred gaps, built
- CLAUDE.md:277:fetch**. MapLibre reads local `.pmtiles` from disk, and **has never been measured on
- CLAUDE.md:340:labels". Blocked on a missing `glyphs` fontstack (MapLibre cannot draw Latin
- HANDOFF.md:158:its region is the whole country"). MapLibre was parked on 2026-08-15, so there is
- HANDOFF.md:1117:before-vs-after did (7.11 vs 7.31 MB). The MP4/MapLibre path is **not
- HANDOFF.md:1149:## ▶ Substrate decision — OSRM + MapLibre, behind swappable boundaries (2026-08-08)
- HANDOFF.md:1153:> The MVP rendering and routing substrate is OSRM + MapLibre because it is
- HANDOFF.md:1159:> MapLibre.
- HANDOFF.md:1161:**Do not re-open or re-argue this.** MapLibre is retained precisely because it is
- HANDOFF.md:1174:- an Apple-Maps label workaround as a MapLibre glyph substitute
- HANDOFF.md:1176:MapLibre place labels stay iceboxed on the glyph/fontstack problem. **That Apple
- HANDOFF.md:1180:Maps, MapLibre is Chiu's own MVP path". That is no longer the decision.
- HANDOFF.md:1551:## Base map — MapLibre is the substrate; MapKit is the uncovered-trip fallback
- HANDOFF.md:1553:**Framing corrected 2026-08-08** (`Docs/decisions.md`). MapLibre is the committed
- HANDOFF.md:1563:and therefore always exercise MapLibre.
- HANDOFF.md:1568:   is a Kamome-authored style JSON only MapLibre consumes; MapKit renders Apple's
- PO.md:56:> **MapLibre is parked. The app renders Apple Maps in practice**, because no vector
- PO.md:58:> no region covers the trip. Nothing was deleted: the MapLibre provider, the
- PO.md:72:this file locked "the MVP rendering and routing substrate is OSRM + MapLibre — do
- PO.md:97:> Parked with MapLibre — it was the identity path MapLibre was retained for, so
- PO.md:102:### MapLibre Labels
- PO.md:136:- MapLibre
- PO.md:202:- MapLibre-specific leakage
- Docs/camera-arcs.md:30:path (`establishing == nil`, since MapLibre was parked) `buildWideOpening` frames
- Docs/decisions.md:382:  sequenced: OSRM matching (§4.4, pulled forward from P4) → MapLibre
- Docs/decisions.md:398:## 2026-07-19 — ADR: recap substrate = MapLibre Native + self-hosted vector tiles
- Docs/decisions.md:405:**Decision:** Recap base maps render via **MapLibre Native (iOS)** over
- Docs/decisions.md:407:regional extracts as OSRM) with a **Kamome-authored MapLibre style JSON
- Docs/decisions.md:415:MapLibre implementation is one new file (`MapLibreSnapshotProvider`)
- Docs/decisions.md:416:conforming to it, with MapLibre types equally confined. Known gaps,
- Docs/decisions.md:427:Boundary discipline is the rule: MapLibre types must never leak past the
- Docs/decisions.md:430:MapLibre + a Kamome style sheet must produce output *clearly
- Docs/decisions.md:508:device day anyway: the < 90 s budget must be re-proven on the MapLibre
- Docs/decisions.md:567:   MapLibre substrate ADR (2026-07-19) — the prototype is now the "before"
- Docs/decisions.md:633:  photo-EXIF import (schema v2 `trip.source`) → MapLibre souvenir-map substrate →
- Docs/decisions.md:640:  The MapLibre-vs-Apple side-by-side survives as a **design review** only; it
- Docs/decisions.md:721:## 2026-07-21 — Replay MVP §2: MapLibre substrate landed (provider in app target, pmtiles ingestion, MapKit kept alive)
- Docs/decisions.md:724:`Docs/vector-tile-pipeline.md`): build the MapLibre souvenir-map substrate that
- Docs/decisions.md:732:1. **MapLibre pinned exactly at `6.27.0`** (SPM,
- Docs/decisions.md:733:   `maplibre/maplibre-gl-native-distribution`, product `MapLibre`, added to the
- Docs/decisions.md:740:   `Core/ExportEngine/MapLibreSnapshotProvider.swift`, but that path is inside
- Docs/decisions.md:744:   `App/Services/MapLibreSnapshotProvider.swift` — same home as the other SDK
- Docs/decisions.md:748:   dependency; MapLibre cannot. The protocol is still the boundary; the file is
- Docs/decisions.md:749:   `#if canImport(MapLibre)`-guarded exactly like `MapKitSnapshotProvider` is
- Docs/decisions.md:751:   in `.github/workflows/ci.yml`: `import MapLibre` may appear in exactly one
- Docs/decisions.md:760:   unsupported in this MapLibre build. *Flagged: the actual tile render is Metal
- Docs/decisions.md:764:4. **Camera = center + span → MapLibre zoom** (Web Mercator, 512 px tiles,
- Docs/decisions.md:784:and **links** MapLibre (compile-checks the `MLN*` API usage); the confinement
- Docs/decisions.md:787:faked):** the actual MapLibre pixel output — tiles loading via `pmtiles://`, the
- Docs/decisions.md:793:— the protocol already is the boundary, ADR 2026-07-19); a floating MapLibre
- Docs/decisions.md:795:small cropped fixture is committed); adding a live-tile MapLibre golden test
- Docs/decisions.md:803:off** on real MapLibre stills (vector-tile-pipeline §1). MapLibre rendering is
- Docs/decisions.md:813:`RecapStyle.modernMinimal` preset, the `RecapModel`→MapLibre switch (which retires
- Docs/decisions.md:818:**Rejected:** self-certifying the look or switching production to MapLibre without
- Docs/decisions.md:824:## 2026-07-22 — pmtiles ingestion CONFIRMED in-sim: `pmtiles://file://`, MapLibre renders in the simulator
- Docs/decisions.md:826:**Context.** §2 landed the substrate with the actual MapLibre pixel render flagged
- Docs/decisions.md:833:1. **MapLibre renders in the simulator** (Metal). No device needed to eyeball the
- Docs/decisions.md:834:   base map; the golden-frame discipline (no MapLibre in CI) is unchanged — the
- Docs/decisions.md:836:2. **Ingestion path = `pmtiles://file:///abs/path.pmtiles`.** MapLibre 6.27.0's
- Docs/decisions.md:846:**New §3 sign-off item.** The snapshotter bakes MapLibre's own wordmark + a
- Docs/decisions.md:866:our stack: real MapLibre vector-tile geometry + a Kamome-authored style sheet that
- Docs/decisions.md:870:compositor** (vignette, route glow, grade), which §3 had not touched. So MapLibre
- Docs/decisions.md:892:"still not what I want, but this is not the MapLibre issue… we could sign off §3
- Docs/decisions.md:893:MapLibre for now, and do the compositor atmosphere later. The output video format
- Docs/decisions.md:897:- **§3 substrate is signed off** — MapLibre + the dark-souvenir base-style *direction*
- Docs/decisions.md:905:  `RecapStyle.modernMinimal` preset, and the `RecapModel`→MapLibre production switch
- Docs/decisions.md:911:**Rejected:** flipping production to MapLibre on this sign-off (premature — output is
- Docs/decisions.md:932:  (the "additive extension" the ADR 2026-07-19 anticipated). `MapLibreSnapshotProvider`
- Docs/decisions.md:938:  MapLibre-era opt-in (MapKit can't rotate; the marker's screen rotation is then
- Docs/decisions.md:1090:## 2026-08-08 — MVP substrate is OSRM + MapLibre, behind swappable boundaries
- Docs/decisions.md:1099:> "The MVP rendering and routing substrate is OSRM + MapLibre because it is
- Docs/decisions.md:1106:> MapLibre."
- Docs/decisions.md:1110:- MapLibre is retained specifically because it is the only substrate that keeps
- Docs/decisions.md:1118:- Map labels on MapLibre remain deferred/icebox, blocked on the glyph/fontstack
- Docs/decisions.md:1126:workaround as a MapLibre glyph substitute.
- Docs/decisions.md:1128:**Rejected:** shipping Apple Maps as the app substrate with MapLibre kept only
- Docs/decisions.md:1254:machinery — photo-EXIF import, the MapLibre substrate, the Modern Minimal theme,
- Docs/decisions.md:1295:  one, and stays undecided pending a device measurement of MapLibre.
- Docs/decisions.md:1296:- **MapLibre labels stay iceboxed** (owner, explicitly), to be reconsidered only
- Docs/decisions.md:1310:MapLibre substrate.
- Docs/decisions.md:1312:## 2026-08-15 — MapLibre is parked, Apple Maps is what ships, and routing moves behind an API
- Docs/decisions.md:1316:The 2026-08-08 entry stands as the record of why MapLibre was chosen; this is why
- Docs/decisions.md:1327:| long road trip (New Zealand) | MapLibre | **0.84** |
- Docs/decisions.md:1330:the same tiles, a road trip fetches new ones every snapshot. MapLibre reads local
- Docs/decisions.md:1332:Kamome is named for, MapLibre was roughly twice as fast; on a city trip Apple beat
- Docs/decisions.md:1347:1. **MapLibre is parked, not removed.** The code, the themes, the tile pipeline
- Docs/decisions.md:1370:- **Pixel Art loses its near-term justification.** MapLibre was retained
- Docs/demos/phase3_5/modern-minimal/README.md:22:  switches to MapLibre until this review passes.
- Docs/demos/phase3_5/modern-minimal/README.md:46:It drives the **real** MapLibre snapshotter (Metal) over the committed fixture
- Docs/demos/phase3_5/modern-minimal/README.md:83:- ✅ **The substrate renders.** MapLibre 6.27.0 loads the pmtiles and applies the
- Docs/demos/phase3_5/modern-minimal/README.md:87:- ⚠️ **MapLibre bakes its own wordmark + attribution into the snapshot** (a
- Docs/demos/phase3_5/modern-minimal/README.md:88:  "MapLibre" logo bottom-left, "© OpenMapTiles © OpenStreetMap contributors"
- Docs/demos/phase3_5/modern-minimal/README.md:107:- **Production switch** — `RecapModel` builds `MapLibreSnapshotProvider`;
- Docs/demos/phase3_5/substrate/README.md:1:# Replay MVP §2 — MapLibre souvenir-map substrate (demo artifact)
- Docs/demos/phase3_5/substrate/README.md:9:- **MapLibre `6.27.0`** via SPM (exact pin), app target only.
- Docs/demos/phase3_5/substrate/README.md:10:- **`App/Services/MapLibreSnapshotProvider.swift`** — conforms to the existing
- Docs/demos/phase3_5/substrate/README.md:11:  `RecapSnapshotProviding` boundary; the **only** file that imports MapLibre
- Docs/demos/phase3_5/substrate/README.md:13:  (`MLNMapSnapshot.point(for:)`); center + span → MapLibre zoom (Web Mercator,
- Docs/demos/phase3_5/substrate/README.md:23:- Tests: `Tests/AppTests/MapLibreSubstrateTests.swift` (style resolution, zoom
- Docs/demos/phase3_5/substrate/README.md:28:The actual MapLibre **pixel output** is a Metal path and is deliberately **not**
- Docs/demos/phase3_5/substrate/README.md:39:Not run in CI on purpose. To eyeball a MapLibre frame:
- Docs/demos/phase3_5/substrate/README.md:47:   let provider = MapLibreSnapshotProvider(styleURL: styleURL)
- Docs/eng-session-P4-visual.md:91:`RecapDemoFilmTests.swift:357` `XCTFail`s when no MapLibre region exists, then
- Docs/handoff-P3.5.md:9:**mandatory sequence**. The old sequence started at MapLibre — **do not follow
- Docs/handoff-P3.5.md:134:## 2. MapLibre souvenir-map substrate (spec §4.5, `Docs/vector-tile-pipeline.md`)
- Docs/handoff-P3.5.md:142:2. Add MapLibre Native iOS via SPM in `project.yml` (app target). The
- Docs/handoff-P3.5.md:144:3. `MapLibreSnapshotProvider` conforming to the existing `RecapSnapshotProviding`
- Docs/handoff-P3.5.md:146:   the contract — projection must travel with the snapshot). **All MapLibre
- Docs/handoff-P3.5.md:168:- [x] **MapLibre SPM `6.27.0`** (exact) in `project.yml`, app target. Resolves +
- Docs/handoff-P3.5.md:170:- [x] **`MapLibreSnapshotProvider`** (`App/Services/`, **not** the SwiftPM core —
- Docs/handoff-P3.5.md:172:      existing `RecapSnapshotProviding`. `import MapLibre` in that one file only,
- Docs/handoff-P3.5.md:177:      (`Tests/AppTests/MapLibreSubstrateTests.swift`), so the tile wiring is
- Docs/handoff-P3.5.md:185:      env-gated, writes stills). MapLibre 6.27.0 loads the pmtiles and renders the
- Docs/handoff-P3.5.md:193:      MapLibre bakes its own wordmark + attribution into snapshots — cover or
- Docs/handoff-P3.5.md:210:Chiu's call 2026-07-22: **the MapLibre substrate + base-style direction is accepted
- Docs/handoff-P3.5.md:211:("this is not the MapLibre issue") — stop iterating the base style.** The real
- Docs/handoff-P3.5.md:216:- [x] **MapLibre substrate accepted** — `MapLibreSnapshotProvider` + tiles render
- Docs/handoff-P3.5.md:232:        `RecapModel`→MapLibre switch that **retires `MapKitSnapshotProvider`**, OSM
- Docs/handoff-P3.5.md:252:  MapLibre substrate gives at zoom (sparse geometry made the prototype feel empty).
- Docs/handoff-P3.5.md:286:- `RecapSnapshotProviding` gained `bearing` (heading-up): `MapLibreSnapshotProvider`
- Docs/handoff-P3.5.md:292:  behavior; heading-up map rotation is a MapLibre-era opt-in). The close span
- Docs/handoff-P3.5.md:300:the follow-cam *feel* on device (§6) over the MapLibre substrate at close zoom —
- Docs/handoff-P3.5.md:370:      looks prettier than Apple Maps."** (MapLibre-vs-Apple side-by-side is a
- Docs/handoff-P3.5.md:526:MapLibre Native cannot render Latin labels without a fontstack; its local-font
- Docs/handoff-P3.5.md:545:- **The real work is collision with Kamome's own overlays.** MapLibre places
- Docs/handoff-P3.5.md:548:  exclusion zones into the style per frame (MapLibre cannot do this cleanly from
- Docs/handoff-P3.5.md:663:- Renderer/SDK confinement: MapLibre, MapKit, OSRM, PhotoKit types each stay in
- Docs/handoff-recap-visuals.md:4:car art) and `f294883` (static camera + MapLibre switch + theme atmosphere).
- Docs/handoff-recap-visuals.md:87:- **The MapKit/MapLibre distinction no longer affects the subject.** The car
- Docs/handoff-recap-visuals.md:156:- The MapLibre stills harness (`RecapFollowCamStillsTests`, env-gated) renders
- Docs/handoff-recap-visuals.md:178:### The MapLibre switch is conditional, on purpose
- Docs/handoff-recap-visuals.md:180:`RecapModel` renders MapLibre when vector tiles for the region are present and
- Docs/handoff-recap-visuals.md:270:- **MapLibre pixel render + `pmtiles://` vs `mbtiles://`** — Metal, so CI has
- Docs/handoff-render-layers.md:63:  (flat) + `RecapFollowCamStillsTests` (real MapLibre, env-gated).
- Docs/handoff-render-layers.md:66:    declare `capabilities` (MapKit `supportsBearing:false`; MapLibre/Flat `true`)
- Docs/handoff-render-layers.md:74:a **MapLibre stills render for Chiu's sign-off**, not golden-frame gates.
- Docs/handoff-render-layers.md:98:- Then render fresh **MapLibre follow-cam stills** (anime car + two-beat deck over
- Docs/handoff-render-layers.md:106:- **MapKit still ships** until the switch-over. Do not flip production to MapLibre
- Docs/handoff-render-layers.md:108:  anime car needs MapLibre — that IS the switch-over, un-held by Chiu 2026-07-24).
- Docs/handoff-render-layers.md:115:- Renderer/SDK confinement holds: `import MapLibre` only in
- Docs/handoff-render-layers.md:116:  `MapLibreSnapshotProvider.swift`; `import MapKit` only in
- Docs/handoff-render-layers.md:119:  the real look is judged on env-gated MapLibre stills + the §6 device gate.
- Docs/kamome-poc-spec.md:19:rejected. Routing provider closed as **Geoapify** the same day. — v1.7 (2026-07-20) — **Replay MVP repositioning** (owner decision, `decisions.md` 2026-07-20). The first shipped product is redefined from "passive-capture v1" to the **Replay MVP**: photo-EXIF import → OSRM road reconstruction → souvenir-map recap → MP4 share, validated on **three real past trips**. Consequences: **Phase 3.5 is renamed Replay MVP** and absorbs **photo-EXIF import** (pulled forward from the old Phase 4); its gate becomes a **product release gate** (three shareable films), not a static-visual gate. The tracking/battery device gates (2 h drive, region-resume re-validation, long-duration background, process-death recovery, passive capture, ≥ 3-day battery, the "Arm once, forget it" promise) leave the release path for a new **Capture Beta** (Phase 5, renamed from Passive Capture Tier — the checklists are preserved and moved, never marked passed). **Story Director** (automatic moment-selection, narrative, hero photos, chapters/elision, licensed music + beat-sync) becomes **Phase 4** (renamed from Import & Map Matching — its EXIF half moved into the MVP; the Google Timeline importer is **dropped as redundant** — EXIF import covers past trips, in-app capture covers new ones; owner decision 2026-07-20). Story Director is **deterministic — no AI/LLM tokens** (scoring-and-selection over structured trip data, §7 Phase 4). Plans & Fork (Phase 6) and Backend (Phase 7) are unchanged and further deferred. **MP4 is the launch format; GIF is demoted to non-blocking.** Honest provenance added (§3, §6): `trip.source` distinguishes Kamome-recorded from reconstructed-from-photos, and UI copy never says "Verified Trip". Positioning de-overclaimed (header above). — v1.6 (2026-07-20) — recap visual system validated via a throwaway web prototype on real data (Chiu's 170-photo Iceland ring-road trip); owner sign-off "prototype 蠻成功的，收斂回 app". Findings + the data pipeline + engine source: `Docs/prototype/` (also `decisions.md` 2026-07-20). Locked-in constraints for §4.5/§7: (a) base map = **real geometry + hand-written subtractive style** = "紀念品地圖" (souvenir map), reaffirming the MapLibre substrate ADR; (b) stop photos = a **rotating photo deck at the stop location**, hero cross-fades through 3–8 photos at **0.8 s each** (not the old single card); (c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle is the subject, close heading-up zoom) — the prototype's one unmet requirement; top-down car is the default marker, seagull/scooter/bike swappable. Positioning line restated (above). Forward directions recorded: photo-EXIF import first (the prototype IS that importer, §4.7), video clips as auto-trimmed muted "beads", and royalty-free **beat-synced** music (bundled library + offline beat maps, events quantized to the beat; free=silent export, premium=in-app track). No architecture change — these constrain existing components (`RecapSnapshotProviding`, `CameraPath`, `OverlayTimeline`, `RecapTheme`, `ImportKit`). v1.5 (2026-07-19) — recap visual pivot (owner decision after reviewing the P3 demo artifact): the recap is a stylized, premium animated replay, not Apple-tile output — vision in `Docs/kamome-animation-vision.md`; recap base-map substrate moves MKMapSnapshotter → MapLibre Native + self-hosted vector tiles with Kamome-authored themed styles (ADR in `Docs/decisions.md` 2026-07-19; implementer guide `Docs/vector-tile-pipeline.md`); §0 gains rule 6 (storytelling engine + recognizable identity); §4.5 step 2 rewritten + visual quality bar added; Phase 3 scope frozen as the pipeline milestone; new **Phase 3.5 Recap Visual System** (OSRM §4.4 pulled forward → MapLibre substrate → Modern Minimal theme; no renumbering of P4–P7). v1.4 (2026-07-18) — fork demoted from positioning to mechanism: positioning line rewritten (memory-engine framing), §1.5 fork row relabeled P6 bet, §4.5 end card copy → "Get this route"; all user-facing copy uses Save / Get / Inspired by (S6/S7 screen wording settled at P6 — internal names, table `plan.forked_from`, and `.kamome` schema unchanged). v1.3 (2026-07-15) — battery-moat repositioning: passive capture tier (§1.8, §2.3), map matching promoted to core (§4.4), trip import (§4.7), phases renumbered (fork → Phase 6, backend → Phase 7), transactional monetization note (§1.6). v1.2 (2026-07-11) added Roadtrippers analysis, Taiwan-market adaptations, Kamome branding, handoff checklist & kickoff prompt.
- Docs/kamome-poc-spec.md:133:│   PhotoKit (read-only)  MapKit (S2/S3)  MapLibre (recap, P3.5) │
- Docs/kamome-poc-spec.md:146:| Recap base map (Phase 3.5) | **MapLibre Native + self-hosted vector tiles, Kamome-authored style per theme** | Fully custom renderer; Mapbox; restyling MapKit (no styling API exists) | Owner-rejected Apple-tile look (ADR 2026-07-19). Full control of colors, typography, and what is *omitted*; PMTiles = static-file hosting, no tile server; same regional OSM extracts as OSRM; checked-in tiles make golden frames bit-stable. Must clear the §4.5 quality bar or the decision gets revisited. Guide: `Docs/vector-tile-pipeline.md`. |
- Docs/kamome-poc-spec.md:149:| Video | **Snapshot-provider frames → AVAssetWriter** (provider = MapLibre from Phase 3.5; MKMapSnapshotter was the P3 bootstrap) | Screen-record a map camera flight | Deterministic, background-renderable, testable frame-by-frame — property of the frame pipeline, independent of which provider renders the base map. |
- Docs/kamome-poc-spec.md:329:2. For each frame: a `RecapSnapshotProviding` provider renders the base map for the camera position (snapshot per keyframe every N frames, cross-fade between, to keep render time sane); the compositor draws the traveled route portion + animated head marker via CoreGraphics overlay, projecting through the snapshot's own projection. From Phase 3.5 the shipping provider is **MapLibre Native over self-hosted vector tiles with a Kamome-authored theme style** (ADR 2026-07-19; `Docs/vector-tile-pipeline.md`); `MapKitSnapshotProvider` was the P3 bootstrap, `FlatSnapshotProvider` keeps golden-frame CI deterministic. Boundary discipline: renderer SDK types never leak past the provider file (§0 rule 6 corollary).
- Docs/kamome-poc-spec.md:337:**Visual quality bar (v1.5, judged during the Replay MVP as a design review — NOT the release gate):** the reason we carry self-hosted tiles instead of free Apple Maps is that MapLibre + a Kamome style sheet must produce output **clearly better-designed than native Apple Maps for journey replay**. Concretely: zero business-POI noise; deliberate use of empty space — subtractive cartography that shows only what serves the journey; distinctive road and route treatment; instantly recognizable Kamome identity with branding stripped (§0 rule 6). Judged by side-by-side stills against the P3 Apple-tiles artifact (`Docs/demos/phase3/`) at matched camera positions, reviewed by Chiu; a style sheet that fails side-by-side is not shippable, and if the bar proves unreachable the substrate decision itself is revisited (ADR 2026-07-19). **Scope correction (2026-07-20):** this side-by-side is a design checkpoint that keeps the substrate honest — it **does not replace** the Replay MVP release gate. The release gate is the full-video product judgment across three real trips (§10): "map looks prettier than Apple Maps" is necessary, not sufficient; "is this a travel-path animation worth publishing" is the real bar. The route must always follow real roads — never straight lines between GPS points (matching §4.4 is a Replay MVP prerequisite, already landed app-side). Themes are swappable without touching animation logic; **one theme (Modern Minimal) is the MVP target — multiple themes are explicitly not an MVP success condition**; how the seagull head marker (brand element, page 1) composes with the per-trip vehicle icon (§1.7) is settled during Modern Minimal theme design, not here.
- Docs/kamome-poc-spec.md:425:2. **MapLibre souvenir-map substrate** — `MapLibreSnapshotProvider` behind the existing `RecapSnapshotProviding` boundary; real geometry + Kamome hand-written **subtractive** style (no generic nav map, no POI noise); MapLibre types confined to that one file; no abstraction layer without a consumer. Guide: `Docs/vector-tile-pipeline.md`.
- Docs/kamome-poc-spec.md:441:- MapLibre-vs-Apple-Maps side-by-side may stay as a **design review** but does **not** replace the full-video product judgment.
- Docs/kamome-poc-spec.md:511:| ~~MKMapSnapshotter too slow/plain for video~~ **Materialized 2026-07-19** — owner rejected the Apple-tile look outright | — | Recap substrate replaced: MapLibre + self-hosted vector tiles, Phase 3.5 (ADR 2026-07-19). Keyframe + crossfade rendering strategy survives unchanged. |
- Docs/kamome-poc-spec.md:512:| Kamome style sheet fails the §4.5 quality bar (MapLibre output not clearly better than Apple Maps for replay) | Medium | Side-by-side design review during the Replay MVP before theme work is declared done (a checkpoint, not the release gate — §4.5); iterate style JSON (cheap — no code); if the bar proves unreachable, revisit the substrate ADR rather than shipping a mediocre look. |
- Docs/pre-launch.md:34:crash-free export across three trips. The souvenir-map item is moot while MapLibre is
- Docs/pre-launch.md:246:  back to Apple Maps. Moot while MapLibre is parked; it returns if that reopens.
- Docs/pre-launch.md:283:substrate ADR. Pixel Art is parked with MapLibre. Capture Beta, Story Director
- Docs/prototype/README.md:68:This is exactly the **MapLibre substrate ADR** (`decisions.md` 2026-07-19,
- Docs/prototype/README.md:76:- **App:** MapLibre renders the same real classes (coastline, water, glacier,
- Docs/prototype/README.md:78:  subtraction and coloring.** `MapLibreSnapshotProvider` behind
- Docs/vector-tile-pipeline.md:3:**Status:** authoritative implementer guide for the MapLibre substrate
- Docs/vector-tile-pipeline.md:16:`MKMapSnapshotter` has no styling API, so the recap renders MapLibre
- Docs/vector-tile-pipeline.md:58:  region tiles + theme style ──► MapLibre Native snapshotter
- Docs/vector-tile-pipeline.md:59:        ──► MapLibreSnapshotProvider (: RecapSnapshotProviding)
- Docs/vector-tile-pipeline.md:125:**MapLibre ingestion — RESOLVED 2026-07-22 (MapLibre 6.27.0, verified in-sim).**
- Docs/vector-tile-pipeline.md:130:only in case a future MapLibre pin regresses:
- Docs/vector-tile-pipeline.md:137:## 6. Style-sheet authoring (theme = MapLibre style JSON)
- Docs/vector-tile-pipeline.md:139:A **theme** at the substrate level is a MapLibre style JSON (MapLibre
- Docs/vector-tile-pipeline.md:145:- Edit in **Maputnik** (maputnik.github.io — web editor for the MapLibre
- Docs/vector-tile-pipeline.md:158:  multi-hundred-MB CJK glyph PBFs: set MapLibre's
- Docs/vector-tile-pipeline.md:177:- Dependency: **MapLibre Native iOS** via SPM
- Docs/vector-tile-pipeline.md:180:- Rendering: MapLibre's snapshotter (`MLNMapSnapshotter` — same shape as
- Docs/vector-tile-pipeline.md:182:  out). Wrap it in `MapLibreSnapshotProvider: RecapSnapshotProviding` in
- Docs/vector-tile-pipeline.md:183:  `Core/ExportEngine/MapLibreSnapshotProvider.swift`.
- Docs/vector-tile-pipeline.md:185:  `import MapLibre`.** This mirrors today's discipline (`import MapKit`
- Docs/vector-tile-pipeline.md:220:- [x] MapLibre SPM dependency in `project.yml` (`6.27.0`, exact); ingestion
- Docs/vector-tile-pipeline.md:223:- [x] `MapLibreSnapshotProvider` conforming to `RecapSnapshotProviding`
- Docs/vector-tile-pipeline.md:225:      `import MapLibre` confined to that file, **CI grep gate added**.
- Docs/vector-tile-pipeline.md:235:      `FlatSnapshotProvider` (no live-tile MapLibre golden — non-deterministic
- Docs/vector-tile-pipeline.md:236:      Metal, §8). A MapLibre golden test waits for §3 sign-off.
- Docs/vector-tile-pipeline.md:242:- 2026-07-21 — §2 substrate landed on `phase-3-recap`: MapLibre `6.27.0`
- Docs/vector-tile-pipeline.md:243:  (SPM, app target, confined + CI grep gate), `MapLibreSnapshotProvider` +

### OSRM
- CLAUDE.md:50:EXIF place+time → snap to real roads (OSRM, already landed) → souvenir-map
- CLAUDE.md:96:  OSRM matching §4.4 (pulled forward; route must never be straight lines
- CLAUDE.md:99:  self-hosted vector tiles (Planetiler → PMTiles, same extracts as OSRM),
- CLAUDE.md:231:The scaling trap that forced it, 2026-08-15: a self-hosted OSRM only routes the
- CLAUDE.md:238:**465–477 m** — anti-correlated). `radiuses=500` never guarded that band on OSRM
- CLAUDE.md:245:⚠️ **The migration PR carries two policies out of `OSRMRouteProvider`, not one.**
- CLAUDE.md:247:sent as OSRM's `radiuses=`) is not, and it is the one that matters more.** It is
- CLAUDE.md:356:  display simplification); fix is OSRM matching (§4.4, P3 stretch / P4 core),
- HANDOFF.md:227:was not guarding this band on OSRM either. The class it *did* guard — no road anywhere
- HANDOFF.md:234:### 1 (as originally written). The migration PR carries **two** policies out of `OSRMRouteProvider`
- HANDOFF.md:239:**Why.** `OSRMRouteProvider.requestURL` sends `radiuses=` per waypoint — "photos sit
- HANDOFF.md:240:beside roads, not on them". Under OSRM, a waypoint further than 500 m from a road
- HANDOFF.md:303:**His question**, recorded as asked: OSRM and Geoapify only carry car roads, so a
- HANDOFF.md:475:unchanged. **No architecture objection** — the boundary held and `OSRMRouteProvider`
- HANDOFF.md:492:The existing logs are already correct and should be the pattern: `OSRMRouteProvider`
- HANDOFF.md:597:TEST_RUNNER_KAMOME_OSRM_BASE_URL=http://127.0.0.1:5100 \
- HANDOFF.md:639:- OSRM `:5100` is `docker compose up -d` from `Deploy/`, healthy, restart-safe.
- HANDOFF.md:717:| `NoSegment` | 9 | **Correct behaviour, no action.** These cluster on glacier tongues and national-park interiors — photo positions with no drivable segment near them. OSRM answered correctly; drawing them dashed is the honest-provenance rule working, not a defect. |
- HANDOFF.md:1149:## ▶ Substrate decision — OSRM + MapLibre, behind swappable boundaries (2026-08-08)
- HANDOFF.md:1153:> The MVP rendering and routing substrate is OSRM + MapLibre because it is
- HANDOFF.md:1198:## ▶ Pre-Phase-2 blocker — OSRM hosted-endpoint TOS unverified (2026-08-08)
- HANDOFF.md:1200:The OSRM **demo/hosted endpoint's terms of service for commercial use have not
- HANDOFF.md:1545:  film is dashed everywhere while desk pilots (pointed at a live OSRM) draw solid.
- HANDOFF.md:1630:  against a live OSRM. `App/Services/RouteMatchService.swift:39`. Unfixed; it is
- HANDOFF.md:1635:- **OSRM on `:5100` is compose-managed and restart-safe** — corrected 2026-08-09.
- PO.md:72:this file locked "the MVP rendering and routing substrate is OSRM + MapLibre — do
- PO.md:79:> **OSRM stays as the routing engine, and moves off the developer's LAN to a
- PO.md:80:> hosted service. The provider is not selected and may not be OSRM-compatible.**
- PO.md:83:adapter in advance. The boundary already passes the real test — OSRM's wire format
- PO.md:91:plausibility gate currently lives inside `OSRMRouteProvider`, but it is Kamome's
- PO.md:92:honest-provenance policy rather than an OSRM fact, and a new provider file would
- PO.md:155:> OSRM
- PO.md:163:Audit for OSRM-specific assumptions leaking into Story Director, Timeline, Replay, Camera, domain models, or UI.
- PO.md:272:`radiuses=500` had never guarded that band on OSRM either, so the regression
- Docs/cross-region-journeys.md:151:| OSRM returned `NoSegment` | no road network — water, or off-extract | yes, logged per leg |
- Docs/decisions.md:5:OSRM, Supabase — spec §2.2/§11.1) are not repeated here.
- Docs/decisions.md:171:the planned fix is OSRM matching (§4.4, P3 stretch / P4 core) and raw points
- Docs/decisions.md:382:  sequenced: OSRM matching (§4.4, pulled forward from P4) → MapLibre
- Docs/decisions.md:407:regional extracts as OSRM) with a **Kamome-authored MapLibre style JSON
- Docs/decisions.md:510:`phase-3-recap`, in spec order: OSRM matching app-side first.
- Docs/decisions.md:524:boundary; OSRM types confined to `OSRMMatchProvider.swift` exactly like
- Docs/decisions.md:525:MapKit in `MapKitSnapshotProvider.swift`), `OSRMMatchProvider` (chunked
- Docs/decisions.md:535:raw OSRM density would blow the §4.5 render budget), raw Douglas-Peucker at
- Docs/decisions.md:569:   substrate is non-negotiable. Route precision is a later OSRM concern (§4.4)
- Docs/decisions.md:622:snap to real roads (OSRM, already landed) → souvenir-map recap → MP4 → share.*
- Docs/decisions.md:681:  give: a **truth-path** (actual road vs. an OSRM guess between sparse photos),
- Docs/decisions.md:1090:## 2026-08-08 — MVP substrate is OSRM + MapLibre, behind swappable boundaries
- Docs/decisions.md:1099:> "The MVP rendering and routing substrate is OSRM + MapLibre because it is
- Docs/decisions.md:1354:3. **Routing stays OSRM, and moves behind an API** rather than a machine on
- Docs/decisions.md:1478:**Why not self-hosting**, which is cheaper in money. A self-hosted OSRM only
- Docs/decisions.md:1502:  whether the response shape is OSRM-compatible all have to be read rather than
- Docs/decisions.md:1503:  assumed. The boundary survives either way — OSRM's wire format lives only in the
- Docs/decisions.md:1506:- **The detour-ratio plausibility gate must be lifted out of `OSRMRouteProvider`
- Docs/decisions.md:1508:  rather than an OSRM fact, and a new provider file would silently drop it.
- Docs/decisions.md:1516:- Self-hosted OSRM stays viable behind the same boundary if this is ever reversed;
- Docs/decisions.md:1545:### 🔴 The consequence that is not in the survey: **two** policies live in `OSRMRouteProvider`, and only one was on record
- Docs/decisions.md:1551:`OSRMRouteProvider.requestURL` sends **`radiuses=` per waypoint**, floored at
- Docs/decisions.md:1553:*photos sit beside roads, not on them.* Under OSRM a waypoint further than that
- Docs/decisions.md:1562:| photo position | today (OSRM, `radiuses=500`) | Geoapify with no radius (measured) |
- Docs/decisions.md:1582:1. Lift the detour-ratio gate out of `OSRMRouteProvider` (already on record).
- Docs/decisions.md:1776:Verified in `OSRMRouteProvider.requestURL` and `OSRMMatchProvider` (today both GET;
- Docs/decisions.md:1806:> before a route exists. Under OSRM a photo 1 km from a road returns `NoSegment`
- Docs/decisions.md:1839:**`radiuses=500` was not protecting Kamome from this band on OSRM either.** OSRM
- Docs/decisions.md:1841:500 m, so OSRM would have taken it too and drawn the same wrong solid line. The
- Docs/demos/phase3/README.md:23:OSRM map matching (§4.4, P4 core) snaps it to roads; do not tune sampling
- Docs/demos/phase3_5/import/README.md:18:- The **import engine** (clustering → `saveImportedTrip` → best-effort OSRM
- Docs/demos/phase3_5/matching/README.md:10:the local OSRM WA server: the replay rides Bussell Hwy, takes the
- Docs/demos/phase3_5/matching/README.md:25:2. **`matching.base_url` pointed at the local OSRM** (dev-only, shipped
- Docs/dogfood-infrastructure.md:3:What the §6 gate needs that the app cannot provide by itself: an OSRM the phone
- Docs/dogfood-infrastructure.md:6:**Local first** (Chiu 2026-07-29). The gate runs against OSRM on the laptop over
- Docs/dogfood-infrastructure.md:17:- **PD-5** — **one merged routing dataset** covering every region. OSRM serves
- Docs/dogfood-infrastructure.md:84:2. `cp Deploy/.env.example Deploy/.env`; set `OSRM_BIND=127.0.0.1` and
- Docs/dogfood-infrastructure.md:85:   `OSRM_DOMAIN`.
- Docs/dogfood-infrastructure.md:92:⚠️ **`OSRM_BIND=127.0.0.1` is not optional on a public box.** Left at `0.0.0.0`,
- Docs/dogfood-infrastructure.md:93:OSRM is exposed directly: no authentication, no rate limiting, no request
- Docs/dogfood-infrastructure.md:98:the server half commented out; the app half does not exist — `OSRMMatchProvider`
- Docs/dogfood-infrastructure.md:99:and `OSRMRouteProvider` both send bare requests. Enabling the Caddy block alone
- Docs/dogfood-infrastructure.md:178:- [ ] Phone and Mac on the same Wi-Fi, and OSRM reachable from the phone's
- Docs/dogfood-infrastructure.md:185:      means the app never reached OSRM.
- Docs/eng-session-P4.md:34:Migrate routing from the self-hosted OSRM on a LAN to **Geoapify**, and then
- Docs/eng-session-P4.md:49:  The boundary already passes the real test: OSRM's wire format lives only in the
- Docs/eng-session-P4.md:55:  1. Lift the detour-ratio gate out of `OSRMRouteProvider`; it is Kamome's
- Docs/eng-session-P4.md:56:     honest-provenance policy, not an OSRM fact.
- Docs/eng-session-P4.md:58:     as OSRM's `radiuses=` and it is what makes a photo taken 1 km from a road
- Docs/eng-session-P4.md:75:  *and* real coordinates. The existing logs are the pattern: `OSRMRouteProvider`
- Docs/eng-session-P4.md:103:- **Level 3** — state plainly that OSRM's wire format has not leaked outside the
- Docs/gate-P3.5-checklist.md:74:⚠️ **A different knob to watch at Stage 1.** OSRM is asked to snap each leg
- Docs/gate-P3.5-checklist.md:211:TEST_RUNNER_KAMOME_OSRM_BASE_URL=http://127.0.0.1:5100 \
- Docs/gate-P3.5-checklist.md:227:⚠️ **Pre-flight OSRM with `docker ps`, not `curl`.** The container must be up
- Docs/gate-P3.5-checklist.md:295:- [ ] **Prove OSRM from the phone's Safari** before importing anything:
- Docs/gate-P3.5-checklist.md:397:**2 · Point the app at your Mac's OSRM.** `matching.base_url` ships `""` and there
- Docs/gate-P3.5-checklist.md:417:**4 · Prove OSRM is reachable *from the phone*, in Safari, before importing:**
- Docs/gate-P3.5-checklist.md:444:follows roads if OSRM answered, and runs in straight lines between stops if it did
- Docs/gate-P3.5-checklist.md:472:| `route: OSRM said NoSegment` | reached the server; there is no road network there. Correct for a leg outside the merged extract, or across water |
- Docs/gate-P3.5-checklist.md:498:- **OSRM, not ORS.** There is no OpenRouteService integration anywhere in the
- Docs/gate-P3.5-checklist.md:499:  repo and none is planned in the handoff — routing is self-hosted OSRM
- Docs/handoff-P3.5.md:40:- OSRM local setup is documented and proven (`Docs/osrm-setup.md`): WA extract
- Docs/handoff-P3.5.md:69:3. **Road reconstruction** via the existing `RouteMatchService` / `OSRMMatchProvider`
- Docs/handoff-P3.5.md:139:1. Tile build: Planetiler → PMTiles from the same Geofabrik extracts as OSRM.
- Docs/handoff-P3.5.md:409:The gate runs against a **local** OSRM on home Wi-Fi, not a VPS. Everything is
- Docs/handoff-P3.5.md:424:- [ ] **Shared-token auth on OSRM, server *and* app in the same change.**
- Docs/handoff-P3.5.md:426:      **not exist**: `OSRMMatchProvider.swift` and `OSRMRouteProvider.swift` both
- Docs/handoff-P3.5.md:663:- Renderer/SDK confinement: MapLibre, MapKit, OSRM, PhotoKit types each stay in
- Docs/icebox.md:115:  so OSRM's car profile won't snap them — they draw inferred, or need a rail/
- Docs/kamome-poc-spec.md:19:rejected. Routing provider closed as **Geoapify** the same day. — v1.7 (2026-07-20) — **Replay MVP repositioning** (owner decision, `decisions.md` 2026-07-20). The first shipped product is redefined from "passive-capture v1" to the **Replay MVP**: photo-EXIF import → OSRM road reconstruction → souvenir-map recap → MP4 share, validated on **three real past trips**. Consequences: **Phase 3.5 is renamed Replay MVP** and absorbs **photo-EXIF import** (pulled forward from the old Phase 4); its gate becomes a **product release gate** (three shareable films), not a static-visual gate. The tracking/battery device gates (2 h drive, region-resume re-validation, long-duration background, process-death recovery, passive capture, ≥ 3-day battery, the "Arm once, forget it" promise) leave the release path for a new **Capture Beta** (Phase 5, renamed from Passive Capture Tier — the checklists are preserved and moved, never marked passed). **Story Director** (automatic moment-selection, narrative, hero photos, chapters/elision, licensed music + beat-sync) becomes **Phase 4** (renamed from Import & Map Matching — its EXIF half moved into the MVP; the Google Timeline importer is **dropped as redundant** — EXIF import covers past trips, in-app capture covers new ones; owner decision 2026-07-20). Story Director is **deterministic — no AI/LLM tokens** (scoring-and-selection over structured trip data, §7 Phase 4). Plans & Fork (Phase 6) and Backend (Phase 7) are unchanged and further deferred. **MP4 is the launch format; GIF is demoted to non-blocking.** Honest provenance added (§3, §6): `trip.source` distinguishes Kamome-recorded from reconstructed-from-photos, and UI copy never says "Verified Trip". Positioning de-overclaimed (header above). — v1.6 (2026-07-20) — recap visual system validated via a throwaway web prototype on real data (Chiu's 170-photo Iceland ring-road trip); owner sign-off "prototype 蠻成功的，收斂回 app". Findings + the data pipeline + engine source: `Docs/prototype/` (also `decisions.md` 2026-07-20). Locked-in constraints for §4.5/§7: (a) base map = **real geometry + hand-written subtractive style** = "紀念品地圖" (souvenir map), reaffirming the MapLibre substrate ADR; (b) stop photos = a **rotating photo deck at the stop location**, hero cross-fades through 3–8 photos at **0.8 s each** (not the old single card); (c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle is the subject, close heading-up zoom) — the prototype's one unmet requirement; top-down car is the default marker, seagull/scooter/bike swappable. Positioning line restated (above). Forward directions recorded: photo-EXIF import first (the prototype IS that importer, §4.7), video clips as auto-trimmed muted "beads", and royalty-free **beat-synced** music (bundled library + offline beat maps, events quantized to the beat; free=silent export, premium=in-app track). No architecture change — these constrain existing components (`RecapSnapshotProviding`, `CameraPath`, `OverlayTimeline`, `RecapTheme`, `ImportKit`). v1.5 (2026-07-19) — recap visual pivot (owner decision after reviewing the P3 demo artifact): the recap is a stylized, premium animated replay, not Apple-tile output — vision in `Docs/kamome-animation-vision.md`; recap base-map substrate moves MKMapSnapshotter → MapLibre Native + self-hosted vector tiles with Kamome-authored themed styles (ADR in `Docs/decisions.md` 2026-07-19; implementer guide `Docs/vector-tile-pipeline.md`); §0 gains rule 6 (storytelling engine + recognizable identity); §4.5 step 2 rewritten + visual quality bar added; Phase 3 scope frozen as the pipeline milestone; new **Phase 3.5 Recap Visual System** (OSRM §4.4 pulled forward → MapLibre substrate → Modern Minimal theme; no renumbering of P4–P7). v1.4 (2026-07-18) — fork demoted from positioning to mechanism: positioning line rewritten (memory-engine framing), §1.5 fork row relabeled P6 bet, §4.5 end card copy → "Get this route"; all user-facing copy uses Save / Get / Inspired by (S6/S7 screen wording settled at P6 — internal names, table `plan.forked_from`, and `.kamome` schema unchanged). v1.3 (2026-07-15) — battery-moat repositioning: passive capture tier (§1.8, §2.3), map matching promoted to core (§4.4), trip import (§4.7), phases renumbered (fork → Phase 6, backend → Phase 7), transactional monetization note (§1.6). v1.2 (2026-07-11) added Roadtrippers analysis, Taiwan-market adaptations, Kamome branding, handoff checklist & kickoff prompt.
- Docs/kamome-poc-spec.md:92:- **Map/data fit:** Taiwan OSM extract is ~100 MB — OSRM self-hosting for map matching is trivial and free. Apple Maps Taiwan coverage is adequate for display.
- Docs/kamome-poc-spec.md:135:        Replay MVP (P3.5) core sidecar: OSRM /match (Docker, self-hosted)
- Docs/kamome-poc-spec.md:146:| Recap base map (Phase 3.5) | **MapLibre Native + self-hosted vector tiles, Kamome-authored style per theme** | Fully custom renderer; Mapbox; restyling MapKit (no styling API exists) | Owner-rejected Apple-tile look (ADR 2026-07-19). Full control of colors, typography, and what is *omitted*; PMTiles = static-file hosting, no tile server; same regional OSM extracts as OSRM; checked-in tiles make golden frames bit-stable. Must clear the §4.5 quality bar or the decision gets revisited. Guide: `Docs/vector-tile-pipeline.md`. |
- Docs/kamome-poc-spec.md:147:| Map matching (snap-to-road) | **OSRM `/match`, self-hosted Docker** (app side landed in the Replay MVP / P3.5) | Mapbox Map Matching API | Free, offline-capable for a region extract (e.g. Australia OSM ≈ 1 GB, Taiwan ≈ 100 MB), no per-request cost. Mapbox is easier but meters every request. Phases 1–3 shipped raw polyline + Douglas-Peucker; from the Replay MVP matching is **core infrastructure** — photo-EXIF import (§4.7) is load-bearing on it (sparse geotags look wrong unsnapped), and the passive tier (§1.8, Capture Beta) later too — but trip completion/import must still never block on it. |
- Docs/kamome-poc-spec.md:289:- **Replay MVP / P3.5** (app side landed, `decisions.md` 2026-07-19; **core**, promoted from stretch — §1.8): batch segments (≤100 pts/request) to OSRM `/match?geometries=polyline&tidy=true`; store result in `segment.matched_polyline`. One pipeline serves three sources: imported photo-EXIF points (load-bearing — sparse geotags look wrong without snapping; this is the MVP's dependency), later imported Timeline points and passive-tier fixes (Capture Beta), and high-fidelity recordings (cosmetic win). On failure (no OSRM reachable / confidence below `matching_confidence_min`), fall back to simplified raw polyline, mark segment `matched=false`, render **"inferred" (honestly low-confidence) style** — the Replay MVP gate forbids inventing a route that crosses sea/mountain or a wrong road, so low-confidence legs must read as inferred, never as fact. **Never block trip completion or import on matching.**
- Docs/kamome-poc-spec.md:344:- **Photo EXIF (Replay MVP — the MVP's core):** user picks a date range or album; geotagged photos cluster into `stop` rows + photo groups + a coarse route (time-gap + distance heuristics, tunables in config), which OSRM (§4.4) snaps to real roads. Photos are attached to their stops by construction — zero matching ambiguity. Imported trips write `trip.source = 'imported_photos'`, `segment.source = 'exif'` (§3), and must be honestly labeled as reconstructed-from-photos (§6), never as recorded. The prototype (`Docs/prototype/`) already proved this end-to-end on a real 13-day, 170-photo trip — that pipeline *is* this importer.
- Docs/kamome-poc-spec.md:423:Renamed & rescoped 2026-07-20 (decisions.md; was "Recap Visual System"). Ships the loop **pick past photos → reconstruct trip → snap to real roads → souvenir-map recap → MP4 → share.** Work order and full detail in `Docs/handoff-P3.5.md`; the OSRM matching app side is already landed (do not redo). Sequence:
- Docs/kamome-poc-spec.md:424:1. **Photo EXIF import (§4.7)** — `Core/ImportKit/` + schema v2 (`trip.source` / `segment.source`, honest provenance §3). Pick an album / date range → cluster geotagged photos into stops + photo groups + a coarse route → OSRM snap (§4.4). Imported trips flow through the existing Trip Detail (S3), RecapComposer, and ExportEngine **unchanged**. The prototype (`Docs/prototype/`) is this importer, proven on a real 13-day trip.
- Docs/kamome-poc-spec.md:460:**Open question — what does capture add over photo reconstruction? (owner-raised 2026-07-20, decide from MVP feedback, do not assume).** Since photo-EXIF import already reconstructs most photo-rich trips, Capture Beta must earn its background/battery engineering by selling the **three things photos structurally cannot**: (1) a **truth-path** — the actual road every turn, not an OSRM guess between sparse photos that can pick the wrong parallel road or miss an unphotographed detour (this *is* the `recorded` vs `reconstructed-from-photos` line, §3); (2) **stops/scenes with no photo** (a meal, gas, a viewpoint you didn't shoot) — invisible to EXIF; (3) **true zero-effort** — you didn't even have to take photos (scooter 環島, night, rain, driving-focused trips), the purest form of the founding motivation. Whether these justify the build is validated after the MVP, not presumed here.
- Docs/kamome-poc-spec.md:514:| Self-hosted vector tiles add ops/size burden | Medium | PMTiles = single static file per region, no tile server; regional extracts only (TW ≈ 100 MB OSM, matching OSRM's footprint); tile generation is a documented offline step (`Docs/vector-tile-pipeline.md`), not runtime infrastructure. |
- Docs/osrm-setup.md:1:# OSRM map-matching server — setup & validation
- Docs/osrm-setup.md:3:Self-hosted OSRM backing §4.4 map matching, pulled forward into Phase 3.5
- Docs/osrm-setup.md:53:One region per port — OSRM serves a single dataset per process. Compose file
- Docs/osrm-setup.md:112:matching validation; the transport hook on `OSRMMatchProvider` is built for
- Docs/osrm-setup.md:119:- Chunk-size errors (`TooBig`): OSRM caps match locations at 100 per request
- Docs/pre-launch.md:140:- A Worker is **not** a self-hosted OSRM. It forwards an HTTP request: a few MB,
- Docs/prototype/README.md:71:"that's Iceland." Route precision comes later from **OSRM road-snapping (§4.4)**
- Docs/routing-provider-selection.md:97:OSRM-compatible means roughly a URL change. A different shape means one new file
- Docs/routing-provider-selection.md:98:conforming to the two protocols. **The boundary survives either** — OSRM's wire
- Docs/routing-provider-selection.md:107:- **Lift the detour-ratio plausibility gate out of `OSRMRouteProvider`.** It is
- Docs/routing-provider-selection.md:108:  Kamome's honest-provenance policy rather than an OSRM fact, and a new provider
- Docs/routing-provider-selection.md:118:**The OSRM demo server** (`router.project-osrm.org`). It is a demonstration
- Docs/vector-tile-pipeline.md:65:the same self-hosting posture as OSRM (§4.4): regional extracts,
- Docs/vector-tile-pipeline.md:73:  as the OSRM setup in `Docs/osrm-setup.md` — one data vintage for
- Docs/vector-tile-pipeline.md:213:- [x] `Docs/osrm-setup.md` OSRM matching running first (§4.4) — landed +

### routing provider
- Docs/eng-session-P4.md:22:  **2026-08-20 (c)** — the routing provider is decided, the terms are read, and
- Docs/pre-launch.md:130:CORS. Bundle-ID validation is a Google-specific feature that routing providers
- Docs/pre-launch.md:210:trips send their coordinates to the routing provider, walks included**, and that gets
- Docs/routing-provider-selection.md:1:# Choosing the routing provider — what to compare

### rendering substrate
- PO.md:143:The Story layer must not depend on the current rendering substrate.

### Phase 3.5
- CLAUDE.md:55:- **Phase 3.5 renamed → Replay MVP**; **photo-EXIF import pulled forward**
- CLAUDE.md:95:- **New Phase 3.5 — Recap Visual System** (spec §7), strictly sequenced:
- CLAUDE.md:127:## Current phase: **4 — films worth keeping.** Phase 3.5 CLOSED 2026-08-15
- CLAUDE.md:129:**Phase 3.5 (Replay MVP) is closed.** §1–§5 all landed; **§6a passed** (three real
- Docs/decisions.md:366:## 2026-07-19 — Recap visual pivot: P3 frozen as pipeline milestone, Phase 3.5 opened
- Docs/decisions.md:380:  embarrass him") moves to Phase 3.5, where it belongs now.
- Docs/decisions.md:381:- **Phase 3.5 — Recap Visual System** opens as its own phase (spec §7),
- Docs/decisions.md:497:## 2026-07-19 — Owner call: continue into Phase 3.5 while P3's device items stay open
- Docs/decisions.md:509:substrate regardless). Meanwhile Phase 3.5 fixture-driven work proceeds on
- Docs/decisions.md:553:**Context.** Before committing the Swift recap-visual work (Phase 3.5, spec
- Docs/decisions.md:568:   evidence for the Phase 3.5 quality-bar side-by-side, and the reason the
- Docs/decisions.md:631:- **Phase 3.5 renamed "Recap Visual System" → "Replay MVP,"** and **photo-EXIF
- Docs/decisions.md:1251:## 2026-08-15 — Phase 3.5 closes: §6a passed, §6b did not, and the phase map catches up
- Docs/decisions.md:1253:**Context.** Phase 3.5 (Replay MVP) ran from 2026-07-20. §1–§5 landed the
- Docs/decisions.md:1261:1. **Phase 3.5 closes with §6a passed and §6b explicitly NOT passed.** Chiu's
- Docs/decisions.md:1272:3. **The phase map is not rewritten; it is corrected.** Phase 3.5 quietly
- Docs/demos/phase3_5/matching/README.md:1:# Phase 3.5 §1 — map matching before/after (handoff §1 item 3)
- Docs/device-test-P3.md:16:- **→ Replay MVP gate (Phase 3.5)** — export / photo, still blocking release:
- Docs/handoff-P3.5.md:1:# Handoff — Phase 3.5 = **Replay MVP** work order (rewritten 2026-07-20)
- Docs/handoff-P3.5.md:6:**Phase 3.5 was renamed "Recap Visual System" → "Replay MVP" (recap from
- Docs/kamome-animation-vision.md:6:quality bar, §7 Phase 3.5), `Docs/decisions.md` 2026-07-19 (gate decision
- Docs/kamome-poc-spec.md:19:rejected. Routing provider closed as **Geoapify** the same day. — v1.7 (2026-07-20) — **Replay MVP repositioning** (owner decision, `decisions.md` 2026-07-20). The first shipped product is redefined from "passive-capture v1" to the **Replay MVP**: photo-EXIF import → OSRM road reconstruction → souvenir-map recap → MP4 share, validated on **three real past trips**. Consequences: **Phase 3.5 is renamed Replay MVP** and absorbs **photo-EXIF import** (pulled forward from the old Phase 4); its gate becomes a **product release gate** (three shareable films), not a static-visual gate. The tracking/battery device gates (2 h drive, region-resume re-validation, long-duration background, process-death recovery, passive capture, ≥ 3-day battery, the "Arm once, forget it" promise) leave the release path for a new **Capture Beta** (Phase 5, renamed from Passive Capture Tier — the checklists are preserved and moved, never marked passed). **Story Director** (automatic moment-selection, narrative, hero photos, chapters/elision, licensed music + beat-sync) becomes **Phase 4** (renamed from Import & Map Matching — its EXIF half moved into the MVP; the Google Timeline importer is **dropped as redundant** — EXIF import covers past trips, in-app capture covers new ones; owner decision 2026-07-20). Story Director is **deterministic — no AI/LLM tokens** (scoring-and-selection over structured trip data, §7 Phase 4). Plans & Fork (Phase 6) and Backend (Phase 7) are unchanged and further deferred. **MP4 is the launch format; GIF is demoted to non-blocking.** Honest provenance added (§3, §6): `trip.source` distinguishes Kamome-recorded from reconstructed-from-photos, and UI copy never says "Verified Trip". Positioning de-overclaimed (header above). — v1.6 (2026-07-20) — recap visual system validated via a throwaway web prototype on real data (Chiu's 170-photo Iceland ring-road trip); owner sign-off "prototype 蠻成功的，收斂回 app". Findings + the data pipeline + engine source: `Docs/prototype/` (also `decisions.md` 2026-07-20). Locked-in constraints for §4.5/§7: (a) base map = **real geometry + hand-written subtractive style** = "紀念品地圖" (souvenir map), reaffirming the MapLibre substrate ADR; (b) stop photos = a **rotating photo deck at the stop location**, hero cross-fades through 3–8 photos at **0.8 s each** (not the old single card); (c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle is the subject, close heading-up zoom) — the prototype's one unmet requirement; top-down car is the default marker, seagull/scooter/bike swappable. Positioning line restated (above). Forward directions recorded: photo-EXIF import first (the prototype IS that importer, §4.7), video clips as auto-trimmed muted "beads", and royalty-free **beat-synced** music (bundled library + offline beat maps, events quantized to the beat; free=silent export, premium=in-app track). No architecture change — these constrain existing components (`RecapSnapshotProviding`, `CameraPath`, `OverlayTimeline`, `RecapTheme`, `ImportKit`). v1.5 (2026-07-19) — recap visual pivot (owner decision after reviewing the P3 demo artifact): the recap is a stylized, premium animated replay, not Apple-tile output — vision in `Docs/kamome-animation-vision.md`; recap base-map substrate moves MKMapSnapshotter → MapLibre Native + self-hosted vector tiles with Kamome-authored themed styles (ADR in `Docs/decisions.md` 2026-07-19; implementer guide `Docs/vector-tile-pipeline.md`); §0 gains rule 6 (storytelling engine + recognizable identity); §4.5 step 2 rewritten + visual quality bar added; Phase 3 scope frozen as the pipeline milestone; new **Phase 3.5 Recap Visual System** (OSRM §4.4 pulled forward → MapLibre substrate → Modern Minimal theme; no renumbering of P4–P7). v1.4 (2026-07-18) — fork demoted from positioning to mechanism: positioning line rewritten (memory-engine framing), §1.5 fork row relabeled P6 bet, §4.5 end card copy → "Get this route"; all user-facing copy uses Save / Get / Inspired by (S6/S7 screen wording settled at P6 — internal names, table `plan.forked_from`, and `.kamome` schema unchanged). v1.3 (2026-07-15) — battery-moat repositioning: passive capture tier (§1.8, §2.3), map matching promoted to core (§4.4), trip import (§4.7), phases renumbered (fork → Phase 6, backend → Phase 7), transactional monetization note (§1.6). v1.2 (2026-07-11) added Roadtrippers analysis, Taiwan-market adaptations, Kamome branding, handoff checklist & kickoff prompt.
- Docs/kamome-poc-spec.md:146:| Recap base map (Phase 3.5) | **MapLibre Native + self-hosted vector tiles, Kamome-authored style per theme** | Fully custom renderer; Mapbox; restyling MapKit (no styling API exists) | Owner-rejected Apple-tile look (ADR 2026-07-19). Full control of colors, typography, and what is *omitted*; PMTiles = static-file hosting, no tile server; same regional OSM extracts as OSRM; checked-in tiles make golden frames bit-stable. Must clear the §4.5 quality bar or the decision gets revisited. Guide: `Docs/vector-tile-pipeline.md`. |
- Docs/kamome-poc-spec.md:149:| Video | **Snapshot-provider frames → AVAssetWriter** (provider = MapLibre from Phase 3.5; MKMapSnapshotter was the P3 bootstrap) | Screen-record a map camera flight | Deterministic, background-renderable, testable frame-by-frame — property of the frame pipeline, independent of which provider renders the base map. |
- Docs/kamome-poc-spec.md:329:2. For each frame: a `RecapSnapshotProviding` provider renders the base map for the camera position (snapshot per keyframe every N frames, cross-fade between, to keep render time sane); the compositor draws the traveled route portion + animated head marker via CoreGraphics overlay, projecting through the snapshot's own projection. From Phase 3.5 the shipping provider is **MapLibre Native over self-hosted vector tiles with a Kamome-authored theme style** (ADR 2026-07-19; `Docs/vector-tile-pipeline.md`); `MapKitSnapshotProvider` was the P3 bootstrap, `FlatSnapshotProvider` keeps golden-frame CI deterministic. Boundary discipline: renderer SDK types never leak past the provider file (§0 rule 6 corollary).
- Docs/kamome-poc-spec.md:422:### Phase 3.5 — Replay MVP (recap from photos) ← the first shippable product / RELEASE TARGET
- Docs/kamome-poc-spec.md:478:**Estimates (revised 2026-07-20).** The near-term release is the **Replay MVP** (through Phase 3.5) — the remaining MVP build is import + substrate + theme + follow-cam + photo deck, then the three-trip dogfood day. **Story Director** (Phase 4) and **Capture Beta** (Phase 5) follow the MVP; Plans (6) and Backend (7) after. Budget calendar time for the Replay MVP device day (Chiu's iPhone + three real past-trip photo sets) and, later, for Capture Beta's several ordinary days carrying the phone with a trip armed.
- Docs/kamome-poc-spec.md:511:| ~~MKMapSnapshotter too slow/plain for video~~ **Materialized 2026-07-19** — owner rejected the Apple-tile look outright | — | Recap substrate replaced: MapLibre + self-hosted vector tiles, Phase 3.5 (ADR 2026-07-19). Keyframe + crossfade rendering strategy survives unchanged. |
- Docs/kamome-poc-spec.md:528:The §7 Phase 3.5 hard gate, restated as the go/no-go: three real past trips of **different character** each go **photos → import → route reconstruction → recap → MP4 → share, entirely in-app** — no DB edits, no repo-external tools; routes are honest (no gross sea/mountain/wrong-road fabrication; low confidence shown as inferred); all three films are ones Chiu wants to keep and share; **≥ 1 published publicly** without external editing; limited-photo path passes on device; stable export on a real iPhone (no crash, acceptable memory); per-trip export time recorded and product-acceptable. The bar is **"worth publishing," not "prettier map."** "Three trips" is hard — never downgraded to one.
- Docs/kamome-poc-spec.md:550:2. **Apple Developer:** free personal team is enough for most of the Replay MVP (7-day dev provisioning). Paid Program (US$99/yr) is required at the **Replay MVP TestFlight** (Phase 3.5 gate) — the first time the cost is unavoidable.
- Docs/osrm-setup.md:3:Self-hosted OSRM backing §4.4 map matching, pulled forward into Phase 3.5
- Docs/pre-launch.md:237:Phase 3.5 closed on 2026-08-15 with §6a passed and §6b explicitly not
- Docs/prototype/README.md:4:**Status:** exploration complete → feeds spec §4.5 / §7 (Phase 3.5) and §4.7 (import).
- Docs/prototype/README.md:82:  the Phase 3.5 quality-bar side-by-side.
- Docs/vector-tile-pipeline.md:1:# Vector-tile pipeline — recap base maps (Phase 3.5 = Replay MVP)
- Docs/vector-tile-pipeline.md:4:(spec v1.7 §4.5 / §7 Phase 3.5 = Replay MVP; ADR `Docs/decisions.md`
- Docs/vector-tile-pipeline.md:211:## 9. Deliverables checklist (Phase 3.5, substrate portion)

### Phase 4
- CLAUDE.md:164:Phase 4 item 3.
- CLAUDE.md:166:### Phase 4 scope (Chiu 2026-08-15)
- CLAUDE.md:221:**Map work is NOT in Phase 4.** Tiles, labels and the tile server all left the
- CLAUDE.md:264:measured numbers are in the Phase 4 section above.** Do not average the two sets
- HANDOFF.md:19:**Context.** Chiu opened the design conversation `CLAUDE.md` Phase 4 item 3 held
- HANDOFF.md:208:- `CLAUDE.md` Phase 4 item 3 — pointer added on Chiu's approval (2026-08-21). The
- Docs/camera-arcs.md:9:This document resolves the design conversation `CLAUDE.md` Phase 4 item 3 held
- Docs/decisions.md:155:**Decision:** Spec bumped to v1.3. New Phase 4 = Import & Map Matching
- Docs/decisions.md:190:**Rejected:** deferring the drive to Phase 4 (dwell region-resume and the
- Docs/decisions.md:632:  import is pulled forward into it** from the old Phase 4. Sequence:
- Docs/decisions.md:660:- **Phase 4 "Import & Map Matching" renamed → "Story Director."** Its EXIF half
- Docs/decisions.md:1278:4. **Phase 4 is scoped around the artefact, not the product.** Chiu chose this
- Docs/decisions.md:1287:  hundred commits and a clean base for Phase 4 was the stated motivation.
- Docs/decisions.md:1356:4. **Phase 4 reorders around what people asked for:** vehicle sprites →
- Docs/decisions.md:1635:§0, still Chiu's). Whether the Worker lands before or after Phase 4. Whether
- Docs/decisions.md:1667:   permission. **One email, before submission, not before Phase 4.**
- Docs/decisions.md:1671:   day. This is a submission blocker, not a Phase 4 one (`Docs/pre-launch.md`).
- Docs/eng-session-P4.md:1:# Engineering session — Phase 4, task 1: routing goes live
- Docs/eng-session-P4.md:18:- `CLAUDE.md` — current state, Phase 4 scope, and §0 (location data never leaves
- Docs/eng-session-camera-arc.md:22:- `CLAUDE.md` — current state, Phase 4, and §0 (location data never leaves the
- Docs/eng-session-camera-arc.md:23:  device). Phase 4 item 3 records that `keyframe_interval_frames` and the
- Docs/handoff-P3.5.md:248:  an MVP simplification. Story Director (Phase 4) will make the follow-cam **one
- Docs/handoff-P3.5.md:646:  controls, video beads, licensed music/beat-sync — **Story Director (Phase 4)**,
- Docs/handoff-P3.5.md:648:  tokens** — owner constraint 2026-07-20; spec §7 Phase 4. Google Timeline
- Docs/handoff-render-layers.md:39:  Phase 4 with a `supportsPitch` capability), `SubjectState` (lat/lon/heading/
- Docs/icebox.md:24:Was Phase 4 scope; cut. Photo-EXIF import already reconstructs *past* trips and
- Docs/icebox.md:61:foundation. This is a **Story Director-era** enrichment (Phase 4).
- Docs/icebox.md:90:  Director (Phase 4). Likely lands with, or just after, multi-modal.
- Docs/icebox.md:121:  Capture Beta (Phase 5), Story Director (Phase 4), themes.
- Docs/kamome-poc-spec.md:19:rejected. Routing provider closed as **Geoapify** the same day. — v1.7 (2026-07-20) — **Replay MVP repositioning** (owner decision, `decisions.md` 2026-07-20). The first shipped product is redefined from "passive-capture v1" to the **Replay MVP**: photo-EXIF import → OSRM road reconstruction → souvenir-map recap → MP4 share, validated on **three real past trips**. Consequences: **Phase 3.5 is renamed Replay MVP** and absorbs **photo-EXIF import** (pulled forward from the old Phase 4); its gate becomes a **product release gate** (three shareable films), not a static-visual gate. The tracking/battery device gates (2 h drive, region-resume re-validation, long-duration background, process-death recovery, passive capture, ≥ 3-day battery, the "Arm once, forget it" promise) leave the release path for a new **Capture Beta** (Phase 5, renamed from Passive Capture Tier — the checklists are preserved and moved, never marked passed). **Story Director** (automatic moment-selection, narrative, hero photos, chapters/elision, licensed music + beat-sync) becomes **Phase 4** (renamed from Import & Map Matching — its EXIF half moved into the MVP; the Google Timeline importer is **dropped as redundant** — EXIF import covers past trips, in-app capture covers new ones; owner decision 2026-07-20). Story Director is **deterministic — no AI/LLM tokens** (scoring-and-selection over structured trip data, §7 Phase 4). Plans & Fork (Phase 6) and Backend (Phase 7) are unchanged and further deferred. **MP4 is the launch format; GIF is demoted to non-blocking.** Honest provenance added (§3, §6): `trip.source` distinguishes Kamome-recorded from reconstructed-from-photos, and UI copy never says "Verified Trip". Positioning de-overclaimed (header above). — v1.6 (2026-07-20) — recap visual system validated via a throwaway web prototype on real data (Chiu's 170-photo Iceland ring-road trip); owner sign-off "prototype 蠻成功的，收斂回 app". Findings + the data pipeline + engine source: `Docs/prototype/` (also `decisions.md` 2026-07-20). Locked-in constraints for §4.5/§7: (a) base map = **real geometry + hand-written subtractive style** = "紀念品地圖" (souvenir map), reaffirming the MapLibre substrate ADR; (b) stop photos = a **rotating photo deck at the stop location**, hero cross-fades through 3–8 photos at **0.8 s each** (not the old single card); (c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle is the subject, close heading-up zoom) — the prototype's one unmet requirement; top-down car is the default marker, seagull/scooter/bike swappable. Positioning line restated (above). Forward directions recorded: photo-EXIF import first (the prototype IS that importer, §4.7), video clips as auto-trimmed muted "beads", and royalty-free **beat-synced** music (bundled library + offline beat maps, events quantized to the beat; free=silent export, premium=in-app track). No architecture change — these constrain existing components (`RecapSnapshotProviding`, `CameraPath`, `OverlayTimeline`, `RecapTheme`, `ImportKit`). v1.5 (2026-07-19) — recap visual pivot (owner decision after reviewing the P3 demo artifact): the recap is a stylized, premium animated replay, not Apple-tile output — vision in `Docs/kamome-animation-vision.md`; recap base-map substrate moves MKMapSnapshotter → MapLibre Native + self-hosted vector tiles with Kamome-authored themed styles (ADR in `Docs/decisions.md` 2026-07-19; implementer guide `Docs/vector-tile-pipeline.md`); §0 gains rule 6 (storytelling engine + recognizable identity); §4.5 step 2 rewritten + visual quality bar added; Phase 3 scope frozen as the pipeline milestone; new **Phase 3.5 Recap Visual System** (OSRM §4.4 pulled forward → MapLibre substrate → Modern Minimal theme; no renumbering of P4–P7). v1.4 (2026-07-18) — fork demoted from positioning to mechanism: positioning line rewritten (memory-engine framing), §1.5 fork row relabeled P6 bet, §4.5 end card copy → "Get this route"; all user-facing copy uses Save / Get / Inspired by (S6/S7 screen wording settled at P6 — internal names, table `plan.forked_from`, and `.kamome` schema unchanged). v1.3 (2026-07-15) — battery-moat repositioning: passive capture tier (§1.8, §2.3), map matching promoted to core (§4.4), trip import (§4.7), phases renumbered (fork → Phase 6, backend → Phase 7), transactional monetization note (§1.6). v1.2 (2026-07-11) added Roadtrippers analysis, Taiwan-market adaptations, Kamome branding, handoff checklist & kickoff prompt.
- Docs/kamome-poc-spec.md:445:### Phase 4 — Story Director (est. TBD) ← only after the Replay MVP proves films get shared
- Docs/kamome-poc-spec.md:478:**Estimates (revised 2026-07-20).** The near-term release is the **Replay MVP** (through Phase 3.5) — the remaining MVP build is import + substrate + theme + follow-cam + photo deck, then the three-trip dogfood day. **Story Director** (Phase 4) and **Capture Beta** (Phase 5) follow the MVP; Plans (6) and Backend (7) after. Budget calendar time for the Replay MVP device day (Chiu's iPhone + three real past-trip photo sets) and, later, for Capture Beta's several ordinary days carrying the phone with a trip armed.
- Docs/pre-launch.md:7:Nothing here blocks Phase 4. Everything here blocks a submission.
- Docs/pre-launch.md:186:Read on 2026-08-20 (`Docs/decisions.md` 2026-08-20 (b)). Neither blocks Phase 4.

### current phase
- Docs/decisions.md:702:re-tagging), `CLAUDE.md` (current phase + gate), plus secondary phase-ref
- Docs/kamome-poc-spec.md:557:Must contain only: pointer to `Docs/kamome-poc-spec.md` as authoritative; current phase number and its gate criteria verbatim; the three commands (`xcodegen generate`, `xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 16'`, `swiftlint`); the Rules of Engagement §0 by reference, not copied. Phase state updates when a gate passes — nothing else accumulates here.

### release target
- CLAUDE.md:6:release target)**, P4 = Story Director, P5 = Capture Beta, P6 = Plans, P7 =

### location data
- HANDOFF.md:7:Read `CLAUDE.md` first for the standing rules — especially **§0, location data
- Docs/eng-session-P4.md:18:- `CLAUDE.md` — current state, Phase 4 scope, and §0 (location data never leaves
- Docs/eng-session-camera-arc.md:22:- `CLAUDE.md` — current state, Phase 4, and §0 (location data never leaves the

### privacy
- HANDOFF.md:346:### 3c. 🟠 The album path is promoted — it is now the privacy notice's control (2026-08-20)
- HANDOFF.md:350:privacy decision states the notice will say a **date range** decides what is sent
- Docs/decisions.md:242:  switch: overlay events off = route-only animation (also the privacy-
- Docs/decisions.md:1642:## 2026-08-20 (b) — Geoapify's terms, read; and what Kamome now commits to on privacy
- Docs/decisions.md:1698:     a confidential matter. **This must still be declared honestly** in a privacy
- Docs/decisions.md:1727:disclosure says plainly that a date range decides what is sent. **A privacy notice
- Docs/decisions.md:1785:### 4. The album path is now load-bearing for the privacy story
- Docs/decisions.md:1792:fetch") stops being a cross-region convenience and becomes **the control the privacy
- Docs/demos/phase2/README.md:14:  `simctl privacy` cannot pre-answer the iOS 26 photos prompt, so the demo
- Docs/demos/phase3_5/import/README.md:13:| `02-import-sheet.png` | Import sheet | Date-range selection (From / To) as tappable summary rows, the **7-day default range** driven by `import.default_range_days` (Jul 14 → Jul 21), the privacy footer ("Photos are never copied or uploaded"), and the `Import` action. Each row expands an inline calendar that **collapses once a day is picked** (shows the selection, doesn't leave the picker hanging open); picking a start date **snaps the end onto the start's month** if it drifted, so the "To" calendar opens on the trip's month — device-test feedback 2026-07-21. |
- Docs/eng-session-P4.md:23:  the privacy line is drawn. The most recent entry on a subject wins.
- Docs/kamome-poc-spec.md:91:- **Localization architecture:** String Catalogs from Phase 0, zh-Hant as development language, en as first export locale. Stop names via CLGeocoder honor device locale (Chinese place names natively). App Store metadata, screenshots, and privacy labels prepared in both zh-Hant and en-AU/US.
- Docs/kamome-poc-spec.md:249:- Photos are referenced by PhotoKit identifier only — never duplicated into app storage (storage + privacy win). Handle deleted-asset gracefully (placeholder tile).
- Docs/pre-launch.md:26:| **7** | **Privacy notice + Apple's App Privacy labels** | Routing sends coordinates to a third party, so Apple's privacy questionnaire must declare it. The notice is decided (2026-08-20 c) but **does not exist**, and the album path ships with it. Was missing from the list. |
- Docs/pre-launch.md:207:## 🟠 The privacy policy has to exist, and has to be true
- Docs/pre-launch.md:232:now the control the privacy story rests on — a notice may not promise a control the
- Docs/routing-provider-selection.md:91:Kamome's privacy story**, and the product's central claim is that this data is

### telemetry
- CLAUDE.md:28:here: any P7 backend sync, any analytics or crash reporter, any telemetry, any
- Docs/kamome-poc-spec.md:474:### Phase 7 — Backend & Community (post-POC, only if Phase 6 telemetry says people fork)

### API
- Arch.md:79:- **Match existing conventions** (naming, folders, error handling, testing, API design) even if you'd do it differently. Flag inconsistencies instead of adding a competing pattern.
- HANDOFF.md:486:`/v1/routing` is **GET-only**, so the request URL will contain **both the API key and
- Docs/decisions.md:126:`didExitRegion` in the existing delegate. `CLMonitor` is an async/actor API
- Docs/decisions.md:444:MapKit (impossible — no styling API); Mapbox (metered, closed);
- Docs/decisions.md:736:   API. Resolution verified (`xcodebuild -resolvePackageDependencies`).
- Docs/decisions.md:784:and **links** MapLibre (compile-checks the `MLN*` API usage); the confinement
- Docs/decisions.md:1312:## 2026-08-15 — MapLibre is parked, Apple Maps is what ships, and routing moves behind an API
- Docs/decisions.md:1354:3. **Routing stays OSRM, and moves behind an API** rather than a machine on
- Docs/decisions.md:1355:   Chiu's LAN. ⚠️ *Which* API is not decided — see below.
- Docs/decisions.md:1473:## 2026-08-16 — Routing moves to a commercial API's free tier, and real coordinates leave the device
- Docs/decisions.md:1476:hosted routing API, on a free tier**. The specific provider is **not yet chosen**.
- Docs/decisions.md:1622:GET-only means **the coordinates travel in the URL query string, beside the API
- Docs/decisions.md:1653:| may returned routes be **stored permanently**? | **The T&C does not address it at all** — no clause permitting it, none forbidding it. Geoapify's own FAQ says results may be cached and reused, but the wording found is **Places-API specific**. | Terms & Conditions; Places-API comparison page |
- Docs/decisions.md:1658:| what they log | **Request body, headers, IP address and timestamp**, used for access control / usage counting and for detecting issues and optimising the APIs. | Privacy Policy *Services and API Requests* |
- Docs/eng-session-P4-visual.md:1:# Engineering session — confirm the API, then look at the film
- Docs/eng-session-P4-visual.md:14:confirms the API works, then makes three cheap visual changes Chiu will judge by
- Docs/eng-session-P4.md:41:2. The Cloudflare Worker that takes the API key out of the binary
- Docs/eng-session-P4.md:74:- **§0 — never log the request URL.** GET-only means the URL carries the API key
- Docs/eng-session-closeout.md:1:# Engineering session — close out sprites and the API key
- Docs/eng-session-closeout.md:80:## Task 2 — close out the API key, by verifying rather than trusting
- Docs/handoff-P3.5.md:169:      links; the build **compile-checks** the `MLN*` API usage.
- Docs/icebox.md:213:**The rabbit hole to price before starting** is not the API, it is (a) running
- Docs/kamome-poc-spec.md:31:3. **Prefer boring tech.** No reactive frameworks beyond what SwiftUI requires. Use Swift Concurrency (async/await) only where the OS API forces it (location callbacks, photo fetches, video export). No Combine pipelines for business logic.
- Docs/kamome-poc-spec.md:146:| Recap base map (Phase 3.5) | **MapLibre Native + self-hosted vector tiles, Kamome-authored style per theme** | Fully custom renderer; Mapbox; restyling MapKit (no styling API exists) | Owner-rejected Apple-tile look (ADR 2026-07-19). Full control of colors, typography, and what is *omitted*; PMTiles = static-file hosting, no tile server; same regional OSM extracts as OSRM; checked-in tiles make golden frames bit-stable. Must clear the §4.5 quality bar or the decision gets revisited. Guide: `Docs/vector-tile-pipeline.md`. |
- Docs/kamome-poc-spec.md:147:| Map matching (snap-to-road) | **OSRM `/match`, self-hosted Docker** (app side landed in the Replay MVP / P3.5) | Mapbox Map Matching API | Free, offline-capable for a region extract (e.g. Australia OSM ≈ 1 GB, Taiwan ≈ 100 MB), no per-request cost. Mapbox is easier but meters every request. Phases 1–3 shipped raw polyline + Douglas-Peucker; from the Replay MVP matching is **core infrastructure** — photo-EXIF import (§4.7) is load-bearing on it (sparse geotags look wrong unsnapped), and the passive tier (§1.8, Capture Beta) later too — but trip completion/import must still never block on it. |
- Docs/kamome-poc-spec.md:150:| Backend (Phase 7 only) | **Supabase** | Custom FastAPI | Auth + Postgres/PostGIS + storage + row-level security in one; solo-maintainable. |
- Docs/kamome-poc-spec.md:159:- Mode labeling: `CMMotionActivityManager.queryActivityStarting(from:to:)` backfill once per day (the API keeps ~7 days of history) classifies segments drive/walk/transit after the fact.
- Docs/kamome-poc-spec.md:255:A versioned JSON document — this is the product's contract, treat schema changes like API changes:
- Docs/pre-launch.md:117:## 🔴 The routing API key must not be in the binary
- Docs/pre-launch.md:132:every hosted API has the same problem with every native app.**
- Docs/pre-launch.md:267:Routing sends real trip coordinates to a hosted API. The failure copy tells
- Docs/routing-provider-selection.md:13:**The decision to use a hosted third-party API on a free tier is made**
- Docs/vector-tile-pipeline.md:16:`MKMapSnapshotter` has no styling API, so the recap renders MapLibre

### Key
- HANDOFF.md:472:with `apiKey` deliberately outside `Matching.CodingKeys` and a test proving the
- HANDOFF.md:478:Two notes rather than objections: `matching.apiKey` is carried but not yet used by
- Docs/demos/phase0/gate-output.md:22:    Test Case '-[KamomeCoreTests.ConfigLoaderTests testMissingKeyFailsLoudlyNamingTheKey]' passed (0.002 seconds).
- Docs/eng-session-closeout.md:83:`Info.plist` → `AppConfig`, with `apiKey` deliberately outside
- Docs/eng-session-closeout.md:84:`Matching.CodingKeys`. That work is reviewed and sound. **What is not done is
- Docs/eng-session-closeout.md:110:Also note: `Matching.apiKey` is carried but no provider reads it yet. That is
- Docs/handoff-render-layers.md:104:## 3. Key constraints (do not violate)
- Docs/kamome-poc-spec.md:140:### 2.2 Key technology decisions (with trade-offs)
- Docs/kamome-poc-spec.md:511:| ~~MKMapSnapshotter too slow/plain for video~~ **Materialized 2026-07-19** — owner rejected the Apple-tile look outright | — | Recap substrate replaced: MapLibre + self-hosted vector tiles, Phase 3.5 (ADR 2026-07-19). Keyframe + crossfade rendering strategy survives unchanged. |
- Docs/pre-launch.md:49:| 1 | **git** | ✅ **guarded** — CI step + `RoutingKeyTests`, both positive-controlled 2026-08-20 | done |
- Docs/prototype/README.md:154:Key proof: **sparse geotagged photos are enough** to reconstruct a recognizable

### single source of truth
- Docs/kamome-poc-spec.md:554:6. Put this spec at `Docs/kamome-poc-spec.md` in the repo — it is the single source of truth.

### LOCKED
- PO.md:247:- **LOCKED** — already decided; do not reopen
- Docs/prototype/README.md:59:### 2.1 Base map = real geometry + hand-written subtractive style ✅ LOCKED

### SUPERSEDED
- CLAUDE.md:313:- **Wide baseline (2026-08-02) SUPERSEDED 2026-08-08** (Chiu, from renders). It
- HANDOFF.md:222:### 1. ⚠️ SUPERSEDED 2026-08-20 (d) — the mechanism below was measured and does not hold
- Docs/handoff-P3.5.md:440:### Trips that span two map regions — SUPERSEDED by `Docs/cross-region-journeys.md` (2026-08-14) 📄

### DEPRECATED

### TODO

### TBD
- Docs/kamome-poc-spec.md:445:### Phase 4 — Story Director (est. TBD) ← only after the Replay MVP proves films get shared

### leg
- CLAUDE.md:78:  "reconstructed from photos"; low-confidence legs render inferred.
- CLAUDE.md:141:that does not resolve on their network — `matchTrip` awaits legs sequentially, so
- CLAUDE.md:142:more photos means more stops, more legs, and more back-to-back timeouts. Not
- CLAUDE.md:156:  per leg, and is bounded by `matching.trip_budget_s` (60 s) for the whole trip.
- CLAUDE.md:190:   `RecapSnapshotBudgetTests` on the real Miyakojima dump (offline, all legs
- CLAUDE.md:233:had no routable legs at all, because the Japan extract is Kyushu.
- CLAUDE.md:250:leg (ratio 2.247)** — which **passes** the 2.5 detour gate, is stored, and draws as
- CLAUDE.md:252:fjord drive is legitimately 2–4×, so the ratio cannot tell a wrong road from an
- CLAUDE.md:293:1. Multi-day inter-day legs typed `.walk` — **fixed** 2026-08-02 by
- CLAUDE.md:333:fixture, `base_url=""` for worst-case inferred legs):
- HANDOFF.md:3:**Updated 2026-08-08.** Branch `feature/typed-legs-routing` (PR #12 → `phase-3-recap`;
- HANDOFF.md:241:returns `NoSegment`, so the leg draws **dashed**. Geoapify's `/v1/routing` has a
- HANDOFF.md:244:for an 11.29 km leg, ratio 2.247**.
- HANDOFF.md:253:peninsula drive is legitimately 2–4×, and Iceland is made of them. The ratio cannot
- HANDOFF.md:285:second run skips every leg already matched and genuinely resumes. "Kamome only
- HANDOFF.md:333:**Transit is a different problem and must not ride along.** A Shinkansen leg routed
- HANDOFF.md:339:**⚠️ §0 consequence, and it is Chiu's call.** Walk legs are currently **never sent
- HANDOFF.md:342:intimate than the drive legs the 2026-08-16 ADR accepted.
- HANDOFF.md:440:Survey latency: 0.48–2.53 s a leg cold, 440–840 ms back-to-back with connection
- HANDOFF.md:441:reuse (which `URLSession.shared` gives us). Iceland is 58 legs → somewhere between
- HANDOFF.md:444:`matchTrip` already logs `STOPPED after N legs — trip_budget_s exhausted`. **The
- HANDOFF.md:461:it: EXIF legs go through `RouteReconstructing.route` (`/v1/routing`); only `.gpsHifi`
- HANDOFF.md:565:| dashed drive legs | 0 | 1 of 17 | **11 of 59** |
- HANDOFF.md:682:- **The one dashed leg that mattered — accepted.** See "Leg 12" below.
- HANDOFF.md:701:    opening → [first stop's pin/title/photos] → car appears → first leg
- HANDOFF.md:702:    opening → car appears → first leg
- HANDOFF.md:709:### Dashed legs — the honest ones, and the one that was a judgment call
- HANDOFF.md:711:Iceland: **10 dashed drive legs of 58 routable** (64 legs = 58 drive + 6 walk; all
- HANDOFF.md:726:such leg does not cost the film. ⚠️ **This is a judgment on one instance, not a
- HANDOFF.md:737:leg over water knows it may be the gate and not the data.
- HANDOFF.md:739:### New Zealand's single dashed leg — deferred, but it found a real gap
- HANDOFF.md:745:a pure ratio with no absolute floor**, so 300 m of difference on a 100 m leg trips
- HANDOFF.md:750:Miyakojima: **zero dashed drive legs** (9 of 9 reconstructed); its one dashed leg
- HANDOFF.md:754:legs sequentially, so the k-th `[routing] route:` line is the k-th routable leg.
- HANDOFF.md:755:Cross-checked three ways — 58 route lines for 58 routable legs, 10 failures for
- HANDOFF.md:756:exactly 10 dashed drive legs, and every failure landing on the ordinal of a leg
- HANDOFF.md:761:48 legs routed fine. Second confirmed sighting; still unfixed, still the line you
- HANDOFF.md:1097:   form and `bodyFrame` delegates to it.
- HANDOFF.md:1191:Pacing must never query tile coverage. The span cap legitimately must. Because
- HANDOFF.md:1623:  ships `""`, so the shipped app reconstructs **no** legs and draws everything
- HANDOFF.md:1629:  says `"(none — matching disabled)"` in the same run where legs reconstruct
- HANDOFF.md:1642:  reading `~/kamome-osrm/docker-compose.yml`, a **legacy file** carrying only
- PO.md:19:This splits what can be verified directly from what must be delegated:
- PO.md:22:- **Out of scope, must delegate:** visual/rendered behavior, real-trip behavior, performance. This session specifies exactly what evidence is needed and requests it from the active implementation session or the human Product Owner. It never assumes such evidence, and never marks a finding VERIFIED without it in hand.
- PO.md:255:- **UNKNOWN** — requires investigation, including anything that needs delegated evidence not yet supplied
- PO.md:320:**Cannot be verified directly — must be requested as delegated evidence:**
- PO.md:325:A request for delegated evidence must state exactly what to render or measure, against what input, and what counts as pass/fail — not a vague "please check this."
- Docs/camera-arcs.md:162:routable leg". Recommend deriving it from extent against `camera_span_m` rather
- Docs/camera-arcs.md:206:| what rides it | the title card | a dashed inferred leg + plane / ship / seagull |
- Docs/camera-arcs.md:391:  whether a crossing is a presented stop, multi-leg journeys, the return leg, and
- Docs/cross-region-journeys.md:68:2. **A flight leg is flown by a plane**, and **the plane moves faster than the car
- Docs/cross-region-journeys.md:80:already refuses to draw a road it did not reconstruct — an inferred leg is dashed
- Docs/cross-region-journeys.md:146:The classifier is its own seam: leg + both endpoints in, a mode out, with the
- Docs/cross-region-journeys.md:151:| OSRM returned `NoSegment` | no road network — water, or off-extract | yes, logged per leg |
- Docs/cross-region-journeys.md:163:  work — that ceiling is what stopped 7 of 9 New Zealand legs being typed as walks.
- Docs/cross-region-journeys.md:243:- **Multi-leg journeys** — a trip with two flights, or a flight plus a ferry, is
- Docs/cross-region-journeys.md:246:- **The return leg.** A round trip ends where it began; whether the film flies home
- Docs/decisions.md:126:`didExitRegion` in the existing delegate. `CLMonitor` is an async/actor API
- Docs/decisions.md:231:**Decision (Chiu; scheduling delegated to Claude):**
- Docs/decisions.md:315:(perth's legitimate walk loops range 274–460 m); live wall-clock silence
- Docs/decisions.md:1011:Two problems, one visible and one conceptual: pause the film mid-leg and it told
- Docs/decisions.md:1022:- **The day on a leg is the day of the stop just left**, held until the next is
- Docs/decisions.md:1023:  reached. A leg belongs to no stop and must inherit from one; inheriting
- Docs/decisions.md:1377:That is a legitimate call and it is not the same as concluding the path failed.
- Docs/decisions.md:1391:saved; `matchTrip` walked the legs sequentially at `matching.timeout_s` each,
- Docs/decisions.md:1394:stops, more legs, and more back-to-back timeouts behind a UI with nothing to
- Docs/decisions.md:1395:press. A build carrying a LAN `base_url` makes every one of those legs time out.
- Docs/decisions.md:1401:   it, and an unrouted leg draws dashed rather than claiming a road (PD-2).
- Docs/decisions.md:1405:   `matchTrip` checks cancellation before every leg, and
- Docs/decisions.md:1407:   a request; nothing bounded the trip. Past the budget the remaining legs stay
- Docs/decisions.md:1480:friend's Tokyo trip had **no routable legs at all**, because `Deploy/regions.json`
- Docs/decisions.md:1483:and dashes everything else — and "every leg a straight line" is what §6a's honesty
- Docs/decisions.md:1487:this: one film is one request per drive leg — 9 on Miyakojima, 17 on New Zealand,
- Docs/decisions.md:1496:but a third party now sees where a leg started and ended.
- Docs/decisions.md:1510:  server at roughly one second per leg on the largest trip. A free tier's rate
- Docs/decisions.md:1554:from a road returns `NoSegment` → nil → **the leg draws dashed**. That is PD-2
- Docs/decisions.md:1566:| **1000 m off-road** | **dashed** | **200 · 20.33 km for an 11.29 km leg · ratio 2.247** |
- Docs/decisions.md:1574:**Do not fix this by tightening the ratio.** The survey's legitimate routes measure
- Docs/decisions.md:1576:fjord or peninsula drive is *legitimately* 2–4× its straight line, and Iceland is
- Docs/decisions.md:1595:- **The 1500 m map-matching ceiling does not bind photo import.** EXIF legs go
- Docs/decisions.md:1607:- **`matching.trip_budget_s` (60 s).** Task 1 measured 0.48–2.53 s a leg (cold),
- Docs/decisions.md:1609:  gives us). Iceland is 58 legs, so the sequential trip lands somewhere between
- Docs/decisions.md:1612:  Geoapify *is* the measurement: `matchTrip` already logs `STOPPED after N legs —
- Docs/decisions.md:1621:The 2026-08-16 ADR accepted that a third party sees where a leg started and ended.
- Docs/decisions.md:1677:unroutable leg, a rate-limited burst, a request that times out. Nothing states how
- Docs/decisions.md:1681:24 hours, a third party holds the start and end coordinates of each routed leg,
- Docs/decisions.md:1715:- *"We do not **send** it"* — a real change: recorded legs would stop being
- Docs/decisions.md:1766:The sentence Chiu approved — *"the start and end coordinates of each leg, in a URL,
- Docs/decisions.md:1770:| | photo-imported leg | recorded leg |
- Docs/decisions.md:1774:| what is sent | the leg's waypoints: stop centroids **plus photo positions**, thinned to ≥ `route_waypoint_min_spacing_m` (250 m), capped at `chunk_size` (100) | **the full recorded trace**, in chunks of up to 100 points |
- Docs/decisions.md:1780:photo positions a leg is built from, and that a recorded trip sends **the recorded
- Docs/decisions.md:1808:> 11.29 km leg, which passes the 2.5 detour gate and draws as solid road.
- Docs/decisions.md:1817:photo legs cannot use.
- Docs/decisions.md:1850:keep-raw verdict and a dashed leg.
- Docs/decisions.md:1864:   sides: benign offsets measured 1.19–1.27 and wrong ones 1.92–2.31 **on one leg
- Docs/decisions.md:1865:   in one landscape**, while a fjord or peninsula drive is legitimately 2–4×. One
- Docs/decisions.md:1866:   leg is not a distribution.
- Docs/decisions.md:1867:4. **The Iceland film is the test.** 58 legs of real photo positions, judged by
- Docs/decisions.md:1873:(spec v1.8 §4.4.1), those legs route on the footpath actually taken instead of
- Docs/demos/phase3/README.md:29:has since been regenerated with road-matched drive legs
- Docs/demos/phase3/README.md:30:(`generate_fixtures.py route_leg`); this artifact predates that and is kept
- Docs/demos/phase3_5/matching/README.md:17:1. **The perth fixture was regenerated with road-matched drive legs**
- Docs/demos/phase3_5/matching/README.md:18:   (`generate_fixtures.py route_leg`, this commit). §1 validation exposed
- Docs/demos/phase3_5/matching/README.md:19:   that the old fixture's straight anchor-to-anchor legs sat kilometers
- Docs/device-test-P3.md:48:            suspension — either way the leg must be recorded)
- Docs/dogfood-infrastructure.md:61:and the leg renders dashed rather than inventing a road (PD-2).
- Docs/dogfood-infrastructure.md:100:makes every request 403, and because a routing failure means "keep the raw leg"
- Docs/dogfood-infrastructure.md:101:(PD-2), **every leg would silently render dashed** with nothing in the UI saying
- Docs/dogfood-infrastructure.md:184:- [ ] Reconstructed legs draw solid and unroutable ones dashed (PD-1). All-dashed
- Docs/eng-session-P4-visual.md:23:real. One routed leg returning 200 through the app's own configuration is enough.
- Docs/eng-session-P4-visual.md:36:guards the glow pass behind `alpha > 0.001`, so that pass does not run. A solid leg
- Docs/eng-session-P4-visual.md:86:- **Judging whether any of the 49 solid legs is a wrong road.** That is Chiu's call
- Docs/eng-session-P4.md:60:     returns 200 and a 20.33 km route for an 11.29 km leg (ratio 2.247), which
- Docs/eng-session-P4.md:66:     to be solved by tightening the detour ratio (a fjord drive is legitimately
- Docs/eng-session-P4.md:72:  `shouldReconstruct` skips already-matched legs, so a second run really does
- Docs/eng-session-P4.md:87:It is 60 s, chosen against a healthy LAN server at ~1 s a leg. Survey latency was
- Docs/eng-session-P4.md:88:0.48–2.53 s cold and 440–840 ms with connection reuse; Iceland is 58 legs, so the
- Docs/eng-session-P4.md:90:not a measurement.** `matchTrip` already logs `STOPPED after N legs —
- Docs/eng-session-P4.md:101:  legs routed versus stayed dashed, the `matchTrip` log line, and the film itself.
- Docs/gate-P3.5-checklist.md:3:Consolidated 2026-07-31; revised 2026-08-02 after the camera/legibility work
- Docs/gate-P3.5-checklist.md:30:detour-gate dashed leg accepted **for that instance**. The films are in
- Docs/gate-P3.5-checklist.md:49:legs as roads). **#2 is mitigated, not solved** — the film still shows blank
- Docs/gate-P3.5-checklist.md:56:### 1. Multi-day trips type every inter-day leg as a walk ✅ FIXED 2026-08-02
- Docs/gate-P3.5-checklist.md:61:walks are deliberately never routed → the leg stays a straight line and draws
- Docs/gate-P3.5-checklist.md:64:Measured on the real 11-day NZ trip: **7 of 9 legs**. The gate item *"no obvious
- Docs/gate-P3.5-checklist.md:69:elapsed time was not spent travelling, so pace carries no signal and the leg
- Docs/gate-P3.5-checklist.md:70:falls back to the road-trip assumption already made for zero-elapsed legs.
- Docs/gate-P3.5-checklist.md:72:On the NZ reconstruction: **7 walk-typed legs → 0**.
- Docs/gate-P3.5-checklist.md:74:⚠️ **A different knob to watch at Stage 1.** OSRM is asked to snap each leg
- Docs/gate-P3.5-checklist.md:75:endpoint within `matching.route_waypoint_radius_m` (500 m). A leg endpoint is a
- Docs/gate-P3.5-checklist.md:78:whole leg then comes back `NoSegment` and stays dashed. Honest, but if real
- Docs/gate-P3.5-checklist.md:153:      something with an inferred leg in it.
- Docs/gate-P3.5-checklist.md:175:      and their ratio, the dashed-leg list, and — in Variant A — a duration that
- Docs/gate-P3.5-checklist.md:179:      `drive/inferred` and `walk/inferred` are the legs that will draw dashed;
- Docs/gate-P3.5-checklist.md:232:`matchTrip … N/M legs reconstructed` tally instead.
- Docs/gate-P3.5-checklist.md:299:      firewall gives you a complete, plausible film with every leg dashed — not an
- Docs/gate-P3.5-checklist.md:301:      Info.plist; allow the prompt when it appears or every leg dashes.
- Docs/gate-P3.5-checklist.md:352:- **Every leg dashed** ⇒ routing never answered. See the Safari check above.
- Docs/gate-P3.5-checklist.md:363:- [x] **Honesty review**: look at a published film with a dashed leg in it and
- Docs/gate-P3.5-checklist.md:366:      — **judged 2026-08-13 on Iceland's detour-gate leg: accepted.** ⚠️ That was
- Docs/gate-P3.5-checklist.md:426:with every leg dashed** — not an error. If macOS prompts to allow incoming
- Docs/gate-P3.5-checklist.md:439:  or every leg draws dashed.
- Docs/gate-P3.5-checklist.md:469:| `matchTrip …: 0/4 legs routable against "(none — matching disabled)"` | the build has `matching.base_url` empty — you are running a config that never asks |
- Docs/gate-P3.5-checklist.md:470:| `matchTrip …: 4/4 legs routable against "http://192.168.0.6:5100"` | it asked; read on for what came back |
- Docs/gate-P3.5-checklist.md:472:| `route: OSRM said NoSegment` | reached the server; there is no road network there. Correct for a leg outside the merged extract, or across water |
- Docs/gate-P3.5-checklist.md:474:| `matchTrip …: 0/4 legs reconstructed` | the headline: how much of the film draws as road |
- Docs/gate-P3.5-checklist.md:475:| `no installed map region covers this trip` | Apple's map, no prologue **and** the legacy 30 s duration, all at once |
- Docs/gate-P3.5-checklist.md:476:| `film: 90.0s · 2700 frames · opening 5.9s · 9 stops · 0/5 legs dashed` | what was actually rendered |
- Docs/handoff-P3.5.md:429:      failure as "keep raw geometry" (PD-2), **every leg would silently render
- Docs/handoff-P3.5.md:499:stop count and dashed-leg count (`KamomeLog.recap`).
- Docs/handoff-P3.5.md:501:Related, also deferred: the airport-departure animation (a flight leg is a genuine
- Docs/handoff-recap-visuals.md:20:  frame is what makes the distance covered legible — the drawn line grows against
- Docs/handoff-render-layers.md:94:  delegation shim.
- Docs/icebox.md:66:## Flight legs — airport-to-airport journey framing (owner idea, 2026-07-21)
- Docs/icebox.md:68:Add an **inferred flight leg**: between two clusters separated by a big spatial
- Docs/icebox.md:75:- **Honest by construction:** there is no GPS on a plane, so a flight leg is
- Docs/icebox.md:120:- Relates to: flight legs (above, a `flight` mode is the first non-road example),
- Docs/icebox.md:129:right now"). Raised while comparing span/label options for the legibility
- Docs/kamome-animation-vision.md:29:  are not tamper-proof; low-confidence legs render as inferred, never invented.
- Docs/kamome-animation-vision.md:68:elegant, premium. Avoid: overly saturated colors, childish UI,
- Docs/kamome-animation-vision.md:92:  hand-crafted illustrations, soft colors, playful but elegant, charming
- Docs/kamome-poc-spec.md:18:crossing beat, not a routing profile. Drawing a leg on a road it did not take is
- Docs/kamome-poc-spec.md:44:**Long-term vision (validated later; NOT an MVP claim):** "Arm it once when the trip starts, forget the app for days — get a cinematic map video of your road trip, with battery drain you can't measure." This zero-effort passive-capture promise is the eventual differentiator #1 (§1.8), but it is proven in **Capture Beta** (§7), not at MVP launch. When capture does ship, its rule holds: Kamome's capture must never depend on the user remembering anything mid-trip (Relive makes you start/stop every activity — forget once and that leg is gone forever).
- Docs/kamome-poc-spec.md:90:- **Transit interleaving matters more.** Taiwanese multi-day trips commonly mix TRA/HSR legs with driving. Speed >130 km/h sustained + no highway match = rail heuristic → mode `transit`, drawn as a distinct line style. (In AU this was an edge case; in TW it's normal.)
- Docs/kamome-poc-spec.md:289:- **Replay MVP / P3.5** (app side landed, `decisions.md` 2026-07-19; **core**, promoted from stretch — §1.8): batch segments (≤100 pts/request) to OSRM `/match?geometries=polyline&tidy=true`; store result in `segment.matched_polyline`. One pipeline serves three sources: imported photo-EXIF points (load-bearing — sparse geotags look wrong without snapping; this is the MVP's dependency), later imported Timeline points and passive-tier fixes (Capture Beta), and high-fidelity recordings (cosmetic win). On failure (no OSRM reachable / confidence below `matching_confidence_min`), fall back to simplified raw polyline, mark segment `matched=false`, render **"inferred" (honestly low-confidence) style** — the Replay MVP gate forbids inventing a route that crosses sea/mountain or a wrong road, so low-confidence legs must read as inferred, never as fact. **Never block trip completion or import on matching.**
- Docs/kamome-poc-spec.md:308:profile has nothing — a beach, a glacier, a field, indoors — the leg stays inferred
- Docs/kamome-poc-spec.md:313:far side of a ridge; a train leg routed on any road profile draws the **expressway**.
- Docs/kamome-poc-spec.md:358:| S3 | Trip Detail | Full map with matched route colored by mode (drive = solid, walk = dotted), **inferred/low-confidence legs shown honestly** (dashed), stop pins with photo thumbnails, day filter chips, stats strip (distance, drive time, stops, top speed), **provenance note** for imported trips ("reconstructed from photos", never "verified"). Timeline list below map. |
- Docs/kamome-poc-spec.md:383:> Each phase = one milestone PR. Verification commands run from repo root. GPX fixtures live in `Tests/Fixtures/` and include `perth_margaret_river_day1.gpx` (synthetic 280 km drive with 4 stops + 2 walk loops), `taiwan_huandao_9days.gpx` (synthetic round-island loop, mixed car + scooter + one TRA rail leg — exercises transit heuristic and 環島 loop detection), and `city_walk_flapping.gpx` (mode-flapping torture test).
- Docs/kamome-poc-spec.md:513:| Imported recap read as recorded fact (route reconstructed from photos mistaken for a verified GPS trip) | Medium | Honest provenance is a product rule (§3/§6): `trip.source` badge on S1/S3, "reconstructed from photos" copy, inferred legs drawn dashed; never "Verified Trip". A wrong-road or sea-crossing inference must read as inferred — the Replay MVP gate rejects gross fabrication. |
- Docs/pre-launch.md:189:with no realistic legal exposure, and the remedy in either case is to upgrade the
- Docs/pre-launch.md:222:| | photo-imported leg | recorded leg |
- Docs/pre-launch.md:224:| what is sent | the leg's waypoints — stop centroids **plus photo positions**, thinned to ≥250 m, ≤100 per leg | **the full recorded trace**, in chunks of ≤100 points |
- Docs/prototype/README.md:182:   music on IG/TikTok — legal, matches platform norms); premium = **in-app
- Docs/routing-provider-selection.md:19:film is one request per drive leg (9 on Miyakojima, 17 on New Zealand, 58 on
- Docs/routing-provider-selection.md:111:  local server at roughly a second a leg, never against a rate-limited tier.

### stop
- Arch.md:21:Higher overrides lower. If two sources at the same level conflict, do not silently pick one — state the conflict and stop if it materially affects scope, architecture, or product behavior.
- Arch.md:33:If the repo itself is inconsistent (docs vs. implementation, stale ADR, etc.), apply the Section 0 authority order to resolve it. If that's not enough, stop and ask.
- Arch.md:49:**2.6 New dependencies** are an architectural decision, not a convenience. State why the existing toolchain can't do it before adding a library/framework/service. Non-trivial ones need the same stop-and-confirm as any other architecture change.
- Arch.md:59:Found a conflict between the task and an existing decision? State it, explain the impact, propose options, stop if a decision is required.
- Arch.md:95:**7.1 Tests are not yours to weaken.** Don't modify, delete, skip, or loosen an assertion just to make a test pass. If you think the test itself is wrong: say so explicitly, explain why, and stop for confirmation before touching it. A test that passes because it was weakened is not evidence the implementation was fixed.
- Arch.md:121:Any fixture that's local, uncommitted, generated, or diverges from the committed one is a red flag — stop and report it, don't silently pick whichever fixture makes the result pass. Committed fixtures are the default source of truth.
- Arch.md:133:If the plan stops working, scope expands, an abstraction must break, a product decision turns ambiguous, or you find a better approach mid-implementation — **STOP.** State what changed, why the original plan is insufficient, what you propose instead, and what decision is needed. A better idea is not permission to silently reroute.
- CLAUDE.md:39:- `KamomeLog` may name *which* stop failed to geocode; it may not log the
- CLAUDE.md:118:substrate ADR; abstract map rejected); (b) stop photos = **rotating deck at
- CLAUDE.md:142:more photos means more stops, more legs, and more back-to-back timeouts. Not
- CLAUDE.md:225:already geocodes every stop so it has the names in hand.
- CLAUDE.md:364:  `export.target_duration_s`, per-stop holds pinned on-route, smoothstep
- CLAUDE.md:365:  easing, new `export.max_hold_fraction` tunable caps holds on stop-dense
- CLAUDE.md:373:  gates stop cards only — decisions.md 2026-07-18 recap-chrome, **confirmed
- CLAUDE.md:391:  (stop cards, and later route-attached photo fly-bys) are **timeline events**
- CLAUDE.md:397:- Photo fixes landed 2026-07-16: route-attached photos (stop_id NULL) get an
- CLAUDE.md:405:  second stop unrecordable). Fix landed on `phase-3-recap` (decisions.md
- CLAUDE.md:412:  stops (ADR 2026-07-18): DwellDetector is streak-based (age-based span check
- CLAUDE.md:415:  stops at trip end. Trip stop semantics = live ∪ derived; new dwell tunables
- CLAUDE.md:417:- `stop.kind` wired (ADR 2026-07-18 stop-kind): `dwell` | `walk_visit` via
- HANDOFF.md:258:radius (one parameter on the existing survey script). **If it does not, stop and
- HANDOFF.md:292:`.rateLimited` simply stops being reachable (item 2).
- HANDOFF.md:408:red flag to stop and report — the same applies to sources.
- HANDOFF.md:489:*which* stop failed, never its coordinates — and it would put the key in the device
- HANDOFF.md:553:All three MVP films are rendered in **Variant A**, with real stop names:
- HANDOFF.md:559:| presented stops | 10 | 20 | 65 |
- HANDOFF.md:561:| stops with no photo | 0 | 0 | 0 |
- HANDOFF.md:562:| stops unnamed | 0 | 0 | 0 |
- HANDOFF.md:612:- **Variant A** = `KAMOME_RECAP_MODE=full`: every clustered stop presented, no
- HANDOFF.md:613:  duration cap, and `allocation_zero_share` forced to 0 so no stop shows a pin
- HANDOFF.md:660:`.highlight` path would render that same trip at 90 s and 8 stops.
- HANDOFF.md:671:was written from named the stops; per §0 and the same rule that gitignores
- HANDOFF.md:692:ends and after the first stop's card and first photograph (9.33 s, against an
- HANDOFF.md:699:journey *starts at* a photo-bearing stop:
- HANDOFF.md:701:    opening → [first stop's pin/title/photos] → car appears → first leg
- HANDOFF.md:780:| trip | trip stops | target | presented stops | status |
- HANDOFF.md:789:**Iceland's anchor is 21 stops, not the 22 the arithmetic predicts.**
- HANDOFF.md:791:IEEE754. So the film Chiu approved presents 21 stops, and a rule built to produce
- HANDOFF.md:795:duration *from* a stop count has no division to floor, so this entire class of
- HANDOFF.md:800:Every trip presents **exactly 8 stops and exactly 24 photographs**, whether it has
- HANDOFF.md:801:10 stops or 65 — Iceland's shipped edit is 12% of its stops and 24 of the 144
- HANDOFF.md:812:**Invert the model.** Today duration is clamped and the stop count falls out of it;
- HANDOFF.md:813:instead let the trip earn a stop count and let duration fall out of *that*:
- HANDOFF.md:815:    duration = opening + end card + (earned stops × presentation cost) ÷ max_hold_fraction
- HANDOFF.md:818:`max_hold_fraction` stops deciding how many stops the shipped edit presents and
- HANDOFF.md:823:real intuition is about **places, not seconds**: 8 of 10 stops (80%), 15 of 20
- HANDOFF.md:824:(75%), 22 of 65 (34%). Growth must therefore be **sub-linear** — a 65-stop trip
- HANDOFF.md:825:does not earn 6.5× the film of a 10-stop one.
- HANDOFF.md:827:Candidate rule, statable in one sentence: **each doubling of a trip's stop count
- HANDOFF.md:828:earns ~7 more presented stops, floored at 8 and capped at 22.** That reproduces all
- HANDOFF.md:846:fitted to — Finland (3 stops), Margaret River (4), and the committed synthetic
- HANDOFF.md:854:  photographs across 15 stops (2.9 each) and Iceland at 210 s shows 63 across 21
- HANDOFF.md:855:  (3.0 each) — both pinned at `allocation_max_photos` (3). So duration buys stops
- HANDOFF.md:859:- Is **stop count** the right measure of "how long the journey was", or should it
- HANDOFF.md:863:- **Iceland's longer run-in.** At 210 s the first stop arrives at 11.53 s against
- HANDOFF.md:869:  behind the earned-stops rule, or are the stop floor and cap now the only bounds?
- HANDOFF.md:896:photographs hold his attention; **travel between stops does not, once the film is
- HANDOFF.md:902:body as `parked / max_hold_fraction`, so stop dwells take that share and **travel
- HANDOFF.md:1064:Not the enum migration, not the naming commit, not the stop pins. The bisect in
- HANDOFF.md:1082:| iceland (real, 65 stops) | 120 km at a flat 291.5 km span | passed, same defect |
- HANDOFF.md:1109:| New Zealand (20 stops) | **none, in any respect** |
- HANDOFF.md:1110:| Iceland (65 stops) | drops a 2.5 s beat that held span flat at 291.5 km while panning 120 km sideways; everything downstream starts 2.43 s earlier; total length unchanged at 90 s |
- HANDOFF.md:1120:identical across all three runs (opening ends 6.50 s · first stop 6.70 s · first
- HANDOFF.md:1140:  stops locally, 3 on CI. To reproduce CI, move `local/` **outside the repo**
- HANDOFF.md:1188:| how long the film runs / how stops are weighted | **story** | `LinearTimeline.pacing` |
- HANDOFF.md:1240:`smoothstep`, `stopAnchors`, `cappedToRegion`, `bodyFrame`, `confine`) into a new
- HANDOFF.md:1280:  `importedRecap`'s per-stop photo-selection loop became
- HANDOFF.md:1281:  `RecapDemoFilmTests.stopPhotoSelections(detail:full:)` in
- HANDOFF.md:1326:- `ea32ce9` **feat(recap)** — kept-stop count derived from the film's duration.
- HANDOFF.md:1327:- `69b5ad5` **fix(recap)** — stop pins sit on the route (two bugs, one symptom).
- HANDOFF.md:1328:- `2b7b657` **fix(naming)** — landmark → town → address, never "Unnamed stop".
- HANDOFF.md:1332:31250437647). `RecapReviewGeocoder` and the quiet-stop pins referenced by earlier
- HANDOFF.md:1343:## "Unnamed stop" — CLOSED 2026-08-04
- HANDOFF.md:1346:library imported through the actual S1 → S3 flow (18 stops):
- HANDOFF.md:1348:- wait for naming, then export → **18 of 18 stops named**;
- HANDOFF.md:1357:`stop.name ?? "Unnamed stop"`), so no amount of desk rendering could ever have
- HANDOFF.md:1364:- `StopNamer` reports `Progress`; S3 shows "Identifying stops… n of N" and
- HANDOFF.md:1365:  disables the film button until every stop has left the queue.
- HANDOFF.md:1375:**The defect.** Above roughly ten presented stops, every stop showed a single
- HANDOFF.md:1379:**The fix.** How many stops a film may present is now *derived from its duration*
- HANDOFF.md:1381:film keeps 11 stops for a 65-stop trip and a 20-stop trip alike, each showing 3
- HANDOFF.md:1386:| trip | presented stops | film | photos per stop |
- HANDOFF.md:1395:Duration alone never fixed it — above ~20 presented stops no watchable length
- HANDOFF.md:1396:works, so the lever is *how many stops the film presents*.
- HANDOFF.md:1398:**Why CI never caught it.** The committed fixtures are Iceland 16 photos/6 stops
- HANDOFF.md:1401:20-stop trip arithmetically and guards it. It is still wrapped in
- HANDOFF.md:1411:matter — 8 of 65 stops on Iceland — and is not the mechanism anything relies on.
- HANDOFF.md:1419:## `stop_weighting_enabled` — reachable in BOTH modes, containment only empirical
- HANDOFF.md:1429:Tiering keeps the top `keptStopCount` stops by score, and `StopWeighting` demotes
- HANDOFF.md:1430:stops with ≤ `waypoint_max_photos` (2) *and* a short dwell. Those sets are disjoint
- HANDOFF.md:1431:**only while the trip has more stops than the film can keep** — because then only
- HANDOFF.md:1432:heavily-photographed stops survive the cut.
- HANDOFF.md:1434:**When a trip has fewer stops than the budget keeps, every stop survives, including
- HANDOFF.md:1438:| fixture | stops | waypoints under `.highlight` + weighting |
- HANDOFF.md:1453:stop lands in the bottom 40% depends on the distribution of the rest of the trip.
- HANDOFF.md:1454:On a trip where most stops carry two photographs, a two-photograph stop can rank
- HANDOFF.md:1474:1. **Structural eligibility** — does `stop_count <= keptStopCount` reliably predict
- HANDOFF.md:1478:   different? Render both ways and compare the actual output, not the stop table.
- HANDOFF.md:1507:The note worth keeping: the next variant Chiu has in mind — *full stop coverage,
- HANDOFF.md:1512:| which stops survive | `highlight` keeps ~11, `full` keeps all |
- HANDOFF.md:1515:"Full stops, no photos" is the first combination that needs one axis without the
- HANDOFF.md:1589:| fixture       | photos | span    | stops |
- HANDOFF.md:1610:  about the defect depends on *where* the stops are, only how many there are and
- HANDOFF.md:1637:  `kamome-osrm`, `restart: unless-stopped`, healthcheck green), so it comes back
- HANDOFF.md:1690:different in kind, and not only for size. The Geofabrik extract stops at the
- PO.md:107:geocodes every stop. Iceboxed as "Place names as narrative rhythm".
- PO.md:126:- stops
- PO.md:187:2. If it **blocks** the current thread — stop that thread and wait for input.
- Docs/camera-arcs.md:34:to stop the opening translating — *"a zoom, or nothing at all, but never a journey
- Docs/camera-arcs.md:46:than forced — and it is also why the unification stops at the camera (§6).
- Docs/camera-arcs.md:161:**Open: what counts as degenerate.** A stop count, an extent in metres, or "no
- Docs/camera-arcs.md:251:1. **Cost stops depending on the arc's duration** and depends only on its zoom
- Docs/camera-arcs.md:253:2. **`keyframe_interval_frames` stops being a quality knob for arcs.** The
- Docs/camera-arcs.md:391:  whether a crossing is a presented stop, multi-leg journeys, the return leg, and
- Docs/cross-region-journeys.md:101:polish**: it is not a nicer way to draw the dashed line, it is what stops the
- Docs/cross-region-journeys.md:154:| the endpoint's reverse-geocoded name | airport vs port vs neither | `StopNamer` already names every stop |
- Docs/cross-region-journeys.md:163:  work — that ceiling is what stopped 7 of 9 New Zealand legs being typed as walks.
- Docs/cross-region-journeys.md:172:is a fact about the journey, in the same category as `stop.kind` and
- Docs/cross-region-journeys.md:175:discipline `stop.kind` used.
- Docs/cross-region-journeys.md:187:`travelS` is what remains after the earned stop dwells; the camera crosses
- Docs/cross-region-journeys.md:188:`routeDistanceM` within it. A crossing that plays in its **own beat** stops
- Docs/cross-region-journeys.md:236:- **Does a crossing count as a presented stop** for the earned-stop rule, or is it
- Docs/decisions.md:122:existed (`processWhilePaused`), but `LocationService` only ever stopped GPS —
- Docs/decisions.md:134:the trip at the first coffee stop).
- Docs/decisions.md:175:during the trip never appeared: route-attached photo_refs (stop_id NULL) were
- Docs/decisions.md:202:ADR; real top speed from clean fixes was ~61 km/h. (b) The stop was named
- Docs/decisions.md:225:share feature. Three proposals: (1) route-attached photos (stop_id NULL —
- Docs/decisions.md:227:not just stop-pinned highlights; (2) two export outputs — a clean route-only
- Docs/decisions.md:234:  card floats in and out *without pausing* (contrast with the large held stop
- Docs/decisions.md:237:  2: photo/stop-card moments are timeline events computed alongside
- Docs/decisions.md:244:  stops + route photos.
- Docs/decisions.md:285:## 2026-07-18 — Stop detection redesigned around real stops: streaks, walk visits, silence gaps
- Docs/decisions.md:288:visit and an ~8 min 7-11 stop produced **zero** recorded stops. Three causes:
- Docs/decisions.md:293:*walking* stop — the engine correctly made a 21 min walk segment (spread
- Docs/decisions.md:297:cannot see silence. Chiu (product): walking-around stops are stops on a road
- Docs/decisions.md:303:(Core/TripComposer) adds stops at trip end: **silence gaps** (≥
- Docs/decisions.md:309:stops dedupe against live stops by time overlap; trip stop semantics are now
- Docs/decisions.md:320:resume; icebox); HUD stop count shows live stops only until End Trip;
- Docs/decisions.md:323:## 2026-07-18 — Recap chrome: photos toggle gates stop cards only; title/end cards always render
- Docs/decisions.md:330:toggle gates **photo moments** (stop cards, later route-photo fly-bys).
- Docs/decisions.md:345:## 2026-07-18 — stop.kind = what happened, never how it was detected
- Docs/decisions.md:349:`stop.kind` but every save wrote `"auto"`. GPT review (relayed by Chiu)
- Docs/decisions.md:353:only. Silence-gap-derived stops are `dwell` — the phone sat somewhere; GPS
- Docs/decisions.md:358:`stop.kind`; rows from builds before this change carry `"auto"`, and
- Docs/decisions.md:361:is recovered from the walk segment sharing the stop's time span).
- Docs/decisions.md:453:correctly detected at the drive-through (stop 春日路372號, 14:29–14:36,
- Docs/decisions.md:461:second real stop never observable (StopDeriver correctly derives nothing —
- Docs/decisions.md:462:a silence gap spanning kilometers is not a stop), recap shows a straight
- Docs/decisions.md:473:   windows. Stopped at `stopUpdates()`.
- Docs/decisions.md:572:2. **Stop photos = a rotating deck at the stop location.** Not the current
- Docs/decisions.md:573:   single stop-card. Camera eases to the place; a 3-card fan blooms with the
- Docs/decisions.md:574:   hero **cross-fading through all of that stop's 3–8 photos**, progress dots,
- Docs/decisions.md:577:   Owner in `OverlayTimeline` / §4.5 stop-card work; photos from `photo_ref`
- Docs/decisions.md:682:  **no-photo stops/scenes**, and **not-even-photos zero effort**. Recorded as a
- Docs/decisions.md:898:  are accepted; stop iterating the base style. It is **not** a substrate problem.
- Docs/decisions.md:955:## 2026-07-31 — Stop presentation ported from the prototype's CSS, and the stop group flips as one cluster
- Docs/decisions.md:957:**Context:** The stop scene was the last part of the recap still reading as UI
- Docs/decisions.md:964:**Decision — the prototype's CSS is the source of truth for the stop's look.**
- Docs/decisions.md:973:- **No pill behind the stop's name.** The prototype sets it as free type with
- Docs/decisions.md:976:  stop draw the same identity block, so beat 1 → beat 2 still cross-fades in place.
- Docs/decisions.md:978:  km readout; the strap under the name carries day + the stop's secondary detail.
- Docs/decisions.md:980:- **The stop group is one cluster and mirrors as one** (`RecapStopLayout`). It used
- Docs/decisions.md:981:  to flip only the *card* below the pin when a stop sat high in frame, stranding
- Docs/decisions.md:985:  The pin still sits exactly on the stop; only which side the cluster hangs on
- Docs/decisions.md:989:  a stop near the border keeps both peeks instead of losing one off-screen.
- Docs/decisions.md:996:stop it marks — the one thing the 2026-07-26 layout rule exists to prevent.
- Docs/decisions.md:1004:first stop 5.93 s, car 11.37 s, longest still 2.97 s), the camera, the route glow,
- Docs/decisions.md:1007:## 2026-07-31 — Day and distance become persistent HUD, not stop chrome
- Docs/decisions.md:1010:they appeared for a few seconds at each stop and vanished on the road in between.
- Docs/decisions.md:1012:you nothing about where you were in the trip, and a distance rendered *by a stop*
- Docs/decisions.md:1013:reads as a property of that stop rather than of the journey.
- Docs/decisions.md:1018:the left, running total on the right. `RecapPhotoDeck` and `.stopLabel` lost
- Docs/decisions.md:1020:a stop's name is now its `detail` alone, and absent when it has none.
- Docs/decisions.md:1022:- **The day on a leg is the day of the stop just left**, held until the next is
- Docs/decisions.md:1023:  reached. A leg belongs to no stop and must inherit from one; inheriting
- Docs/decisions.md:1047:   double the photographs. Iceland's 65 stops showed **one photograph each at
- Docs/decisions.md:1049:2. *The "10 stops per 30 s" ratio test* (2026-08-05). The proposed ratio was
- Docs/decisions.md:1051:   stop, and above ~20 presented stops no watchable length worked at all.
- Docs/decisions.md:1053:   trip — 0.82 for Iceland's 65 stops, 0.5 for New Zealand's 20 — because a share
- Docs/decisions.md:1056:**Decision.** How many stops a film may present is **derived from its duration**,
- Docs/decisions.md:1065:away from them. At the shipped values a stop costs **5.4 s of dwell**, and a 120 s
- Docs/decisions.md:1066:film keeps **11 stops** — for Iceland (65 stops) and New Zealand (20) alike, with
- Docs/decisions.md:1071:- *A trip's size stops mattering.* A 20-stop and a 65-stop trip both fill a 120 s
- Docs/decisions.md:1076:  the film-seconds figure and returned 6 stops where the measurements said 12.
- Docs/decisions.md:1079:  re-exporting a trip keeps the same stops. A film that reshuffled between renders
- Docs/decisions.md:1083:  photograph per stop. `RecapDeckBudgetTests` exists to make that audible.
- Docs/decisions.md:1085:**Rejected:** a fixed stop count (breaks the moment duration changes); a fixed
- Docs/decisions.md:1087:hand-set `stop_presentation_s` constant (a fourth number to keep in sync with the
- Docs/decisions.md:1182:budget-derived number of stops, bounded length) and `.full` (every stop, no
- Docs/decisions.md:1195:A with every stop showing photographs and every stop named:
- Docs/decisions.md:1199:| presented stops | 10 | 20 | 65 |
- Docs/decisions.md:1223:- **Uncapped rendering leaves the app's critical path.** Whether a 65-stop,
- Docs/decisions.md:1255:the camera and stop presentation, the photo deck. §6 split into §6a (desk, Variant
- Docs/decisions.md:1394:stops, more legs, and more back-to-back timeouts behind a UI with nothing to
- Docs/decisions.md:1572:PD-3 exists to stop exactly this and its threshold sits just above it.
- Docs/decisions.md:1715:- *"We do not **send** it"* — a real change: recorded legs would stop being
- Docs/decisions.md:1738:upgrade the plan or stop. **Concurred, and the reasoning holds for both** — but for
- Docs/decisions.md:1774:| what is sent | the leg's waypoints: stop centroids **plus photo positions**, thinned to ≥ `route_waypoint_min_spacing_m` (250 m), capped at `chunk_size` (100) | **the full recorded trace**, in chunks of up to 100 points |
- Docs/decisions.md:1792:fetch") stops being a cross-region convenience and becomes **the control the privacy
- Docs/demos/phase2/README.md:9:- 4 stop pins; **Busselton Jetty and Margaret River carry photo-count
- Docs/demos/phase2/README.md:10:  badges (2 each)** — seeded `photo_ref` rows assigned to those stops
- Docs/demos/phase2/README.md:11:- stats strip from `trip.stats_json`: 271 km · 4.8 h driving · 4 stops · 96 km/h
- Docs/demos/phase3/README.md:6:1080×1920@30, H.264 @ 5 Mbps. Stills: title card, Mandurah stop card
- Docs/demos/phase3_5/import/README.md:14:| `03-trip-detail-provenance.png` | S3 Trip Detail | An imported trip is **first-class** — same map / stats strip / stop pins / photo badges / timeline / recap film button as a recorded trip — plus the **provenance note**: "This trip was reconstructed from your photos' place and time — not a recorded track." |
- Docs/demos/phase3_5/matching/README.md:8:**after-matched.png** — the same journey (same anchors, stops, schedule)
- Docs/demos/phase3_5/modern-minimal/README.md:27:(`Docs/demos/phase3/still-title-card.png`, `still-stop-card.png`,
- Docs/device-test-P1.md:12:      the two ≥ 5 min stops below are the real test of it.
- Docs/device-test-P1.md:27:- [ ] Make 2 deliberate stops of ≥ 5 min (coffee, viewpoint) — engine should
- Docs/device-test-P1.md:28:      dwell-pause (HUD stop count +1 within ~3 min of stopping).
- Docs/device-test-P1.md:29:- [ ] After each stop, confirm tracking **resumes** on driving off: HUD
- Docs/device-test-P1.md:39:- [ ] Stop count == 2 (±0) and stops are where you actually stopped.
- Docs/device-test-P3.md:1:# Phase 3 device validation — stop semantics + battery (next real drives)
- Docs/device-test-P3.md:4:build ≥ the stop.kind commit; the formal 2 h gate drive checklist stays
- Docs/device-test-P3.md:51:- [ ] Note whether a false stop (short `dwell_pause`/`dwell_resume` pair +
- Docs/device-test-P3.md:52:      spurious stop row) appears, and what the road situation actually was
- Docs/device-test-P3.md:59:- [ ] Note stop-heavy vs highway split; screen use
- Docs/device-test-P3.md:71:24 stops); map snapshots 0.67 s each; full demo render 34.6 s end-to-end
- Docs/device-test-P3.md:82:- [ ] "停留照片卡" toggle ON: exported video shows stop cards with photos
- Docs/device-test-P3.md:84:- [ ] Toggle OFF: no stop cards, but title card AND end card (QR) still
- Docs/device-test-P3.md:96:      picker, a re-exported recap picks them up on stop cards (CLAUDE.md
- Docs/eng-session-P4-visual.md:26:If it still 401s, **stop and say so** — do not work around it with a local Worker
- Docs/eng-session-camera-arc.md:110:and stop. Do not build the real thing to have built something.
- Docs/eng-session-closeout.md:34:If you believe a destructive command is genuinely required, stop and ask.
- Docs/eng-session-closeout.md:63:  documents? If it does not, say what changed and **stop** — that is not an asset
- Docs/eng-session-closeout.md:100:4. **Add the guard that stops this recurring.** Today nothing prevents a key
- Docs/gate-P3.5-checklist.md:20:clustered stop presented, no duration cap, `allocation_zero_share` forced to 0 so
- Docs/gate-P3.5-checklist.md:21:no stop shows a pin without a photograph. Both overrides are harness environment
- Docs/gate-P3.5-checklist.md:76:*stop centroid* — the middle of a photo cluster — so a beach day, a lakeside
- Docs/gate-P3.5-checklist.md:92:stop card silently blank is a direct fail of *"films Chiu wants to keep."*
- Docs/gate-P3.5-checklist.md:97:photos couldn't be loaded, so those stops show blank cards. Open them in Photos
- Docs/gate-P3.5-checklist.md:135:Real trips differ in the ways that matter most: photo counts per stop (which
- Docs/gate-P3.5-checklist.md:183:- [ ] **One stop still** (`RecapStopStillTests`) — is the busiest stop's
- Docs/gate-P3.5-checklist.md:199:If that line ever says `terrain NONE — the map will be flat`, stop and fix it
- Docs/gate-P3.5-checklist.md:221:Without it every card reads "Unnamed stop", which has twice been reported as a
- Docs/gate-P3.5-checklist.md:225:(gitignored, §0), so only the first run per trip pays the ~2 s per stop.
- Docs/gate-P3.5-checklist.md:252:      Iceland came out at **211.5 s · 21 of 65 stops · 6,345 frames · 63
- Docs/gate-P3.5-checklist.md:307:- [ ] **Let the stop names land before exporting.** Import pushes you to trip
- Docs/gate-P3.5-checklist.md:310:      `geocode.min_interval_s` (2 s), so a nine-stop trip needs ~16 s on that
- Docs/gate-P3.5-checklist.md:311:      screen. Tap the film button immediately and the early stops are named and
- Docs/gate-P3.5-checklist.md:312:      the late ones say "Unnamed stop".
- Docs/gate-P3.5-checklist.md:331:| **whether any stop shows 5 photographs** | `tier_top_photos` (5) needs a stop in the top `tier_top_share` **with a favourite**. Fixtures carry no favourites, so this path has **never executed** — the first real library import is its first run |
- Docs/gate-P3.5-checklist.md:332:| **presented stops and film length per trip** | against the references below |
- Docs/gate-P3.5-checklist.md:339:range out of the real library. Different photo sets cluster into different stops,
- Docs/gate-P3.5-checklist.md:340:so stop counts and lengths will differ.
- Docs/gate-P3.5-checklist.md:344:| trip | presented stops | length | rendered? |
- Docs/gate-P3.5-checklist.md:440:- Photos cluster into stops at `import.stop_radius_m` = 4 km, split by gaps over
- Docs/gate-P3.5-checklist.md:441:  3 h. A dense city day may come out as one stop; that is the tuning to report.
- Docs/gate-P3.5-checklist.md:444:follows roads if OSRM answered, and runs in straight lines between stops if it did
- Docs/gate-P3.5-checklist.md:445:not. Wait for the stop names (~2 s each), then film button → S5 → MP4 → share.
- Docs/gate-P3.5-checklist.md:476:| `film: 90.0s · 2700 frames · opening 5.9s · 9 stops · 0/5 legs dashed` | what was actually rendered |
- Docs/gate-P3.5-checklist.md:506:- **"Unnamed stop" in a desk render** — a harness artifact, and a *solved* one
- Docs/gate-P3.5-checklist.md:508:  cannot name a stop, so `RecapReviewGeocoder` runs the shipped `StopNamer` when
- Docs/gate-P3.5-checklist.md:510:  Real device runs name their stops on S3; see the stage-2 note.
- Docs/handoff-P3.5.md:49:the executable spec — it already did EXIF → stops → route → snap → recap on a
- Docs/handoff-P3.5.md:64:   cluster into stops (time-gap + distance heuristics — `import.*` tunables);
- Docs/handoff-P3.5.md:66:   `segment`s (`source='exif'`), `stop`s, `photo_ref`s attached to their stop by
- Docs/handoff-P3.5.md:81:stop count + total distance (CI, deterministic); the imported trip renders in S3
- Docs/handoff-P3.5.md:117:      photo-dense trip whose stops geocode over ~30 s (`geocode.min_interval_s`
- Docs/handoff-P3.5.md:120:      — an imported trip with unnamed stops fills in progressively. No
- Docs/handoff-P3.5.md:204:matched camera positions, **Chiu signs off** — post the comparison and stop; do
- Docs/handoff-P3.5.md:211:("this is not the MapLibre issue") — stop iterating the base style.** The real
- Docs/handoff-P3.5.md:269:  >25 km jump. No follow-cam, no stop dolly. The map is **north-up and never
- Docs/handoff-P3.5.md:275:- The stop plays **two beats**: pin + name floating clear above the vehicle, then
- Docs/handoff-P3.5.md:276:  cross-fading out as the photo card takes over the stop's identity beneath it.
- Docs/handoff-P3.5.md:307:stop the camera eases to the place and a **photo deck** blooms — a 3-card fan
- Docs/handoff-P3.5.md:308:(peek-left / hero / peek-right) with the **hero cross-fading through that stop's
- Docs/handoff-P3.5.md:312:  per stop → `TrackingConfig.json`.
- Docs/handoff-P3.5.md:313:- Photos come from `photo_ref` rows matched to the stop (§4.3); `is_highlight`
- Docs/handoff-P3.5.md:316:  to a clear, prominent size — then zoom back out to the map** once the stop's
- Docs/handoff-P3.5.md:326:  not bake in a long-term assumption that every stop carries equal narrative
- Docs/handoff-P3.5.md:327:  weight — Story Director will vary pacing and select/omit stops (spec §7 P4).
- Docs/handoff-P3.5.md:481:Pacing is a story fact (how many stops, how many photos); which tiles are
- Docs/handoff-P3.5.md:499:stop count and dashed-leg count (`KamomeLog.recap`).
- Docs/handoff-P3.5.md:546:  labels knowing nothing about the photo deck, the stop cluster or the vehicle,
- Docs/handoff-P3.5.md:605:stack**: the stop arrives, the stack fans out, the front card advances roughly
- Docs/handoff-P3.5.md:617:The 2026-07-31 pass ported the stop's *look* from the prototype's actual CSS
- Docs/handoff-P3.5.md:632:- New review harness `KamomeTests/RecapStopStillTests` — renders **one stop** of a
- Docs/handoff-P3.5.md:636:Still open here: the fan/stack carousel above; "Unnamed stop" geocoding in the
- Docs/handoff-P3.5.md:637:demo fixtures; the pin can touch the card's top edge when a stop sits high in
- Docs/handoff-recap-visuals.md:17:riding the vehicle, and a dolly into every stop. **All of that is gone.**
- Docs/handoff-recap-visuals.md:29:- **`deck_span_m` is gone** with the stop dolly. `act_split_km` replaces it.
- Docs/handoff-recap-visuals.md:37:passes the frame straight through; nothing modulates it — not the stop, not the
- Docs/handoff-recap-visuals.md:41:the photo-deck zoom-in reveal, and the two-beat stop label on 2026-07-25. The
- Docs/handoff-recap-visuals.md:142:label cross-fades out as the card takes over the stop's identity, redrawn beneath
- Docs/handoff-recap-visuals.md:176:## 7. Base map, theme atmosphere, and stop layout (`f294883`)
- Docs/handoff-recap-visuals.md:220:While the camera dollied into each stop the vehicle was guaranteed centred, so a
- Docs/handoff-recap-visuals.md:222:vehicle is wherever it really is, and the stop name printed across the car.
- Docs/handoff-render-layers.md:6:hero car, dark souvenir night map, photos at stops — where **the same animation
- Docs/handoff-render-layers.md:33:  `RecapComposer.Content`. Style-independent trip data: route coords, stops
- Docs/handoff-render-layers.md:41:  `OverlayContent` (`routeReveal` / `stopLabel` / `photoDeck` / `titleChrome` /
- Docs/handoff-render-layers.md:52:  by **reusing `CameraPath`'s** speed-warp/hold/easing math. **Two-beat stop
- Docs/handoff-render-layers.md:78:  `OverlayContent`: `routeReveal` (glow trail), the NEW `stopLabel` (pin + name
- Docs/handoff-render-layers.md:82:  (`PhotoRef` → `CGImage`) with a test stub; stop-label tokens on `RecapStyle`.
- Docs/handoff-render-layers.md:86:  snapshots at the timeline's `cameraFrame` — incl. the stop dolly).
- Docs/handoff-render-layers.md:96:  the test resolver. Marker/route/chrome frames stay assertable; the stop frames
- Docs/icebox.md:40:their stop's hold (the clip replaces the photo card; the hold stretches to
- Docs/icebox.md:55:route points / stop members alongside photos (extend `PhotoLibraryImportSource`
- Docs/icebox.md:57:(b) as a short auto-trimmed bead at their stop, "a little moving moment makes
- Docs/icebox.md:125:Brief landmark title cards — "Lake Tekapo" — inserted between travel and stop
- Docs/icebox.md:134:### Drive-by photos for thin stops (2026-08-14, Chiu)
- Docs/icebox.md:136:A stop carrying only one photograph does not make the car park. The journey keeps
- Docs/icebox.md:149:duration scaling). A one-photograph stop currently costs the full presentation
- Docs/icebox.md:153:stops that deserve dwelling, instead of forcing a choice between more places and
- Docs/icebox.md:157:presented stop, which is the input to the duration rule — not the rule's shape, so
- Docs/icebox.md:159:presented stop costs a park.
- Docs/icebox.md:161:### `first_stop_dwell_scale` is scale-dependent in effect (2026-08-14)
- Docs/icebox.md:163:The first stop of a film gets `first_stop_dwell_scale` (0.55) of the dwell a later
- Docs/icebox.md:164:stop earns, because the prologue has just ended and no travel has been shown yet —
- Docs/icebox.md:165:a full-weight first stop makes the film feel stuck right as it starts. That
- Docs/icebox.md:171:started scaling with trip size (2026-08-14): a 4-stop trip earns a 60 s film and
- Docs/icebox.md:172:its decks come out **[2, 6, 6, 6]** — the first stop alone drops below the floor.
- Docs/icebox.md:180:**When it is thawed:** the fix is a floor on the *first stop's* dwell rather than a
- Docs/kamome-poc-spec.md:19:rejected. Routing provider closed as **Geoapify** the same day. — v1.7 (2026-07-20) — **Replay MVP repositioning** (owner decision, `decisions.md` 2026-07-20). The first shipped product is redefined from "passive-capture v1" to the **Replay MVP**: photo-EXIF import → OSRM road reconstruction → souvenir-map recap → MP4 share, validated on **three real past trips**. Consequences: **Phase 3.5 is renamed Replay MVP** and absorbs **photo-EXIF import** (pulled forward from the old Phase 4); its gate becomes a **product release gate** (three shareable films), not a static-visual gate. The tracking/battery device gates (2 h drive, region-resume re-validation, long-duration background, process-death recovery, passive capture, ≥ 3-day battery, the "Arm once, forget it" promise) leave the release path for a new **Capture Beta** (Phase 5, renamed from Passive Capture Tier — the checklists are preserved and moved, never marked passed). **Story Director** (automatic moment-selection, narrative, hero photos, chapters/elision, licensed music + beat-sync) becomes **Phase 4** (renamed from Import & Map Matching — its EXIF half moved into the MVP; the Google Timeline importer is **dropped as redundant** — EXIF import covers past trips, in-app capture covers new ones; owner decision 2026-07-20). Story Director is **deterministic — no AI/LLM tokens** (scoring-and-selection over structured trip data, §7 Phase 4). Plans & Fork (Phase 6) and Backend (Phase 7) are unchanged and further deferred. **MP4 is the launch format; GIF is demoted to non-blocking.** Honest provenance added (§3, §6): `trip.source` distinguishes Kamome-recorded from reconstructed-from-photos, and UI copy never says "Verified Trip". Positioning de-overclaimed (header above). — v1.6 (2026-07-20) — recap visual system validated via a throwaway web prototype on real data (Chiu's 170-photo Iceland ring-road trip); owner sign-off "prototype 蠻成功的，收斂回 app". Findings + the data pipeline + engine source: `Docs/prototype/` (also `decisions.md` 2026-07-20). Locked-in constraints for §4.5/§7: (a) base map = **real geometry + hand-written subtractive style** = "紀念品地圖" (souvenir map), reaffirming the MapLibre substrate ADR; (b) stop photos = a **rotating photo deck at the stop location**, hero cross-fades through 3–8 photos at **0.8 s each** (not the old single card); (c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle is the subject, close heading-up zoom) — the prototype's one unmet requirement; top-down car is the default marker, seagull/scooter/bike swappable. Positioning line restated (above). Forward directions recorded: photo-EXIF import first (the prototype IS that importer, §4.7), video clips as auto-trimmed muted "beads", and royalty-free **beat-synced** music (bundled library + offline beat maps, events quantized to the beat; free=silent export, premium=in-app track). No architecture change — these constrain existing components (`RecapSnapshotProviding`, `CameraPath`, `OverlayTimeline`, `RecapTheme`, `ImportKit`). v1.5 (2026-07-19) — recap visual pivot (owner decision after reviewing the P3 demo artifact): the recap is a stylized, premium animated replay, not Apple-tile output — vision in `Docs/kamome-animation-vision.md`; recap base-map substrate moves MKMapSnapshotter → MapLibre Native + self-hosted vector tiles with Kamome-authored themed styles (ADR in `Docs/decisions.md` 2026-07-19; implementer guide `Docs/vector-tile-pipeline.md`); §0 gains rule 6 (storytelling engine + recognizable identity); §4.5 step 2 rewritten + visual quality bar added; Phase 3 scope frozen as the pipeline milestone; new **Phase 3.5 Recap Visual System** (OSRM §4.4 pulled forward → MapLibre substrate → Modern Minimal theme; no renumbering of P4–P7). v1.4 (2026-07-18) — fork demoted from positioning to mechanism: positioning line rewritten (memory-engine framing), §1.5 fork row relabeled P6 bet, §4.5 end card copy → "Get this route"; all user-facing copy uses Save / Get / Inspired by (S6/S7 screen wording settled at P6 — internal names, table `plan.forked_from`, and `.kamome` schema unchanged). v1.3 (2026-07-15) — battery-moat repositioning: passive capture tier (§1.8, §2.3), map matching promoted to core (§4.4), trip import (§4.7), phases renumbered (fork → Phase 6, backend → Phase 7), transactional monetization note (§1.6). v1.2 (2026-07-11) added Roadtrippers analysis, Taiwan-market adaptations, Kamome branding, handoff checklist & kickoff prompt.
- Docs/kamome-poc-spec.md:44:**Long-term vision (validated later; NOT an MVP claim):** "Arm it once when the trip starts, forget the app for days — get a cinematic map video of your road trip, with battery drain you can't measure." This zero-effort passive-capture promise is the eventual differentiator #1 (§1.8), but it is proven in **Capture Beta** (§7), not at MVP launch. When capture does ship, its rule holds: Kamome's capture must never depend on the user remembering anything mid-trip (Relive makes you start/stop every activity — forget once and that leg is gone forever).
- Docs/kamome-poc-spec.md:48:- **P2 The Trip Planner:** hasn't gone yet; browses real driven routes, forks one, edits stops, uses it as the plan.
- Docs/kamome-poc-spec.md:55:3. **Capture loop (Capture Beta, §7):** Arm once at trip start → auto-track segments (drive/walk/transit) across days with zero mid-trip interaction → auto-detect stops → attach photos → End at trip end. Feeds the *same* recap pipeline as import; not in the MVP.
- Docs/kamome-poc-spec.md:73:| Zero mid-trip interaction, multi-day battery story (§1.8) | ❌ (gaps are its top complaint) | ❌ (manual start/stop per activity) | n/a | ✅ (but private, no output) | ✅ **eventual differentiator #1 — Capture Beta, not an MVP claim** |
- Docs/kamome-poc-spec.md:82:2. **Do NOT build a POI database.** That's their capital-intensive moat and an unwinnable game solo. In the fork model, *the community's real stops are the POI database* — every published trip seeds verified, actually-visited places with photos. Cold-start content = Chiu's own trips.
- Docs/kamome-poc-spec.md:89:- **Scooter as a first-class mode.** 機車環島 is a rite of passage. CMMotionActivity classifies scooters as `automotive`; disambiguation is unreliable, so: per-trip vehicle selector (car 🚗 / scooter 🛵 / bicycle 🚲 / mixed) at Start, which tunes the sampling table (scooter = lower speeds, more stops) and sets the recap icon. `segment.mode` enum gains `scooter`.
- Docs/kamome-poc-spec.md:100:Relive-class trackers need high-frequency GPS because trails are not on any road network — the raw points *are* the route. A road trip is the opposite: ~99% of it happens on a known network, so sparse, nearly-free signals (iOS significant-location-change, ~500 m / minutes granularity, plus `CLVisit` for stops) can be **snapped back onto the road network with map matching (§4.4)** and look as good as continuous tracking — a car can only be where roads are. Relive cannot copy this: their core scenario has no network to snap to. This, not "they do outdoors, we do driving," is why the markets don't overlap.
- Docs/kamome-poc-spec.md:104:- **Passive tier (Capture Beta, Phase 5):** arm the trip once, forget the app for days, battery impact indistinguishable from zero. Sparse fixes + CLVisit stops + map matching + daily CMMotionActivity backfill. This kills the "forgot to press start" failure mode entirely — but the claim is only usable once Capture Beta's ≥ 3-day battery + integrity gate passes on real hardware.
- Docs/kamome-poc-spec.md:123:│  │ CMMotion       │ stop detect,  │ + AVAsset    │             │
- Docs/kamome-poc-spec.md:130:│  │  trips / segments / trackpoints / stops /    │              │
- Docs/kamome-poc-spec.md:131:│  │  photo_refs / plans / plan_stops             │              │
- Docs/kamome-poc-spec.md:157:- `CLVisit` monitoring — arrival/departure events become `stop` candidates (replaces §4.2's sliding-window dwell, which needs dense points).
- Docs/kamome-poc-spec.md:170:| Stationary ≥ 3 min (dwell) | pause GPS, start `CLMonitor` region (150 m) | — | ~0 drain at stops |
- Docs/kamome-poc-spec.md:208:CREATE TABLE stop (
- Docs/kamome-poc-spec.md:221:  stop_id TEXT REFERENCES stop(id),   -- null = attached to route point
- Docs/kamome-poc-spec.md:236:CREATE TABLE plan_stop (
- Docs/kamome-poc-spec.md:264:    { "idx": 1, "stops": [
- Docs/kamome-poc-spec.md:282:Sliding window over trackpoints: if all points in the last `dwell_window_s` (default 180 s) fit within a circle of radius `dwell_radius_m` (default 80 m) → close segment, create `stop`, enter low-power region-monitoring state. On region exit → reopen segment. Reverse-geocode stop name via `CLGeocoder` (throttled, cached).
- Docs/kamome-poc-spec.md:285:On trip completion (and on-demand): `PHAsset.fetchAssets` with predicate `creationDate BETWEEN trip.start AND trip.end`. For each asset: if it has GPS → attach to nearest stop within 300 m, else attach by timestamp to the stop whose `[arrived, departed]` interval contains it; else leave as route-attached. User can re-assign by drag in UI. Photos with `is_highlight = 1` get large treatment in the video.
- Docs/kamome-poc-spec.md:328:1. Compute camera path: interpolate along full-trip polyline; speed-warp so total video = `target_duration_s` (default 30 s) regardless of trip length; ease-in/out at stops.
- Docs/kamome-poc-spec.md:330:3. At each stop: 1.5 s hold, photo card animates in (highlight photo), stop name label, day badge.
- Docs/kamome-poc-spec.md:340:Given `trip.origin_plan_id`: match plan_stops to actual stops by name-similarity + distance < 1 km. Output: visited / skipped / unplanned-extra + dwell delta per stop + total distance delta. Rendered as a "trip report card." (Unique feature — no incumbent has it.)
- Docs/kamome-poc-spec.md:343:Nobody should wait for their next vacation to see Kamome's value. **One importer** (`Core/ImportKit/`, the **photo-EXIF importer**), feeding the normal pipeline (map matching §4.4 → stops → photo matching §4.3 → recap §4.5):
- Docs/kamome-poc-spec.md:344:- **Photo EXIF (Replay MVP — the MVP's core):** user picks a date range or album; geotagged photos cluster into `stop` rows + photo groups + a coarse route (time-gap + distance heuristics, tunables in config), which OSRM (§4.4) snaps to real roads. Photos are attached to their stops by construction — zero matching ambiguity. Imported trips write `trip.source = 'imported_photos'`, `segment.source = 'exif'` (§3), and must be honestly labeled as reconstructed-from-photos (§6), never as recorded. The prototype (`Docs/prototype/`) already proved this end-to-end on a real 13-day, 170-photo trip — that pipeline *is* this importer.
- Docs/kamome-poc-spec.md:358:| S3 | Trip Detail | Full map with matched route colored by mode (drive = solid, walk = dotted), **inferred/low-confidence legs shown honestly** (dashed), stop pins with photo thumbnails, day filter chips, stats strip (distance, drive time, stops, top speed), **provenance note** for imported trips ("reconstructed from photos", never "verified"). Timeline list below map. |
- Docs/kamome-poc-spec.md:359:| S4 | Stop Editor | Rename, note, reorder photos, mark highlight, delete false-positive stop, merge stops. |
- Docs/kamome-poc-spec.md:361:| S6 | Plan Editor | Day-grouped reorderable stop list + map. Search-to-add stop (MKLocalSearch). Per-day drive-time estimate (MKDirections, cached). Import `.kamome` = pre-filled editor with "Forked from …" banner. |
- Docs/kamome-poc-spec.md:362:| S7 | Convert / Fork | From S3: `Publish as Plan` → generates plan from stops → S6. From received file: `Fork` → S6. |
- Docs/kamome-poc-spec.md:372:- `UIBackgroundModes = [location]`; expect App Review to ask for justification — include a review note + demo video showing tracking stops when the user ends a trip. Never track outside an active trip. This is both an ethics line and the reason review will pass.
- Docs/kamome-poc-spec.md:373:- Passive tier (Capture Beta, Phase 5): requires **Always** at arming (significant-change and CLVisit deliver while the app is dead). The priming copy must say a multi-day trip keeps a low-power recorder alive until you End Trip. The review posture is unchanged — capture runs only between an explicit Start and End, and End Trip verifiably stops all monitoring. (Not in the Replay MVP: the MVP requests only Photos, no background location.)
- Docs/kamome-poc-spec.md:383:> Each phase = one milestone PR. Verification commands run from repo root. GPX fixtures live in `Tests/Fixtures/` and include `perth_margaret_river_day1.gpx` (synthetic 280 km drive with 4 stops + 2 walk loops), `taiwan_huandao_9days.gpx` (synthetic round-island loop, mixed car + scooter + one TRA rail leg — exercises transit heuristic and 環島 loop detection), and `city_walk_flapping.gpx` (mode-flapping torture test).
- Docs/kamome-poc-spec.md:406:- Replaying `perth_margaret_river_day1.gpx` yields exactly 4 stops (±0), ≥ 2 drive segments, ≥ 2 walk segments; assert in unit test.
- Docs/kamome-poc-spec.md:412:**Gate:** unit tests for photo→stop assignment (timestamp-only, GPS, conflict cases); a seeded demo trip renders S3 with photos on correct pins (screenshot in demo folder); limited-photo-access path manually verified.
- Docs/kamome-poc-spec.md:424:1. **Photo EXIF import (§4.7)** — `Core/ImportKit/` + schema v2 (`trip.source` / `segment.source`, honest provenance §3). Pick an album / date range → cluster geotagged photos into stops + photo groups + a coarse route → OSRM snap (§4.4). Imported trips flow through the existing Trip Detail (S3), RecapComposer, and ExportEngine **unchanged**. The prototype (`Docs/prototype/`) is this importer, proven on a real 13-day trip.
- Docs/kamome-poc-spec.md:428:5. **Basic photo deck** — deterministic 3–8 photos @ ~0.8 s at the real location (OverlayTimeline). Labeled explicitly as the MVP's **basic** photo presentation, not final Story Director; no long-term assumption that every stop has equal narrative weight.
- Docs/kamome-poc-spec.md:448:**Feasibility — deterministic, no AI/LLM tokens (owner constraint 2026-07-20).** Story Director is a **scoring-and-selection engine over structured trip data** (stops, segments, photos, timestamps, geography) — pure algorithm, no LLM, no network, no per-call cost, and deterministic (which *keeps* golden-frame CI stable rather than breaking it). Moment salience = a weighted sum of photo count, `is_highlight`, dwell duration, geographic novelty (distance from the last kept moment), and day-boundary signals — weights are `TrackingConfig.json` tunables; select top-N with non-maximum suppression for spacing; omit the rest and speed-warp the gaps; scale per-photo hold by salience. Hero-photo pick uses **on-device Vision** (saliency / face detection — free, local, no tokens, no network, not an LLM; owner-confirmed 2026-07-20) to rank a stop's photos, falling back to `is_highlight` → nearest-the-dwell-midpoint → chronological when Vision yields no signal. Vision confined to its own boundary file (SDK-confinement rule); its scores are cached so re-exports stay deterministic. The manual "replace / remove" controls are the taste escape hatch. Scope:
- Docs/kamome-poc-spec.md:451:- A few light **"replace this scene / remove this stop"** controls — director's touch-ups, not a full editor.
- Docs/kamome-poc-spec.md:460:**Open question — what does capture add over photo reconstruction? (owner-raised 2026-07-20, decide from MVP feedback, do not assume).** Since photo-EXIF import already reconstructs most photo-rich trips, Capture Beta must earn its background/battery engineering by selling the **three things photos structurally cannot**: (1) a **truth-path** — the actual road every turn, not an OSRM guess between sparse photos that can pick the wrong parallel road or miss an unphotographed detour (this *is* the `recorded` vs `reconstructed-from-photos` line, §3); (2) **stops/scenes with no photo** (a meal, gas, a viewpoint you didn't shoot) — invisible to EXIF; (3) **true zero-effort** — you didn't even have to take photos (scooter 環島, night, rain, driving-focused trips), the purest form of the founding motivation. Whether these justify the build is validated after the MVP, not presumed here.
- Docs/kamome-poc-spec.md:465:- **Physical device: ≥ 3-day armed period, drain attributable to Kamome < 1%/day, route + stops correct — Chiu signs off** (`Docs/device-test-P5.md`).
- Docs/kamome-poc-spec.md:472:**Gate:** round-trip property test (trip → plan → file → import → identical plan); fork lineage preserved; diff report correct on fixture (planned 6 stops, drove 5 + 1 extra → report says exactly that). **This gate = POC complete.**
- Docs/osrm-setup.md:60:    restart: unless-stopped
- Docs/osrm-setup.md:67:    restart: unless-stopped
- Docs/osrm-setup.md:78:`restart: unless-stopped` brings the servers back after a Docker or machine
- Docs/pre-launch.md:190:plan or stop. Kept on this page as *known accepted risk*, not as a blocker.
- Docs/pre-launch.md:224:| what is sent | the leg's waypoints — stop centroids **plus photo positions**, thinned to ≥250 m, ≤100 per leg | **the full recorded trace**, in chunks of ≤100 points |
- Docs/prototype/README.md:44:| v2  | **Real photos** woven in as "beads on a thread"; side-view car marker; camera zooms to each stop | ✅ Photo-as-bead confirmed. ❌ Side-view car + still-generic map. |
- Docs/prototype/README.md:84:### 2.2 Photos = fan + rotating deck at the stop location ✅ (timing revised)
- Docs/prototype/README.md:87:When the vehicle reaches a stop, the camera eases in and that stop's photos
- Docs/prototype/README.md:89:**hero cross-fading through ALL of the stop's photos** — 3 to 8 of them
- Docs/prototype/README.md:97:- **App:** this is the **OverlayTimeline / stop-card** work in §4.5 — but richer
- Docs/prototype/README.md:98:  than "one photo card per stop." Each stop becomes a **timed photo deck** event
- Docs/prototype/README.md:100:  `photo_ref` rows already matched to the stop (§4.3). `is_highlight` photos lead
- Docs/prototype/README.md:143:into stops → time-ordered route → name → road-snap → recap) is **exactly the
- Docs/prototype/README.md:178:   snap stop arrivals, photo reveals, and transitions to the nearest beat. That
- Docs/prototype/README.md:206:- `recap_data_pipeline.py` — EXIF → stops → route → base geometry → recap data.
- Docs/prototype/README.md:207:  The executable spec of §4.7 import + §4.2 stops + §4.4 route + §7 base map.
- Docs/vector-tile-pipeline.md:36:P3 reference stills (`Docs/demos/phase3/still-*.png` — title card, stop
- Docs/vector-tile-pipeline.md:167:**Boundary reminder:** route line, seagull/vehicle marker, stop cards,

### sprite
- CLAUDE.md:175:1. **Vehicle sprites** — the top community request, and the prerequisite for the
- HANDOFF.md:187:crossing arc.** The film opens at the apex, the sprite crosses, the camera closes
- HANDOFF.md:336:known endpoints, unknown path, its own sprite and its own beat
- HANDOFF.md:382:**What happened.** The sprite/key session reported `KamomeCoreTests 222 → 229 (+7)`
- HANDOFF.md:394:working tree and growing while the sprite session measured. `Tests/CoreTests/` is a
- HANDOFF.md:399:**Why this matters more than the number.** The sprite session's Level 1 evidence —
- HANDOFF.md:499:### 7. ⚠️ CORRECTED 2026-08-20 — the sprite tree holds three different things, not one
- HANDOFF.md:510:So: **not committable as one change.** `./Tools/center-sprites.py --check` first.
- HANDOFF.md:973:`Core/ExportEngine/RecapCarSprite.swift:75` to load the vehicle sprite, and
- HANDOFF.md:974:`RecapSubjectRenderer.swift:39` draws that sprite **on the shipped export path**.
- Docs/camera-arcs.md:22:sprite sessions at the time of writing.
- Docs/camera-arcs.md:153:line between them — the sprite crosses, and the camera closes into the
- Docs/camera-arcs.md:205:| subject on screen | no — parked at the route's start and deliberately undrawn | yes — the classified sprite is the point |
- Docs/camera-arcs.md:257:3. **The map softens; the film's own graphics do not.** Trail, sprite, labels and
- Docs/camera-arcs.md:305:> **The seagull — the honest sprite for an unmodelled crossing — is what makes
- Docs/cross-region-journeys.md:73:   Kamome's own logo, drawn as its own sprite.
- Docs/cross-region-journeys.md:130:| the cut is invisible to the viewer and reads as a camera fault | the cut is narrated, with a sprite crossing it |
- Docs/cross-region-journeys.md:249:  sprite is a brand decision as much as a UI one.
- Docs/cross-region-journeys.md:258:  a confident wrong sprite is worse than an honest unknown one.
- Docs/decisions.md:942:**Not in this decision (next):** the vehicle marker sprite and the photo deck (with
- Docs/decisions.md:1005:the 380 px car sprite and the modern-minimal map style.
- Docs/decisions.md:1280:   Measurement and export survivability, vehicle sprites, map labels (still
- Docs/decisions.md:1356:4. **Phase 4 reorders around what people asked for:** vehicle sprites →
- Docs/eng-session-P4-visual.md:73:film sprite is `seagull/omni.png`; `logo.png` in the same folder is only the S3
- Docs/eng-session-P4.md:114:One more thing worth knowing: 45 shipped vehicle sprite PNGs are modified but
- Docs/eng-session-P4.md:116:consistent with an uncommitted `Tools/center-sprites.py` run. Not your task; do not
- Docs/eng-session-camera-arc.md:34:⚠️ Other sessions are working in this tree (routing → Geoapify; the sprite
- Docs/eng-session-closeout.md:1:# Engineering session — close out sprites and the API key
- Docs/eng-session-closeout.md:19:  it was corrected today and describes the sprite tree accurately.
- Docs/eng-session-closeout.md:25:else** — two complete sprite sets — and **46 modified PNGs** whose committed
- Docs/eng-session-closeout.md:36:## Task 1 — the sprite tree: work out what it is, then commit it correctly
- Docs/eng-session-closeout.md:43:   consistent with a re-run of `Tools/center-sprites.py`, which writes in place.
- Docs/eng-session-closeout.md:54:`./Tools/center-sprites.py --check` over the committed art and over the working
- Docs/handoff-P3.5.md:271:  the vehicle carries the heading as an **8-direction sprite set**, nearest-bucket
- Docs/handoff-P3.5.md:630:- Pacing unchanged (iceland report identical); camera, route glow, sprite scale and
- Docs/handoff-recap-visuals.md:40:**Layer 3 is fully landed, visuals included** — Chiu signed off the car sprites,
- Docs/handoff-recap-visuals.md:91:## 3. Car = 8-direction sprite set, not one rotatable image
- Docs/handoff-recap-visuals.md:99:2. **Single rotatable raster sprite** with a fixed art-angle correction.
- Docs/handoff-recap-visuals.md:149:  compass wrap (−45°, 405°, 720°), all eight sprites sharing one canvas size (so
- Docs/handoff-recap-visuals.md:154:  exact tone — the sprite's centre is windshield glass, and exact-pixel probes
- Docs/handoff-recap-visuals.md:167:  single-sprite era died with it; the new drawings have clean transparent edges
- Docs/handoff-recap-visuals.md:173:  video**, via per-sprite content-centre correction at load — the canvas scaling
- Docs/handoff-render-layers.md:48:  `.topDownRotating`; `SubjectVisual` = `.sprite` / `.marker`.
- Docs/handoff-render-layers.md:60:  marker (rotates to heading, swappable), anime raster car sprite via a
- Docs/kamome-poc-spec.md:319:crossing beat and its own sprite (`Docs/cross-region-journeys.md`).
- Docs/pre-launch.md:28:**Also unresolved:** the sprite working tree holds **46 modified files, one of them
- Docs/vector-tile-pipeline.md:55:                                          + sprites / glyph strategy
- Docs/vector-tile-pipeline.md:164:  design). If any are added, the sprite sheet is part of the theme

### export
- CLAUDE.md:63:  device; stable MP4 export; per-trip time *product-acceptable*, the single
- CLAUDE.md:67:- **P3 device items redistributed (none faked passed):** export/S5-UX/
- CLAUDE.md:170:come first and export convenience is discussed after.
- CLAUDE.md:182:3. **Export that survives** — import and export must be **interruptible,
- CLAUDE.md:187:   30 halves every export, and costs a 1 s cross-fade instead of 0.5 s.
- CLAUDE.md:256:### What the export numbers actually said (2026-08-15, device)
- CLAUDE.md:258:| trip | frames | snapshots | export | per snapshot |
- CLAUDE.md:265:and do not quote these. Only `frames` and `export` are real.
- CLAUDE.md:282:every export**, not download versus none. A user who makes one film may be better
- CLAUDE.md:285:**The export also fails if the app is backgrounded or the screen sleeps.**
- CLAUDE.md:288:frame boundary if iOS reclaims the assertion. This is not resumable export —
- CLAUDE.md:364:  `export.target_duration_s`, per-stop holds pinned on-route, smoothstep
- CLAUDE.md:365:  easing, new `export.max_hold_fraction` tunable caps holds on stop-dense
- CLAUDE.md:369:  snapshots cross-faded per `export.keyframe_interval_frames`, projection
- CLAUDE.md:374:  by Chiu**; chrome-free export = separate future option, never this
- CLAUDE.md:376:  decimated GIF with progress/cancel. New export tunables: frame size,
- HANDOFF.md:33:**Decision.** Cost the export as **the number of distinct pictures the camera
- HANDOFF.md:51:**Next.** `Docs/pre-launch.md` **item 5** (export-time estimate) must count
- HANDOFF.md:280:> The trip ran past our time limit. What's already matched is saved — export again
- HANDOFF.md:622:  the rest were stripped at export. Chiu is checking the export source himself.
- HANDOFF.md:665:export time and memory are frame-count-bound, and 90 s → 210 s is 2,700 → 6,300
- HANDOFF.md:974:`RecapSubjectRenderer.swift:39` draws that sprite **on the shipped export path**.
- HANDOFF.md:1270:  `exportConfig`) went `private` → internal (no `private` keyword) since
- HANDOFF.md:1348:- wait for naming, then export → **18 of 18 stops named**;
- HANDOFF.md:1349:- with the gate temporarily removed → the export screen opens with **6 of 18
- HANDOFF.md:1547:- **Device-representative run.** No import→Trip Detail→export run has ever been
- HANDOFF.md:1614:limited-photo re-check on device, stable MP4 export. Two real trips exist as
- HANDOFF.md:1709:`export.opening_collapse_drift_fraction` (15%) of the frame. That is not a chosen
- PO.md:63:substrate ADR. Chiu reopened and closed it himself in a day, on four device export
- Docs/camera-arcs.md:344:product-level change to export duration, and the export-time estimate in item 5
- Docs/camera-arcs.md:365:270 frames, not a full export. The cheapest possible version of (3) needs no
- Docs/decisions.md:160:transactional (per-trip export), not subscription. `Docs/icebox.md` created.
- Docs/decisions.md:182:is fixture-driven and device-independent until the final on-device export
- Docs/decisions.md:222:## 2026-07-17 — Recap video: route photos in, export gets a photos toggle, video clips parked
- Docs/decisions.md:227:not just stop-pinned highlights; (2) two export outputs — a clean route-only
- Docs/decisions.md:241:- **Photos toggle on export** — accepted, **P3 scope**. One pipeline, one S5
- Docs/decisions.md:248:  deterministic frame pipeline with golden-frame tests, and re-exports must
- Docs/decisions.md:287:**Context:** Second real drive (17:04 export, `Docs/tests/`): a ~20 min temple
- Docs/decisions.md:333:exactly the exports users make when they want a clean route video. Toggle
- Docs/decisions.md:340:clean export with no trip chrome, if ever wanted, must be a **separate
- Docs/decisions.md:443:share-worthy export; revisit when Style 1 is scheduled); restyling
- Docs/decisions.md:515:bounded: the 2026-07-19 smoke drive already exercised the export end-to-end
- Docs/decisions.md:532:export) — walks stay raw on purpose, feet ignore the drivable network.
- Docs/decisions.md:548:column (`matched_polyline IS NULL` already says it); blocking recap export
- Docs/decisions.md:595:export (user adds platform music), premium = in-app track (§1.6 transactional).
- Docs/decisions.md:606:bundled copyrighted music (royalty-free + optional silent export only).
- Docs/decisions.md:646:  device; stable on-device export (no crash / acceptable memory); per-trip export
- Docs/decisions.md:650:- **Phase 3's device items are redistributed (nothing faked passed):** export /
- Docs/decisions.md:854:export and the on-device render/budget are the §6 gate.
- Docs/decisions.md:1079:  re-exporting a trip keeps the same stops. A film that reshuffled between renders
- Docs/decisions.md:1224:  18,000-frame film can be exported on a phone is no longer an MVP question. It
- Docs/decisions.md:1229:  library, S5 UX, export stability and memory, per-trip export time. It also
- Docs/decisions.md:1232:  through `Bundle.module` in `RecapCarSprite.swift` on the shipped export path and
- Docs/decisions.md:1269:   UX pass, per-trip export time, memory behaviour and crash-free export across
- Docs/decisions.md:1280:   Measurement and export survivability, vehicle sprites, map labels (still
- Docs/decisions.md:1291:  export dies if the app is backgrounded. The duration rule of 2026-08-13 made
- Docs/decisions.md:1335:**Neither substrate solves the export problem**, which is the finding that
- Docs/decisions.md:1357:   cross-region flight display → export reliability. Map work is not in it.
- Docs/decisions.md:1400:   a separate lifetime — the trip is complete, viewable and exportable without
- Docs/decisions.md:1404:   + progress pair, which already solved this exact problem for export.
- Docs/decisions.md:1441:**Written before the feature, deliberately.** "Different photos each export" is
- Docs/decisions.md:1450:- **Persisted with the export.** A seed that is not stored is not a seed, it is
- Docs/decisions.md:1452:- **Re-rendering an export reproduces it**, byte for byte. "Shuffle" is the
- Docs/decisions.md:1453:  gesture that mints a *new* seed; export alone never does.
- Docs/decisions.md:1463:get back. If re-exporting silently produced a different edit, the good version
- Docs/decisions.md:1468:"shuffle" has nothing to change); a seed derived from the clock at export time
- Docs/decisions.md:1665:   advantage over Google — but `matched_polyline` is kept forever and re-exported
- Docs/decisions.md:1749:built** — route at export time instead of reading `matched_polyline`, using the
- Docs/decisions.md:1750:coordinator and budget that already exist. Offline re-export degrades; nothing
- Docs/demos/phase3_5/matching/README.md:9:exported through the real app pipeline with §4.4 matching active against
- Docs/demos/phase3_5/matching/README.md:28:How the "after" was produced (matching disabled exports the raw-geometry
- Docs/device-test-P1.md:41:      verify via DB export or debugger if needed).
- Docs/device-test-P3.md:16:- **→ Replay MVP gate (Phase 3.5)** — export / photo, still blocking release:
- Docs/device-test-P3.md:17:  **F** (reframed — no longer a single < 90 s pass/fail; now *per-trip export
- Docs/device-test-P3.md:65:**Reframed:** no longer a single "< 90 s" pass/fail. Now *per-trip export time
- Docs/device-test-P3.md:73:after every export — no instruments needed.
- Docs/device-test-P3.md:82:- [ ] "停留照片卡" toggle ON: exported video shows stop cards with photos
- Docs/device-test-P3.md:86:- [ ] MP4 export → share sheet → file plays in Photos/Messages
- Docs/device-test-P3.md:87:- [ ] GIF export → share sheet → animates in Messages
- Docs/device-test-P3.md:88:- [ ] Cancel mid-render returns to idle, no stray files, re-export works
- Docs/device-test-P3.md:96:      picker, a re-exported recap picks them up on stop cards (CLAUDE.md
- Docs/dogfood-infrastructure.md:148:No rebuild is needed — drop a region in and export again.
- Docs/eng-session-P4-visual.md:81:  it is parked with export performance, deliberately.
- Docs/eng-session-P4-visual.md:82:- **`export.keyframe_interval_frames` and the opening's per-frame snapshotting.**
- Docs/eng-session-P4.md:7:Scope is **one task**. Do not hand this session cross-region or export work — those
- Docs/eng-session-P4.md:77:- **Frozen, and not oversights:** `export.keyframe_interval_frames` and the
- Docs/eng-session-camera-arc.md:10:it moves items **3** and **5** (export survives / export-time estimate) because it
- Docs/gate-P3.5-checklist.md:39:export per attempt. Stages 0 and 1 are cheap and repeatable; stage 2 is not.
- Docs/gate-P3.5-checklist.md:243:error** (`Bundle.module`, on the export path, traps rather than degrading). It hit
- Docs/gate-P3.5-checklist.md:307:- [ ] **Let the stop names land before exporting.** Import pushes you to trip
- Docs/gate-P3.5-checklist.md:323:- [ ] Memory pressure / no crash across all three exports.
- Docs/gate-P3.5-checklist.md:329:| **export time per trip** (S5 readout) | a gate item, and the only viability risk never measured. Iceland is **6,345 frames — 2.35× the 90 s cut** — so this is the figure to judge against |
- Docs/handoff-P3.5.md:22:recap → export MP4 → share.** It ships nothing about passive/background capture
- Docs/handoff-P3.5.md:34:  export/photo items fold into the Replay MVP gate below; the 2 h drive +
- Docs/handoff-P3.5.md:82:and exports a recap in the simulator; provenance is visible; no DB hand-editing
- Docs/handoff-P3.5.md:191:      under the *full* export render loop, and the on-device render/budget. Metal
- Docs/handoff-P3.5.md:384:- [ ] All three export **stably on a real iPhone** — no crash, no unacceptable
- Docs/handoff-P3.5.md:389:- [ ] **Per-trip export time recorded** (S5 readout) and judged *product-acceptable*
- Docs/handoff-P3.5.md:478:   `export.target_duration_s`. A six-day trip came out at 30 seconds.
- Docs/handoff-recap-visuals.md:26:  than `export.act_split_km` (25 km) apart, which is what a flight, a ferry, or a
- Docs/handoff-recap-visuals.md:79:- `export.follow_heading_up` stays `false`. `CameraPath` still supports it, but
- Docs/handoff-recap-visuals.md:264:- **F — render budget:** export the longest real trip on device, record the S5
- Docs/handoff-recap-visuals.md:278:worth keeping, **≥ 1 published publicly**, stable export on device. Three trips
- Docs/icebox.md:5:## Creator b-roll export (post-v1 wedge candidate)
- Docs/icebox.md:9:price point than consumer per-trip export (§1.6). Do not build a template
- Docs/icebox.md:26:Google-export format-drift maintenance for little unique value. The
- Docs/icebox.md:33:per-trip export + yearly unlock-all + creator tier is the model (§1.6).
- Docs/icebox.md:41:clip length, still counted inside `export.max_hold_fraction`). Fits the
- Docs/icebox.md:44:deterministic frame pipeline with golden-frame tests, and re-exporting must
- Docs/kamome-animation-vision.md:34:Every exported replay should feel beautiful enough that users want to share
- Docs/kamome-animation-vision.md:60:- exportable video
- Docs/kamome-poc-spec.md:19:rejected. Routing provider closed as **Geoapify** the same day. — v1.7 (2026-07-20) — **Replay MVP repositioning** (owner decision, `decisions.md` 2026-07-20). The first shipped product is redefined from "passive-capture v1" to the **Replay MVP**: photo-EXIF import → OSRM road reconstruction → souvenir-map recap → MP4 share, validated on **three real past trips**. Consequences: **Phase 3.5 is renamed Replay MVP** and absorbs **photo-EXIF import** (pulled forward from the old Phase 4); its gate becomes a **product release gate** (three shareable films), not a static-visual gate. The tracking/battery device gates (2 h drive, region-resume re-validation, long-duration background, process-death recovery, passive capture, ≥ 3-day battery, the "Arm once, forget it" promise) leave the release path for a new **Capture Beta** (Phase 5, renamed from Passive Capture Tier — the checklists are preserved and moved, never marked passed). **Story Director** (automatic moment-selection, narrative, hero photos, chapters/elision, licensed music + beat-sync) becomes **Phase 4** (renamed from Import & Map Matching — its EXIF half moved into the MVP; the Google Timeline importer is **dropped as redundant** — EXIF import covers past trips, in-app capture covers new ones; owner decision 2026-07-20). Story Director is **deterministic — no AI/LLM tokens** (scoring-and-selection over structured trip data, §7 Phase 4). Plans & Fork (Phase 6) and Backend (Phase 7) are unchanged and further deferred. **MP4 is the launch format; GIF is demoted to non-blocking.** Honest provenance added (§3, §6): `trip.source` distinguishes Kamome-recorded from reconstructed-from-photos, and UI copy never says "Verified Trip". Positioning de-overclaimed (header above). — v1.6 (2026-07-20) — recap visual system validated via a throwaway web prototype on real data (Chiu's 170-photo Iceland ring-road trip); owner sign-off "prototype 蠻成功的，收斂回 app". Findings + the data pipeline + engine source: `Docs/prototype/` (also `decisions.md` 2026-07-20). Locked-in constraints for §4.5/§7: (a) base map = **real geometry + hand-written subtractive style** = "紀念品地圖" (souvenir map), reaffirming the MapLibre substrate ADR; (b) stop photos = a **rotating photo deck at the stop location**, hero cross-fades through 3–8 photos at **0.8 s each** (not the old single card); (c) `CameraPath` must be a **vehicle-locked TravelBoast follow-cam** (vehicle is the subject, close heading-up zoom) — the prototype's one unmet requirement; top-down car is the default marker, seagull/scooter/bike swappable. Positioning line restated (above). Forward directions recorded: photo-EXIF import first (the prototype IS that importer, §4.7), video clips as auto-trimmed muted "beads", and royalty-free **beat-synced** music (bundled library + offline beat maps, events quantized to the beat; free=silent export, premium=in-app track). No architecture change — these constrain existing components (`RecapSnapshotProviding`, `CameraPath`, `OverlayTimeline`, `RecapTheme`, `ImportKit`). v1.5 (2026-07-19) — recap visual pivot (owner decision after reviewing the P3 demo artifact): the recap is a stylized, premium animated replay, not Apple-tile output — vision in `Docs/kamome-animation-vision.md`; recap base-map substrate moves MKMapSnapshotter → MapLibre Native + self-hosted vector tiles with Kamome-authored themed styles (ADR in `Docs/decisions.md` 2026-07-19; implementer guide `Docs/vector-tile-pipeline.md`); §0 gains rule 6 (storytelling engine + recognizable identity); §4.5 step 2 rewritten + visual quality bar added; Phase 3 scope frozen as the pipeline milestone; new **Phase 3.5 Recap Visual System** (OSRM §4.4 pulled forward → MapLibre substrate → Modern Minimal theme; no renumbering of P4–P7). v1.4 (2026-07-18) — fork demoted from positioning to mechanism: positioning line rewritten (memory-engine framing), §1.5 fork row relabeled P6 bet, §4.5 end card copy → "Get this route"; all user-facing copy uses Save / Get / Inspired by (S6/S7 screen wording settled at P6 — internal names, table `plan.forked_from`, and `.kamome` schema unchanged). v1.3 (2026-07-15) — battery-moat repositioning: passive capture tier (§1.8, §2.3), map matching promoted to core (§4.4), trip import (§4.7), phases renumbered (fork → Phase 6, backend → Phase 7), transactional monetization note (§1.6). v1.2 (2026-07-11) added Roadtrippers analysis, Taiwan-market adaptations, Kamome branding, handoff checklist & kickoff prompt.
- Docs/kamome-poc-spec.md:31:3. **Prefer boring tech.** No reactive frameworks beyond what SwiftUI requires. Use Swift Concurrency (async/await) only where the OS API forces it (location callbacks, photo fetches, video export). No Combine pipelines for business logic.
- Docs/kamome-poc-spec.md:32:4. **Every phase ends with a demo artifact** (screen recording script or exported file) placed in `Docs/demos/phaseN/`.
- Docs/kamome-poc-spec.md:74:| Import past trips (photo EXIF) | ❌ | ❌ | ❌ | export-only | ✅ **Replay MVP core loop — photo-EXIF import** |
- Docs/kamome-poc-spec.md:83:3. **They validate the money.** 38M+ trips planned, monetized via subscriptions and booking commissions — proof that road-trip planning has willing payers. Kamome's future monetization (post-POC, icebox): **transactional, not subscription** — a 2–4-trips-per-year product dies of subscription churn (Strava's weekly cadence is why its subscription works). Candidates: per-trip HD/no-watermark export (~US$3–5), yearly unlock-all, higher-priced creator tier (4K b-roll export). Premium video styles, fork-count analytics for creators — not bookings. Details in `Docs/icebox.md`.
- Docs/kamome-poc-spec.md:91:- **Localization architecture:** String Catalogs from Phase 0, zh-Hant as development language, en as first export locale. Stop names via CLGeocoder honor device locale (Chinese place names natively). App Store metadata, screenshots, and privacy labels prepared in both zh-Hant and en-AU/US.
- Docs/kamome-poc-spec.md:250:- `trip → plan` conversion and `plan → .kamome` export are pure functions over these tables; keep them in `Core/PlanKit/` with unit tests.
- Docs/kamome-poc-spec.md:251:- **Honest provenance (2026-07-20).** `trip.source` is load-bearing, not cosmetic: it separates what Kamome **actually recorded** (`recorded`) from what was **reconstructed from photo locations** (`imported_photos`) or a Timeline export (`imported_timeline`). Both produce first-class recaps, but the distinction must surface in the UI (S1 card badge, S3 detail — §5). GPS and EXIF are **not** tamper-proof evidence; never present an imported trip as proof, and never use copy like "Verified Trip". This is a product rule, not a nicety (§6).
- Docs/kamome-poc-spec.md:332:5. Encode via `AVAssetWriter` (H.264). GIF export: same frames at 12 fps, 480 px wide, `ImageIO` with palette quantization.
- Docs/kamome-poc-spec.md:333:Acceptance bar (**revised 2026-07-20**): each of the three real dogfood trips exports on a real iPhone in a **product-acceptable** time, **recorded per trip** via the S5 readout — no crash, no unacceptable memory pressure. The single "< 90 s on an iPhone 13-class device" number was a simulator-era target and is **not** re-used as a pass/fail line without fresh device data; it survives only as a rough sanity reference. What actually gates is Chiu's judgment that the film is worth sharing (§10). This feature is the marketing engine — over-invest here.
- Docs/kamome-poc-spec.md:363:| S8 | Settings | Tracking profile (Battery saver / Balanced / High fidelity → maps to config presets), permissions status + fix-it deep links, data export (GPX + JSON), delete all data. |
- Docs/kamome-poc-spec.md:376:- Privacy nutrition label: location + photos, "data not collected" (true until Phase 7 — a genuine marketing point: "your location history never leaves your phone"). Import strengthens the point: photos and any Timeline export are parsed on-device and never uploaded.
- Docs/kamome-poc-spec.md:418:- **Fold into the Replay MVP gate:** on-device MP4 export, S5 UX / progress / cancel / share sheet, limited-photo re-check, per-trip render time recorded. GIF is now **non-blocking** — MP4 is the launch format, so the old "GIF < 8 MB" line is retired as a gate.
- Docs/kamome-poc-spec.md:439:- All three export **stably on a real iPhone** — no crash, no unacceptable memory pressure.
- Docs/kamome-poc-spec.md:440:- **Per-trip export time recorded** (S5 readout), judged **product-acceptable** — the retired single < 90 s number is not the criterion.
- Docs/kamome-poc-spec.md:448:**Feasibility — deterministic, no AI/LLM tokens (owner constraint 2026-07-20).** Story Director is a **scoring-and-selection engine over structured trip data** (stops, segments, photos, timestamps, geography) — pure algorithm, no LLM, no network, no per-call cost, and deterministic (which *keeps* golden-frame CI stable rather than breaking it). Moment salience = a weighted sum of photo count, `is_highlight`, dwell duration, geographic novelty (distance from the last kept moment), and day-boundary signals — weights are `TrackingConfig.json` tunables; select top-N with non-maximum suppression for spacing; omit the rest and speed-warp the gaps; scale per-photo hold by salience. Hero-photo pick uses **on-device Vision** (saliency / face detection — free, local, no tokens, no network, not an LLM; owner-confirmed 2026-07-20) to rank a stop's photos, falling back to `is_highlight` → nearest-the-dwell-midpoint → chronological when Vision yields no signal. Vision confined to its own boundary file (SDK-confinement rule); its scores are cached so re-exports stay deterministic. The manual "replace / remove" controls are the taste escape hatch. Scope:
- Docs/kamome-poc-spec.md:453:- **Licensed music + beat-sync** — bundled royalty-free library + offline beat maps, recap events quantized to the beat; free = silent export, premium = in-app track (§1.6 transactional).
- Docs/kamome-poc-spec.md:469:Do not start until **both** the Replay MVP and Story Director have real sharing evidence — plan/fork must never block or delay the video product. Scope: plan tables, S6/S7, trip→plan conversion, `.kamome` export/import + URL scheme, plan-vs-actual diff §4.6, drive-time estimates. Stretch: 環島 loop detection + progress ring + badge (§1.7).
- Docs/kamome-poc-spec.md:528:The §7 Phase 3.5 hard gate, restated as the go/no-go: three real past trips of **different character** each go **photos → import → route reconstruction → recap → MP4 → share, entirely in-app** — no DB edits, no repo-external tools; routes are honest (no gross sea/mountain/wrong-road fabrication; low confidence shown as inferred); all three films are ones Chiu wants to keep and share; **≥ 1 published publicly** without external editing; limited-photo path passes on device; stable export on a real iPhone (no crash, acceptable memory); per-trip export time recorded and product-acceptable. The bar is **"worth publishing," not "prettier map."** "Three trips" is hard — never downgraded to one.
- Docs/kamome-poc-spec.md:533:- ≥ 1 payment signal for HD / no-watermark export (fake-door price probe is fine at this stage).
- Docs/osrm-setup.md:11:and every newly ended trip — and any recap export — matches automatically
- Docs/osrm-setup.md:108:(`Docs/demos/phase3/` seeding notes), export a recap, and confirm the
- Docs/pre-launch.md:23:| **4** | *(optional)* **Lower-quality export option** | A real feature with real design questions. Genuinely optional. |
- Docs/pre-launch.md:24:| **5** | **Export time estimate** ⬆️ | **Promoted out of 4.** Not optional: a six-minute export with no estimate reads as broken. The loop already knows the frame count and the measured per-snapshot cost. |
- Docs/pre-launch.md:34:crash-free export across three trips. The souvenir-map item is moot while MapLibre is
- Docs/pre-launch.md:176:requires it inside exported media, and the film draws a *line* rather than
- Docs/pre-launch.md:194:  at export time instead of reading `matched_polyline`; offline re-export degrades,
- Docs/pre-launch.md:243:- **Per-trip export time** never recorded from the S5 readout.
- Docs/pre-launch.md:256:  **implemented but never verified on a device** — a locked screen mid-export is
- Docs/pre-launch.md:258:  session**: start an export, lock the screen, wait, see whether it survives.
- Docs/pre-launch.md:259:- Resumable export is deliberately **not** built. `AVAssetWriter` cannot resume
- Docs/prototype/README.md:151:export-everything friction; (c) photos are the emotional payload anyway. Timeline
- Docs/prototype/README.md:180:   user adds *after* export on IG loses this, because the timing won't match.
- Docs/prototype/README.md:181:4. **Two export paths:** free = **silent export** (clean, user adds platform
- Docs/routing-provider-selection.md:28:optimisation, it is the product: a trip is saved, re-exported offline months
- Docs/routing-provider-selection.md:80:exporting again will help — because that budget is ours and the other failures
- Docs/vector-tile-pipeline.md:107:- Max zoom: recap cameras sit at `export.camera_span_m` (city-to-regional
- Docs/vector-tile-pipeline.md:194:- Snapshot prefetch, keyframe cadence (`export.keyframe_interval_frames`)


## Reading budget recommendation

Basis: file metadata, declared status lines, and hit density only — no document
was read in full, so these are priors for Stage 2, not conclusions.

Files that MUST be read in full in Stage 2 (target: no more than 8):

- PO.md — the audit's own charter; §"Documentation Coherence" and §"Decision Classification" define what counts as a violation; carries uncommitted edits.
- CLAUDE.md — the hub every session loads; carries the densest phase/status claims (declares spec "v1.7" while the spec says 1.8) and uncommitted edits; most conflicts will route through it.
- Docs/kamome-poc-spec.md — the declared authoritative spec (v1.8, 2026-08-20); the anchor every other doc claims consistency with.
- Docs/pre-launch.md — the active launch-blocker list; densest 🔴 API-key/privacy claims, which must agree with ADRs 2026-08-20 (a)–(d); uncommitted edits.
- Docs/camera-arcs.md — newest design doc, untracked, self-declared "recommended NOT decided"; must be checked against the CLAUDE.md freeze language, cross-region-journeys.md, and eng-session-camera-arc.md.
- Docs/cross-region-journeys.md — requirements input to camera-arcs; claims to supersede two stubs in handoff-P3.5.md, a supersession chain to verify.
- Docs/routing-provider-selection.md — short (121 lines), banner-CLOSED; the center of the Geoapify/OSRM conflict cluster together with the four 2026-08-20 ADRs.
- Docs/eng-session-camera-arc.md — untracked session prompt that pairs with camera-arcs.md and claims to move pre-launch items 3 and 5; small (111 lines).

Files that need only a targeted range:

- Docs/decisions.md:1179-1897 — every ADR from the §6a/§6b split onward is live decision surface (Phase 3.5 close, MapLibre parked, Geoapify a–d); earlier entries via the ledger index above, pulled individually only when a conflict cites them.
- HANDOFF.md:1-60 and 17-540 — the header still says "Updated 2026-08-08 / branch feature/typed-legs-routing" while the top sections are dated 2026-08-20/21; the two PO/Architecture findings sections plus the known-bug and RESUME headers are the live state. Sections after L641 are marked CLOSED/RESOLVED and need only spot checks.
- Docs/handoff-P3.5.md:1-45 and 329-360 and 640-669 — status header, §6 gate framing (gate-P3.5-checklist declares this §6 "authoritative"), and the standing rules; the §1–§5 work-order bodies describe landed work.
- Docs/gate-P3.5-checklist.md:1-115 — the split mapping, status, and known defects; Stages 0–3 are procedure, already judged for §6a.
- Docs/eng-session-P4.md:1-45, Docs/eng-session-P4-visual.md:1-30, Docs/eng-session-closeout.md:1-40 — enough of each untracked session prompt to decide whether the session already ran (the branch's commits suggest P4's task is done) and whether the doc is now stale.
- Docs/vector-tile-pipeline.md:1-46 — declares itself "authoritative implementer guide for the MapLibre substrate"; check that self-claim against the 2026-08-15 "MapLibre is parked" ADR; §1 carries the abandon condition.
- Docs/dogfood-infrastructure.md:1-33 — OSRM-era infrastructure doc; header check for staleness against the Geoapify closure.
- Docs/osrm-setup.md:1-13 — same staleness check; likely historical but still says the app "matches automatically" when pointed at OSRM.
- Docs/icebox.md:66-110 — flight-legs and multi-modal entries vs. spec v1.8's "journeys are multi-modal by design" (icebox exit rule is "spec version bump", and a bump happened).
- Docs/device-test-P3.md:1-24 — the redistribution header, to confirm item destinations still match the current phase map.
- Docs/handoff-recap-visuals.md:91-125 — §3 sprite-set constraints, referenced as the basis of Phase 4 item 1 (vehicle sprites).
- Docs/kamome-animation-vision.md:1-36 — status/scope note only; the body is the long-term north star, explicitly not a checklist.

Files that can be skipped entirely in Stage 2:

- Arch.md — engineering-session conduct rules; process, no product/architecture state claims to conflict.
- Docs/demos/phase0/gate-output.md, Docs/demos/phase2/README.md, Docs/demos/phase3/README.md — dated gate records; historical by construction.
- Docs/demos/phase3_5/import/README.md, Docs/demos/phase3_5/matching/README.md, Docs/demos/phase3_5/substrate/README.md — same; artifacts of a closed phase.
- Docs/demos/phase3_5/modern-minimal/README.md — "DRAFT v2 NOT signed off" header is dated 2026-07-22 and the sign-off ADR exists (L889); a demo README, not a decision surface — skip unless the theme sign-off chain is disputed.
- Docs/device-test-P1.md — Phase 1 checklist, superseded in role by device-test-P3's redistribution; historical.
- Docs/prototype/README.md — self-declared "exploration complete, nothing here ships"; findings already absorbed into spec v1.6.
- Docs/handoff-render-layers.md — closed refactor handoff (landed `c933121`); its constraints live on in later docs.

## Appendix — first 15 lines of each file (verbatim)

### Arch.md
```
# Engineering Agent Operating Rules (Final)

You are a senior software architect and engineer.

Your default failure mode is writing code that works but is structurally wrong — tightly coupled, hard to test, hard to extend, or inconsistent with the project's existing architecture.

Your job is not merely to make the current task work. Your job is to make the **smallest correct change that preserves the project's product decisions, architectural boundaries, and long-term maintainability.**

---

## 0. Decision Authority

Order of authority when deciding anything architectural or product-level:

1. Explicit product decisions / requirements
```

### CLAUDE.md
```
# Kamome — working memory for Claude Code

**Authoritative spec:** `Docs/kamome-poc-spec.md` (v1.7, 2026-07-20 **Replay
MVP repositioning** — see below; the first release ships a **photo-import
recap**, not passive capture). Phase map: **P3.5 = Replay MVP (current
release target)**, P4 = Story Director, P5 = Capture Beta, P6 = Plans, P7 =
backend. Earlier: v1.5 recap visual pivot, v1.4 fork = mechanism (user-facing
copy says Save / Get this route, never "fork"), v1.3 battery-moat. Read it
before any work.
Rules of Engagement: spec §0 — phase gates are hard gates, no magic numbers
(all tunables in `Config/TrackingConfig.json`), boring tech, demo artifact per
phase, flag anything needing the physical device, honest provenance (never
"Verified Trip" — recorded vs reconstructed-from-photos is a product rule).

## §0 · Location data never leaves the device by default (Chiu 2026-08-03)
```

### HANDOFF.md
```
# HANDOFF — current state

**Updated 2026-08-08.** Branch `feature/typed-legs-routing` (PR #12 → `phase-3-recap`;
PR #11 is `phase-3-recap` → `main` and holds until the §6 gate). Written so a fresh
session (or a fresh person) can pick this up without being briefed by hand.

Read `CLAUDE.md` first for the standing rules — especially **§0, location data
never leaves the device**, which constrains the fixture work below more than
anything else here.

Scope notes: `Docs/handoff-P3.5.md` is the Replay MVP work order;
`Docs/gate-P3.5-checklist.md` is the §6 gate runbook. This file is the *session
state* on top of them — what is done, what is open, and why.

---
```

### PO.md
```
# Kamome — Product Owner & Architecture Governor

## Role

Act as my **Product Owner + Software Architect partner**.

The human Product Owner has final authority. Your job is to help clarify, challenge, and restore coherence between **product direction, architecture, implementation, and documentation**.

Do not silently turn technical observations into product decisions.

This session never edits application code, at any point, even after Product Owner approval — including drafting patches meant to be applied directly. Its output is limited to audits, decisions, recommendations, and instructions handed to the implementation session.

---

## Session Access & Scope
```

### Docs/camera-arcs.md
```
# The contained arc — how the camera crosses a gap

**Status: design recommended by the PO/architecture session (2026-08-21), NOT
decided, nothing built.** A scoped implementer guide in the shape of
`Docs/cross-region-journeys.md`, not an ADR. **No entry goes into
`Docs/decisions.md` until something has been rendered and judged** — the standing
rule that unverified work is never written as settled architecture.

This document resolves the design conversation `CLAUDE.md` Phase 4 item 3 held
open: *"how the camera crosses large spatial gaps — the opening's
panorama-to-detail move and the cross-region flight are the same problem, and
will be designed together rather than tuned separately."*

Read `Docs/cross-region-journeys.md` first — its requirements (Chiu 2026-08-14)
are inputs here and are not re-opened. This document is the **presentation** half
```

### Docs/cross-region-journeys.md
```
# Cross-region journeys — requirements and design space

**Status: requirements decided by Chiu (2026-08-14), design NOT decided, nothing
built.** This is a scoped implementer guide in the shape of
`Docs/vector-tile-pipeline.md`, not an ADR. No entry goes into `Docs/decisions.md`
until something has been rendered and judged — the standing rule that unverified
work is never written as settled architecture.

Supersedes the two deferred stubs in `Docs/handoff-P3.5.md`: "Trips that span two
map regions" and the airport-departure animation noted beside it. Both are folded
in here.

---

## Why this is open now
```

### Docs/decisions.md
```
# Kamome — Architecture Decision Records

Append-only. Format: date, context, decision, alternative rejected. Decisions
already made in the spec (GRDB over SwiftData, MapKit over Mapbox, XcodeGen,
OSRM, Supabase — spec §2.2/§11.1) are not repeated here.

## 2026-07-12 — GRDB 6.x, not 7.x

**Context:** Spec mandates GRDB. The dev Mac currently has only Command Line
Tools with Swift 5.10 (macOS 14.4 cannot run Xcode 16, which needs 14.5+).
GRDB 7 requires a newer toolchain than local Swift 5.10.
**Decision:** Pin `GRDB.swift` at `from: "6.29.0"`.
**Rejected:** GRDB 7.x — revisit (one-line bump in `Package.swift`) once the
Mac is upgraded and Xcode 16 is installed; before Phase 1 device work ideally.

```

### Docs/demos/phase0/gate-output.md
```
# Phase 0 gate run — 2026-07-12, dev Mac (Xcode 15.4, iPhone 15 simulator, iOS 17.5)

All three §7 Phase 0 gate criteria, actual command output.

## 1. `xcodegen generate`

    ⚙️  Generating plists...
    ⚙️  Generating project...
    ⚙️  Writing project...
    Created project at /Users/chenwenqiu/Kamome/Kamome.xcodeproj

## 2. `xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 15'`

9 tests, 0 failures — app tests (String Catalog zh-Hant/en, bundled config)
plus KamomeCore package tests (schema v1, config loader, round-trip):
```

### Docs/demos/phase2/README.md
```
# Phase 2 demo artifacts (spec §7 gate)

## s3-demo-trip.png

S3 Trip Detail rendering the seeded demo trip (`-demo-seed -demo-open-trip`
launch arguments, iPhone 17 Pro simulator, iOS 26.5):

- Perth → Margaret River route polyline (drive mode, solid)
- 4 stop pins; **Busselton Jetty and Margaret River carry photo-count
  badges (2 each)** — seeded `photo_ref` rows assigned to those stops
- stats strip from `trip.stats_json`: 271 km · 4.8 h driving · 4 stops · 96 km/h
- timeline with reverse-geocode-style names and photo thumbnails; the tiles
  render the §3 graceful-placeholder path (asset ids deliberately dangling —
  `simctl privacy` cannot pre-answer the iOS 26 photos prompt, so the demo
  proves assignment + placeholder handling; live PhotoKit matching is covered
```

### Docs/demos/phase3/README.md
```
# Phase 3 demo — recap video (§4.5)

`kamome-p3-recap.mp4` — the perth_margaret_river_day1 fixture rendered
end-to-end through the shipping pipeline (CameraPath → RecapRenderLoop →
MKMapSnapshotter tiles → RecapFrameCompositor → RecapVideoEncoder): 30 s,
1080×1920@30, H.264 @ 5 Mbps. Stills: title card, Mandurah stop card
(day badge), end card (stats + "Get this route" QR — encodes
`kamome://route/demo`, the P3 placeholder payload until P6/P7).

Rendered 2026-07-19 on the iPhone 17 Pro simulator in **34.6 s** (real map
tiles, snapshot prefetch on). The GIF twin (22 MB) is not committed —
regenerate both with:

```bash
TEST_RUNNER_KAMOME_DEMO_RENDER=1 TEST_RUNNER_KAMOME_DEMO_OUT=/tmp \
```

### Docs/demos/phase3_5/import/README.md
```
# Replay MVP §1 — Photo EXIF Import: S1 UI + honest provenance

Artifact for `handoff-P3.5.md` §1 (the S1 UI + provenance-label half; the import
**engine** landed earlier and is proven by CI — see below). Captured
2026-07-21 in the iPhone 17 Pro simulator (Xcode 26.6). Kamome build
`com.chiu.kamome.dev`.

## What these show

| Shot | Screen | Proves |
| --- | --- | --- |
| `01-home-imported-badge.png` | S1 Home | `Import from photos` is the hero action; live capture (vehicle picker + Start Journey) is demoted to a secondary "Record a new trip live" section; an imported trip card carries the **`From photos`** provenance badge (§3) — never "verified". |
| `02-import-sheet.png` | Import sheet | Date-range selection (From / To) as tappable summary rows, the **7-day default range** driven by `import.default_range_days` (Jul 14 → Jul 21), the privacy footer ("Photos are never copied or uploaded"), and the `Import` action. Each row expands an inline calendar that **collapses once a day is picked** (shows the selection, doesn't leave the picker hanging open); picking a start date **snaps the end onto the start's month** if it drifted, so the "To" calendar opens on the trip's month — device-test feedback 2026-07-21. |
| `03-trip-detail-provenance.png` | S3 Trip Detail | An imported trip is **first-class** — same map / stats strip / stop pins / photo badges / timeline / recap film button as a recorded trip — plus the **provenance note**: "This trip was reconstructed from your photos' place and time — not a recorded track." |

```

### Docs/demos/phase3_5/matching/README.md
```
# Phase 3.5 §1 — map matching before/after (handoff §1 item 3)

**before-p3-artifact.png** — frame from the frozen P3 demo
(`Docs/demos/phase3/kamome-p3-recap.mp4`): the camera is in the middle of
Geographe Bay, route line crossing open water between Bunbury and
Busselton.

**after-matched.png** — the same journey (same anchors, stops, schedule)
exported through the real app pipeline with §4.4 matching active against
the local OSRM WA server: the replay rides Bussell Hwy, takes the
roundabout, and curves onto Causeway Rd into Busselton — no open-water
crossing; every drive segment carries a `matched_polyline` (worst chunk
confidence ≈ 0.98, gate `confidence_min` 0.5 untouched).

Two things changed between the frames, deliberately:
```

### Docs/demos/phase3_5/modern-minimal/README.md
```
# §3 Modern Minimal — design review harness (needs Chiu + a real render)

Modern Minimal is the **one** MVP theme (spec §4.5; handoff-P3.5 §3). Its
acceptance is **not** a test — it is a **side-by-side design review that Chiu
signs off** (vector-tile-pipeline §1 quality bar). This folder is the review
setup. The theme itself cannot be self-certified: the actual look is a Metal
render that is not produced in this repo's CI.

## Status

- `Config/RecapThemes/modern-minimal.json` — **DRAFT v2, NOT signed off.**
  **v1 (pale "desaturated OSM") was rejected by Chiu 2026-07-22** — it read as an
  engineering map with the contrast turned down. v2 is a **dark atmospheric
  souvenir map** matching the validated prototype + WIP demo
  (`Docs/prototype`, artifact "Kamome Recap 冰島環島"): dark-navy sea, dark-slate
```

### Docs/demos/phase3_5/substrate/README.md
```
# Replay MVP §2 — MapLibre souvenir-map substrate (demo artifact)

Landed 2026-07-21 on `phase-3-recap`. This is the **functional substrate**, not
the shipping look: Modern Minimal (§3) is a separate step gated on Chiu's
side-by-side design review. MapKit is still the base map users see until then.

## What landed (verified in-repo, CI-green)

- **MapLibre `6.27.0`** via SPM (exact pin), app target only.
- **`App/Services/MapLibreSnapshotProvider.swift`** — conforms to the existing
  `RecapSnapshotProviding` boundary; the **only** file that imports MapLibre
  (CI grep gate). Projection travels with the snapshot
  (`MLNMapSnapshot.point(for:)`); center + span → MapLibre zoom (Web Mercator,
  512 px tiles, `scale = 1`). No pitch/bearing yet (follow-cam, §4).
- **`App/Services/RecapMapStyle.swift`** — pure (no SDK) resolver that injects the
```

### Docs/device-test-P1.md
```
# Phase 1 device test — checklist (Chiu signs off; spec §7 Phase 1 gate)

The unit gates (GPX replay) pass in CI. This manual test is the remaining
Phase 1 gate criterion and needs a physical iPhone, a car, and ~2 h.

## Build preconditions (decisions.md 2026-07-12: must land before this drive)

- [ ] Always-permission priming + background location flow (landed Phase 2).
- [ ] Dwell region-resume in `LocationService` (decisions.md 2026-07-15) —
      without it the first dwell pause turns GPS off permanently and the rest
      of the trip is lost. GPX replay cannot cover the CoreLocation side, so
      the two ≥ 5 min stops below are the real test of it.

## Setup

```

### Docs/device-test-P3.md
```
# Phase 3 device validation — stop semantics + battery (next real drives)

Tracked validation items (Chiu, 2026-07-18). These ride any drive on a
build ≥ the stop.kind commit; the formal 2 h gate drive checklist stays
`Docs/device-test-P1.md`. Findings → `Docs/decisions.md`.

## ⚠️ Redistribution 2026-07-20 (Replay MVP repositioning — history preserved, nothing marked passed)

Per `decisions.md` 2026-07-20, these items were **split by destination**. Every
checkbox below stays exactly as it was — **unchecked items remain unchecked**;
this section only records *which gate each item now belongs to*.

- **→ Capture Beta (Phase 5)** — tracking / background / battery, no longer on
  the release path: **A, B, C, D, E**, and **H's 2 h continuous drive**. These
  validate live capture, which the Replay MVP does not ship.
```

### Docs/dogfood-infrastructure.md
```
# Dogfood infrastructure — routing + map regions for the Replay MVP gate

What the §6 gate needs that the app cannot provide by itself: an OSRM the phone
can reach, and map tiles for wherever the real trips actually went.

**Local first** (Chiu 2026-07-29). The gate runs against OSRM on the laptop over
home Wi-Fi; a VPS comes later, for production. Nothing here is local-only by
construction — `Deploy/docker-compose.yml` is the same file on both, and the
migration is a `.env` edit plus `--profile public`.

Everything is declared in [`Deploy/`](../Deploy/README.md). `Deploy/regions.json`
is the single source for both halves of the stack; the scripts read it, and
adding a region is an edit there.

Decisions this implements (Fable architecture review, 2026-07-26):
```

### Docs/eng-session-P4-visual.md
```
# Engineering session — confirm the API, then look at the film

**Paste the block below as the first message of a fresh Claude Code session.**

---

```
You are the engineering session for Kamome, operating under `Arch.md`. Read it
first, then `CLAUDE.md`, then `Docs/decisions.md` entries **2026-08-20 (a)–(d)**
and `HANDOFF.md`'s "Findings — PO/Architecture session (2026-08-20)".

The routing migration is done and on `feature/geoapify-routing` (`e366df2`,
`556f828`, `1cedbd2`, plus Chiu's `2d221e0`). This session does not redo it. It
confirms the API works, then makes three cheap visual changes Chiu will judge by
looking.
```

### Docs/eng-session-P4.md
```
# Engineering session — Phase 4, task 1: routing goes live

**Paste the block below as the first message of a fresh Claude Code session.**
It is written to be self-contained: it names the reading order, the one task, the
constraints that are already decided, and what counts as done.

Scope is **one task**. Do not hand this session cross-region or export work — those
are separate sessions, in the order set by `Docs/pre-launch.md`.

---

```
You are the engineering session for Kamome, operating under `Arch.md`. Read it
first — it is your charter, and §7/§8 (verification is mandatory, three levels)
and §12 (communicate before implementing) are the parts I will hold you to.
```

### Docs/eng-session-camera-arc.md
```
# Engineering session — the contained arc, Pass 1 (rendering only)

**Paste the block below as the first message of a fresh Claude Code session.**

Scope is **one pass of one task**. This session does **not** build the crossing
beat, does not change the film, and does not touch `Docs/cross-region-journeys.md`
work. Pass 2 is a separate session and is gated on Chiu judging Pass 1's render.

Slots into `Docs/pre-launch.md` **item 2** (cross-region) as its prerequisite, and
it moves items **3** and **5** (export survives / export-time estimate) because it
changes the snapshot count by roughly 4×.

---

```
```

### Docs/eng-session-closeout.md
```
# Engineering session — close out sprites and the API key

**Paste the block below as the first message of a fresh Claude Code session.**
Two closing tasks, deliberately in one session because both are about *what is
already in the tree* rather than new features. Neither is the routing migration —
that is `Docs/eng-session-P4.md` and a different session.

---

```
You are the engineering session for Kamome, operating under `Arch.md`. Read it
first. §7 (verification is mandatory, and tests are not yours to weaken), §9
(fixture and baseline discipline) and §14 (never say "done") are the parts that
matter most here.

```

### Docs/gate-P3.5-checklist.md
```
# §6 Replay MVP gate — owner runbook

Consolidated 2026-07-31; revised 2026-08-02 after the camera/legibility work
closed; **revised 2026-08-13 for the §6a / §6b split**. The gate items themselves
live in `Docs/handoff-P3.5.md` §6 and stay authoritative; this is the **order to
do them in**, written for Chiu rather than for an implementer.

## The split, and how these stages map onto it

§6 became two gates on 2026-08-13 (Chiu; ADR in `Docs/decisions.md`), over
**different variants**, because that is what actually ships:

| stage here | gate | where | variant |
|---|---|---|---|
| Stage 0 + Stage 1 | **§6a — the film** | the desk | **A** (`recap_mode: full`, harness-only) |
```

### Docs/handoff-P3.5.md
```
# Handoff — Phase 3.5 = **Replay MVP** work order (rewritten 2026-07-20)

Written for the next Claude session picking up `phase-3-recap`. Everything here
assumes you have read `CLAUDE.md` and `Docs/kamome-poc-spec.md` (v1.7) first.

**Phase 3.5 was renamed "Recap Visual System" → "Replay MVP" (recap from
photos)** by the 2026-07-20 owner decision (`decisions.md` 2026-07-20 Replay MVP
repositioning; spec §7). This file is the work order for that release, in
**mandatory sequence**. The old sequence started at MapLibre — **do not follow
that; the new first item is Photo EXIF Import.** Prioritise product order over
the historical order (spec §0; owner instruction 2026-07-20).

When in doubt, prefer doing less: every tunable goes in
`Config/TrackingConfig.json`, every renderer SDK stays confined to one provider
file, no gate item is ever marked passed without the artifact that proves it,
```

### Docs/handoff-recap-visuals.md
```
# Handoff — Recap Layer 3 + visual redesign (2026-07-25)

Branch `phase-3-recap`, commits `ce28db6` (Layer 3 + redesign), `2917008` (final
car art) and `f294883` (static camera + MapLibre switch + theme atmosphere).
131 tests green, `swiftlint --strict` clean. **Not merged — PR #11 holds until
the §6 three-real-trip gate.**

**This closes the recap-visuals phase.** Nothing in the pipeline is waiting on a
design decision; what remains before PR #11 is device validation (§7). Read §0
first if you are picking this up cold — the camera model reverses what earlier
sections of this document and `handoff-P3.5.md` describe.

## 0. The camera is static — read this before the rest

The final and largest reversal of the session (Chiu 2026-07-25). Sections 1–6
```

### Docs/handoff-render-layers.md
```
# Handoff — Recap render-layers refactor (2026-07-24)

The recap OUTPUT / video-format redesign (CLAUDE.md "recap OUTPUT / video-format
redesign") became a **render-pipeline re-architecture** on Chiu's direction
(2026-07-24). Target: a TravelBoast/Relive-class animated map video — cute anime
hero car, dark souvenir night map, photos at stops — where **the same animation
timeline can render in any visual style** (TravelBoast / modern-minimal /
cinematic) without rewriting the story/timing logic.

Branch `phase-3-recap`. Foundation + Layers 1–2 committed at `c933121`. **Not
merged** — PR #11 holds until the §6 three-trip gate.

## The architecture (the one rule)

Story/timing and rendering couple **only** through style-independent value
```

### Docs/icebox.md
```
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
```

### Docs/kamome-animation-vision.md
```
# Kamome Animation Vision

**Status:** Product direction from Chiu, 2026-07-19, after reviewing the P3
demo artifact (`Docs/demos/phase3/kamome-p3-recap.mp4`), approved with
refinements the same day. Integrated into spec v1.5 (§0 rule 6, §4.5
quality bar, §7 Phase 3.5), `Docs/decisions.md` 2026-07-19 (gate decision
+ substrate ADR), and `Docs/vector-tile-pipeline.md` (implementer guide).
Pipeline mechanics of §4.5 (camera path, overlay timeline, encoding,
budgets) are unaffected.

**Scope note — Replay MVP repositioning (2026-07-20, `decisions.md`).** This
document is the *long-term* visual north star; it is not the MVP checklist.
Product evolution is two layers: **(1) Replay MVP** — auto-generate a real-road
trip animation from imported photos; **(2) Story Director** — add automatic
selection, narrative, hero photos, pacing, and music. Read every ambition below
```

### Docs/kamome-poc-spec.md
```
# Kamome 卡摸咩 — POC Design Spec & Build Plan

**Product name:** Kamome / 卡摸咩 (かもめ, "seagull" — inspired by the Taiwanese classic 《快樂的出帆》; the seagull follows the traveler out and comes home with the memories)
**Positioning:** **"Kamome turns your road trips into stories you can relive and share."** (Owner-restated north star, 2026-07-20 — this line sits above every feature call.)

**Two-layer product evolution (2026-07-20, Chiu — supersedes the earlier "passive-capture v1" framing).** The long-term vision is unchanged: *Kamome automatically remembers your journey and directs it into a travel film worth rewatching.* But the **first shipped product is deliberately smaller, publishable, and verifiable — the Replay MVP:** *pick a past trip's photos → Kamome rebuilds the route from their EXIF place + time, snaps it to real roads, and auto-generates a cool, shareable travel-path animation (MP4).* The MVP does **not** promise full passive background recording or the automatic story-directing; those are proven later (**Capture Beta**, **Story Director** — §7) and the architecture must not block them. The evolution is two layers: **(1) Replay MVP** — auto-generate a real-road trip animation; **(2) Story Director** — on top of the MVP, add automatic moment-selection, narrative, hero photos, pacing, and music, becoming a true trip-memory director. Do not cram Story Director into the MVP now. **Do not let MVP copy claim 12-day zero-touch capture or imperceptible battery** — those are Capture-Beta-validated promises, not launch claims (see §1, §7, §10).

Founder motivation (Chiu, keep verbatim): *built first for myself — I love travelling but can't be bothered to organize; the trip ends and Kamome has already made the movie.* This is a **storytelling / memory** product, not a GPS or planning tool. Fork is the underlying mechanism (§3.1), not the marketing language: user-facing copy says **Save / Get this route / Inspired by**, never "fork" ("GitHub for road trips" is engineer-brain framing — ordinary travelers save and get inspired; they don't fork). **Taiwan-first launch, English-ready by design.**
**Brand element:** the animated "you are here" head marker in the recap video is a small seagull, not a dot. This is the mascot and the app icon.
**Platform:** iOS 17+, Swift 5.10+, SwiftUI. Base localization zh-Hant, second locale en. All user-facing strings in String Catalogs from Phase 0 — never hardcoded.
**Audience for this doc:** Claude (Claude Code) as the implementing engineer. Chiu as product owner / reviewer.
**Doc version:** 1.8 (2026-08-20) — **journeys are multi-modal by design** (owner
decision, `Docs/decisions.md` 2026-08-20). Kamome must eventually reconstruct a
journey whatever the transport mode — drive, walk, cycle, transit. **Car ships
first and is the only mode routed today**, but the roadmap and the architecture now
```

### Docs/osrm-setup.md
```
# OSRM map-matching server — setup & validation

Self-hosted OSRM backing §4.4 map matching, pulled forward into Phase 3.5
(decisions.md 2026-07-19): the recap replay must follow real roads, never
straight lines between GPS points. The same Geofabrik extracts later feed the
Planetiler → PMTiles vector-tile build (`Docs/vector-tile-pipeline.md`), so
keep the downloaded `.osm.pbf` files.

The app side is already wired and dormant: `matching.base_url` in
`Config/TrackingConfig.json` is `""` (disabled). Point it at a running server
and every newly ended trip — and any recap export — matches automatically
(`RouteMatchService`; drive/scooter segments only, walks stay raw).

## 1. Get extracts

```

### Docs/pre-launch.md
```
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
```

### Docs/prototype/README.md
```
# Recap visual prototype — findings & spec reference

**Date:** 2026-07-20 · **Owner sign-off:** Chiu ("prototype 蠻成功的，收斂回 app")
**Status:** exploration complete → feeds spec §4.5 / §7 (Phase 3.5) and §4.7 (import).

This folder is a **throwaway web prototype** (HTML/JS) built to de-risk the
recap *visual system* on real data before committing the Swift implementation.
The language is different from the app on purpose — it let us iterate the
*feel* in hours instead of days. Everything here is a spec reference for the
app; nothing here ships. Read this doc, then skim `recap_engine.html`
(the animation logic) and `recap_data_pipeline.py` (the data flow).

Built and reviewed live with Chiu over one session. Real input: **170 geotagged
iPhone photos from Chiu's actual 13-day Iceland ring-road trip (Oct 2023)** —
not synthetic fixtures. The whole thing was generated from those photos alone,
```

### Docs/routing-provider-selection.md
```
# Choosing the routing provider — what to compare

> ## ✅ CLOSED 2026-08-20 — the provider is **Geoapify**
>
> Chiu ran the survey on 2026-08-19 and decided. The ADR carries the measured
> results, the two questions the survey did **not** close, and the second policy
> the migration has to carry: `Docs/decisions.md` **2026-08-20**.
>
> Everything below is kept as the record of *what was asked* — it is the reason the
> survey measured what it did. **It is not an open question.** Do not re-run this
> checklist against another provider unless Chiu reopens the choice.

**The decision to use a hosted third-party API on a free tier is made**
(`Docs/decisions.md` 2026-08-16, including its §0 consequence: real trip
coordinates now leave the device to a third party). **Which provider is not.**
```

### Docs/vector-tile-pipeline.md
```
# Vector-tile pipeline — recap base maps (Phase 3.5 = Replay MVP)

**Status:** authoritative implementer guide for the MapLibre substrate
(spec v1.7 §4.5 / §7 Phase 3.5 = Replay MVP; ADR `Docs/decisions.md`
2026-07-19). This is Replay MVP work order §2 (`Docs/handoff-P3.5.md`).
Written to be executable by a fresh implementer with no other context.
Read `Docs/kamome-animation-vision.md` first — it is the "why" behind
every choice here.

---

## 1. Why this exists (and when to abandon it)

The recap's base map must be fully Kamome-controlled: colors, typography,
road treatment, and above all **what is omitted**. Apple's
```

