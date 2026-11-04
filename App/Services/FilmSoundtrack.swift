import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence

/// The person's answer on the film sheet's 「音樂」 row (handoff-music §4.2).
/// 自動 is the default (Chiu 2026-11-03, ADR
/// 2026-11-03-the-film-chooses-its-music-and-plays-it-on-silent).
enum FilmMusicChoice: String, Sendable, CaseIterable {
    case auto
    case none
}

/// **The film's music, decided before a frame is drawn** (handoff-music §4.1):
/// the basis a later 「換音樂」 cuts to, and — unless the person chose 無音樂 or
/// no track fits — the track and its arrangement.
struct FilmSoundtrackPlan: @unchecked Sendable {
    struct Track {
        let manifest: SoundtrackManifest
        let audioURL: URL
        let plan: SoundtrackPlan
    }

    let basis: FilmSoundtrackBasis
    let track: Track?

    /// The basis as the film row stores it.
    var basisJSON: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(basis)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// **The app's half of the film's music** (`Docs/handoff-music-in-the-film.md`
/// §2.3, §4.1): the picker's context built from the trip, the pick, and the
/// render of one track into a soundtrack file. ExportEngine decides; this
/// file only gathers what it decides from.
///
/// **§0 (§4.4).** The style is the trip's country in disguise, so it is never
/// in a log line, `ExportLogHistory` or the film's metadata. Nor is the track
/// id, which begins with its style: the handoff's `.private` was measured not
/// to hold — on the simulator a `.private` value read back in full into the
/// kept export history (2026-11-04). Logs say counts and times; the film's row
/// keeps which track it carries, on the device.
enum FilmSoundtrack {
    // MARK: - The pick

    @MainActor
    static func plan(
        timeline: LinearTimeline, trip: RecapTrip, analyses: [String: PhotoAnalysisRecord],
        appearance: RecapAppearance, request: RecapExportRequest, config: TrackingConfig
    ) -> FilmSoundtrackPlan {
        let (tripId, choice) = (request.tripId, request.music)
        let started = ContinuousClock.now
        let catalog = SoundtrackCatalog.bundled(limits: config.soundtrack)
        let cues = timeline.cueSheet()
        let context = context(
            timeline: timeline, trip: trip, analyses: analyses, appearance: appearance, tripId: tripId, config: config
        )
        let ranking = SoundtrackPicker.rank(
            catalog: catalog.manifests, context: context, cues: cues, config: config.soundtrack
        )
        let basis = FilmSoundtrackBasis(cues: cues, ranking: ranking.choices.map(\.manifest.id))
        if ranking.styleFellBack {
            // A declared fallback, said without naming either style (§4.4).
            KamomeLog.recap.notice("music: the trip's own style has no track that fits this film — another style plays")
        }
        var track: FilmSoundtrackPlan.Track?
        if choice == .auto, let best = ranking.choices.first {
            track = arranged(best.manifest, cues: cues, durationS: timeline.durationS, catalog: catalog, config: config)
        }
        let ms = (ContinuousClock.now - started) / .milliseconds(1)
        KamomeLog.recap.notice("""
            music: \(Self.outcome(choice: choice, track: track), privacy: .public) \
            in \(ms, format: .fixed(precision: 0)) ms · plan \(cues.count) cues · \
            \(ranking.choices.count) tracks fit · \(context.photoMood.photoCount) photographs measured
            """)
        return FilmSoundtrackPlan(basis: basis, track: track)
    }

    private static func outcome(choice: FilmMusicChoice, track: FilmSoundtrackPlan.Track?) -> String {
        choice == .none ? "none asked" : track == nil ? "NO TRACK FITS — the film is silent" : "picked"
    }

    /// The track and its arrangement for these cues, or nil when its audio is
    /// missing or the arrangement refuses — both logged.
    static func arranged(
        _ manifest: SoundtrackManifest, cues: [FilmCue], durationS: Double, catalog: SoundtrackCatalog,
        config: TrackingConfig
    ) -> FilmSoundtrackPlan.Track? {
        guard let audioURL = catalog.audioURL(for: manifest) else {
            KamomeLog.recap.error("music: a track's audio is missing from the bundle")
            return nil
        }
        do {
            let plan = try SoundtrackArrangement.plan(
                manifest: manifest, cues: cues, durationS: durationS, config: config.soundtrack
            )
            return FilmSoundtrackPlan.Track(manifest: manifest, audioURL: audioURL, plan: plan)
        } catch {
            // Fixed words only: the arrangement's message names the track.
            KamomeLog.recap.error("music: the arrangement refused a track")
            return nil
        }
    }

    /// **What the picker knows** (§2.3), from the timeline (country by film
    /// time, film type, duration), the analyser's rows for the photographs the
    /// film shows, the appearance it is drawn in and the trip's id.
    static func context(
        timeline: LinearTimeline, trip: RecapTrip, analyses: [String: PhotoAnalysisRecord],
        appearance: RecapAppearance, tripId: String, config: TrackingConfig
    ) -> SoundtrackContext {
        let countries = timeline.soundtrackCountries()
        return SoundtrackContext(
            countryShare: countries.share, destinationCountry: countries.destination,
            photoMood: photoMood(
                trip: trip, analyses: analyses, nightLuminanceMax: config.soundtrack.mood.nightLuminanceMax
            ),
            filmType: timeline.filmType, durationS: timeline.durationS, appearance: appearance,
            seed: SoundtrackContext.seed(tripId: tripId)
        )
    }

    /// The mood of the photographs the film shows. Rows from the version-1
    /// analyser carry no mood and are left out; with none left the mood is
    /// neutral and the film's shape decides (§2.4).
    static func photoMood(
        trip: RecapTrip, analyses: [String: PhotoAnalysisRecord], nightLuminanceMax: Double
    ) -> PhotoMood {
        let photos = trip.stops.flatMap(\.photos).compactMap { ref -> PhotoMood.Photo? in
            guard case let .asset(id) = ref, let row = analyses[id], row.version >= PhotoAnalysisVersion.mood,
                  let luminance = row.luminance, let saturation = row.saturation, let warmth = row.warmth
            else { return nil }
            return PhotoMood.Photo(
                labels: row.sceneLabels ?? 0, luminance: luminance, saturation: saturation, warmth: warmth
            )
        }
        return PhotoMood(photos: photos, nightLuminanceMax: nightLuminanceMax)
    }

    // MARK: - The render

    /// Renders `track` into a scratch `.m4a` and returns it. Reads
    /// `shouldContinue` between chunks; a cancelled render leaves no file.
    nonisolated static func render(
        _ track: FilmSoundtrackPlan.Track, config: TrackingConfig.Soundtrack, preview: Bool = false,
        shouldContinue: @escaping () -> Bool = { true }
    ) throws -> URL {
        let url = scratchURL(extension: "m4a", preview: preview)
        try RecapSoundtrackRenderer(config: config).render(
            plan: track.plan, trackURL: track.audioURL, to: url, shouldContinue: shouldContinue
        )
        return url
    }

    /// A fresh file in tmp. An export's own files take the render prefix, so
    /// `sweepLeftoverRenders` finds a killed one's; a 「換音樂」 preview takes
    /// its own, so an export starting meanwhile never sweeps it away.
    nonisolated static func scratchURL(extension ext: String, preview: Bool = false) -> URL {
        let prefix = preview ? previewFilePrefix : "\(RecapExportJob.renderFilePrefix)music-"
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)\(UUID().uuidString).\(ext)")
    }

    nonisolated static let previewFilePrefix = "kamome-music-preview-"
}
