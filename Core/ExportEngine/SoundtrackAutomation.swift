import Foundation
import KamomeConfig

/// A value over film time, piecewise linear between its points (in log space
/// when `logarithmic`, which is how a filter sweep is heard). Before the first
/// point it holds the first value, after the last the last. Two points at one
/// time make a step.
public struct SoundtrackCurve: Equatable {
    public struct Point: Equatable {
        public let timeS: Double
        public let value: Double
    }

    public let points: [Point]
    public let logarithmic: Bool

    public func value(atS time: Double) -> Double {
        guard let first = points.first else { return 0 }
        guard time > first.timeS else { return first.value }
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if points[mid].timeS <= time { low = mid } else { high = mid - 1 }
        }
        guard low + 1 < points.count else { return points[low].value }
        let from = points[low]
        let to = points[low + 1]
        let fraction = (time - from.timeS) / (to.timeS - from.timeS)
        guard logarithmic, from.value > 0, to.value > 0 else { return from.value + (to.value - from.value) * fraction }
        return exp(log(from.value) + (log(to.value) - log(from.value)) * fraction)
    }
}

/// The arranged music's beat lattice in film time.
struct SoundtrackGrid {
    let anchorS: Double
    let beatS: Double
    let barS: Double

    func nearestBeatS(_ time: Double) -> Double {
        anchorS + ((time - anchorS) / beatS).rounded() * beatS
    }

    /// The first downbeat at or after `time`.
    func downbeatS(atOrAfter time: Double) -> Double {
        anchorS + ((time - anchorS) / barS - 1e-9).rounded(.up) * barS
    }
}

/// **The moments the music answers** (handoff §2.5 item 5): a dip at each stop,
/// a return on the downbeat after the car sets off, a small lift as each
/// photograph changes. No added sound — only level and brightness move.
struct SoundtrackAutomation {
    struct Curves {
        let gain: SoundtrackCurve
        let cutoffHz: SoundtrackCurve
        let accents: [SoundtrackPlan.Accent]
    }

    /// One stop's dip: settling from `startS` to `settledS`, held, then
    /// returning from `releaseS` to full at `fullS`.
    struct Dip {
        var startS: Double
        var settledS: Double
        var releaseS: Double
        var fullS: Double
    }

    let grid: SoundtrackGrid
    let config: TrackingConfig.Soundtrack
    let manifest: SoundtrackManifest

    func curves(cues: [FilmCue]) -> Curves {
        let arrivals = cues.filter { $0.kind == .stopArrives }.map(snapped)
        let dips = merged(arrivals.compactMap { dip(arrival: $0, cues: cues) })
        let lifts = config.photoAccentEnabled
            ? cues.filter { $0.kind == .photoChanges }.map(snapped).filter { lift in
                dips.contains { $0.settledS <= lift.timeS && lift.timeS < $0.releaseS }
            }
            : []
        let base = pow(10, normalisationDb / 20)
        let dipped = base * pow(10, config.stopDipDb / 20)
        var gain = [SoundtrackCurve.Point(timeS: 0, value: base)]
        var cutoff = [SoundtrackCurve.Point(timeS: 0, value: config.openCutoffHz)]
        for dip in dips {
            gain += [point(dip.startS, base), point(dip.settledS, dipped), point(dip.releaseS, dipped), point(dip.fullS, base)]
            cutoff += [point(dip.startS, config.openCutoffHz), point(dip.settledS, config.stopCutoffHz)]
            cutoff += liftPoints(lifts.map(\.timeS).filter { dip.settledS <= $0 && $0 < dip.releaseS }, until: dip.releaseS)
            cutoff += [point(dip.releaseS, config.stopCutoffHz), point(dip.fullS, config.openCutoffHz)]
        }
        return Curves(
            gain: SoundtrackCurve(points: gain, logarithmic: false),
            cutoffHz: SoundtrackCurve(points: cutoff, logarithmic: true),
            accents: (arrivals + lifts).sorted { $0.timeS < $1.timeS }
        )
    }

    /// The gain that brings the track to `target_lufs`, held under the true-peak
    /// ceiling: a quiet track is lifted only as far as its peaks allow.
    var normalisationDb: Double {
        min(config.targetLufs - manifest.integratedLufs, config.truePeakMaxDbtp - manifest.truePeakDbtp)
    }

    /// An accent on the nearest beat when one is within tolerance, else on the
    /// cue itself — the music answers the picture, never the reverse (§2.5 item 6).
    func snapped(_ cue: FilmCue) -> SoundtrackPlan.Accent {
        let beat = grid.nearestBeatS(cue.timeS)
        guard abs(beat - cue.timeS) <= config.accentSnapToleranceS else {
            return SoundtrackPlan.Accent(cue: cue, timeS: cue.timeS, snapped: false)
        }
        return SoundtrackPlan.Accent(cue: cue, timeS: beat, snapped: true)
    }

    /// The dip a stop's arrival opens, released by the next `go` — or, for the
    /// last stop, by the closing reveal or the end card.
    private func dip(arrival: SoundtrackPlan.Accent, cues: [FilmCue]) -> Dip? {
        let releases: Set<FilmCue.Kind> = [.go, .endReveal, .endCard]
        guard let release = cues.first(where: { releases.contains($0.kind) && $0.timeS > arrival.cue.timeS })?.timeS,
              release > arrival.timeS else { return nil }
        let full = grid.downbeatS(atOrAfter: release + config.returnMinRampBeats * grid.beatS)
        let settled = min(arrival.timeS + config.dipRampBeats * grid.beatS, release)
        return Dip(startS: arrival.timeS, settledS: settled, releaseS: release, fullS: full)
    }

    /// Dips that touch become one: the music does not surface between two stops
    /// it would have to duck again for at once.
    private func merged(_ dips: [Dip]) -> [Dip] {
        var result: [Dip] = []
        for dip in dips.sorted(by: { $0.startS < $1.startS }) {
            if var last = result.last, dip.startS <= last.fullS {
                last.releaseS = max(last.releaseS, dip.releaseS)
                last.fullS = max(last.fullS, dip.fullS)
                result[result.count - 1] = last
            } else {
                result.append(dip)
            }
        }
        return result
    }

    /// Each lift opens the dipped filter a step over `photo_accent_attack_s` and
    /// settles back over `photo_accent_decay_beats`, cut short by the next lift
    /// or the release.
    private func liftPoints(_ times: [Double], until releaseS: Double) -> [SoundtrackCurve.Point] {
        let lifted = min(config.stopCutoffHz * config.photoAccentCutoffRatio, config.openCutoffHz)
        let bounds = Array(times.dropFirst()) + [releaseS]
        return zip(times, bounds).flatMap { start, bound -> [SoundtrackCurve.Point] in
            let peak = start + config.photoAccentAttackS
            guard peak < bound else { return [] }
            let settled = min(peak + config.photoAccentDecayBeats * grid.beatS, bound)
            return [point(start, config.stopCutoffHz), point(peak, lifted), point(settled, config.stopCutoffHz)]
        }
    }

    private func point(_ time: Double, _ value: Double) -> SoundtrackCurve.Point {
        SoundtrackCurve.Point(timeS: time, value: value)
    }
}
