# The release artifact scan needs no key

**Status:** Decided (Chiu, 2026-10-02)
**Supersedes:** ledger entry "2026-09-12 (d)" (`Docs/decisions.md`)

## Context

`Scripts/release/check-archive.sh` proves the routing key is not inside a built
`.xcarchive`/`.ipa` — the only proof of that (ledger "2026-09-02" §S1). Since
2026-09-12 it did this by taking the real Geoapify key from
`KAMOME_ROUTING_API_KEY` and matching it byte-for-byte across every file,
binaries included, and refused to run without it.

Chiu, reviewing the submission sequence: *「為什麼檢查打包出來的檔案裡沒有 key 用一個真
的 key？⋯ 就單純檢查裡面 code 裡面沒 key 不行嗎？浪費時間增加可能的錯誤。」* The exact scan
made the release procedure put the real secret into a shell to run one command,
then asked for that same secret to be rotated — the gate's own method was a
reason to handle the thing it existed to keep out of reach.

## Decision

`check-archive.sh` takes no key. Its first check is a **shape** scan instead of
an exact one: a 32-hex run, bounded by non-hex bytes (so a SHA-1 or a dash-free
UUID doesn't false-positive), inside every Mach-O file found under a `.app` in
the artifact — the main executable and each framework's, not just
`Info.plist`. It fails, rather than passes, if no executable is found to scan.
The other four checks (`KamomeRoutingAPIKey` absent from `Info.plist`, the
shipped `matching.base_url`, the local-network permission, the side-load
switch) are unchanged.

**Consequence for S7 (`Docs/release-readiness.md`):** rotating the Geoapify key
no longer has to follow the artifact check — the check doesn't use the key, so
there is no order to keep. S7 is owed because of IPAs and build logs already
out, independent of this archive.

## Rejected

- **Keep the exact scan, document the risk better.** Does not remove the
  defect Chiu named: the procedure still puts a real secret into a shell for a
  release check to run.
- **Drop the binary scan, keep only the text-resource scan.** That is what
  shipped until this ADR and is weaker than intended: the 2026-08-20 incident
  (ledger "2026-09-02") was a key in a shipped `Info.plist`, read with
  `PlistBuddy` — a resource, not a binary — but nothing then checked the
  executables at all. The shape scan now covers both.

## Consequences

**What is given up:** the exact scan matched the real key byte for byte, so it
could not miss it whatever its shape. The shape scan can — **a key that is not
32 lowercase hex passes.** **INFERRED** that a rotated Geoapify key keeps that
shape; the cheapest way to settle it is to look at the new key when Geoapify
issues it.

**VERIFIED 2026-10-02**, on `Kamome 0.2.1 (638).xcarchive`, with no key in the
environment: the gate passes; the shipped executables (main + MapLibre.framework)
carry no 32-hex run. Measured noise that set the scan's scope to Mach-O files
only: the `.dSYM` (not shipped) carried thousands of 32-hex runs, and
`MapLibre.framework/Assets.car` carried a handful — neither a credential.
**Positive-controlled** on a copy with a planted fake key appended to the main
executable: fails with the key's path named. `check.sh`'s `env -u
KAMOME_ROUTING_API_KEY` guard on the test stage is kept (it covers a stale
export, not this gate) with its comment updated.
