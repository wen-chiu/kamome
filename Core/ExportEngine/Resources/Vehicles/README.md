# Vehicle assets — the specification for anyone drawing a new set

This folder holds the moving subject of a recap film. Read this before drawing
anything; every constraint here exists because something looked wrong once.

## Two kinds of subject, and they are not interchangeable

| kind | what it is | files | rotates? |
|---|---|---|---|
| `directional` | a vehicle drawn in 3/4 perspective — car, scooter, bike, and later plane and ship | **8** | never at runtime; the renderer *picks* the drawing that faces the heading |
| `omni` | a mark that stands for "you are here" — the Kamome seagull | **1** | never, and it must not imply a direction |

**A directional set is not a rotatable image.** A 3/4 drawing only reads
correctly at the angle it was drawn; spinning one breaks the perspective at every
intermediate angle. That is why there are eight, and why nothing is ever rotated
in code. This was tried the other way and rejected — see
`Docs/handoff-recap-visuals.md` §3.

**An omni mark is not a one-frame vehicle.** It never turns, so it must read the
same travelling in any direction. A bird facing left looks like it is flying
backwards on an eastbound leg.

## Folder convention

```
Vehicles/
  car-red/     n.png ne.png e.png se.png s.png sw.png w.png nw.png  logo.png
  car-blue/    n.png … nw.png  logo.png
  seagull/     omni.png  logo.png
  vehicles.json
```

`logo.png` is the **picker thumbnail** — one representative image per subject, for
the UI that lets someone choose. It is not part of the eight and is never drawn
into a film, so it does not share the set's canvas and carries no direction. Every
selectable subject should have one.

**One folder is one selectable subject.** Its folder name is its id. There is no
nesting and no second level — grouping ("these are all cars") is a presentation
fact and lives in `vehicles.json`, so a set can be regrouped or renamed for the
picker without moving a single file.

Adding a subject is a folder plus one manifest entry. Removing one is deleting
the folder and its entry.

`vehicles.json` carries what a filename cannot: display name per language, the
type it groups under, its kind, an optional size override, and whether it appears
in the user's picker. **That last field matters** — the cross-region plane and
ship will exist as assets before they are user-selectable, and they must never
appear in a picker, because the app chooses them from the journey rather than the
user choosing them.

## Directional sets — the eight drawings

- **512 × 512, transparent background, one canvas size across all eight.**
- **N is the rear view** (driving away from the viewer). **E and W are profiles**,
  nose right and nose left. **S is head-on.** The four diagonals sit between.
- Content centred within roughly **±35 px** of the canvas centre.
- The subject may fill anywhere from about half to three-quarters of the canvas
  depending on direction. **That variation is correct** — a car seen side-on
  really is longer on screen than one seen from behind.

⚠️ **Scaling is by canvas, never by content bounds.** This is why all eight must
share one canvas size: scale by content and the subject *pulses* as it turns,
because the drawing's own bounding box changes with the angle. A test enforces
the shared canvas size; do not work around it.

### Centring is a tool's job, not a prompt's

**Run `./Tools/center-sprites.py <folder>` on every new set. Do not hand-place
anything, and do not trust an image generator to centre.**

The renderer puts the **canvas** centre at the vehicle's position, so a drawing
whose content sits off-centre draws the vehicle away from where it actually is —
and because each drawing is off by a different amount, the subject *jumps
sideways relative to the route as it turns*. That is the defect the tool exists to
make impossible.

It translates content to the canvas centre and sizes one square canvas per set so
the widest drawing fills 74% — car-red's proportion, which keeps every subject's
apparent size comparable at the same `subject_length_px`. **It never rescales
content**, so the honest size variation between a profile and a rear view
survives. Run `--check` first; the write is in place.

Measured when the tool landed (2026-08-16): generated sets were off by up to
58 px, 13.7% of canvas, with content running off the edge on 10 drawings across
three sets. Every set is now within half a pixel — including `car-red`, whose
±35 px offset had been carried as "known and accepted" and is simply gone.

## Omni marks — the single drawing

- **Square canvas, transparent, the mark centred.** The canvas centre is "you are
  here", so anything visually off-centre will read as off-centre for the whole
  film.
- **Symmetric, or near enough that it implies no heading.**
- **A filled shape, not a line drawing.** The mark is small and moving, and thin
  lines mush together at the size it is actually seen. Draw it as a silhouette —
  a solid disc with the subject knocked out of it reads at any size and carries
  its own contrast.
- **It must separate from an unpredictable background.** The map underneath may
  be dark, green, blue or grey, and the mark cannot rely on any of them. Give it
  a light rim or a soft shadow. This is why every map pin in every app has a ring
  or a shadow — it is not decoration, it is what keeps the mark a distinct object.
- **Check it small before shipping it.** View it at roughly 5% and confirm it is
  still one recognisable shape. A mark that only works large is a logo, not a
  marker; the two are different executions of the same identity.

## Colour

The shipped car is **red** deliberately: a saturated warm colour is the one thing
a map almost never uses for a large area, so it stays visible over terrain,
water, roads and parks alike. A new set does not have to be red, but it does have
to answer the same question — *what does this look like on top of a map I cannot
predict?* Dark greens and blues are the two that disappear.

## What the loader guarantees, and what it demands

- **All eight or nothing.** A partial directional set never renders; the subject
  falls back to the car. A missing file is a silent visual bug otherwise.
- Decoded once and cached — the render loop asks every frame, and an export must
  not decode PNGs thousands of times.
- Deterministic: the same trip re-exported produces the same frames. Nothing here
  may become order- or time-dependent.
