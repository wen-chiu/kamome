import Foundation
import KamomeConfig

/// **How one track is fitted to one film** (`Docs/handoff-music-in-the-film.md`
/// §2.5): which stretches of the track play when, and how loud and how bright the
/// music is at every moment. Pure — the renderer (`RecapSoundtrackRenderer`) only
/// carries the plan out.
///
/// A clip always plays at 1× — **no time-stretch and no pitch-shift, ever**: a
/// stretched track is the "something is wrong" sound Chiu hears at once. So
/// `filmEndS − filmStartS` is `sourceEndS − sourceStartS` by construction.
public struct SoundtrackPlan: Equatable {
    public struct Clip: Equatable {
        public let sourceStartS: Double
        public let sourceEndS: Double
        public let filmStartS: Double
        /// Equal-power fades at the clip's two ends. A cut is two clips
        /// overlapping by one fade, centred on the cut.
        public let fadeInS: Double
        public let fadeOutS: Double

        public var filmEndS: Double { filmStartS + (sourceEndS - sourceStartS) }
    }

    /// A moment the music answered, and where: on the nearest beat when one was
    /// within `accent_snap_tolerance_s`, otherwise on the cue itself.
    public struct Accent: Equatable {
        public let cue: FilmCue
        public let timeS: Double
        public let snapped: Bool
    }

    public let durationS: Double
    public let clips: [Clip]
    /// Linear amplitude over film time: loudness normalisation × the stop dips.
    public let gain: SoundtrackCurve
    /// The low-pass cutoff over film time, interpolated in log frequency.
    public let cutoffHz: SoundtrackCurve
    public let accents: [Accent]
    /// The music's grid in film time: every beat is `gridAnchorS + n · beatS`,
    /// every downbeat `gridAnchorS + n · barS`. One lattice for the whole film,
    /// because every cut and repeat joins bar line to bar line.
    public let gridAnchorS: Double
    public let beatS: Double
    public let barS: Double
    /// Film time of the track's final hit: the end card's arrival.
    public let finalHitS: Double
    /// How far into the track the film starts (§2.5 item 3).
    public let introOffsetS: Double
    /// How many times a repeatable stretch was played again (§2.5 item 4).
    public let repeats: Int
}

public enum SoundtrackArrangement {
    public struct ArrangementError: Error, CustomStringConvertible {
        public let description: String
    }

    /// One stretch of the track, before cross-fades are added.
    struct Segment {
        let sourceStartS: Double
        let sourceEndS: Double
        let filmStartS: Double
        var lengthS: Double { sourceEndS - sourceStartS }
    }

    /// How the body before the ending is played: from `introOffsetS`, through
    /// `repeats` extra plays of the stretch `section`, to the phrase line `cutBar`.
    struct BodyRoute {
        let introOffsetS: Double
        let section: SoundtrackManifest.Section?
        let repeats: Int
        let cutBar: Int
    }

    /// **The plan.** The ending is anchored first, the body fitted to the time
    /// left before it, and the moments laid over both.
    public static func plan(
        manifest: SoundtrackManifest, cues: [FilmCue], durationS: Double, config: TrackingConfig.Soundtrack
    ) throws -> SoundtrackPlan {
        guard let endCardS = cues.last(where: { $0.kind == .endCard })?.timeS, endCardS <= durationS else {
            throw ArrangementError(description: "the film has no end card to land the final hit on")
        }
        guard let outro = manifest.outro else {
            throw ArrangementError(description: "\(manifest.id) has no outro")
        }
        // 1. Anchor the ending: the final hit arrives with the end card.
        let outroStartS = manifest.timeS(bar: outro.startBar)
        let outroFilmS = endCardS - (manifest.finalHitS - outroStartS)
        // 2–4. Fit the body on phrase lines, starting inside the intro and
        // repeating a section when the film outlasts the track.
        let route = try bestRoute(manifest: manifest, outroFilmS: outroFilmS, cues: cues, config: config)
        let segments = Self.segments(route, manifest: manifest, outroFilmS: outroFilmS, durationS: durationS)
        let grid = SoundtrackGrid(anchorS: outroFilmS, beatS: manifest.beatS, barS: manifest.barS)
        // 5. The moments.
        let automation = SoundtrackAutomation(grid: grid, config: config, manifest: manifest).curves(cues: cues)
        return SoundtrackPlan(
            durationS: durationS,
            clips: clips(segments, manifest: manifest, durationS: durationS, config: config),
            gain: automation.gain, cutoffHz: automation.cutoffHz, accents: automation.accents,
            gridAnchorS: grid.anchorS, beatS: grid.beatS, barS: grid.barS, finalHitS: endCardS,
            introOffsetS: segments.first.map { $0.filmStartS == 0 ? $0.sourceStartS : 0 } ?? 0,
            repeats: route?.repeats ?? 0
        )
    }

    // MARK: - The body

    /// Every bar a cut may leave from: each phrase line inside every section
    /// but the ending, and the ending's own start (playing straight on).
    static func phraseLines(_ manifest: SoundtrackManifest, phraseBars: Int) -> [Int] {
        let body = manifest.sections.filter { $0.role != .outro }
        let lines = body.flatMap { Array(stride(from: $0.startBar, to: $0.endBar, by: max(phraseBars, 1))) }
        return Array(Set(lines + [manifest.outro?.startBar].compactMap { $0 })).sorted()
    }

