@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **A whole film with its music, rendered at the desk** — `Docs/handoff-music-in-the-film.md`
/// §8 PR A, judged by Chiu's ear. Env-gated, never CI.
///
/// It does what the export will do (§4.1): the timeline is planned, the music is
/// arranged from its cue sheet and rendered **while the map draws**, then the
/// two are muxed with the picture copied. Then the music is rendered and muxed a
/// second time with nothing else running — what 「換音樂」 costs. Every stage is
/// timed and printed, so §4.1a's numbers are measured rather than modelled.
///
///   TEST_RUNNER_KAMOME_SOUNDTRACK=margaret-river \
///   TEST_RUNNER_KAMOME_SOUNDTRACK_TRACK=$HOME/Kamome-music/kept/anthem-depart-s1855554642.m4a \
///   TEST_RUNNER_KAMOME_FORCE_DURATION_S=90 \
///   xcodebuild -scheme Kamome test -destination '…' -only-testing:KamomeTests/RecapSoundtrackFilmTests
///
/// `KAMOME_SOUNDTRACK_TRACK` is a real track (`.m4a` or `.wav`) with its
/// manifest beside it under the same name, `.json` — written by
/// `Tools/kamome-beatmap.py`. Without it the synthetic click track plays
/// (`SyntheticSoundtrack`). Films go to `~/Kamome-films/soundtrack/` on the Mac
/// unless `KAMOME_RENDER_OUT` says otherwise. Audio never enters the repository.
final class RecapSoundtrackFilmTests: XCTestCase {
    private struct Stage {
        let name: String
        let seconds: Double
    }

    func testRenderFilmWithMusic() async throws {
        let fixture = HarnessEnv.value("KAMOME_SOUNDTRACK") ?? ""
        try XCTSkipUnless(!fixture.isEmpty, "Manual listening harness — set KAMOME_SOUNDTRACK to a fixture name.")
        let outDir = try outputDirectory()
        let (trackURL, manifest) = try track(in: outDir)
        let soundtrack = try AppConfig.loadOrDie().soundtrack
        try manifest.validate(limits: soundtrack)
        let scene = try await RecapReviewScene.make(fixture: fixture)
        let timeline = scene.timeline

        var stages: [Stage] = []
        let cues = timeline.cueSheet()
        let plan = try timed("arrange", into: &stages) {
            try SoundtrackArrangement.plan(manifest: manifest, cues: cues, durationS: timeline.durationS, config: soundtrack)
        }
        report(plan: plan, cues: cues, manifest: manifest)

        let name = "\(fixture)-\(Int(timeline.durationS.rounded()))s-\(manifest.id)"
        let silent = outDir.appendingPathComponent("\(name)-silent.mp4")
        let music = outDir.appendingPathComponent("\(name).m4a")
        // The music renders alongside the drawing, as the export will run it.
        let renderer = RecapSoundtrackRenderer(config: soundtrack)
        let musicTask = Task.detached { () -> Double in
            let started = Date.now
            try renderer.render(plan: plan, trackURL: trackURL, to: music)
            return Date.now.timeIntervalSince(started)
        }
        let drawingStarted = Date.now
        try await draw(scene, to: silent)
        stages.append(Stage(name: "drawing + encode", seconds: Date.now.timeIntervalSince(drawingStarted)))
        stages.append(Stage(name: "music (alongside drawing)", seconds: try await musicTask.value))

        let film = outDir.appendingPathComponent("\(name).mp4")
        try await timedAsync("mux", into: &stages) {
            try await RecapFilmMuxer.mux(videoFrom: silent, soundtrack: music, to: film)
        }
        try? FileManager.default.removeItem(at: silent)

        // 「換音樂」: the music again, alone, and the picture taken out of the film.
        let again = outDir.appendingPathComponent("\(name)-again.m4a")
        try timed("music (alone)", into: &stages) { try renderer.render(plan: plan, trackURL: trackURL, to: again) }
        let replaced = outDir.appendingPathComponent("\(name)-again.mp4")
        try await timedAsync("mux (replace)", into: &stages) {
            try await RecapFilmMuxer.replaceMusic(in: film, with: again, to: replaced)
        }
        try? FileManager.default.removeItem(at: again)
        try? FileManager.default.removeItem(at: replaced)

        print("KAMOME_SOUNDTRACK_FILM \(film.path) · \(String(format: "%.1f", timeline.durationS)) s film · "
            + stages.map { "\($0.name) \(String(format: $0.seconds < 1 ? "%.3f" : "%.2f", $0.seconds)) s" }
                .joined(separator: " · "))
        XCTAssertTrue(FileManager.default.fileExists(atPath: film.path))
    }

