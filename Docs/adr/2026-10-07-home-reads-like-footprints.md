# Home reads like Footprints: one trip, one name, one figure, one mark

**Status:** Decided (Chiu, 2026-10-07)
**Supersedes:** 2026-09-23 visit pill on every entry (first visits now unmarked
on the row); extends 2026-09-23 (e) (provenance by exception) to Home

## Context
A pre-release review of 旅程 | 足跡 at the desk (synthetic demo library, zh-Hant
and en, light and dark) found the two segments reading as two apps:
- One trip, two vocabularies: Home "4 個停留點" / "271 km", Footprints
  "3 個地點" / "公里" (VERIFIED, simulator).
- One trip, two distances: Home printed `stats.distanceM` (every trackpoint,
  flights included); Footprints the ground kilometres of Chiu's 2026-09-23 rule.
  The demo trip read 271 km on Home and no distance in Footprints (VERIFIED;
  its legs were never routed at the desk).
- One trip, two provenance rules: Home marked a photo trip, Footprints did not.
- 「初訪」 on 6 of 7 entries; a long name truncated and pushed its dates under
  it; tracking and `.italic()` spread and slanted hanzi; the drawer chevron's
  target was 28 × 20 pt; the large title repeated the segment's own name.

## Decision
Chiu, 2026-10-07: 「A1-A3、7、9 先直接在這個分支改 / 4、5、6、8、10 也同意你可以改」.
- Home rows take Footprints' type (flag + serif name), its words (`journey_km`,
  `journey_places`), its figures (`LegLength.groundMeters(trip:repository:)`,
  shared) and its provenance rule (a recording and the sample marked; a photo
  trip unmarked on screen, said by VoiceOver). A cover photograph leads the row.
- Home's buttons sit in a bottom inset; the list runs the whole height.
- Both segments use an inline title: the segmented control names the page.
- The visit pill appears from a second visit; the drawer still says 初訪.
- Tracking, upper case and italics apply to Latin-script languages only.
- An entry's name wraps to two lines beside its dates; the chevron's target is
  44 pt.

## Rejected
- Footprints falling back to `stats.distanceM`: it counts flights, which
  2026-09-23 refused.
- Tapping an entry to open its drawer instead of the diary: a behaviour change
  the enlarged target makes unnecessary.

## Consequences
Trip Detail's stat card and the film still print `stats.distanceM` (the film
minus flights), so a trip can still show a third figure there — UNKNOWN how
often it differs on a routed trip; a routed real import compared on the three
screens settles it (#242).
