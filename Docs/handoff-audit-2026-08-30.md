# Findings — the 2026-08-30 PO/architecture audit

The render loop's shake and ghosting, the opening that never showed a country,
a shipping-path comment that is wrong, the MapLibre-premise sweep that is owed,
and one open §0 question. **Live.**

*Moved verbatim out of `HANDOFF.md` on 2026-08-31 when that file was put on a
300-line budget (`Scripts/check-doc-budget.sh`). Nothing was edited; `HANDOFF.md`
carries the live summary and points here.*

---

## Findings — PO/Architecture session (2026-08-30)

**Context.** A full direction-and-architecture recovery audit, plus Chiu's second
round of outside feedback. The product decisions from it are `Docs/decisions.md`
**2026-08-30**; the documentation contradictions it found are **fixed** in the
same pass and listed in finding 6. What is below is what an implementer needs and
would not otherwise see.

⚠️ **Read finding 1 before touching the render loop, the camera, or
`keyframe_interval_frames`.**

---

### 1. 🔴 The shake and the ghosting are **one mechanism**, and the obvious fix is the wrong one

**The single most important finding of this session.** Chiu's P0
(`Docs/decisions.md` 2026-08-30): *"影片晃動感太明顯 不夠流暢 會有殘影."*

**VERIFIED from code** (`RecapRenderLoop.swift:93–118`, `FrameCompositor.swift:90–93`).
The base map is not drawn per frame. It is snapshotted every
`keyframe_interval_frames` (**15**), and the 14 frames in between are filled by
**alpha-blending the two neighbouring snapshots**:

    context.draw(previous.image, in: frameRect)          // the map at position A
    context.setAlpha(CGFloat(background.blend))
    context.draw(background.current.image, in: frameRect) // the map at position B

While the camera is moving, A and B are **the same map at two different
geographic positions**. Superimposed at partial alpha, every coastline, road and
label appears **twice, offset**, cross-dissolving — and the pair snaps forward
twice a second. **One mechanism, both symptoms**: the double image is the
"殘影", the 0.5 s stepping is the "晃動".

`RecapBackground.point()` interpolates the *projection* between the two snapshots
as well, so the trail and the vehicle are drawn at a blended projection — they sit
correctly on **neither** of the two images, but between them.

**Why it is there, and why nobody noticed.** The loop's own comment says it:

> `keyframe_interval_frames` (15 → two map updates a second) **is sized for a
> static camera**, where consecutive keyframes are identical and the value cache
> makes them free.

That was true on **2026-07-25**, when Chiu made the camera static. `FollowCamera`
— a continuously-moving dead-zone dolly — landed **2026-08-01**. The premise
expired and the number did not move. The same comment shows the defect was
already met once and only half-fixed:

> The opening prologue is the one stretch where the camera actually moves, and at
> that interval the map steps twice a second while the overlays run at 30 —
> **which is exactly what read as a janky zoom.** Snapshot every frame there and
> nowhere else.

The opening was fine-sampled; the body was left at 15 because the body camera was
believed to be static. It is not.

**A precise, cheap falsification** — do this before anything else:

- **Prediction:** ghosting and stepping appear **during travel** and are **absent
  during stop beats**. During a stop the subject is stationary, the dead-zone
  dolly parks, `previousKey == nextKey`, and the loop takes the
  `RecapBackground(current:)` branch — no blend at all.
- **Test:** render ~10 s of *body* (not opening) twice, identical but for the body
  interval — 15 versus 1 — and compare. Minutes, on the existing still/film
  harnesses.
- **Pass/fail:** if interval 1 is clean and interval 15 shows a double image, the
  mechanism is confirmed and this entry can be marked VERIFIED end to end. If
  interval 1 still judders, the cause is elsewhere and **stop** — the camera track
  itself is next (`FollowCamera` is pre-simulated and pure, so dump
  `(t, lat, lon, spanM)` and look at the second derivative).

⚠️ **Do NOT "fix" this by lowering `keyframe_interval_frames`.** Three reasons,
and the third is the one that matters:

1. It is **frozen** (`Docs/current-state.md`, Chiu 2026-08-15).
2. Fine-sampling the whole body multiplies snapshots by ~15. On device a snapshot
   costs **0.72–1.55 s**; a 3.5-minute film already costs about six minutes to
   export and the phone thermally throttles. This turns it into an hour.
