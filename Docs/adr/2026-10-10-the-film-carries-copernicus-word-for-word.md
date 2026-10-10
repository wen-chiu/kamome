# The film carries Copernicus's acknowledgement word for word, and its credit wraps

**Status:** Decided (Chiu, 2026-10-10)
**Supersedes:** nothing; settles the conflict #114 recorded inside ledger entry "2026-09-18 (f)"

## Context
Ledger 2026-09-18 (f) says the Copernicus wording "is prescribed and may not
shorten". PR #77 shipped the film credit as `EU-DEM (Copernicus)` on an INFERRED
reading of Delegated Regulation 1159/2013 Art. 3. Two sources at the same level
disagreed (#114). `AboutView` already carries the full sentence.

The full sentence is 91 characters. With the frozen OSM half, a European film's
credit is ~150 characters, wider than a 1080 frame at the credit's 24 px
(VERIFIED by `RecapMapCreditTests.testTheLongestCreditWrapsInsideTheFrame`,
which fails on one line). The credit is never shrunk to fit (ADR 2026-09-13).

## Decision
Chiu, 2026-10-10: 「改114」. The ADR's reading wins.
- EU-DEM's film credit is the prescribed sentence:
  *Produced using Copernicus data and information funded by the European Union - EU-DEM layers*.
- The credit wraps instead of running off the frame: whole ` · ` clauses per
  line where they fit, words where one clause alone does not. Same corner, same
  type, same plate; more than one line keeps the plate's corner radius.
- Terrain credits are joined by ` / ` (was `/`), so a line can break between them.

## Rejected
- Smaller type for European films: a credit that shrinks to fit could shrink to
  nothing, and 24 px is the size judged legible.
- A second, credits-only frame at the end: the obligation binds the work, and a
  clip cut from the middle of a film would lose it.

## Consequences
- Films whose extent touches EU-DEM's box (Europe, Iceland, and long flights
  into it) draw the credit on two to four lines. Every other film is unchanged.
- Place names keep clear of one credit line only. On a wrapped credit a name
  near the bottom edge can sit under it; the credit is drawn last and stays
  legible. Owed: a render of a European film for Chiu.
