# Known bugs and accepted cosmetic costs

Three standing items: an import bug that is understood and not worth fixing yet,
an open modelling question about `RecapMode`, and one cosmetic tradeoff Chiu has
seen and chosen to keep.

*Moved verbatim out of `HANDOFF.md` on 2026-08-31 when that file was put on a
300-line budget (`Scripts/check-doc-budget.sh`). Nothing was edited; `HANDOFF.md`
carries the live summary and points here.*

---

## 🐛 Known and not fixed — the import date range clips at timezone edges (2026-08-18)

**Symptom you will meet:** a photograph taken early on the first morning of a
trip, or late on the last night, is missing from an imported trip — and the date
range plainly covers that day.

**Cause.** A photo's `creationDate` is an absolute instant. `ImportFlowModel.dayBounds()`
turns the picked days into instants with `Calendar.current`, which is the
*device's* zone at the moment of import. Import an Iceland trip while sitting in
Taiwan and the day boundary moves by eight hours, so "1 August" means 1 August in
Taipei — clipping the Icelandic small hours at each edge of the range.

**Why it is not fixed here.** Doing it properly needs each photograph's own
timezone, which PhotoKit does not hand over with `creationDate`; it would mean
reading EXIF `OffsetTimeOriginal` per asset, or inferring the zone from the
photo's coordinates. Both are real work, and the clipping is small — hours at two
edges of a multi-day range.

**What to do if it bites.** Widen the picked range by a day at each end; the
clustering drops the extra photos anyway if they are not part of the journey.
Written down so the next person meeting a missing first-morning photo does not go
hunting for a clustering bug that is not there.

**Deliberately correct, do not "fix":** `dayBounds` widening the end to that
day's last second (there is no "lost the last day" bug), and the `min`/`max` swap
that makes an inverted range harmless.

## Open question — RecapMode may be two axes, not one (Chiu 2026-08-06)

`RecapMode` is being introduced as a two-case enum (`highlight` | `full`).
**Deliberately no placeholder cases**: every `switch` over it is exhaustive with
no `default:`, so the compiler forces every call site to be revisited when a case
is added. That is the extensibility mechanism — not speculative cases sitting
unused.

The note worth keeping: the next variant Chiu has in mind — *full stop coverage,
zero photographs* — mixes **two independent axes**:

| axis | today's cases differ on it |
|---|---|
| which stops survive | `highlight` keeps ~11, `full` keeps all |
| how many photographs each gets | `highlight` gives 3, `full` gives 0–3 |

"Full stops, no photos" is the first combination that needs one axis without the
other, and a third case would encode a *pair* of choices as a single name. If a
fourth follows, `RecapMode` should probably split into two orthogonal enums rather
than grow. **Not acting on this now** — recorded so the pressure is recognised
when it arrives instead of being rediscovered.

## Known cosmetic tradeoff — flat glacier (Chiu 2026-08-06: leave it)

`Config/RecapThemes/modern-minimal.json` draws the `ice` layer **opaque**
(`#4e5c64`) to kill the pale cross over Vatnajökull — a z6 tile seam where the ice
polygon runs into the tile buffer and both neighbours draw the overlap
(diagnosed `71caf77`). An opaque fill cannot double-blend.

The cost: `hillshade` is layer 1 and `ice` is layer 5, so **the glacier renders
flat, without terrain texture**. Chiu has seen it and chosen to keep it for now —
cosmetic polish, not urgent. The proper fix is clipping the landcover buffer in
Planetiler and rebuilding all four regions, which keeps translucency; do not do
that rebuild without asking.

