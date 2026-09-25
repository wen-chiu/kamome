# Handoff — Vision auto-pick (ADR 2026-09-25 (c))

**State, 2026-09-25.** Code done, `./check.sh` green on the simulator. **Never run on a phone.**
Every device number in the ADR's table is UNKNOWN until the steps below are run. The pick itself
is safe to ship without them: with no analysis, or with analysis that found nothing, the film
picks exactly as before (VERIFIED, `PhotoSignalPickTests`).

## What exists

| Piece | Where |
|---|---|
| Pure pick with signals | `Core/ImportKit/PhotoDeckSelector+Signals.swift`, `PhotoSignal.swift` |
| Schema v11 `photo_analysis`, reads, delete sweep | `Core/Persistence/PhotoAnalysisRecord.swift` |
| Vision on one photograph | `App/Services/PhotoAnalyzer.swift` |
| Background run, per trip, single flight | `App/Services/PhotoAnalysisCoordinator.swift` |
| Trip switch + utility-not-counted | `RecapComposer.photoInputs` / `analysisInputs` |
| Tunables (all INFERRED) | `Config/TrackingConfig.json` → `photo_analysis` |
| DEBUG probe with before/after | `UI/TripDetail/PhotoAnalysisProbeView.swift` |

## ⚠️ Device steps — the physical phone, a Debug build, the Iceland trip

1. Open the Iceland trip. Trip Detail → ⋯ → **Photo analysis probe**.
2. **Measure — on device only.** Wait for it to finish (it counts). Screenshot the numbers. This is
   what the background run does: `local` = full image on the phone, `thumbnail` = only Photos'
   own thumbnail (original in iCloud), `none` = no pixels.
3. **Measure — allow iCloud.** Screenshot again. `network` rows are downloads; their fetch time is
   the iCloud cost. (Bytes are not measured: `requestImage` does not report them.)
4. Scroll: every film stop shows **time** (the old pick) above **analysed** (the new one).
   Screenshot the stops that changed — this is the before/after the ADR owes Chiu.
5. The same lines are in the log as `photo-probe:` (About → Export diagnostics), numbers only.

Both measure buttons **write the rows**, so after step 3 that trip's analysis is what an
iCloud-allowed run would produce, not what the shipping background run would. Delete and
re-import the trip to go back.

## What the numbers decide

- **Per-photo time × photos per trip** → whether a background run finishes while the person is
  still looking at the trip, or needs `BGProcessingTask` (not built).
- **`thumbnail` share and how its decks compare with `allow iCloud`** → whether
  `allow_network` false leaves the feature useful on an Optimise-Storage phone. Turning it on is
  Chiu's call (cellular data, unasked).
- **Consecutive-distance histogram + the decks** → `duplicate_distance`. Too low: bursts survive.
  Too high: different views at one stop collapse.
- **Score quantiles + the decks** → whether aesthetics suits travel photographs; only then
  consider quality in stop ranking (ADR point 4).
- **On an iOS 17 phone** the aesthetics line reads `—`: only screenshots and bursts change.

## Not done

- No progress shown to the person; the export sheet just re-reads when a run finishes.
- An export and a run at once: not measured (ADR table, INFERRED).
- `PhotoAnalysisVersion.current` bumps re-analyse everything and revert every trip to the
  time-based pick until done — by design, worth knowing before bumping it.
