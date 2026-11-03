import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **A track fitted to a film without bending it** (`Docs/handoff-music-in-the-film.md`
/// §2.5): the last chord on the end card, every cut on a phrase line, nothing
/// played at other than 1×, and the moments answered on the beat only when the
/// beat is near. On the synthetic track (`SyntheticSoundtrack`), 120 BPM.
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

    func testAccentsLandOnTheBeatWithinToleranceOrOnTheCue() throws {
        for tolerance in [0.0, 0.1, 0.25] {
            let plan = try SoundtrackTestSupport.plan(durationS: 120, overrides: ["accent_snap_tolerance_s": tolerance])
            XCTAssertFalse(plan.accents.isEmpty)
            for accent in plan.accents {
                let beats = (accent.timeS - plan.gridAnchorS) / plan.beatS
                let nearestS = plan.gridAnchorS + ((accent.cue.timeS - plan.gridAnchorS) / plan.beatS).rounded() * plan.beatS
                if accent.snapped {
                    XCTAssertEqual(beats, beats.rounded(), accuracy: 1e-9, "a snapped accent off the beat")
                    XCTAssertLessThanOrEqual(abs(accent.timeS - accent.cue.timeS), tolerance + 1e-9)
                } else {
                    XCTAssertEqual(accent.timeS, accent.cue.timeS, "an unsynced accent must play on its cue")
                    XCTAssertGreaterThan(abs(nearestS - accent.cue.timeS), tolerance, "a beat was in reach and missed")
                }
            }
            // Half a beat reaches every cue; no tolerance reaches none of these.
            if tolerance == 0.25 { XCTAssertTrue(plan.accents.allSatisfy(\.snapped)) }
            if tolerance == 0 { XCTAssertTrue(plan.accents.allSatisfy { !$0.snapped }) }
        }
    }

    func testAStopDipsAndTheMusicReturnsOnTheDownbeatAfterGo() throws {
        let config = try SoundtrackTestSupport.soundtrack()
        let plan = try SoundtrackTestSupport.plan(durationS: 120)
        let cues = SoundtrackTestSupport.cues(durationS: 120)
        let full = plan.gain.value(atS: 0)
        let arrival = try XCTUnwrap(cues.first { $0.kind == .stopArrives })
        let accent = try XCTUnwrap(plan.accents.first { $0.cue == arrival })
        let settled = accent.timeS + config.dipRampBeats * plan.beatS
        XCTAssertEqual(plan.gain.value(atS: settled + 0.01), full * pow(10, config.stopDipDb / 20), accuracy: 1e-9)
        XCTAssertEqual(plan.cutoffHz.value(atS: settled + 0.01), config.stopCutoffHz, accuracy: 1e-6)
        let go = try XCTUnwrap(cues.first { $0.kind == .go && $0.stopIndex == arrival.stopIndex }).timeS
        let downbeats = stride(from: plan.gridAnchorS - 100 * plan.barS, to: 200, by: plan.barS)
        let back = try XCTUnwrap(downbeats.first { $0 >= go + config.returnMinRampBeats * plan.beatS - 1e-9 })
        XCTAssertEqual(plan.gain.value(atS: back), full, accuracy: 1e-9, "full again on the downbeat")
        XCTAssertLessThan(plan.gain.value(atS: back - 0.05), full, "and not before it")
        XCTAssertEqual(plan.cutoffHz.value(atS: back), config.openCutoffHz, accuracy: 1e-6)
    }

    func testAPhotographChangingOpensTheFilterAStep() throws {
        let config = try SoundtrackTestSupport.soundtrack()
        let plan = try SoundtrackTestSupport.plan(durationS: 120)
        let lift = try XCTUnwrap(plan.accents.first { $0.cue.kind == .photoChanges })
        XCTAssertEqual(plan.cutoffHz.value(atS: lift.timeS + config.photoAccentAttackS),
                       config.stopCutoffHz * config.photoAccentCutoffRatio, accuracy: 1e-6)
        let off = try SoundtrackTestSupport.plan(durationS: 120, overrides: ["photo_accent_enabled": false])
        XCTAssertFalse(off.accents.contains { $0.cue.kind == .photoChanges })
        XCTAssertEqual(off.cutoffHz.value(atS: lift.timeS + config.photoAccentAttackS), config.stopCutoffHz, accuracy: 1e-6)
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
            return 20 * log10(plan.gain.value(atS: 0))
        }
        XCTAssertEqual(try gain(lufs: -14.5, peak: -3), 0.5, accuracy: 1e-9, "lifted to the target")
        XCTAssertEqual(try gain(lufs: -14.5, peak: -1.2), 0.2, accuracy: 1e-9, "but only as far as the peaks allow")
        XCTAssertEqual(try gain(lufs: -13.4, peak: -1.5), -0.6, accuracy: 1e-9, "a loud track comes down")
    }

    func testAFilmWithNoEndCardIsRefused() throws {
        XCTAssertThrowsError(try SoundtrackArrangement.plan(
            manifest: manifest, cues: [FilmCue(kind: .opening, timeS: 0)], durationS: 60,
            config: SoundtrackTestSupport.soundtrack()
        ))
    }
}
