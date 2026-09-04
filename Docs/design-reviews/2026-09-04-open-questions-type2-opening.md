# Request for review: four visual questions in the type-2 opening

**This is a request, not a review** — engineering asking for four judgements it
should not make. Written 2026-09-04 alongside ADRs 2026-09-03 and 2026-09-04.
The format is `DESIGNER.md`'s; the verdict sections are left for whoever answers.

**Jurisdiction: the film** (`DESIGNER.md` §1). Every question below is inside
decisions already paid for with measurements, so none of them reopens a decision
— each is a value or a moment those decisions deliberately left to an eye.

## Evidence

Renders `~/Kamome-films/type2-2026-09-04b/`, `kamome-auckland-crossing.mp4` and
`kamome-ishigaki-crossing.mp4`, 60.0 s each. Frames extracted beside them at
0.04 / 3.0 / 5.0 / 6.6 / 8.0 s, plus 2.9 / 3.1 / 6.5 / 6.7 s for question 3.
Both are **synthetic fixtures** — no §0 exposure.

---

## 1. The boarding pass's orange is a second accent

The card ships Chiu's mockup hex **`#FF6A3D`**. The film's accent is
**`#FF8A5B`** (`RecapStyle.routeAccent`), and that token's own comment says it
exists so the film has *"one accent rather than three near-misses"*.

Both are deliberate: Chiu supplied `#FF6A3D` as part of 登機證樣式（完整）, and
engineering shipped the target rather than quietly substituting the film's value.
**Whether the two collapse to one is a visual decision.** Frame: `akl-8.0s.png`,
the pass against the trail's accent elsewhere in the same film.

## 2. The `DISTANCE` icon does not read as a plane

The bottom row's first field is marked with a small grey dart. At its drawn size
(~26 px at the 1080 reference) it reads as a triangle, not an aircraft. The
mockup's icon is a recognisable side-view plane.

Options engineering can implement either way: redraw the glyph, drop the icon and
keep the label, or bundle a real icon set. Frame: `akl-8.0s.png`, bottom left of
the card.

## 3. 🔴 The origin mark cuts out for 3.59 s — is that a flicker?

**The behaviour, and it is deliberate.** The departure airport's stop pin and the
flight's origin mark are the same point, so exactly one is ever drawn (ADR
2026-09-04 §3). The origin mark and its `TAIWAN` label are therefore absent for
the departure stop's whole scene.

**On `auckland-crossing` that is 3.00 s → 6.59 s.** Measured, not estimated:

| | |
|---|---|
| 0.00 – 3.00 s | both marks, both names |
| 3.00 – 6.59 s | **origin gone**; the stop's own pin and label |
| 6.59 – 10.59 s | both marks again, and the crossing |

⚠️ **It is a hard cut on both edges, not a cross-fade.** `holdingStop` is a
boundary test, so the mark vanishes in one frame while the thing replacing it —
the stop label — fades in over `deck_label_lead_s`. Frames `flicker-2.9s.png` /
`flicker-3.1s.png` and `flicker-6.5s.png` / `flicker-6.7s.png` are the two edges.

**The question:** does that read as a handoff or as a glitch? If it is a glitch,
the fix is a cross-fade between mark and pin, which is cheap and is the idiom the
stop label → deck handoff already uses.

## 4. Which name wins at the departure airport

Because the name follows the mark, `TAIWAN` is on screen 0–3.00 s and after
6.59 s, and absent in between. The alternative is to keep the country name up
throughout — and then it stacks with the airport's own stop name, reading
**TAOYUAN over TAIWAN** at the same point.

Engineering shipped *"the name follows the mark"* and did **not** choose between
them, because which name wins at a place that has two is a design question.
Frames: `akl-0.04s.png` (country alone) and `akl-5.0s.png` (stop name alone).

## 5. Noted, not asked

At 6.59 s the plane begins its crossing **on top of** the origin mark for a few
frames — they are the same point by construction. Visible in `akl-6.6s.png`.
Included because it is in the same region of the frame as questions 3 and 4; it
may be correct as it stands (an aircraft departing from where the mark is).

---

### Verdict:
### What Works
### Blocking (must fix before ship)
### Recommendations (fix before milestone)
### Polish (batch later)
### Kamome Identity:
### My Recommendation
