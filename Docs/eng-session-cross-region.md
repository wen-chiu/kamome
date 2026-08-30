# Engineering session — the cross-region crossing beat (session 1 of 2)

**Paste the block below as the first message of a fresh Claude Code session.**

`Docs/pre-launch.md` **item 2**. Session 1 builds the crossing as a beat and a
camera move, with **no classifier**: every crossing gets the same sprite. Session
2 is the mode classifier (plane / ship / seagull). Splitting them is
`Docs/cross-region-journeys.md`'s own instruction — *"a classifier with no honest
fallback will be tuned into guessing"* — inverted: with no classifier at all,
there is nothing to tune, and the camera move can be judged on its own.

Camera-arc **Pass 1** (`Docs/eng-session-camera-arc.md`) is **not** a prerequisite.
The move and the crop-scale rendering are independent by design
(`Docs/camera-arcs.md` §7). This session pays the snapshot cost instead; Pass 1
later refunds it.

---

```
You are the engineering session for Kamome, operating under `Arch.md`. Read it
first — §7/§8 (verification is mandatory, three levels), §9 (fixture and baseline
discipline), §11 (plan deviation) and §12 (communicate before implementing). §14:
never say "done".

Read in this order before proposing anything:
- `Docs/current-state.md` — the snapshot. **Run its staleness check first**: its
  "Last synced" line must name the newest ADR in `Docs/decisions.md`. If it does
  not, `decisions.md` wins and you report the staleness before proceeding.
- `CLAUDE.md` — standing rules, especially §0 (location data never leaves the
  device).
- `Docs/camera-arcs.md` — **§0 first (the 2026-08-30 amendment), then §3–§9.**
  §0 corrects the rest of that file and is the reason this task is shaped the way
  it is. §7 carries a 2026-08-28 note about the projection that you must read
  before touching any snapshot geometry.
- `Docs/cross-region-journeys.md` — the requirements (Chiu 2026-08-14). Not
  reopened here.
- `HANDOFF.md` — the 2026-08-21 PO findings (items 3, 4, 5 constrain this
  directly) and the 2026-08-29 entry (the two gulls).

Where a `Docs/handoff-*.md` contradicts an ADR, the ADR wins and the handoff is
stale — say so rather than resolving it quietly.

## Before your first command

- Confirm where you are before building. The repository was cleaned on
  2026-08-30 (worktrees removed, merged branches deleted, checkout returned to
  `main`), so a stale branch should no longer be lying around — but check rather
  than assume, and branch off an up-to-date `main`.
- Other sessions work in this tree. Stage **explicit paths only** — no
  `git add -A`, no `git reset --hard`, no `git clean`, no `git checkout -- <path>`.
- §0: the fixture you author in step 1 is **hand-written plausible coordinates**,
  like every committed fixture. A real dump is never committed; those live only in
  gitignored `Tests/Fixtures/trips/local/`.

## The task

**Make a journey that crosses water play as one continuous move, and render a
film Chiu can judge.**

Six steps, in dependency order. Propose before building (§12), and stop at any
step that turns out to be wrong rather than working around it.

### 1. Author a crossing fixture — nothing can be built or judged without one

**Measured 2026-08-30: no fixture in the tree contains a crossing.** The real
Miyakojima dump has a 20.0 km largest gap and zero discontinuities, confirming
`Docs/cross-region-journeys.md`'s warning that desk fixtures were built from
folders hand-curated to the destination while the device import pulls the travel
days.

Author one: a short drive to a departure point → an **unroutable** crossing over
water → a destination with several stops. Add it to
`RecapCameraContinuityTests`'s fixture list so the gate covers a crossing from
this point on.

### 2. The "no road here" verdict has to survive out of the provider

**The trigger is routability, not distance** (`Docs/camera-arcs.md` §0). Three
cases already exist in the tree and must not be collapsed:

- provider answered **"no plausible route"** (Geoapify `400 No suitable edges`) →
  there is no road → **this is a crossing**;
- **detour gate** rejected it (`RoutePlausibility`, ratio 2.5) → a road exists,
  this route is not trustworthy → dashed, **not** a crossing;
- thrown **`RouteProviderFailure`** → nobody answered, retryable, *"never the
  geography's fault"* → **not** a crossing.

`GeoapifyRouteProvider` has several `return nil` sites and they all look the same
downstream. The geography verdict must reach the domain layer as a **named
reason**. This is the same lift the detour gate needed during the migration — a
Kamome policy trapped inside a provider file (ADR 2026-08-16) — and it is the
prerequisite for everything below.

**Do not use `act_split_km` as the trigger.** It keeps its existing job
(camera-discontinuity detection for the continuity gate). At 25 km it fires 20
times on the Iceland dump and 14 on New Zealand; an arc per firing is the
2026-08-02 act-camera defect rebuilt.

### 3. The crossing becomes its own beat

It gets its own stretch of film time, and **its distance leaves the body-span
derivation**: `RecapDurationPlan.bodySpanM`'s pan floor is
`routeDistanceM / (travelS × camera_pan_window_fraction_per_s)`, so today the
crossing's length is what forces the destination to render as a smudge.

**One span per trip still — derived from the largest local journey, not the
union** (`HANDOFF.md` 2026-08-21 finding 5). A span per segment is per-act
framing, rejected 2026-08-02. Do not build it. If renders show short segments
framed too wide, report it as evidence; it is Chiu's decision, not yours.

### 4. The camera crosses it as a contained arc

Open out to an apex containing both ends, translate wide, close in. Span
interpolates geometrically — `CameraPath.lerp` already does this. The invariant:

  At no moment does the screen contain ground that the previous moment did not
  also contain, somewhere in it.

**No exemption to either continuity gate, and no threshold change.**
`RecapCameraContinuityTests.groundOverlap` divides by the *smaller* footprint, so
a contained move already scores 1.0 at any zoom ratio. Assert instead:

- for any two frames a snapshot interval apart, **the tighter lies entirely inside
  the looser**;
- **the apex is padded enough that `CameraPath.confine` is a no-op** (≥1.25
  satisfies `camera_safe_zone_fraction` 0.8; 1.5 lands at 67%). A confine that
  fires drags the frame off the arc and breaks containment.

`permittedCutTimesS` should become unreachable for crossings. Report whether it
still fires anywhere after your change, and why.

### 5. Fine-sample the arc window — temporary, and say so in the code

`RecapRenderLoop` fine-samples only while `frame < movingUntilFrame`, derived from
`timeline.openingS`. A mid-film arc falls in the body, gets the coarse interval,
and cross-fades between geometrically different pictures — it will look janky for
a reason that is not the design's fault. Extend fine sampling to cover arc
windows.

This is a **known temporary cost**, replaced by crop-scaling in camera-arc Pass 1
(`Docs/camera-arcs.md` §7). Measure it with `RecapSnapshotBudgetTests` and report
the number. Do **not** change `keyframe_interval_frames` in
`Config/TrackingConfig.json` — it is frozen.

### 6. The sprite — one for every crossing, and pick it deliberately

Make the crossing's subject a **parameter of the beat**, not a decision baked into
it. Render the judgement film with the **`plane`** sprite: it already exists, it is
`selectable: false` (reserved for exactly this), and on a hand-authored flight
fixture it is a fixture fact rather than a guess.

**The shipped default for an unmodelled crossing is the seagull, and it is now
unblocked.** It was blocked until 2026-08-30: the fault marker was also a gull, so
one symbol meant two things. PR #23 (`724d4a0`) closed that structurally — the
fault marker is `VehicleMarker.seagullBadge`, an upright non-rotating `#1D6FE0`
disc, on the principle that *"a badge reads as a marker, a bare bird reads as a
bird"*.

