import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence

/// **Changing a finished film's music** (`Docs/handoff-music-in-the-film.md`
/// §1 property 3, §3.2, §4.2): the player's 「換音樂」, and 「再試一次」 when the
/// export kept a silent film because its music failed.
///
/// The picture is never drawn again: the new music is arranged to the cue
/// sheet the film was made with (`FilmSoundtrackBasis`), rendered, and muxed
/// beside the film's own video track into a temporary file — the preview. Only
/// 「使用這首」 (`use`) moves it into the film's place; closing throws it away.
enum FilmMusicChange {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// One row of 「換音樂」. Labelled by mood, never by region (§4.4: a
    /// screenshot is shared).
    struct Option: Identifiable, Equatable {
        /// The track id, or nil for 無音樂.
        let trackId: String?
        let mood: SoundtrackMood?
        /// 1 for the first track of its mood in the list, 2 for the next.
        let take: Int
        let isCurrent: Bool

        var id: String { trackId ?? "none" }
    }

    /// The film's basis, or nil for a film made before music — it has no cue
    /// sheet to cut new music to, so 「換音樂」 is not offered.
    static func basis(of film: FilmRecord) -> FilmSoundtrackBasis? {
        guard film.soundtrackPlanVersion == FilmSoundtrackBasis.planVersion,
              let data = film.soundtrackBasis?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FilmSoundtrackBasis.self, from: data)
    }

    /// **What 「換音樂」 lists** (§4.2): the current choice, the next two by the
    /// picker's score, and 無音樂. nil when the film has no basis.
    static func options(for film: FilmRecord, catalog: SoundtrackCatalog) -> [Option]? {
        guard let basis = basis(of: film) else { return nil }
        let ranked = basis.ranking.filter { catalog.manifest(id: $0) != nil }
        var ids: [String] = []
        if let current = film.soundtrackId, ranked.contains(current) { ids.append(current) }
        ids += ranked.filter { $0 != film.soundtrackId }.prefix(2)
        var seen: [SoundtrackMood: Int] = [:]
        var options = ids.map { id -> Option in
            let mood = catalog.manifest(id: id).flatMap { SoundtrackMood(rawValue: $0.mood) }
            let take = mood.map { mood -> Int in
                seen[mood, default: 0] += 1
                return seen[mood] ?? 1
            } ?? 1
            return Option(trackId: id, mood: mood, take: take, isCurrent: id == film.soundtrackId)
        }
        options.append(Option(trackId: nil, mood: nil, take: 1, isCurrent: film.soundtrackId == nil))
        return options
    }

    /// The music the export would have added: the ranking's first track.
    static func automaticTrackId(for film: FilmRecord) -> String? {
        basis(of: film)?.ranking.first
    }

    /// **Renders `trackId` (nil = 無音樂) beside the film's picture** into a
    /// temporary film and returns it. Seconds, never a redraw (§4.1a).
    @MainActor
    static func preview(film: FilmRecord, trackId: String?, config: TrackingConfig) async throws -> URL {
        guard let filmURL = FilmStore.resolvedURL(relativePath: film.relativePath),
              let basis = basis(of: film) else { throw Failure(description: "the film has no basis to cut music to") }
        let catalog = SoundtrackCatalog.bundled(limits: config.soundtrack)
        var track: FilmSoundtrackPlan.Track?
        if let trackId {
            guard let manifest = catalog.manifest(id: trackId), let durationS = film.durationS,
                  let arranged = FilmSoundtrack.arranged(
                      manifest, cues: basis.cues, durationS: durationS, catalog: catalog, config: config
                  ) else { throw Failure(description: "the track cannot be arranged to this film") }
            track = arranged
        }
        let soundtrack = config.soundtrack
        let started = ContinuousClock.now
        let output = FilmSoundtrack.scratchURL(extension: "mp4", preview: true)
        let musicS = try await Task.detached(priority: .userInitiated) { () -> Double in
            let musicStarted = ContinuousClock.now
            let audio = try track.map { try FilmSoundtrack.render($0, config: soundtrack, preview: true) }
            defer { audio.map { try? FileManager.default.removeItem(at: $0) } }
            let seconds = (ContinuousClock.now - musicStarted) / .seconds(1)
            try await RecapFilmMuxer.replaceMusic(in: filmURL, with: audio, to: output)
            return seconds
        }.value
        let totalS = (ContinuousClock.now - started) / .seconds(1)
        KamomeLog.recap.notice("""
            music changed (preview): music \(musicS, format: .fixed(precision: 2))s · \
            mux \(totalS - musicS, format: .fixed(precision: 2))s
            """)
        return output
    }

    /// **「使用這首」**: the preview takes the film's place, and the row says
    /// which track it now carries. Returns the updated record, or nil when the
    /// film was deleted meanwhile (the preview is then discarded).
    @MainActor
    static func use(preview: URL, film: FilmRecord, trackId: String?, repository: TripRepository) throws -> FilmRecord? {
        guard let filmURL = FilmStore.resolvedURL(relativePath: film.relativePath) else {
            throw Failure(description: "the film's file cannot be found")
        }
        _ = try FileManager.default.replaceItemAt(filmURL, withItemAt: preview)
        let updated = try repository.setFilmSoundtrack(
            filmId: film.id, soundtrackId: trackId, fileBytes: FilmStore.fileSize(at: filmURL)
        )
        if updated == nil { FilmStore.deleteFile(relativePath: film.relativePath) }
        return updated
    }

    /// Removes a preview nobody used.
    static func discard(preview: URL?) {
        preview.map { try? FileManager.default.removeItem(at: $0) }
    }
}
