# Findings — the fallback marker becomes a badge (2026-08-29)

The engineering session that made the subject fallback loud and turned it into a
badge. Findings 1–3, 5, 6 and 6b are **closed**, kept for the measurements that
made the case. Findings 4, 5b, 6c, 6d and 7 are **live** — a trap, two gaps and a
growing token cluster.

*Moved verbatim out of `HANDOFF.md` on 2026-08-31 when that file was put on a
300-line budget (`Scripts/check-doc-budget.sh`). Nothing was edited; `HANDOFF.md`
carries the live summary and points here.*

---

## Findings — engineering session, the silent subject fallback and the badge (2026-08-29)

**Context.** The task 2026-08-28's finding 10 spawned: make the marker fallback
loud, and find out whether it is the bundle crash wearing a different symptom.
Both answered below and in the bundle-lookup entry. Chiu then approved the
resolution diagnostic and asked for two changes to the marker itself.

**Renders for review** (outside the repo, §0): `~/Kamome-films/2026-08-29-fallback-navy/`,
five stills and a `README.md` with the numbers. Same trip, same frame (t=114.3 s)
as every subject still since the size sweep; the failure visual is *forced*, so it
is judged on purpose rather than by accident.

---

### 1. ✅ FIXED — the stand-in had become larger than the thing it stands in for

`fallbackMarkerLengthPx` was a hard-coded **170** while ADR 2026-08-27 moved
`export.subject_length_px` **225 → 157.5**. From that day the fallback seagull
rendered **12.5 px longer than the car**, and nothing failed, because the two
numbers sat side by side with nothing tying them together. Chiu noticed it by
looking.

**The fix is the relationship, not the number.** `fallbackMarkerLengthFraction`
(default **1**) replaces the absolute, and `fallbackMarkerLength(subjectLengthPx:)`
is the one place it is applied. At ≤ 1 the marker is at most the subject, whatever
the subject becomes — the inversion is now structurally impossible rather than
merely corrected. Deliberately the same shape as `length_fraction` in
`vehicles.json`, whose own comment gives this exact reasoning; the manifest cannot
supply this one, because the fallback fires precisely when the manifest could not
be read.

`subjectLengthPx(configured:)` keeps its `max` as defence for a fraction above 1,
and keeps its signature, so no probe call site moved.

**Positive control, run rather than reasoned.** With the fraction set to 1.2 the
new guard fails at all five swept subject lengths —
`("135.0") is greater than ("112.5")` and so on up to `("360.0") is greater than
("300.0")` — and passes at 1. The neighbouring wiring test passed either way,
which is correct: it holds the wiring, the new one holds the bound.

### 2. `RecapRenderTestCase:57`'s `configured: 300` is consistent, not stale — reported, not changed

Asked to look at it and say what I found rather than update it silently. What I
found is that **300 is not a leftover shipped value in this file — it is this
file's own fixture.** `RecapRenderTestCase` builds its `TrackingConfig.Export`
with `subjectLengthPx: 300` (line ~119), and `vehicleHalfPx` clears
`configured: 300`. The probe clears exactly what the render under test draws, so
the two agree and nothing is wrong. 300 is also the suite-wide convention for a
synthetic subject: `CameraPathTests`, `RecapPacingTests`, `RecapEncoderTests`,
`LinearTimelineTests`, `RecapMarkerDeckStillsTests` and `RecapFollowCamStillsTests`
all use it.

**What is true is the reading risk**, and it is the same one that has now cost
this project four times: a number in a test file that resembles a shipped value
but is not one. Changing it would mean changing the fixture too, which moves what
the golden-frame probes render and clear — a real change, for no defect.
**Left alone.**

### 3. ⛔️ SUPERSEDED BY THE BADGE — which navy, and the constraint stated as a number

> **Closed 2026-08-29 without a pick.** Chiu's verdict on these stills was that
> none of them read as blue, and the measurements below say why: every candidate
> that clears a luminance ceiling is too dark for hue to register. The badge
> (finding 6) removed the premise rather than answering the question. **No navy
> was chosen and none should be.** Kept because the numbers are what made the
> badge's case, and because "the target could not be hit" is only visible from
> them.


Chiu wants the marker blue rather than the near-black ink. The constraint is
**luminance, not hue**: `testTheFallbackMarkerContrastsWithItsBaseMap` asserts
< 0.35 on light and > 0.65 on dark, and says in its own comment that it is
asserting visibility rather than an ink.

