# Music leaves Deferred, and every film has it, the free one included

**Status:** Decided (Chiu, 2026-11-03)
**Supersedes:** ledger 2026-08-15 item 4, for music only (chapters and video beads stay deferred); ledger 2026-07-20 (recap visual system), its tier line *free = silent export, premium = in-app track*. Not reopened: 2026-07-20's rejection of bundled copyrighted music.

## Context
- Music has been deferred since 2026-08-15 and called "outside the closeout" since 2026-09-10 (VERIFIED, `Docs/decisions.md`). The source is being made at the desk (`Docs/handoff-music-rethink.md`), and the app half is designed in `Docs/handoff-music-in-the-film.md` (PR #357).
- No paywall exists, so "premium" had nowhere to live (VERIFIED: no purchase code in `App/` or `UI/`).
- The repository is now private (Chiu, 2026-11-03). Bundled tracks committed here are no longer published by the repository itself. They are still extractable from the shipped app.

## Decision
Chiu, 2026-11-03: 「音樂移出 Deferred，免費版也要有音樂」. On the repository: 「repo我已經關起來了」. On defaults: 「預設值等音樂做好再來看」.
1. **Music is in scope.** It is built as `Docs/handoff-music-in-the-film.md` §8 lays out, one PR each.
2. **Every film can carry music, free or not.** No tier gates it.
3. **Defaults wait for the music.** These are the style for unlisted countries, whether 自動 is on, and whether the silent switch silences the player. They are decided once the tracks exist.

## Rejected
- **Free = silent, premium = music** (2026-07-20). Chiu's call. A film is the product's public artefact, and a silent one is the weaker artefact.

## Consequences
- `Docs/current-state.md` no longer lists music under Deferred.
- Still owed before code: Chiu confirms the AVFoundation confinement change (handoff §3.3, `CLAUDE.md` rule 2) and the desk-only Python dependencies (§5).
- The private repository does not relax §0. Location data stays out of commits, issues and PRs as before.
- Never register Kamome's tracks with a Content ID service, so that a shared film is not claimed against its maker (handoff §7).
