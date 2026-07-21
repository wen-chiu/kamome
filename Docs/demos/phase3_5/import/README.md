# Replay MVP §1 — Photo EXIF Import: S1 UI + honest provenance

Artifact for `handoff-P3.5.md` §1 (the S1 UI + provenance-label half; the import
**engine** landed earlier and is proven by CI — see below). Captured
2026-07-21 in the iPhone 17 Pro simulator (Xcode 26.6). Kamome build
`com.chiu.kamome.dev`.

## What these show

| Shot | Screen | Proves |
| --- | --- | --- |
| `01-home-imported-badge.png` | S1 Home | `Import from photos` is the hero action; live capture (vehicle picker + Start Journey) is demoted to a secondary "Record a new trip live" section; an imported trip card carries the **`From photos`** provenance badge (§3) — never "verified". |
| `02-import-sheet.png` | Import sheet | Date-range selection (From / To) as tappable summary rows, the **7-day default range** driven by `import.default_range_days` (Jul 14 → Jul 21), the privacy footer ("Photos are never copied or uploaded"), and the `Import` action. Each row expands an inline calendar that **collapses once a day is picked** (shows the selection, doesn't leave the picker hanging open); picking a start date **snaps the end onto the start's month** if it drifted, so the "To" calendar opens on the trip's month — device-test feedback 2026-07-21. |
| `03-trip-detail-provenance.png` | S3 Trip Detail | An imported trip is **first-class** — same map / stats strip / stop pins / photo badges / timeline / recap film button as a recorded trip — plus the **provenance note**: "This trip was reconstructed from your photos' place and time — not a recorded track." |

## How they were produced (deterministic, no faked pass)

- The **import engine** (clustering → `saveImportedTrip` → best-effort OSRM
  snap) is proven end-to-end in CI by `Tests/AppTests/ImportPipelineE2ETests`
  (`testImportedTripFlowsThroughRecapComposer`) + `PhotoImportClustererTests` —
  synthetic geotagged photos → an `imported_photos` trip that flows through
  `RecapComposer` unchanged. That is the fixture the handoff §1 DoD asks for.
- Shots 01/03 use a DEBUG seed (`-demo-seed-import`, `DemoSeeder.seedImported`)
  that writes an `imported_photos` trip through the **real** persistence path
  (`TripRepository.saveImportedTrip`, `segment.source = exif`, same call
  `ImportService` makes). Photo refs intentionally dangle (asset ids resolve to
  nothing), so thumbnails take the §3 graceful-placeholder path — the **labels**
  are what these shots verify, and they render off real `trip.source` data.
- Shot 02 uses `-demo-open-import` to present the real `ImportSheet`.

## ⚠️ Needs the physical device — NOT faked here (flagged per §0)

The one step these sim shots do **not** exercise live is the PhotoKit
date-range fetch + the Limited Photo Library grant, because **simctl cannot
pre-answer the iOS 26 photo-access prompt and cannot seed geotagged assets**
reliably (dev-Mac toolchain note; `Docs/device-test-P3.md`). On a real device
the flow is: tap `Import from photos` → pick dates → iOS photo-access prompt →
`PhotoLibraryImportSource` fetches geotagged assets → `ImportService.importTrip`
→ push to S3. Two items must be confirmed on hardware and are **not** marked
passed:

- **Full import round-trip from real photos** (real EXIF GPS + timestamps →
  reconstructed trip). Folds into the Replay MVP three-trip release gate (§6).
- **Limited Photo Library path** — `ImportSheet` shows the "Select More Photos"
  section (`presentLimitedLibraryPicker`) only once access is `.limited`; that
  it appears and re-imports against the grown selection is a **Replay MVP gate
  item** (handoff §6) and needs the device.

The friendly `notEnoughGeotaggedPhotos` error and the denied-access error are
wired (`ImportFlowModel.Failure`), but their live triggers are also device-path.
