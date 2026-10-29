# A failed map snapshot is asked twice more, from the same source, before the export fails

**Status:** Decided (Chiu, 2026-10-29)
**Supersedes:** nothing. Until now one failed snapshot failed the export, by default rather than by decision (`RecapExportJob+Render.snapshotProvider`, failure paths 3–5).

## Context
- VERIFIED (#330, simulator, Release 1.0.0 (928), 2026-10-28): under heavy load on the Mac, 3 of 72 snapshots failed with `MLNErrorDomain` 6 (a TLS error, reads timing out). The export failed after 3 min 14 s, and the person starts again from 0%. The same export, tried again, finished.
- VERIFIED (2026-10-29, `TileHTTPFailureTests`, loopback server): a snapshot that failed while the tile host answered 503 draws once the host is back. MapLibre does not keep the failure, so asking again can succeed. `TileRequestCoalescer` keeps only `200` bodies, so it does not keep the failure either.
- INFERRED: a road trip is often exported where the signal is weak, so a dropped connection is an ordinary event. UNKNOWN on a phone: how often a snapshot fails on a weak mobile connection. The cheapest check is one export with one bar of signal (`Docs/device-runbook.md` §D, #112).

## Decision
Chiu 2026-10-29, choosing between retrying twice, once, or not at all: *重試 2 次*. Two retries, the first after 2 s and the second after 4 s. Only when all three attempts fail does the export fail.

1. **The same source, never another.** The retry is the same call with the same style, so it draws the same picture. It is not a fallback (`CHARTER.md` §4); the Apple Maps rule of ADR 2026-09-16 is untouched.
2. **Bounded.** Each attempt keeps its own `snapshot_timeout_s`. At the shipped values, a station that keeps failing costs at most 126 s more before the export fails as before.
3. **Cancel is not held.** Before each wait and after it, the retry asks the export's Cancel, and a stopped export is never retried. Cancel is read between frames, and a retrying station has none.
4. **Said in the log.** Each retry logs `snapshot retry n of 2` with the error's domain and code, never its text (a tile URL is a place, §0). The `render cost` line counts `retried`.

## Rejected
- **One retry.** Also bounded, but it gives a connection that drops for a few seconds only one chance.
- **Keep failing at once.** A whole render is lost to one dropped tile.
- **Retry the whole export.** It repeats minutes of work, where one snapshot is seconds.

## Consequences
- `export.pipeline.snapshot_retry_delays_s` = `[2, 4]` in `Config/TrackingConfig.json`; empty turns retries off. Built in `Core/ExportEngine/SnapshotRetry.swift` and `RecapRenderLoop.StationFetcher`.
- Held by `SnapshotRetryTests` (10 tests; 5 fail with the retry removed, watched red) and the new down-then-up case in `TileHTTPFailureTests`.
- Owed on a phone: one export on a weak signal, reading `retried` and `snapshots (n failed)` (#112).