Measured on the rendered stills, in 0–255 units, against the terrain within 6 px
of the stroke:

| candidate | hex | gull L | beside | **gap** | guard |
|---|---|---:|---:|---:|---|
| white — what shipped until 2026-08-28 | `#FFFFFF` | 217.4 | 191.0 | **26.4** | ✗ |
| the ink, today | `#1C2130` | 34.0 | 190.9 | **156.9** | ✓ |
| A · near | `#17204A` | 34.0 | 190.9 | **156.9** | ✓ |
| B · deep | `#1B2A5B` | 41.5 | 190.9 | **149.4** | ✓ |
| C · bright | `#23407F` | 58.3 | 190.9 | **132.6** | ✓ |

**All three navies clear the guard — run, not calculated** (one temporary edit to
the preset per candidate, reverted; logs `~/Kamome-wt/logs-fallback-diag/guard-*.log`).
A bright cyan `#4FC3F7` was run as a control and **failed at 0.683**, so the guard
bites and is not pinning today's value.

Two things the table does not say. **The white baseline was rendered rather than
recalled** — 26.4 against 156.9 is the argument for the change, in the same frame
and the same units. And **clearing the bar is not clearing the water trap**: the
bar is brightness, the trap is hue, and `navy-C-bright` is included to show where
that begins, not as a recommendation.

**Chiu picks; nothing is committed.** The pick replaces one line in
`RecapStylePresets.modernMinimal(.light)`.

### 4. ⚠️ Base-versus-preset has now bitten four times, and the fourth is the sharp one

The glow "verified fact" quoted the neutral default's alpha 0; the PO session's
ADR quoted the neutral default's blue; both times the shipped preset said
something else. The third was spotting that the ink lives in the preset while the
base `RecapStyle.fallbackMarkerColor` is still white.

**The fourth is worse than a stale reading, and it is live.** `modernMinimal(.dark)`
**does not set `fallbackMarkerColor` at all.** The dark film therefore draws the
base default — white — and the guard's dark assertion (`> 0.65`) passes on a value
nobody wrote for dark. White happens to be right there. That is not the same thing
as it being chosen.

Two consequences worth Chiu's decision, neither acted on:

1. **Changing the base default silently changes the dark film.** This is the
   mechanical reason a navy goes in the light preset — not merely a procedural one.
2. `RecapStyle()`'s neutral defaults are load-bearing for the golden-frame gates
   (its own comment says so) *and* are the dark preset's palette by omission. Those
   are two jobs. Whether `.dark` should state its marker colour explicitly, or the
   base should be documented as "the dark preset's value, and the gates'", is a
   small design question — **reported, not folded into the colour sweep.**

### 5. ✅ RESOLVED BY THE BADGE — the fault gull and the narrator gull are no longer the same bird

**This entry stood as 🔵 CARRY. The badge (finding 6) closed it structurally**,
which is a better outcome than the decision it was waiting for.

`Docs/cross-region-journeys.md` requirement 4 — *"the load-bearing one"* — wants a
seagull as the **narrator of an unmodelled crossing**: honest provenance made
visual, and its own words are that this answer "must be cheap and
**good-looking** rather than a failure state." The fault marker was being styled
in the opposite direction. They were different objects — an omni sprite from
`vehicles.json` versus a vector arc from `RecapStyle` — but a viewer could not
tell them apart.

**A badge reads as a marker; a bare bird reads as a bird.** `.seagull` is
untouched and still drawn (see below); `.seagullBadge` is the fault indicator.
The narrator keeps the plain gull, and nothing has to be decided about which
reading wins.

### 5b. 🔴 THE NEAR-MISS — `.seagull` is also the end-card brand mark

**Found while designing the badge, and it is the reason the badge is a new case
rather than a restyle.** `RecapOverlayChromeDrawing.drawMark` draws
`VehicleMarker.seagull` as **the Kamome wordmark's bird on the end card**, in
`chromeAccentColor`, unrotated — "from the same vector the fallback vehicle
marker uses rather than a bespoke asset".

So the obvious implementation — change `drawSeagull` to draw a badge — would
have **silently turned the brand mark on every end card into a blue disc.** No
test asserts the end card's mark shape; it would have shipped.

The bare gull now has three consumers and they are properly separate: the brand
mark, the fault badge (via its own case), and the cross-region narrator that has
not been built. **Do not restyle `.seagull` in place.**

### 6. ✅ DECIDED — the badge, and the questions it handed back