3. **The right fix is not more snapshots — it is not cross-fading.** Between two
   keyframes the correct operation is to *reproject* one snapshot to the current
   camera (translate, and scale when the span changes), which is exactly
   **crop-scaling** — `Docs/camera-arcs.md` §7, camera-arc Pass 1. The machinery
   is half-present already: `RecapBackground.point()` proves the projection
   relationship between the two frames is known.

**Status: mechanism VERIFIED, effect INFERRED.** Nobody has yet rendered the pair
above. Do not write it up as the confirmed cause of what users saw until they
have.

### 2. 🟠 The opening has never shown a country — VERIFIED, and it is a parking casualty

The East Australia complaint (*"看不到整個澳洲… 不知道在哪裡"*) is not a camera
tuning problem.

`RecapModel.swift:204` builds `establishing` **only** from an installed `.pmtiles`
region. MapLibre was parked 2026-08-15 and nothing installs one, so `establishing`
is permanently `nil`. `CameraPathPrologue.buildWideOpening`'s own doc states the
consequence:

> Without it (no vector tiles, so Apple's map renders) the country view falls back
> to **the trip's own bounds widened by `country_view_padding`**

`country_view_padding` is **2.2** (`Config/TrackingConfig.json:131`). So the
"country" beat has always been *this trip, ×2.2*. On a compact trip inside a large
country that is geographically meaningless — which is precisely what was reported.

**The useful part for whoever fixes it:** parking MapLibre made this *easier*, not
harder. Apple Maps is a **global** base map with no extent limit — the original
constraint ("never wider than the tiles we have") no longer applies to what ships.
The app already geocodes every stop, so a country-level frame is reachable.
`country_view_padding` is a config key and is **not** frozen. Not designed here.

### 3. ⚠️ A shipping-path comment is wrong, and it hides a possibly-large question

`RecapModel.swift:201–203`:

> The region's extent drives the opening establishing shot and switches the film
> onto content-derived pacing (Chiu 2026-07-30). **No region means Apple's map, no
> prologue, and the previous fixed duration.**

**"No prologue" is false.** `CameraPath.swift:166` gates the prologue on
`openingS > 0`, not on `establishing`, and `buildWideOpening` accepts a nil
`establishing` by design (finding 2). Every film gets a prologue. VERIFIED.

**Which makes the rest of that sentence untrustworthy, and it may matter a great
deal.** If "the previous fixed duration" is also true, then **content-derived
pacing is implemented but permanently dead behind a tile condition that can never
be satisfied** — and the "film duration must scale with trip size" question that
has been open since 2026-08-14 would be an *unlocking* job, not a design job.

**UNKNOWN, and worth an hour.** The cheapest thing that would settle it: trace
`totalDurationS` into `CameraPath.init` (`let total = totalDurationS ?? config.targetDurationS`)
and print the resolved duration for two fixtures of very different size through
the shipped path. **Do not assume either answer from the comment** — the comment
has already been shown wrong on its first clause.

### 4. The pattern behind findings 1–3, named, with a sweep owed

Four defects now share one shape: **a value tuned against the MapLibre souvenir
map that silently degraded when Apple Maps became what ships (2026-08-15), with
nobody re-tuning it.**

| # | what | found | how |
|---|---|---|---|
| 1 | route **glow** inverted — lightened on dark, darkened on light | 2026-08-22 | a film review |
| 2 | **cyan trail** vanishes into water on a light base | 2026-08-27 | a film review |
| 3 | **dashed leg** indistinguishable from solid on light | 2026-08-28 | a pixel probe, accidentally |
| 4 | the **establishing shot** silently lost its country beat | 2026-08-30 | this audit |
| 5 | **`keyframe_interval_frames`** — arguably the same class, one substrate earlier: a number whose premise (a static camera) expired | 2026-08-30 | this audit |

Each was found **one film at a time, by accident**. That is an expensive discovery
method and there is no reason to think 4 was the last.

**RECOMMENDATION (needs Chiu):** one deliberate sweep — go through every value and
capability that was chosen while MapLibre was the substrate and ask *"what is this
premised on, and is that still true?"*. The question that catches this class is
not "is this value good?" but **"what was this value tuned against?"** — the same
shape as the question that caught the two colour tokens on 2026-08-29 (*"what does
this colour sit on, on each base?"*). Cheaper as one pass than as four more film
reviews. **Not scheduled; not started.**

### 5. Two claims from an outside analysis, checked and **found wrong** — do not act on them

Chiu was given a third-party analysis of the feedback. Its process advice was
sound (separate the P0 from the features; specify before building; the opening and
ending fit the existing narrow-waist types). **Two of its technical claims do not
survive checking**, and both would have cost real work:

1. ❌ **"The inter-day leg → `.walk` misclassification must be fixed in
   `ImportService.mode` before cross-region can be built."** **That bug was fixed
   on 2026-08-02.** `App/Services/ImportService.swift:120–124` carries the
   `paceUnknowableGapS` guard, and its comment names this exact defect: *"Without
   that, every inter-day leg of a multi-day trip typed as a walk and drew as a
   straight line across whatever lay between."* **The dependency it names as a
   blocker does not exist.**
2. ❌ **"Trip name is a data-model change."** `Trip.title` is already a stored
   column (`Core/Persistence/Records.swift:10`), already flows to the title card
   (`LinearTimeline`: `title = trip.title`), and album imports already use the
   album's own name (`ImportFlowModel:141`). **What is missing is an edit surface,
   not a schema change** — materially smaller than described.

Recorded because both are the kind of confident, plausible claim that gets
believed. The general rule this session applied: **check a claim against the tree
before it becomes a plan**, exactly as the 2026-08-29 rule says for style values.

### 6. Documentation contradictions found and fixed in this pass

Listed so the fixes are auditable rather than silent. All were on `main`.

| what | was | now |
|---|---|---|
| `Docs/_archive/eng-session-P4-visual.md` | "Status: NOT YET RUN (2026-08-21)" — three days after it merged as PR #18, while `current-state.md` said the opposite | banner: EXECUTED AND MERGED; original line kept as the record of what was asked |
| `current-state.md` blockers | "🔴 intermittent bundle **crash**" — `HANDOFF.md` retitled it on 2026-08-28 ("it no longer crashes") | corrected to the silent-miss form |
| `current-state.md` blockers | "worktrees silently skip half the secrets guard" — closed by `2d221e0` | marked closed; the surviving half kept |
| `current-state.md` active work | two tokens "awaiting a colour judgement" — decided, then superseded by the badge | rewritten; the whole section now names one live line |
| `current-state.md` staleness | one-half check (ADR only) that passed twice over stale blockers | two halves: newest ADR **and** newest merged PR; propagated to `CLAUDE.md` and `PO.md` |
| `Docs/decisions.md` | the 2026-08-29 badge decisions existed **only in `HANDOFF.md`**, one trim from being archived out of the ledger | written up as an ADR, dated to the day of the decision |
| `PO.md` | "the implementing session writes the ADR" was only half a rule — nobody was named to write it if they didn't | second half added: the next PO session writes it, back-dated, saying why it is late |
| `Docs/_archive/inventory-2026-08-21.md` | a 247 KB file inventory from 2026-08-21, unbannered and nine days stale | bannered as history |

### 7. ⏳ One §0 question for Chiu, raised not answered

Two films of Chiu's **real trips** are committed to this repository —
`Docs/demos/phase3/kamome-p3-recap.mp4` and
`Docs/demos/phase3_5/kamome-recap-NZ-disaster.MP4` — while current practice
deliberately writes films to `~/Kamome-films/`, "outside the repository
deliberately (§0)". They are demo artifacts, which the Rules of Engagement
require one of per phase, so the two rules genuinely pull against each other.

**They are not in §0's decided-exceptions list** (which names only the Geoapify
routing payloads and one user-initiated share). This is an owner call and only
an owner call: either they become a **recorded exception** ("phase demo artifacts
of the owner's own trips are committed, deliberately"), or they move out. What
should not persist is the current state, where a standing rule says one thing and
the tree says another.

Checked while there, and clean: `Docs/tests/` (real GPX and sqlite drive dumps) is
gitignored, and `Docs/prototype/recap_engine.html` ships `__KDATA__` as a
placeholder — **no real coordinates are committed anywhere.** The §0 wording in
`CLAUDE.md` was corrected in this pass to name both gitignored locations rather
than only one.

**Left alone, deliberately:** `HANDOFF.md`'s "Reference — Phase 4 scope…" section
still restates `current-state.md` at greater length. It is genuine duplication and
two of the contradictions above came from exactly that split — but
`Docs/_archive/eng-session-camera-arc.md` cites the freeze it records, and it carries
reasoning the index does not. **If it moves, `current-state.md` must absorb the
reasoning first.** Same for the 2026-08-21 PO findings section, which should be
archived once camera-arc Pass 1 has run and been judged.

---

