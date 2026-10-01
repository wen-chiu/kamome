import Foundation
import KamomeConfig

/// **How long the export has left, from its own measured pace** (Chiu
/// 2026-09-30, issue #151, ADR 2026-09-30-export-time-left).
///
/// Never a prediction made before the export starts: per-snapshot cost has been
/// measured anywhere from 0.72 s to 7.4 s, by device, network and thermal state,
/// so a number shown up front would be off several-fold. This reads only what
/// *this* export has already spent.
///
/// **It counts stations, not frames.** A film's cost is its snapshots, and
/// stations cluster at stop beats — one station can serve a whole held stop,
/// while a crossing arc spends about one station per two frames
/// (`Docs/camera-arcs.md` §9). Frames delivered per second would swing with
/// every beat; stations delivered per second is the rate the phone is paying.
///
/// Pure arithmetic over numbers the caller measures — the elapsed seconds are
/// handed in, never read off a clock here, so every rule below is a unit test.
///
/// **What it does not cover.** The clock starts when drawing starts, so road
/// finding and the iCloud photo download before it are neither counted nor
/// estimated — the download has its own labelled count on the sheet
/// (`RecapView.photoPreloadProgress`). Encoder finishing after the last frame
/// is not a station either; it reads as "less than a minute".
struct RecapExportTimeLeft: Equatable {
    /// What the sheet says.
    enum Reading: Equatable {
        /// "About N minutes left", N ≥ 1.
        case minutes(Int)
        case underAMinute

        /// The whole minutes the reading stands for — 0 for under one.
        var wholeMinutes: Int {
            switch self {
            case let .minutes(minutes): return minutes
            case .underAMinute: return 0
            }
        }
    }

    /// The frame, exclusive, by which each station's frames have all been
    /// delivered, in film order — `RecapSnapshotStations.Station.frames.upperBound`.
    ///
    /// A GIF export delivers only the frames it keeps, so a station there is
    /// counted done at the next kept frame at or past its end: at most one
    /// station late, and a station with no kept frame (never fetched) is counted
    /// with its neighbours (INFERRED from the stride rule; no GIF timing on a
    /// phone exists).
    let stationEnds: [Int]
    let frameCount: Int
    let warmupS: Double
    let riseToleranceMin: Int
    /// What the screen currently shows; nil until the warm-up has passed.
    private(set) var reading: Reading?

    init(stationEnds: [Int], frameCount: Int, pipeline: TrackingConfig.ExportPipeline) {
        self.stationEnds = stationEnds
        self.frameCount = frameCount
        warmupS = pipeline.estimateWarmupS
        riseToleranceMin = pipeline.estimateRiseToleranceMin
    }

    /// Stations whose every frame has been delivered, given the export's
    /// progress fraction (frames delivered ÷ frame count).
    func stationsDone(fraction: Double) -> Int {
        let delivered = Int((fraction * Double(frameCount)).rounded())
        // `stationEnds` ascends, so this is the first station not yet done.
        var low = 0, high = stationEnds.count
        while low < high {
            let mid = (low + high) / 2
            if stationEnds[mid] <= delivered { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Seconds left at this export's own average pace, or nil while there is
    /// nothing honest to say: inside the warm-up, or before a station is done.
    func remainingS(fraction: Double, elapsedS: Double) -> Double? {
        guard elapsedS >= warmupS, elapsedS > 0 else { return nil }
        let done = stationsDone(fraction: fraction)
        guard done > 0 else { return nil }
        let stationsPerS = Double(done) / elapsedS
        return Double(stationEnds.count - done) / stationsPerS
    }

    /// Takes one progress report and returns what the screen should now say.
    ///
    /// **Monotone-ish**: a falling estimate is shown at once; a rising one only
    /// once it exceeds the shown minutes by more than `riseToleranceMin`. The
    /// pace is an average, so it drifts up when one station is slow and back
    /// when the next is quick — without the tolerance the number would flicker
    /// "4 · 5 · 4". A real slowdown (thermal throttling) still gets through.
    @discardableResult
    mutating func update(fraction: Double, elapsedS: Double) -> Reading? {
        guard let seconds = remainingS(fraction: fraction, elapsedS: elapsedS) else { return reading }
        let fresh = Self.reading(seconds: seconds)
        if let shown = reading,
           fresh.wholeMinutes > shown.wholeMinutes,
           fresh.wholeMinutes <= shown.wholeMinutes + riseToleranceMin {
            return reading
        }
        reading = fresh
        return reading
    }

    /// Seconds as the sheet words them: under a minute, else the nearest whole
    /// minute — "about", so rounding rather than rounding up.
    static func reading(seconds: Double) -> Reading {
        seconds < 60 ? .underAMinute : .minutes(max(1, Int((seconds / 60).rounded())))
    }
}