**Chiu's verdict on the navy sweep: they do not read as blue**, and he is right
about why — every candidate that clears a 0.35 luminance ceiling is too dark for
hue to register. His design instead: a blue disc, a white ring, the gull in white.

**It is structurally better than any colour, and the measurements are the
argument.** Rendered, in 0–255 units:

| still | disc | ring + gull | **badge's own contrast** | terrain | disc vs terrain | ring vs terrain |
|---|---:|---:|---:|---:|---:|---:|
| light · 1.00× | 89.1 | 217.4 | **128.3** | 183.9 | 94.8 | 33.5 |
| light · 0.80× | 89.1 | 217.3 | **128.2** | 186.2 | 97.1 | 31.1 |
| light · 0.65× | 89.1 | 217.1 | **127.9** | 190.5 | 101.3 | 26.6 |
| dark · 1.00× | 89.1 | 217.4 | **128.3** | 81.6 | **7.5** | 135.8 |

The badge's own contrast is **identical to a decimal across three sizes and both
appearances** while the terrain moves 183.9 → 81.6. And the dark row is the proof
of the mechanism: **the blue disc alone is nearly invisible there (7.5)**, yet the
badge reads, because the ring stands 135.8 off it. On light the roles swap — disc
94.8, ring 33.5. Neither colour suffices alone; the pair does, on both. That is
what one colour could never do.

Stills and a README: `~/Kamome-films/2026-08-29-fallback-badge/`.

**Chiu answered two of the three (2026-08-29):**

1. ✅ **One badge for both appearances — accepted.** The token no longer varies by
   appearance: the disc and the on-disc colour live on `RecapStyle` and neither
   preset touches them. The 2026-08-28 oddity — `modernMinimal(.dark)` never set
   this token, so the guard's dark half passed on a white nobody chose — is
   **closed by the design rather than fixed**. There is no longer a dark value to
   choose, so there is nothing left to forget to choose.
2. ✅ **Size: 0.60×**, from the 1.00 / 0.80 / 0.65 sweep — smaller than the
   smallest rendered, so **0.60 was rendered on its own rather than assumed to
   carry**. It draws at **94.5 px** and **legibility does not break between 0.65
   and 0.60**: the gull's double-arc still reads and the ring is still a ring.
   ⏳ **Judged from a still, and Chiu has reserved the right to revisit it from a
   film. Not settled.**
3. ✅ **The blue: `#1D6FE0`** — see finding 6b. Decided with the numbers in hand,
   not defaulted to.

**Two caveats carried deliberately:**

- **The white ring's outer edge is soft on light** and crisp on dark, since white
  against pale terrain is a small step. Worth knowing before judging ring width.
- **`#1D6FE0` is a starting value.** It would have **failed** the old 0.35
  ceiling outright, which is the point: the badge freed the hue.

### 6b. ✅ DECIDED 2026-08-29 — the blue is `#1D6FE0`, and here is the room around it

**Nothing renders differently**: it is the value the branch already carried. What
changed is that it is now a decision. Chiu considered `#2E7FE8`, the lightest
still that clears the rule, and **moved back deliberately once the wall was
explained** — so this is a pick with the numbers in hand rather than a default
that survived.

Rendered at the shipped 0.60× so the colour was judged at the size it ships at:
`~/Kamome-films/2026-08-29-badge-060-blues/`.

| hex | token L | disc | ring + gull | badge's own | terrain | disc vs terrain |
|---|---:|---:|---:|---:|---:|---:|
| `#0B4FC4` deeper | 0.286 | 64.9 | 217.1 | **152.2** | 193.5 | 128.6 |
| `#1D6FE0` today | 0.399 | 89.1 | 217.1 | **127.9** | 193.5 | 104.3 |
| `#2E7FE8` lighter | 0.460 | 102.9 | 217.0 | **114.1** | 193.4 | 90.6 |
| `#1D6FE0` on dark | 0.399 | 89.1 | 217.1 | **127.9** | 102.9 | 13.7 |

**The boundary, stated rather than implied.** The ring and gull are white. Against
white, straddling mid-grey needs the disc below **0.50** and the 0.45 separation
needs it below **0.55**, so **0.50 is the wall** and today's 0.399 has **0.101 of
headroom**. `#2E7FE8` at 0.460 is deliberately near it — 0.040 left — so the last
usable step is visible rather than described.

