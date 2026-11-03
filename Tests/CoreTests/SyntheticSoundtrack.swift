import AVFAudio
import Foundation
import KamomeExportEngine

/// **A track made in the test, never real audio in the repository**: a click on
/// every beat (louder on the downbeat), a different tone in each section, and a
/// full-scale hit on the final-hit bar whose first sample is its loudest — so a
/// test can find the hit to the sample, count beats to prove nothing was
/// stretched, and hear which section is playing.
///
/// Shared by the Core tests and the desk harness (`RecapSoundtrackFilmTests`,
/// listed in `project.yml` for the app test target too): the harness falls back
/// to this when no real track is given.
enum SyntheticSoundtrack {
    /// 120 BPM in 4/4 — a bar is 2 s, a 4-bar phrase 8 s — with every role the
    /// arrangement uses. The same track as `Tests/Fixtures/soundtracks/invalid/`'s
    /// base, so a refusal there is one change away from this.
    static let manifest = SoundtrackManifest(
        id: "synthetic-click", style: "anthem", mood: "depart", file: "synthetic-click.wav",
        durationS: 110.5, bpm: 120, beatsPerBar: 4, firstDownbeatS: 0.25, tempoDriftBpm: 0.1,
        sections: [
            .init(name: "intro", startBar: 0, bars: 8, energy: 1, role: .intro),
            .init(name: "verse", startBar: 8, bars: 16, energy: 2, role: .body, repeatable: true),
            .init(name: "lift", startBar: 24, bars: 8, energy: 3, role: .lift),
            .init(name: "chorus", startBar: 32, bars: 16, energy: 4, role: .peak, repeatable: true),
            .init(name: "ending", startBar: 48, bars: 6, energy: 2, role: .outro)
        ],
        sectionsConfirmed: false, finalHitBar: 52, tailS: 3.0,
        integratedLufs: -14, truePeakDbtp: -1, provenance: .init(engine: "synthetic")
    )

    static let hitAmplitude: Float = 0.9
    static let clickAmplitude: Float = 0.25
    static let downbeatAmplitude: Float = 0.35
    static let toneAmplitude: Float = 0.05
    /// One tone per section, in order: which section plays is audible.
    static let sectionHz: [Double] = [220, 277.18, 329.63, 392, 196]

    /// Writes the track as 32-bit float stereo WAV at `sampleRate`.
    static func write(to url: URL, sampleRate: Double = 48_000) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let total = Int((manifest.durationS * sampleRate).rounded())
        let chunk = 48_000
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)),
              let channels = buffer.floatChannelData else { throw CocoaError(.fileWriteUnknown) }
        var start = 0
        while start < total {
            let count = min(chunk, total - start)
            for index in 0..<count {
                let sample = value(atFrame: start + index, sampleRate: sampleRate)
                channels[0][index] = sample
                channels[1][index] = sample
            }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            start += count
        }
    }

    /// The sample at `frame`: the section's tone, the last beat's click, and the
    /// final hit once it has struck.
    static func value(atFrame frame: Int, sampleRate: Double) -> Float {
        let time = Double(frame) / sampleRate
        let bar = Int(((time - manifest.firstDownbeatS) / manifest.barS).rounded(.down))
        let section = manifest.sections.lastIndex { $0.startBar <= max(bar, 0) } ?? 0
        var sample = toneAmplitude * Float(sin(2 * .pi * sectionHz[section] * time))
        let beat = ((time - manifest.firstDownbeatS) / manifest.beatS).rounded(.down)
        if beat >= 0 {
            let beatFrame = Int(((manifest.firstDownbeatS + beat * manifest.beatS) * sampleRate).rounded())
            let amplitude = Int(beat) % manifest.beatsPerBar == 0 ? downbeatAmplitude : clickAmplitude
            sample += burst(frame - beatFrame, amplitude: amplitude, lengthFrames: 96, sampleRate: sampleRate)
        }
        let hitFrame = Int((manifest.finalHitS * sampleRate).rounded())
        sample += burst(frame - hitFrame, amplitude: hitAmplitude, lengthFrames: 2_400, sampleRate: sampleRate)
        return sample
    }

    /// A decaying cosine, loudest on its first sample.
    private static func burst(_ offset: Int, amplitude: Float, lengthFrames: Int, sampleRate: Double) -> Float {
        guard offset >= 0, offset < lengthFrames else { return 0 }
        let decay = Float(1 - Double(offset) / Double(lengthFrames))
        return amplitude * decay * Float(cos(2 * .pi * 1_000 * Double(offset) / sampleRate))
    }
}
