import Foundation
import KamomeConfig
import KamomeExportEngine

/// **The film's music in the export** (`Docs/handoff-music-in-the-film.md` §4.1):
///
///     plan ─► pick ─► photos ─┬─► draw + encode video (minutes) ─┬─► mux ─► store
///                             └─► arrange + render audio ────────┘
///
/// The picker runs after the plan and before the drawing; the audio renders
/// alongside the drawing and the mux follows the last frame. Its own file
/// because `RecapExportJob+Render.swift` is at its length limit.
///
/// **A soundtrack failure does not lose the film** (§4.1): the silent film is
/// kept, the channel says so, and the finished screen offers 「再試一次」,
/// which re-runs only the music and the mux (`FilmMusicChange`). Not a silent
/// fallback — the person is told (`CHARTER.md` §4).
extension RecapExportJob {
    /// The rendered audio and how long it took, or why it failed.
    typealias MusicResult = Result<(url: URL, seconds: Double), Error>

    /// The picker's answer for this film (§2.3).
    func pickSoundtrack(composed: Composed, plan: Plan) -> FilmSoundtrackPlan {
        FilmSoundtrack.plan(
            timeline: plan.timeline, trip: composed.trip, analyses: composed.detail.analyses,
            appearance: plan.appearance, request: request, config: config
        )
    }

    /// Starts the audio render beside the drawing; nil when there is no track.
    func startMusic(_ soundtrack: FilmSoundtrackPlan, channel: RecapExportChannel) -> Task<MusicResult, Never>? {
        guard let track = soundtrack.track else { return nil }
        let (config, shouldContinue) = (config.soundtrack, channel.shouldContinue)
        return Task.detached(priority: .userInitiated) {
            let started = ContinuousClock.now
            do {
                let url = try FilmSoundtrack.render(track, config: config, shouldContinue: shouldContinue)
                return .success((url, (ContinuousClock.now - started) / .seconds(1)))
            } catch {
                return .failure(error)
            }
        }
    }

    /// **After the last frame**: waits for the music and muxes it beside the
    /// picture. Returns the film to store and the track it carries — the
    /// silent video and nil when there was no music to add or it failed.
    func finishMusic(
        _ task: Task<MusicResult, Never>?, soundtrack: FilmSoundtrackPlan, videoURL: URL,
        clock: ExportStageClock, channel: RecapExportChannel
    ) async -> (url: URL, soundtrackId: String?) {
        guard let task, let track = soundtrack.track else { return (videoURL, nil) }
        clock.enter("mux")
        let audio: URL
        switch await task.value {
        case let .success(rendered):
            clock.record("music", seconds: rendered.seconds)
            audio = rendered.url
        case let .failure(error):
            return musicFailed(error, videoURL: videoURL, channel: channel)
        }
        defer { try? FileManager.default.removeItem(at: audio) }
        let film = FilmSoundtrack.scratchURL(extension: "mp4")
        do {
            try await RecapFilmMuxer.mux(videoFrom: videoURL, soundtrack: audio, to: film)
        } catch {
            try? FileManager.default.removeItem(at: film)
            return musicFailed(error, videoURL: videoURL, channel: channel)
        }
        // The film takes the silent video's name, so a film with music is
        // stored exactly as one without it.
        do {
            _ = try FileManager.default.replaceItemAt(videoURL, withItemAt: film)
        } catch {
            try? FileManager.default.removeItem(at: film)
            return musicFailed(error, videoURL: videoURL, channel: channel)
        }
        return (videoURL, track.manifest.id)
    }

    /// The video, and the music once its render has stopped (it reads the
    /// same cancel flag; a failed export waits for it only to delete its file).
    func cleanup(videoURL: URL, music: Task<MusicResult, Never>? = nil) {
        try? FileManager.default.removeItem(at: videoURL)
        guard let music else { return }
        Task {
            if case let .success(rendered) = await music.value { try? FileManager.default.removeItem(at: rendered.url) }
        }
    }

    private func musicFailed(
        _ error: Error, videoURL: URL, channel: RecapExportChannel
    ) -> (url: URL, soundtrackId: String?) {
        // The domain and code only: a muxer error can name a file, never a place,
        // but the description is not ours to vouch for.
        KamomeLog.recap.error("""
            music: could not be added — \(Self.failureCode(error), privacy: .public); \
            the silent film is kept and the sheet offers to try again
            """)
        channel.musicFailed()
        return (videoURL, nil)
    }
}