**Direction: deeper and more saturated is free** (darker only widens the
separation; no lower bound). **Markedly lighter is not** — past 0.50 the badge
has no dark half and disappears on a pale map exactly as the white gull did.

**A genuinely light blue is reachable only by inverting the pair** — light disc,
dark ring and gull. The rule is symmetric and already permits it: **verified by
running the guard** against a light disc (0.685) and an ink ring (0.130), which
passes unchanged with no code change. Not built, and the still was deliberately
not rendered — it existed to inform a choice that has now been made. It is
recorded so that **the next person who wants a lighter blue finds the exit rather
than failing a test**.

**Nothing about the badge is open except the size**, which Chiu has explicitly
reserved the right to revisit **from a film**; that one is marked open in
`RecapStyle.fallbackMarkerLengthFraction`'s own comment, where it will be read.

### 6c. ⚠️ KNOWN LIMIT — nothing in this project measures post-grade output

The guard asserts **token** luminance; the viewer sees the frame **after the
film's grade**. The disc is 0.399 as a token and renders at 0.349; white renders
at 0.851. The rule survives the grade — the pair still straddles mid-grey and
stays far apart — but the numbers in the test are not the numbers on screen, and
nothing checks that they stay compatible.

**This is the same class of gap as the golden-frame gates being unable to see
`MapKitSnapshotProvider`** (2026-08-22 finding 2): a property that only exists in
the rendered output, guarded only where the rendered output is not. Named here as
a known limit rather than left implicit in a mismatch between two numbers. The
fallback marker is the first token whose entire job is how it reads against the
finished frame, so it is where the gap first bites.

### 6d. ⚠️ KNOWN GAP — nothing asserts the end card's brand mark

**The same shape as 6c, and found by the same change.** The near-miss in finding
5b — that `drawSeagull` is also the end card's brand mark, so restyling it would
have turned the wordmark's bird into a blue disc — was caught by reading the call
graph, and confirmed on this branch by a second person reading the diff.

**That is the whole safety net.** `RecapMarkerDeckStillsTests` iterates
`VehicleMarker.allCases` and *writes* stills; it asserts nothing about them. No
test anywhere asserts the brand mark's shape, so the guarantee that the end card
still shows a bird currently rests on a human noticing.

**A golden still of the end card would close it.** Not built here — it is a new
gate with its own baseline to agree, and this change is already carrying a
restated guard. Named so it is a gap on record rather than a habit of careful
reading.

### 7. ⚠️ The no-reader token cluster is now **four**, and it is growing one at a time

The badge takes its ring and gull from the new `fallbackMarkerOnDiscColor`, so the
only markers still reading `markerAccentColor` are `.scooter` and `.bike` — and
those are reachable from `RecapMarkerDeckStillsTests` and nowhere else. It is now
in the same state as `markerColor`, `cardColor` and `cardTextColor`.

**Counted deliberately, because that is the point:** `cardColor`,
`cardTextColor`, `markerColor`, `markerAccentColor` — **four** tokens that
nothing renders, plus the five `RecapOverlayRendererTests` assertions that
believe they render against an opaque card. Each arrived separately and was
reported separately, which is how a cluster grows without anyone deciding to keep
it. **Reported, not removed**: it is its own change across four test files, and
the line-art markers are not this change's to delete. The number is here so the
next one to join is the fifth rather than another isolated note.

The fallback-specific token was added rather than reusing `markerAccentColor`
because that token means "handlebars and wheels" on the line-art markers. Two
roles under one name is how `markerColor` ended up with no reader at all.



`Docs/cross-region-journeys.md` requirement 4 — *"the load-bearing one"* — wants a
seagull as the **narrator of an unmodelled crossing**: honest provenance made
visual, *"we know you went from here to there; we do not know how"*. Its own words
are that this answer "must be cheap and **good-looking** rather than a failure
state."

The marker is being styled in the opposite direction: since 2026-08-28 it is
partly a diagnostic, and it has to say *something went wrong* at a glance.

**They are different objects** — the narrator is the `seagull` subject in
`vehicles.json` (omni sprite, `length_fraction` 1.0), the fault is
`VehicleMarker.seagull`, a stroked vector arc from `RecapStyle`. **A viewer cannot
tell them apart**, and that is the collision: the same bird would mean "we could
not classify your crossing" in one film and "the artwork failed to load" in
another. Nobody has decided which reading wins, and the navy pick makes the fault
bird more distinctive, not less.

**Noted at Chiu's instruction; deliberately not designed for.**

---