    /// The route with the fewest repeats; among those, the one that puts the
    /// peak nearest the film's strongest moment; then the one starting earliest
    /// in the intro. nil when the ending alone fills the film.
    private static func bestRoute(
        manifest: SoundtrackManifest, outroFilmS: Double, cues: [FilmCue], config: TrackingConfig.Soundtrack
    ) throws -> BodyRoute? {
        guard outroFilmS > 0 else { return nil }
        let strongest = strongestMomentS(cues)
        let scored = routes(manifest: manifest, outroFilmS: outroFilmS, phraseBars: config.phraseBars).map { route in
            (route, peakDistanceS(route, manifest: manifest, outroFilmS: outroFilmS, momentS: strongest))
        }
        guard let best = scored.min(by: { lhs, rhs in
            (lhs.0.repeats, lhs.1, lhs.0.introOffsetS) < (rhs.0.repeats, rhs.1, rhs.0.introOffsetS)
        }) else {
            throw ArrangementError(description: "\(manifest.id) cannot be cut to \(outroFilmS) s before its ending")
        }
        return best.0
    }

    /// Every way to fill `outroFilmS` with whole phrases, starting less than
    /// the intro (or one phrase, whichever is longer) into the track.
    static func routes(manifest: SoundtrackManifest, outroFilmS: Double, phraseBars: Int) -> [BodyRoute] {
        let first = manifest.sections[0]
        let introBars = first.role == .intro ? max(first.bars, phraseBars) : phraseBars
        let maxOffsetS = manifest.timeS(bar: first.startBar + introBars)
        let repeatable = repeatableStretches(manifest)
        let shortest = repeatable.map { Double($0.bars) * manifest.barS }.min() ?? .infinity
        let room = manifest.timeS(bar: manifest.outro?.startBar ?? 0)
        let mostRepeats = shortest.isFinite ? Int(((outroFilmS - room) / shortest).rounded(.up)) + 1 : 0
        var found: [BodyRoute] = []
        for repeats in 0...max(mostRepeats, 0) {
            for section in repeats == 0 ? [nil] : repeatable.map(Optional.some) {
                found += phraseLines(manifest, phraseBars: phraseBars).compactMap { cutBar in
                    route(manifest, section: section, repeats: repeats, cutBar: cutBar, outroFilmS: outroFilmS)
                        .flatMap { $0.introOffsetS <= maxOffsetS ? $0 : nil }
                }
            }
            if !found.isEmpty { return found }
        }
        return found
    }

    /// What may play again: any run of sections that begins on a repeatable
    /// section and ends on one, with no intro or outro inside. **The longest
    /// run wins, by needing the fewest repeats**: a 180 s film on a 120 s track
    /// replays verse-lift-chorus once rather than one chorus five times — the
    /// same eight bars over and over is the assembled sound four rounds of
    /// music were rejected for (`handoff-music-rethink.md` A2; desk render
    /// 2026-11-03).
    static func repeatableStretches(_ manifest: SoundtrackManifest) -> [SoundtrackManifest.Section] {
        let sections = manifest.sections
        let ends = sections.indices.filter { sections[$0].repeatable && [.body, .peak].contains(sections[$0].role) }
        return ends.flatMap { first in
            ends.filter { $0 >= first }.compactMap { last -> SoundtrackManifest.Section? in
                let run = sections[first...last]
                guard !run.contains(where: { $0.role == .intro || $0.role == .outro }) else { return nil }
                return SoundtrackManifest.Section(
                    name: run.map(\.name).joined(separator: "+"), startBar: run.first?.startBar ?? 0,
                    bars: (run.last?.endBar ?? 0) - (run.first?.startBar ?? 0),
                    energy: run.map(\.energy).max() ?? 1, role: .body, repeatable: true
                )
            }
        }
    }

    private static func route(
        _ manifest: SoundtrackManifest, section: SoundtrackManifest.Section?, repeats: Int,
        cutBar: Int, outroFilmS: Double
    ) -> BodyRoute? {
        if let section, cutBar < section.endBar { return nil }
        let repeatedS = Double(repeats * (section?.bars ?? 0)) * manifest.barS
        let offsetS = manifest.timeS(bar: cutBar) + repeatedS - outroFilmS
        guard offsetS >= 0 else { return nil }
        if let section, offsetS >= manifest.timeS(bar: section.startBar) { return nil }
        return BodyRoute(introOffsetS: offsetS, section: section, repeats: repeats, cutBar: cutBar)
    }

    /// The film's strongest moment (§2.5 item 2): the first crossing, else the
    /// last stop before the end reveal; nil when the film has neither.
    static func strongestMomentS(_ cues: [FilmCue]) -> Double? {
        if let crossing = cues.first(where: { $0.kind == .crossing }) { return crossing.timeS }
        let closing = cues.first { $0.kind == .endReveal || $0.kind == .endCard }?.timeS ?? .infinity
        return cues.last { $0.kind == .stopArrives && $0.timeS < closing }?.timeS
    }

