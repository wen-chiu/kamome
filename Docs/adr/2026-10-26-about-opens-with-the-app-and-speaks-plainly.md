# About opens with the app and speaks plainly, and the first-run notice drops 中繼 and 金鑰

**Status:** Decided (Chiu, 2026-10-26; wording and the open points ruled 2026-10-28 on PR #323)
**Supersedes:** the hop-sentence wording of ledger `2026-09-05 (b)` §3 (the relay named as 「中繼」, holding 「金鑰」); the order of `AboutView`, never ruled on before (S2's placement, `Docs/release-readiness.md`)

## Context
A first-time-user walk on 2026-10-10 (#293, VERIFIED on screen and in `AboutView.swift`): 「關於與隱私」 opened on eight terrain licences in accent-blue link text, then privacy written for an engineer (z14 / z13, User-Agent, headers). It never showed the app's name, icon or version, or a way to send feedback or rate the app. The first-run notice said 「卡摸咩的中繼（金鑰放在那裡）」. Separately (#305, VERIFIED from source), `privacy_control` said you decide what is sent by what you import, but Footprints asks Apple to name every journey it finds with no import, starting when Footprints is opened (`HomeView.show`, `FootprintsView.task` → `JourneyDiscoveryModel.refresh`). And `privacy_recorded_body` said a recorded path is never sent, while merging two recorded trips routes the gap between them (VERIFIED: `TripMerger` adds a two-point `mergeGap` leg, which `RouteMatchService` routes like a photo leg).

## Decision
Chiu, 2026-10-26 (#293, #305):
- About's order: name, icon and version → privacy in plain words, with the technical detail behind a 「詳細說明」 row → feedback, linking to https://wen-chiu.github.io/kamome-site/support/ → rating, through the App Store write-review link (Apple ID 6813758768, Chiu 2026-10-27) → map and terrain credits → open-source licences.
- The first-run notice drops 中繼 and 金鑰 and still says once that importing contacts a third party (ADR 2026-09-05 (b)).
- `privacy_control` gains #305's sentence. The site's policy page is Chiu's, with a new effective date.

Chiu, 2026-10-28, on PR #323:
- Diagnostics stays after rating and before the credits. The Footprints sentence says naming begins when Footprints is opened. The rating row stays; it works once the app is public.
- The credit rows are quiet: footnote type in the secondary text colour, still links, every word unchanged.
- `privacy_recorded_body` names the merge exception: the end of one trip and the start of the next are sent. The first-run notice does not change for it.
- The hop sentence says the server keeps none of it: 「（不留存內容）」 / "which keeps none of it". To keep the English card within its ceiling, `privacy_intro` lost "To draw the map, " and "the positions along your route" became "your route's positions". No fact was removed.
- The rest of the draft wording is approved as written.

What the code does: the plain half (`privacy_intro`, the hop, `privacy_control`, `privacy_share`) sits on About; `PrivacyDetailView` carries the server's detail, the two payloads, the tiles and retention, in their old order. That the server holds the key moved into `privacy_relay_detail`, so no fact left the app.

## Rejected
- **Keeping 中繼 and naming no server**: the relay is a party between the phone and Geoapify, and a notice that skips it understates where positions go (Chiu 2026-09-04).
- **#305's example sentence, "It starts only when you tap Find my journeys"**: false once photo access is already allowed.
- **Saying only that import sends positions** (the draft of 2026-10-27): Chiu, 2026-10-28, did not accept a notice silent on merges.
- **Raising `FirstRunNotice.version`**: what is sent and where it goes did not change, only the words.

## Consequences
- New keys `about_version`, `about_feedback`, `about_rate`, `privacy_details`. Changed values: `privacy_hop_relay`, `privacy_relay_detail`, `privacy_control`, `privacy_recorded_body`, and the English `privacy_intro`.
- `LocalizationTests.testTheHopSentencesNameEveryPartyThatHandlesACoordinate` is restated: the extra party is asserted as Kamome's server, not as the word "relay" (agreed by Chiu 2026-10-28). `AboutTests` holds the order, the links, the header and the first-run words. `RouteMatchRecordedLegTests.testAMergeGapLegIsOfferedAndTheNoticeSaysSo` holds the merge exception in code and in copy.
- Owed to Chiu: the site policy's sentence, which he edits himself.