⚠️ **Three gull objects now exist. Name which one you use.**

- `VehicleMarker.seagull` — the bare vector. **Also the end-card brand mark**,
  which is why the badge was a new case rather than a restyle, and the PR records
  that nothing asserts its shape. **Do not restyle it.**
- `VehicleMarker.seagullBadge` — the fault marker. **Never the narrator.** Using
  it would re-create the collision that was just closed.
- the `seagull` folder in `vehicles.json` — an omni PNG sprite, currently
  `selectable: true`, i.e. a choosable subject.

Requirement 4 asks for "Kamome's own logo, drawn as its own sprite", which points
at the omni sprite. If you use it, say what happens to its choosable-subject role;
the precedent is `plane` / `boat`, which are `selectable: false` because they are
crossing art (and the reindeer sets, which are choosable and are *not* — ADR
2026-08-20 (3d)).

## What is already decided — do not redesign these

- **Do not build the mode classifier.** Session 2. One sprite for every crossing
  here.
- **Do not relax either continuity gate.** Tests are not yours to weaken
  (`Arch.md` §7). If your change needs a gate relaxed, the change is wrong.
- **Do not reintroduce per-act / per-segment framing.**
- **Do not change `keyframe_interval_frames` or the opening's every-frame
  interval.** Both frozen (`Docs/current-state.md`).
- **Do not touch the opening's beats.** Dropping the middle beat is camera-arc
  Pass 2 and needs Chiu's sign-off separately.
- **Appearance is a required provider input** (ADR 2026-08-27). Any colour this
  feature introduces — a dashed crossing leg over water especially — must be
  chosen and judged in **both** light and dark. Two tokens have already been
  caught in exactly that trap (`HANDOFF.md` 2026-08-29); do not add a third.
- **Do not write to `Docs/decisions.md`.** Nothing is settled until Chiu has
  judged the film.

## What counts as done

- A rendered film on the crossing fixture, handed to Chiu, in which the crossing
  plays as one continuous move.
- The full suite green — **including the continuity gate with the new crossing
  fixture in it, and no exemption used.** Report the gate's own printed line.
- A measured snapshot count for the film, through the shipped loop, with the
  arc's share named.
- An honest paragraph on what the destination's framing looks like now versus the
  union-derived span it replaces.
- A `HANDOFF.md` entry, including anything that contradicts `Docs/camera-arcs.md`
  or this brief. A finding that exists only in your session has not been
  delivered.

If step 2 shows the geography verdict cannot be separated cleanly, **stop and
report**. Guessing which nil meant water is the one failure this whole design
exists to avoid.
```
