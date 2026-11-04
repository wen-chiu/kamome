import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **A track fitted to a film without bending it** (`Docs/handoff-music-in-the-film.md`
/// §2.5): the last chord on the end card, every cut on a phrase line, nothing
/// played at other than 1×, one level throughout. On the synthetic track
/// (`SyntheticSoundtrack`), 120 BPM.
final class SoundtrackArrangementTests: XCTestCase {
    private let manifest = SyntheticSoundtrack.manifest
    private let lengths: [Double] = [30, 45, 60, 90, 120, 180, 240, 300]
    private let oneSampleS = 1.0 / 48_000

    func testTheFinalHitLandsOnTheEndCardWithinOneSample() throws {
        for durationS in lengths {
            let plan = try SoundtrackTestSupport.plan(durationS: durationS)
            let endCardS = durationS - 3
            let hitS = manifest.finalHitS
            let clip = try XCTUnwrap(plan.clips.last { $0.sourceStartS <= hitS && hitS < $0.sourceEndS }, "\(durationS) s")
            XCTAssertEqual(clip.filmStartS + (hitS - clip.sourceStartS), endCardS, accuracy: oneSampleS, "\(durationS) s")
            XCTAssertEqual(plan.finalHitS, endCardS, "\(durationS) s")
        }
    }

    /// 1× by construction (a clip's film span *is* its source span); what is
    /// left to prove is that the clips cover the film without a gap, start at
    /// its first frame and never run past its last.
    func testTheClipsCoverTheFilmEndToEnd() throws {
        for durationS in lengths {
            let plan = try SoundtrackTestSupport.plan(durationS: durationS)
            XCTAssertEqual(plan.clips.first?.filmStartS, 0, "\(durationS) s")
            for (previous, next) in zip(plan.clips, plan.clips.dropFirst()) {
                XCTAssertLessThanOrEqual(next.filmStartS, previous.filmEndS + 1e-9, "a gap at \(previous.filmEndS) s")
            }
            for clip in plan.clips {
                XCTAssertLessThanOrEqual(clip.filmEndS, durationS + 1e-9)
                XCTAssertGreaterThanOrEqual(clip.sourceStartS, 0)
                XCTAssertLessThanOrEqual(clip.sourceEndS, manifest.durationS + 1e-9)
            }
        }
    }

    func testEveryCutIsOnAPhraseLineAndJoinsTheGrid() throws {
        let phrase = try SoundtrackTestSupport.soundtrack().phraseBars
        let lines = Set(SoundtrackArrangement.phraseLines(manifest, phraseBars: phrase))
        func isLine(_ sourceS: Double) -> Bool {
            let bar = (sourceS - manifest.firstDownbeatS) / manifest.barS
            return abs(bar - bar.rounded()) < 1e-9 && lines.contains(Int(bar.rounded()))
        }
        for durationS in lengths {
            let plan = try SoundtrackTestSupport.plan(durationS: durationS)
            for (previous, next) in zip(plan.clips, plan.clips.dropFirst()) {
                let leaving = previous.sourceEndS - previous.fadeOutS / 2
                let arriving = next.sourceStartS + next.fadeInS / 2
                XCTAssertTrue(isLine(leaving), "\(durationS) s: a cut leaves at \(leaving) s, not a phrase line")
                XCTAssertTrue(isLine(arriving), "\(durationS) s: a cut arrives at \(arriving) s, not a phrase line")
                XCTAssertEqual(previous.filmEndS - previous.fadeOutS / 2, next.filmStartS + next.fadeInS / 2,
                               accuracy: 1e-9, "\(durationS) s: the cross-fade is not centred on the cut")
            }
        }
    }

    func testTheRemainderIsAbsorbedInsideTheIntro() throws {
        let introEndS = manifest.timeS(bar: manifest.sections[0].endBar)
        for durationS in lengths where durationS >= 30 {
            let plan = try SoundtrackTestSupport.plan(durationS: durationS)
            XCTAssertGreaterThanOrEqual(plan.introOffsetS, 0)
            XCTAssertLessThanOrEqual(plan.introOffsetS, introEndS, "\(durationS) s starts past the intro")
            XCTAssertEqual(plan.clips.first?.fadeInS ?? 0 > 0, plan.introOffsetS > 0, "fade in only when starting inside")
        }
    }

    func testAFiveMinuteFilmRepeatsASectionOnItsBarLines() throws {
        let plan = try SoundtrackTestSupport.plan(durationS: 300)
        XCTAssertGreaterThanOrEqual(plan.repeats, 1)
        let played = plan.clips.map { ($0.sourceStartS + $0.fadeInS / 2)...($0.sourceEndS - $0.fadeOutS / 2) }
        let repeated = zip(played, played.dropFirst()).contains { $0.upperBound > $1.lowerBound + 1 }
        XCTAssertTrue(repeated, "a 300 s film on a 110 s track must play some bars twice")
        // A 90 s film needs no repeat: the track is long enough.
        XCTAssertEqual(try SoundtrackTestSupport.plan(durationS: 90).repeats, 0)
    }

    /// A long film replays the longest stretch it can, not one section over and
    /// over: on the desk tool's real manifest (four 8-bar repeatable sections),
    /// a 180 s film once played one 8-bar section five times in a row.
    func testALongFilmReplaysAStretchNotOneSectionOverAndOver() throws {
        let url = SoundtrackTestSupport.fixtures.appendingPathComponent("anthem-depart-s1855554642.json")
        let real = try SoundtrackManifest.load(from: Data(contentsOf: url), limits: SoundtrackTestSupport.soundtrack())
        let plan = try SoundtrackArrangement.plan(
            manifest: real, cues: SoundtrackTestSupport.cues(durationS: 180), durationS: 180,
            config: SoundtrackTestSupport.soundtrack()
        )
        XCTAssertEqual(plan.repeats, 1, "one replay of a long stretch covers 60 s; five of one section is a loop")
        for clip in plan.clips {
            XCTAssertGreaterThan(clip.sourceEndS - clip.sourceStartS, 2 * 8 * real.barS,
                                 "a clip no longer than one 8-bar section means the same bars back to back")
        }
    }

    func testLoudnessIsNormalisedUnderTheTruePeakCeiling() throws {
        let config = try SoundtrackTestSupport.soundtrack()
        func gain(lufs: Double, peak: Double) throws -> Double {
            let quiet = SoundtrackManifest(
                id: "q", style: "s", mood: "m", file: "f", durationS: manifest.durationS, bpm: manifest.bpm,
                beatsPerBar: 4, firstDownbeatS: manifest.firstDownbeatS, tempoDriftBpm: 0, sections: manifest.sections,
                sectionsConfirmed: false, finalHitBar: manifest.finalHitBar, tailS: manifest.tailS,
                integratedLufs: lufs, truePeakDbtp: peak, provenance: .init(engine: "synthetic")
            )
            let plan = try SoundtrackArrangement.plan(manifest: quiet, cues: SoundtrackTestSupport.cues(durationS: 60),
                                                      durationS: 60, config: config)
            return 20 * log10(plan.gain)
        }
        XCTAssertEqual(try gain(lufs: -14.5, peak: -3), 0.5, accuracy: 1e-9, "lifted to the target")
        XCTAssertEqual(try gain(lufs: -14.5, peak: -1.2), 0.2, accuracy: 1e-9, "but only as far as the peaks allow")
        XCTAssertEqual(try gain(lufs: -13.4, peak: -1.5), -0.6, accuracy: 1e-9, "a loud track comes down")
    }

    /// No dip, no lift (ADR 2026-11-03-the-music-plays-straight-through): the
    /// plan carries one gain, and the moments only place the cuts.
    func testTheMusicHasOneLevelForTheWholeFilm() throws {
        let plan = try SoundtrackTestSupport.plan(durationS: 120)
        XCTAssertEqual(plan.gain, 1, accuracy: 1e-12, "the synthetic track is already at the target")
    }

    func testAFilmWithNoEndCardIsRefused() throws {
        XCTAssertThrowsError(try SoundtrackArrangement.plan(
            manifest: manifest, cues: [FilmCue(kind: .opening, timeS: 0)], durationS: 60,
            config: SoundtrackTestSupport.soundtrack()
        ))
    }
}
