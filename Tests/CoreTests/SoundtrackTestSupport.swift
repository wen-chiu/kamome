import Foundation
import KamomeConfig
import KamomeExportEngine
import XCTest

/// What the soundtrack tests share: the shipped config (with an override when a
/// test varies one tunable), and a synthetic film's cue sheet of any length.
enum SoundtrackTestSupport {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var fixtures: URL { repository.appendingPathComponent("Tests/Fixtures/soundtracks") }

    static func shipped() throws -> TrackingConfig {
        try TrackingConfigLoader.load(contentsOf: repository.appendingPathComponent("Config/TrackingConfig.json"))
    }

    /// The shipped `soundtrack` block with some keys replaced — decoded, never
    /// hand-built, so a test cannot use a block the file could not hold.
    static func soundtrack(_ overrides: [String: Any] = [:]) throws -> TrackingConfig.Soundtrack {
        let data = try Data(contentsOf: repository.appendingPathComponent("Config/TrackingConfig.json"))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var block = json["soundtrack"] as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        block.merge(overrides) { _, new in new }
        json["soundtrack"] = block
        return try TrackingConfigLoader.load(from: JSONSerialization.data(withJSONObject: json)).soundtrack
    }

    /// A film of `durationS` with a stop every 12 s: arrival, three photo
    /// changes at awkward times (so some miss the beat), the car setting off 5 s
    /// later; a 3 s end card after a 2.5 s reveal. Times are deliberately off
    /// the 120 BPM grid by varying amounts.
    static func cues(durationS: Double) -> [FilmCue] {
        let endCardS = durationS - 3
        var cues = [FilmCue(kind: .opening, timeS: 0), FilmCue(kind: .go, timeS: 4.13)]
        var stop = 0
        var arrival = 9.07
        while arrival + 5 < endCardS - 2.5 {
            cues.append(FilmCue(kind: .stopArrives, timeS: arrival, stopIndex: stop))
            for offset in [1.71, 2.62, 3.49] {
                cues.append(FilmCue(kind: .photoChanges, timeS: arrival + offset, stopIndex: stop))
            }
            cues.append(FilmCue(kind: .go, timeS: arrival + 5, stopIndex: stop))
            stop += 1
            arrival += 12.3
        }
        cues.append(FilmCue(kind: .endReveal, timeS: endCardS - 2.5))
        cues.append(FilmCue(kind: .endCard, timeS: endCardS))
        return cues
    }

    /// The synthetic track's plan for a film of `durationS`.
    static func plan(durationS: Double, overrides: [String: Any] = [:]) throws -> SoundtrackPlan {
        try SoundtrackArrangement.plan(
            manifest: SyntheticSoundtrack.manifest, cues: cues(durationS: durationS),
            durationS: durationS, config: soundtrack(overrides)
        )
    }
}
