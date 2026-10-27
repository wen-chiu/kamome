# About opens with the app and speaks plainly, and the first-run notice drops 中繼 and 金鑰

**Status:** Decided (Chiu, 2026-10-26)
**Supersedes:** the hop-sentence wording of ledger `2026-09-05 (b)` §3 (the relay named as 「中繼」, holding 「金鑰」); the order of `AboutView`, never ruled on before (S2's placement, `Docs/release-readiness.md`)

## Context
A first-time-user walk on 2026-10-10 (#293, VERIFIED on screen and in `AboutView.swift`): 「關於與隱私」 opened on eight terrain licences in accent-blue link text, then privacy written for an engineer (z14 / z13, User-Agent, headers). It never showed the app's name, icon or version, or a way to send feedback or rate the app. The first-run notice said 「卡摸咩的中繼（金鑰放在那裡）」. Separately (#305, VERIFIED from source), `privacy_control` said you decide what is sent by what you import, but Footprints asks Apple to name every journey it finds with no import, starting when Footprints is opened (`HomeView.show`, `FootprintsView.task` → `JourneyDiscoveryModel.refresh`).

## Decision
Chiu, 2026-10-26 (#293, #305):
- About's order: name, icon and version → privacy in plain words, with the technical detail behind a 「詳細說明」 row → feedback, linking to https://wen-chiu.github.io/kamome-site/support/ → rating, through the App Store write-review link (Apple ID 6813758768, Chiu 2026-10-27) → map and terrain credits → open-source licences.
- The first-run notice drops 中繼 and 金鑰 and still says once that importing contacts a third party (ADR 2026-09-05 (b)).
- `privacy_control` gains #305's sentence. The site's policy page is Chiu's, with a new effective date.
- The final wording comes back to Chiu as one table (#118).

What the code now does:
- The plain half on About: `privacy_intro`, the hop sentence, `privacy_control`, `privacy_share`, then 「詳細說明」 and the policy link. `PrivacyDetailView` carries the server's detail, the two payloads, the tiles and retention, unchanged and in the same order.
- The hop sentence names the relay as Kamome's server; that it holds the key moved into `privacy_relay_detail`, so no fact left the app.
- Diagnostics was not in Chiu's list. It sits after rating (the file a tester sends with feedback) and before the credits. INFERRED placement; Chiu may move it.
- Every credit string is unchanged, word for word (Geoapify, OpenStreetMap, Copernicus); only the section moved.

## Rejected
- **Keeping 中繼 and naming no server**: the relay is a party between the phone and Geoapify, and a notice that skips it understates where positions go (Chiu 2026-09-04).
- **#305's example sentence, "It starts only when you tap Find my journeys"**: false once photo access is already allowed, because opening Footprints starts the scan. The draft says it begins when Footprints is opened.
- **Raising `FirstRunNotice.version`**: what is sent and where it goes did not change, only the words.

## Consequences
- New keys `about_version`, `about_feedback`, `about_rate`, `privacy_details`. Changed values: `privacy_hop_relay`, `privacy_relay_detail`, `privacy_control`. All are drafts for #118.
- `LocalizationTests.testTheHopSentencesNameEveryPartyThatHandlesACoordinate` is restated: the extra party is asserted as Kamome's server, not as the word "relay". `AboutTests` holds the order, the two links, the header and the plain first-run words.
- Owed to Chiu: the site policy's sentence (in the implementing PR), and the wording table.
