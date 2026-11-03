import AVFoundation
import KamomeConfig
import KamomeExportEngine
import XCTest

/// **The plan, carried out** (`Docs/handoff-music-in-the-film.md` §3.1, §3.2):
/// the rendered soundtrack is exactly as long as the film, its final hit sits
/// on the end card's sample, its beats keep their spacing (nothing stretched),
/// and the muxer puts it beside a picture it copies rather than re-encodes.
final class RecapSoundtrackRendererTests: XCTestCase {
    private var directory: URL!
    /// Written once for the class: 110 s of synthetic track is most of a test's time.
    private static let track = FileManager.default.temporaryDirectory
        .appendingPathComponent("kamome-synthetic-\(UUID().uuidString).wav")
    private var track: URL { Self.track }

    override static func setUp() {
        super.setUp()
        try? SyntheticSoundtrack.write(to: track)
    }

    override static func tearDown() {
        try? FileManager.default.removeItem(at: track)
        super.tearDown()
    }

    override func setUpWithError() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: track.path), "the synthetic track was not written")
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-soundtrack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func render(durationS: Double, encoding: RecapSoundtrackRenderer.Encoding, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try RecapSoundtrackRenderer(config: SoundtrackTestSupport.soundtrack()).render(
            plan: SoundtrackTestSupport.plan(durationS: durationS), trackURL: track, to: url, encoding: encoding
        )
        return url
    }

    private func samples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData)[0]
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    func testTheSoundtrackIsExactlyAsLongAsTheFilm() throws {
        for encoding in [RecapSoundtrackRenderer.Encoding.linearPCM, .aac] {
            let url = try render(durationS: 40, encoding: encoding, name: "length-\(encoding).caf")
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.length, 40 * 48_000, "\(encoding)")
            XCTAssertEqual(file.processingFormat.sampleRate, 48_000)
        }
    }

    func testTheFinalHitIsOnTheEndCardsSample() throws {
        let durationS = 40.0
        let output = try samples(render(durationS: durationS, encoding: .linearPCM, name: "hit.caf"))
        let endCard = Int(((durationS - 3) * 48_000).rounded())
        // The hit is the only thing in the track this loud.
        let search = (endCard - 4_800)..<(endCard + 4_800)
        let onset = try XCTUnwrap(search.first { abs(output[$0]) > SyntheticSoundtrack.hitAmplitude * 0.6 })
        XCTAssertLessThanOrEqual(abs(onset - endCard), 1, "the final hit is \(onset - endCard) samples off the end card")
    }

    /// Clicks a beat apart in the source stay a beat apart in the film: no
    /// time-stretch, sample for sample. Read before the first stop's dip.
    func testTheBeatKeepsItsSpacing() throws {
        let output = try samples(render(durationS: 40, encoding: .linearPCM, name: "beat.caf"))
        var onsets: [Int] = []
        var index = 2 * 48_000
        while index < 8 * 48_000 {
            if abs(output[index]) > SyntheticSoundtrack.clickAmplitude * 0.6 {
                onsets.append(index)
                index += 2_000
            } else {
                index += 1
            }
        }
        XCTAssertGreaterThanOrEqual(onsets.count, 10)
        for (previous, next) in zip(onsets, onsets.dropFirst()) {
            XCTAssertLessThanOrEqual(abs(next - previous - 24_000), 1, "a beat of \(next - previous) samples, not 24,000")
        }
    }

    /// **The music plays straight through a stop** (ADR 2026-11-03-the-music-plays-straight-through):
    /// the clicks during the first stop (9–14 s, in the synthetic film) are as
    /// loud and as sharp as the ones before it. Both windows stay inside the
    /// intro (the film starts 3.25 s into the track), where every downbeat meets
    /// the intro's tone at the same phase, so equal means equal.
    func testAStopDoesNotDuckTheMusic() throws {
        let output = try samples(render(durationS: 40, encoding: .linearPCM, name: "stop.caf"))
        func loudest(_ fromS: Double, _ toS: Double) -> Float {
            output[Int(fromS * 48_000)..<Int(toS * 48_000)].map(abs).max() ?? 0
        }
        XCTAssertEqual(loudest(9.5, 12.5), loudest(3.5, 6.5), accuracy: 0.01, "a stop changed the music's level")
    }

    func testACancelledRenderLeavesNoFile() throws {
        let url = directory.appendingPathComponent("cancelled.m4a")
        var chunks = 0
        XCTAssertThrowsError(try RecapSoundtrackRenderer(config: SoundtrackTestSupport.soundtrack()).render(
            plan: SoundtrackTestSupport.plan(durationS: 40), trackURL: track, to: url,
            shouldContinue: {
                chunks += 1
                return chunks < 20
            }
        )) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        XCTAssertEqual(chunks, 20, "cancellation is read before every chunk")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - The muxer

    /// A two-second silent film, small and fast: the picture is not what this tests.
    private func silentFilm(frames: Int = 20) async throws -> URL {
        let url = directory.appendingPathComponent("silent-\(frames).mp4")
        let encoder = try RecapVideoEncoder(outputURL: url, widthPx: 128, heightPx: 128, fps: 10, bitrateMbps: 1)
        let context = try XCTUnwrap(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
        for frame in 0..<frames {
            context.setFillColor(CGColor(srgbRed: Double(frame % 20) / 20, green: 0.4, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            try encoder.append(try XCTUnwrap(context.makeImage()), frame: frame)
        }
        try await encoder.finish()
        return url
    }

    private struct Tracks {
        let video: CMTime
        let audio: CMTime?
        let audioTracks: Int
    }

    private func tracks(_ url: URL) async throws -> Tracks {
        let asset = AVURLAsset(url: url)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videos.first, "\(url.lastPathComponent) has no picture")
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let audioRange = try await audio.first?.load(.timeRange)
        return Tracks(video: try await video.load(.timeRange).duration, audio: audioRange?.duration, audioTracks: audio.count)
    }

    func testTheMuxerPutsMusicBesideThePictureAndCanReplaceIt() async throws {
        let silent = try await silentFilm()
        let music = try render(durationS: 2, encoding: .aac, name: "two.m4a")
        let film = directory.appendingPathComponent("film.mp4")
        try await RecapFilmMuxer.mux(videoFrom: silent, soundtrack: music, to: film)
        let muxed = try await tracks(film)
        XCTAssertEqual(muxed.video.seconds, 2, accuracy: 1e-6, "the picture is unchanged")
        XCTAssertEqual(muxed.audioTracks, 1)
        // AAC's encoder priming: AVFoundation trims the first 2,112 samples of
        // a muxed AAC track implicitly, so the track reads up to that much short
        // at its tail — never at its head (the next test pins the head to the
        // sample). Measured 2026-11-03, handoff §3.2.
        let audio = try XCTUnwrap(muxed.audio).seconds
        XCTAssertLessThanOrEqual(audio, 2 + 1e-6, "the music never outlasts the picture")
        XCTAssertGreaterThanOrEqual(audio, 2 - Self.aacPrimingS - 1e-3, "the music runs as long as the picture")

        // 「換音樂」: the picture comes out of the film itself, its old music is left behind.
        let replaced = directory.appendingPathComponent("replaced.mp4")
        try await RecapFilmMuxer.replaceMusic(in: film, with: music, to: replaced)
        let again = try await tracks(replaced)
        XCTAssertEqual(again.audioTracks, 1, "one soundtrack, not the old one and the new one")
        XCTAssertEqual(again.video.seconds, 2, accuracy: 1e-6)

        // 無音樂.
        let silentAgain = directory.appendingPathComponent("no-music.mp4")
        try await RecapFilmMuxer.replaceMusic(in: film, with: nil, to: silentAgain)
        let none = try await tracks(silentAgain)
        XCTAssertEqual(none.audioTracks, 0)
        XCTAssertEqual(none.video.seconds, 2, accuracy: 1e-6)
    }

    /// AAC encoder delay, in seconds: 2,112 samples at 48 kHz.
    private static let aacPrimingS = 2_112.0 / 48_000

    /// **End to end, as the phone will hear it**: a 40 s film muxed, its music
    /// decoded back by AVFoundation, the final hit found on the end card's
    /// sample. (ffmpeg decodes the same file 2,112 samples late — it does not
    /// apply AAC's implicit priming trim; handoff §3.2.)
    func testTheMuxedFilmKeepsTheFinalHitOnTheEndCard() async throws {
        let silent = try await silentFilm(frames: 400)
        let film = directory.appendingPathComponent("film40.mp4")
        try await RecapFilmMuxer.mux(
            videoFrom: silent, soundtrack: try render(durationS: 40, encoding: .aac, name: "forty.m4a"), to: film
        )
        let asset = AVURLAsset(url: film, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false, AVNumberOfChannelsKey: 1
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var decoded: [Float] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            var bytes = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / 4)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count * 4, destination: &bytes)
            decoded += bytes
        }
        let endCard = 37 * 48_000
        let onset = try XCTUnwrap((endCard - 4_800..<endCard + 4_800).first {
            abs(decoded[$0]) > SyntheticSoundtrack.hitAmplitude * 0.6
        })
        XCTAssertLessThanOrEqual(abs(onset - endCard), 1, "the muxed film's final hit is \(onset - endCard) samples off")
    }

    func testTheMuxerRefusesToWriteOverItsOwnPicture() async throws {
        let silent = try await silentFilm()
        do {
            try await RecapFilmMuxer.mux(videoFrom: silent, soundtrack: nil, to: silent)
            XCTFail("muxed a film over the file it was reading")
        } catch is RecapFilmMuxer.MuxError {}
    }
}
