import AVFAudio
import Foundation
import KamomeConfig

/// **Plan → soundtrack file** (`Docs/handoff-music-in-the-film.md` §3.1).
///
/// `AVAudioEngine` in offline manual rendering: one `AVAudioPlayerNode` per
/// clip (a cross-fade is two nodes overlapping), all into the main mixer, which
/// also converts the track's sample rate. The loop pulls `render_chunk_frames`
/// at a time, applies the plan's gain, and writes the chunk straight to the
/// file — **streamed, never held**: 180 s of 48 kHz stereo float would be ~69 MB.
///
/// The plan is pure and tested in `SoundtrackArrangement`; this file only
/// carries it out. One of the three files allowed AVFoundation, and the only
/// one allowed AVFAudio (`Config/architecture.json`, ADR 2026-11-03).
public final class RecapSoundtrackRenderer {
    public struct RenderError: Error, CustomStringConvertible {
        public let description: String
    }

    /// What the file holds: AAC for a film, lossless PCM for a test that has
    /// to find a sample.
    public enum Encoding {
        case aac
        case linearPCM
    }

    private let config: TrackingConfig.Soundtrack

    public init(config: TrackingConfig.Soundtrack) {
        self.config = config
    }

    /// Renders `plan` from the track at `trackURL` into `outputURL`, exactly
    /// `durationS × sample_rate_hz` frames long. Reads `shouldContinue` between
    /// chunks; a cancelled render throws `CancellationError` and leaves no file.
    public func render(
        plan: SoundtrackPlan, trackURL: URL, to outputURL: URL, encoding: Encoding = .aac,
        shouldContinue: () -> Bool = { true }
    ) throws {
        try? FileManager.default.removeItem(at: outputURL)
        do {
            try renderUnguarded(plan, trackURL, outputURL, encoding, shouldContinue)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private func renderUnguarded(
        _ plan: SoundtrackPlan, _ trackURL: URL, _ outputURL: URL, _ encoding: Encoding, _ shouldContinue: () -> Bool
    ) throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: config.sampleRateHz, channels: AVAudioChannelCount(config.channelCount)
        ) else { throw RenderError(description: "no \(config.sampleRateHz) Hz × \(config.channelCount) format") }
        let chunk = AVAudioFrameCount(config.renderChunkFrames)
        let graph = try Graph(format: format, chunk: chunk, clips: plan.clips.count, trackURL: trackURL)
        for (clip, player) in zip(plan.clips, graph.players) {
            try schedule(clip, on: player, trackURL: trackURL)
        }
        try graph.engine.start()
        defer { graph.engine.stop() }
        graph.players.forEach { $0.play() }

        let output = try AVAudioFile(
            forWriting: outputURL, settings: settings(encoding),
            commonFormat: .pcmFormatFloat32, interleaved: false
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: graph.engine.manualRenderingFormat, frameCapacity: chunk) else {
            throw RenderError(description: "no render buffer")
        }
        let total = AVAudioFramePosition((plan.durationS * config.sampleRateHz).rounded())
        var rendered: AVAudioFramePosition = 0
        while rendered < total {
            guard shouldContinue() else { throw CancellationError() }
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(chunk), total - rendered))
            let status = try graph.engine.renderOffline(frames, to: buffer)
            guard status == .success else { throw RenderError(description: "render stopped (\(status.rawValue))") }
            applyGain(Float(plan.gain), to: buffer)
            try output.write(from: buffer)
            rendered += AVAudioFramePosition(buffer.frameLength)
        }
    }

    /// The engine and its players.
    private struct Graph {
        let engine = AVAudioEngine()
        let players: [AVAudioPlayerNode]

        init(format: AVAudioFormat, chunk: AVAudioFrameCount, clips: Int, trackURL: URL) throws {
            let source = try AVAudioFile(forReading: trackURL).processingFormat
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk)
            players = (0..<clips).map { _ in AVAudioPlayerNode() }
            for player in players {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: source)
            }
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        }
    }

    /// A clip is its fade-in, its middle and its fade-out. The fades are read
    /// into buffers and shaped sample by sample (equal power), so a cross-fade is
    /// exact; the middle streams from the file.
    private func schedule(_ clip: SoundtrackPlan.Clip, on player: AVAudioPlayerNode, trackURL: URL) throws {
        let file = try AVAudioFile(forReading: trackURL)
        let rate = file.processingFormat.sampleRate
        let start = AVAudioFramePosition((clip.sourceStartS * rate).rounded())
        let end = min(AVAudioFramePosition((clip.sourceEndS * rate).rounded()), file.length)
        let filmStart = AVAudioFramePosition((clip.filmStartS * rate).rounded())
        guard end > start else { return }
        let fadeIn = min(AVAudioFramePosition((clip.fadeInS * rate).rounded()), end - start)
        let fadeOut = min(AVAudioFramePosition((clip.fadeOutS * rate).rounded()), end - start - fadeIn)
        let at = { (frame: AVAudioFramePosition) in AVAudioTime(sampleTime: filmStart + frame - start, atRate: rate) }
        if fadeIn > 0 {
            player.scheduleBuffer(try faded(file, from: start, count: fadeIn, rising: true), at: at(start))
        }
        let middle = end - fadeOut - (start + fadeIn)
        if middle > 0 {
            player.scheduleSegment(
                file, startingFrame: start + fadeIn, frameCount: AVAudioFrameCount(middle), at: at(start + fadeIn)
            )
        }
        if fadeOut > 0 {
            player.scheduleBuffer(try faded(file, from: end - fadeOut, count: fadeOut, rising: false), at: at(end - fadeOut))
        }
    }

    private func faded(
        _ track: AVAudioFile, from frame: AVAudioFramePosition, count: AVAudioFramePosition, rising: Bool
    ) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: track.url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)),
              let channels = buffer.floatChannelData else { throw RenderError(description: "no fade buffer") }
        file.framePosition = frame
        try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
        let length = Int(buffer.frameLength)
        for index in 0..<length {
            let progress = (Double(index) + 0.5) / Double(count)
            let gain = Float(rising ? sin(progress * .pi / 2) : cos(progress * .pi / 2))
            for channel in 0..<Int(file.processingFormat.channelCount) { channels[channel][index] *= gain }
        }
        return buffer
    }

    /// The plan's one gain, on the rendered samples. Not the mixer's volume: a
    /// quiet track is lifted, and `outputVolume` stops at 1.
    private func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard gain != 1, let channels = buffer.floatChannelData else { return }
        for channel in 0..<Int(buffer.format.channelCount) {
            for index in 0..<Int(buffer.frameLength) { channels[channel][index] *= gain }
        }
    }

    private func settings(_ encoding: Encoding) -> [String: Any] {
        switch encoding {
        case .aac:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: config.sampleRateHz,
                AVNumberOfChannelsKey: config.channelCount, AVEncoderBitRateKey: config.audioBitrateKbps * 1_000
            ]
        case .linearPCM:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: config.sampleRateHz,
                AVNumberOfChannelsKey: config.channelCount, AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
            ]
        }
    }
}
