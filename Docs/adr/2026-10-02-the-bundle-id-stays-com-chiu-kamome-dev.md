# The App Store bundle id stays com.chiu.kamome.dev

**Status:** Decided (Chiu, 2026-10-02)
**Supersedes:** spec §11.1 item 5 (the id as a placeholder to be renamed)

## Context
`project.yml` called `com.chiu.kamome.dev` a placeholder "until the trademark
check clears" (spec §11.1), and the launch review of 2026-09-30 raised it as
#148: once a version is released on the App Store, the id can never change.
On 2026-09-30 Chiu chose `com.chiu.kamome`, and PR #154 first carried that
rename. It now carries this decision instead.

What was not known then (VERIFIED 2026-10-02, Chiu's screenshot of App Store
Connect): the record "Kamome: Cinematic Trip Recap" already exists under the
`.dev` id, with the store name reserved on it and the bundle id shown as fixed
text. INFERRED from the fixed text: a build has been uploaded to it.

## Decision
Chiu 2026-10-02, shown both paths: *"選 B"*. Kamome ships on the
existing record, and `com.chiu.kamome.dev` is the permanent App Store id.

## Rejected
- **`com.chiu.kamome` on a new record (PR #154's first form):** it needed
  a second App ID and record, the store name handed over from the old record,
  testers re-invited and their trips lost. All of that buys a tidier suffix
  that no user ever sees.

## Consequences
- `PRODUCT_BUNDLE_IDENTIFIER` is unchanged. Its comment no longer says
  placeholder, so the next review does not reopen this.
- `KamomeLog.subsystem` stays `com.chiu.kamome`. The two differ, and that is
  accepted: one is a log filter, the other a store identity.
- A separate internal or beta app, if ever wanted, needs a different id.
- Testers keep their installs and their trips.