    // MARK: - Steps

    private func draw(_ scene: RecapReviewScene, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let encoder = try RecapVideoEncoder(
            outputURL: url, widthPx: scene.config.frameWidthPx, heightPx: scene.config.frameHeightPx,
            fps: scene.config.fps, bitrateMbps: scene.config.videoBitrateMbps
        )
        let loop = RecapRenderLoop(timeline: scene.timeline, compositor: scene.compositor,
                                   provider: scene.provider, config: scene.config)
        try await loop.renderFrames { frame, image in
            try encoder.append(image, frame: frame)
            return true
        }
        try await encoder.finish()
    }

    /// The real track and its manifest, or the synthetic one written beside the film.
    private func track(in outDir: URL) throws -> (URL, SoundtrackManifest) {
        guard let path = HarnessEnv.value("KAMOME_SOUNDTRACK_TRACK") else {
            let url = outDir.appendingPathComponent("synthetic-click.wav")
            try SyntheticSoundtrack.write(to: url)
            print("KAMOME_SOUNDTRACK_TRACK unset — the synthetic click track plays")
            return (url, SyntheticSoundtrack.manifest)
        }
        let url = URL(fileURLWithPath: path)
        let manifestURL = url.deletingPathExtension().appendingPathExtension("json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw HarnessError("no manifest at \(manifestURL.path) — run Tools/kamome-beatmap.py on the track first")
        }
        return (url, try JSONDecoder().decode(SoundtrackManifest.self, from: data))
    }

    private func outputDirectory() throws -> URL {
        let url: URL
        if let override = HarnessEnv.value("KAMOME_RENDER_OUT") {
            url = URL(fileURLWithPath: override, isDirectory: true)
        } else if let home = HarnessEnv.value("SIMULATOR_HOST_HOME") {
            url = URL(fileURLWithPath: home).appendingPathComponent("Kamome-films/soundtrack", isDirectory: true)
        } else {
            throw HarnessError("SIMULATOR_HOST_HOME is unset — set KAMOME_RENDER_OUT to say where the film goes")
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// What the music does and when, for the listener to follow — kinds and
    /// seconds only, never a place (§0).
    private func report(plan: SoundtrackPlan, cues: [FilmCue], manifest: SoundtrackManifest) {
        let counts = Dictionary(grouping: cues, by: \.kind).map { "\($0.key.rawValue) \($0.value.count)" }.sorted()
        print("KAMOME_SOUNDTRACK_CUES " + counts.joined(separator: " · "))
        let clips = plan.clips.map {
            String(format: "track %.2f–%.2f s → film %.2f–%.2f s", $0.sourceStartS, $0.sourceEndS, $0.filmStartS, $0.filmEndS)
        }
        print("KAMOME_SOUNDTRACK_PLAN \(manifest.id) · \(String(format: "%.2f", manifest.bpm)) BPM · starts "
            + String(format: "%.2f s into the track · %d repeat(s) · final hit at %.2f s", plan.introOffsetS,
                     plan.repeats, plan.finalHitS)
            + " · " + clips.joined(separator: " | "))
        let accents = plan.accents.map { String(format: "%@ %.2f%@", $0.cue.kind.rawValue, $0.timeS, $0.snapped ? "♪" : "") }
        print("KAMOME_SOUNDTRACK_ACCENTS " + accents.joined(separator: ", "))
    }

    private func timed<T>(_ name: String, into stages: inout [Stage], _ work: () throws -> T) rethrows -> T {
        let started = Date.now
        let result = try work()
        stages.append(Stage(name: name, seconds: Date.now.timeIntervalSince(started)))
        return result
    }

    private func timedAsync(_ name: String, into stages: inout [Stage], _ work: () async throws -> Void) async rethrows {
        let started = Date.now
        try await work()
        stages.append(Stage(name: name, seconds: Date.now.timeIntervalSince(started)))
    }
}
