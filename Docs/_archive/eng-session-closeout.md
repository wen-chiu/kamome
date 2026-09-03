# Engineering session — close out sprites and the API key

**Status: EXECUTED in substance (2026-08-21).** The sprite tree is resolved —
committed as `6cc6543` (46 re-centred files) and `c0d4583` (reindeer sets with
manifest entries); `git status` clean of PNGs, VERIFIED. The key: Chiu confirms
it is fine (owner report, informal — no verification log exists). The
destructive-command warning below is moot now that the tree is clean; kept as
the record of why it existed.

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

Then read, in this order:
- `CLAUDE.md` — current state and §0.
- `HANDOFF.md`, "Findings — PO/Architecture session (2026-08-20)", **item 7** —
  it was corrected today and describes the sprite tree accurately.
- `Docs/pre-launch.md` — "The order to ship in", and the key section.

## 🔴 Read this before your first command

The working tree on `main` holds **18 untracked PNG files that exist nowhere
else** — two complete sprite sets — and **46 modified PNGs** whose committed
versions are a different, earlier pass. There is no copy of any of it.

**Therefore, for this whole session:** no `git reset --hard`, no `git clean`, no
`git checkout -- <path>`, no `git stash` of untracked files, and no `git add -A`.
Stage explicit paths only. A previous session chained
`git checkout main && git reset --hard origin/main` next to uncommitted work and
was saved only by the checkout failing. Do not repeat that.

If you believe a destructive command is genuinely required, stop and ask.

## Task 1 — the sprite tree: work out what it is, then commit it correctly

A merge session reported this art as landed in `4ed8774`. **It is not** — that
commit carried an earlier pass. What is actually uncommitted is three different
kinds of change, and they are not one commit:

1. **46 modified PNGs** across boat, car-toy, car-white, drone, plane-3d —
   consistent with a re-run of `Tools/center-sprites.py`, which writes in place.
   Same shape as `4ed8774`: pixels only, every set already declared.
2. **`car-red/logo.png`**, which is inside that 46 but is not routine.
   `Vehicles/README.md` says car-red is the **reference proportion the whole
   catalogue is sized against**, and it is also the default subject (a NULL
   `subject` column means car). Changing it can move every other set's apparent
   size.
3. **`reindeer-cute/` and `reindeer-deer/`** — two entirely new sets, 9 files
   each, **untracked**, and **`vehicles.json` does not mention reindeer.**

**Establish the facts before deciding anything.** Start with
`./Tools/center-sprites.py --check` over the committed art and over the working
tree, and report both. The tool's own docstring says `--check` reports without
writing and should always be run first.

Then answer these, with evidence rather than inference:
- Does the working tree's art satisfy the tool's two invariants (one canvas size
  per set; content centred) **better, worse, or the same** as what is committed?
  That decides whether this is progress or a stray run.
- Does `car-red/logo.png` still carry the reference proportion the README
  documents? If it does not, say what changed and **stop** — that is not an asset
  decision.
- What are the reindeer sets **for**? They are currently unreachable art:
  `vehicles.json` has no entry, so nothing can select them, and
  `VehicleCatalogTests` pins the choosable subjects on purpose
  (`testTheSubjectsAUserMayChooseAreExactlyThese`). There is an existing pattern
  for art that ships without being choosable —
  `testTheCrossingSetShipsAsArtButNeverAsAChoice` — but which of the two a
  reindeer is, is a **product decision for Chiu, not yours.** Report and ask.

**Do not add a manifest entry, do not touch a pinned test, and do not delete art
to make a test pass.** If a test's expectation genuinely moved, `Arch.md` §7.5:
the reason goes in the commit message, and "it passes now" is never that reason.

Split into commits along the three lines above, in that order, and report the
test count before and after (§7.4).

## Task 2 — close out the API key, by verifying rather than trusting

The key path is already merged: `cb58686`, `Config/Base.xcconfig` →
`Info.plist` → `AppConfig`, with `apiKey` deliberately outside
`Matching.CodingKeys`. That work is reviewed and sound. **What is not done is
proving it, on `main`, after history was rewritten.**

The branch was force-pushed to split one commit into three. Local history was
therefore replaced. So:

1. **Verify the key never entered a *pushed* commit** — not only that it is
   absent from the current local history. Force-pushed commits remain reachable
   by SHA on GitHub, so a local `git log -S` is not sufficient evidence. Check
   the remote's reflog/events, or state plainly that you cannot and say what
   would settle it.
2. **Verify the key is absent from a built artefact's source inputs and from
   every tracked file on `main`**, and report the exact commands.
3. `.gitignore` and `Config/Secrets.xcconfig.example` — confirm a fresh clone
   cannot accidentally commit a real key, and that the example file cannot be
   mistaken for a working one.
4. **Add the guard that stops this recurring.** Today nothing prevents a key
   being committed tomorrow; the protection is a convention. Propose the
   smallest mechanism — a CI check or a test — that fails when a key-shaped
   secret is tracked. Per `Arch.md` §2.4, give 2–3 options and pick one before
   writing it.

**Out of scope, and do not start it:** the Cloudflare Worker. The key being
inside the IPA is a real submission blocker (`Docs/pre-launch.md`), but it
belongs with the routing migration, which is another session.

Also note: `Matching.apiKey` is carried but no provider reads it yet. That is
correct and deliberate — whether the key goes in a query parameter or a header is
a provider fact, settled in the migration PR. **Do not wire it here.**

## Reporting

`Arch.md` §12 first, before any code: Problem → Boundary → Options → Decision →
Verification plan, for each task separately.

`Arch.md` §14 at the end: "Ready for review", what was verified and at which
level of §8, exact commands with full output, and what is still unknown. Label
anything you could not verify as **Blocked** or **Unknown** rather than implying
it passed.
```
