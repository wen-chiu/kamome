# ADRs — one decision per file

From 2026-09-28 every decision is its own file here. `Docs/decisions.md` holds
everything before that and is frozen; find its entries through
`Docs/decisions-index.md`. **The newest entry on a subject wins across both.**

List them, newest last:

    ls Docs/adr/ | grep -v README

## Name

`YYYY-MM-DD-<lowercase-slug>.md`, dated to the **decision** (Chiu's statement),
not to the day it was written. Two decisions on one day are two files.
`Scripts/check-decisions-index.sh` checks the name, the title and the status line.

## Shape — about 40 lines; the reasoning that does not fit goes in the PR

```markdown
# <the decision, as one sentence>

**Status:** Decided (Chiu, YYYY-MM-DD) | Draft | Superseded by <file>
**Supersedes:** <ledger entry "YYYY-MM-DD (x)" or file>, or nothing

## Context
What forced a decision. Measured facts marked VERIFIED, the rest INFERRED or
UNKNOWN with the cheapest thing that would settle it.

## Decision
What is now true. Quote Chiu where the decision is his.

## Rejected
The alternatives, one line each, and why.

## Consequences
What changes in code, config or the snapshot; what is owed (as issues).
```

The implementing session writes it in the PR that implements it, and updates
`Docs/current-state.md`'s "Last synced" line to name it in the same PR.
When a newer ADR supersedes this one, edit only this file's **Status** line.