    /// How far from `momentS` the peak plays in this route, in film seconds.
    private static func peakDistanceS(
        _ route: BodyRoute, manifest: SoundtrackManifest, outroFilmS: Double, momentS: Double?
    ) -> Double {
        let body = manifest.sections.filter { $0.role != .outro }
        guard let momentS, let peak = body.filter({ $0.role == .peak }).max(by: { $0.energy < $1.energy })
            ?? body.max(by: { $0.energy < $1.energy }) else { return 0 }
        let peakRange = manifest.timeS(bar: peak.startBar)...manifest.timeS(bar: peak.endBar)
        let distances = bodySegments(route, manifest: manifest).compactMap { segment -> Double? in
            let start = max(segment.sourceStartS, peakRange.lowerBound)
            let end = min(segment.sourceEndS, peakRange.upperBound)
            guard end > start else { return nil }
            let filmStart = segment.filmStartS + (start - segment.sourceStartS)
            let filmEnd = filmStart + (end - start)
            return momentS < filmStart ? filmStart - momentS : max(momentS - filmEnd, 0)
        }
        return distances.min() ?? .infinity
    }

    // MARK: - Segments and clips

    static func bodySegments(_ route: BodyRoute, manifest: SoundtrackManifest) -> [Segment] {
        let cutS = manifest.timeS(bar: route.cutBar)
        guard let section = route.section, route.repeats > 0 else {
            return [Segment(sourceStartS: route.introOffsetS, sourceEndS: cutS, filmStartS: 0)]
        }
        let sectionStartS = manifest.timeS(bar: section.startBar)
        let sectionEndS = manifest.timeS(bar: section.endBar)
        var spans = [(route.introOffsetS, sectionEndS)]
        spans += Array(repeating: (sectionStartS, sectionEndS), count: route.repeats)
        if cutS > sectionEndS { spans.append((sectionEndS, cutS)) }
        return laidEnd(spans)
    }

    static func segments(
        _ route: BodyRoute?, manifest: SoundtrackManifest, outroFilmS: Double, durationS: Double
    ) -> [Segment] {
        let outroStartS = manifest.timeS(bar: manifest.outro?.startBar ?? 0)
        // A film shorter than the ending's lead-in starts inside the ending.
        let skippedS = max(-outroFilmS, 0)
        let filmStartS = max(outroFilmS, 0)
        let ending = (outroStartS + skippedS, min(manifest.durationS, outroStartS + skippedS + durationS - filmStartS))
        let body = route.map { bodySegments($0, manifest: manifest) } ?? []
        return laidEnd(body.map { ($0.sourceStartS, $0.sourceEndS) } + [ending])
    }

    /// Spans laid end to end in film time from 0, merging any two that join
    /// in the source without a jump (playing straight on is not a cut).
    private static func laidEnd(_ spans: [(Double, Double)]) -> [Segment] {
        var merged: [(Double, Double)] = []
        for span in spans where span.1 > span.0 {
            if let last = merged.last, abs(last.1 - span.0) < 1e-9 {
                merged[merged.count - 1].1 = span.1
            } else {
                merged.append(span)
            }
        }
        var filmS = 0.0
        return merged.map { span in
            defer { filmS += span.1 - span.0 }
            return Segment(sourceStartS: span.0, sourceEndS: span.1, filmStartS: filmS)
        }
    }

    /// Segments become clips: each cut cross-fades over `crossfade_beats`,
    /// centred on the cut and narrowed only where the track has no audio to
    /// overlap with; the first clip fades in when it starts inside the track,
    /// the last fades out when the film cuts it short.
    static func clips(
        _ segments: [Segment], manifest: SoundtrackManifest, durationS: Double, config: TrackingConfig.Soundtrack
    ) -> [SoundtrackPlan.Clip] {
        let half = config.crossfadeBeats * manifest.beatS / 2
        let joins: [Double] = zip(segments, segments.dropFirst()).map { previous, next in
            min(half, manifest.durationS - previous.sourceEndS, next.sourceStartS, next.filmStartS)
        }
        return segments.enumerated().map { index, segment in
            let before = index > 0 ? joins[index - 1] : 0
            let after = index < joins.count ? joins[index] : 0
            let filmEndS = min(segment.filmStartS + segment.lengthS + after, durationS)
            let start = segment.sourceStartS - before
            let end = segment.sourceStartS + (filmEndS - segment.filmStartS)
            let isLast = index == segments.count - 1
            let fadeIn = index == 0 ? (segment.sourceStartS > 0 ? min(config.fadeInS, end - start) : 0) : 2 * before
            let cutShort = isLast && segment.sourceEndS - segment.sourceStartS > durationS - segment.filmStartS - 1e-9
            let fadeOut = isLast ? (cutShort ? min(config.fadeOutS, end - start) : 0) : 2 * after
            return SoundtrackPlan.Clip(
                sourceStartS: start, sourceEndS: end, filmStartS: segment.filmStartS - before,
                fadeInS: fadeIn, fadeOutS: fadeOut
            )
        }
    }
}
