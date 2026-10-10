import CoreGraphics
import Foundation
import ImageIO
import KamomeExportEngine
import KamomePersistence

/// **Kamome's sample trip** (ADR 2026-09-28-sample-trip): Hualien to Taitung, one
/// day, five public places, created only when the person asks for it on an empty
/// Home.
///
/// Everything it needs ships in `App/Resources/SampleTrip/`: the places, the
/// road between them — OpenStreetMap data, routed once and stored, so the sample
/// never asks the routing relay and never spends its quota — and drawings in
/// place of photographs.
///
/// **Honest provenance.** Its source is `TripSource.sample`, its legs are
/// `SegmentSource.sample`, and its drawings are named by `assetPrefix`, so no
/// screen can mistake it for something the person did.
enum SampleTrip {
    /// The asset id of a sample drawing is this prefix plus the drawing's name.
    /// Never a PhotoKit local identifier, which is a UUID-shaped string.
    static let assetPrefix = "kamome-sample/"

    enum Failure: Error {
        case manifestMissing
        case manifestUnreadable
        case badTime(String)
    }

    // MARK: - Drawings

    static func isSampleAsset(_ assetId: String) -> Bool {
        assetId.hasPrefix(assetPrefix)
    }

    /// The bundled file behind a sample asset id, or nil for any other id.
    static func imageURL(assetId: String, bundle: Bundle = .main) -> URL? {
        guard isSampleAsset(assetId) else { return nil }
        let name = String(assetId.dropFirst(assetPrefix.count))
        return bundle.url(forResource: "sample-\(name)", withExtension: "png")
    }

    /// A sample drawing's ref as the bundled file it is; any other ref unchanged.
    static func onDisk(_ ref: PhotoRef, bundle: Bundle = .main) -> PhotoRef {
        guard case let .asset(id) = ref, let url = imageURL(assetId: id, bundle: bundle) else { return ref }
        return .file(url)
    }

    static func image(assetId: String, bundle: Bundle = .main) -> CGImage? {
        guard let url = imageURL(assetId: assetId, bundle: bundle),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - The manifest

    struct Manifest: Decodable {
        struct Stop: Decodable {
            let id: String
            let names: [String: String]
            let lat: Double
            let lon: Double
            let arrive: String
            let depart: String
            let photos: [String]
        }

        struct Leg: Decodable {
            let polyline: String
        }

        let version: Int
        let titles: [String: String]
        let date: String
        let timeZone: String
        let stops: [Stop]
        let legs: [Leg]
        let film: ManifestFilm?

        enum CodingKeys: String, CodingKey {
            case version, titles, date, stops, legs, film
            case timeZone = "time_zone"
        }
    }

    /// The sample's own film, already made (#285): a bundled MP4 per app
    /// language, and the facts its `FilmRecord` carries. Beside `Manifest`
    /// rather than inside it, for the nesting limit.
    struct ManifestFilm: Decodable {
        let files: [String: String]
        let durationS: Double
        let appearance: String
        let recapMode: String

        enum CodingKeys: String, CodingKey {
            case files
            case durationS = "duration_s"
            case appearance
            case recapMode = "recap_mode"
        }
    }

    static func manifest(bundle: Bundle = .main) throws -> Manifest {
        guard let url = bundle.url(forResource: "sample-trip", withExtension: "json") else {
            throw Failure.manifestMissing
        }
        do {
            return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        } catch {
            throw Failure.manifestUnreadable
        }
    }

    /// `zh-Hant` when the app is showing Chinese, English otherwise — the same
    /// two languages the app ships.
    static func text(_ values: [String: String], localizations: [String] = Bundle.main.preferredLocalizations) -> String {
        let chinese = localizations.first?.hasPrefix("zh") == true
        return (chinese ? values["zh-Hant"] : values["en"]) ?? values["en"] ?? values.values.first ?? ""
    }

    // MARK: - Creating it

    /// Writes the sample as a trip and returns its id. All or nothing: a
    /// failure part-way deletes what was written, so a half-built sample —
    /// one routing would then try to route — never survives.
    @discardableResult
    static func create(
        repository: TripRepository,
        vehicleId: String,
        bundle: Bundle = .main,
        localizations: [String] = Bundle.main.preferredLocalizations
    ) throws -> String {
        let manifest = try manifest(bundle: bundle)
        let times: [Visit] = try manifest.stops.map { stop in
            (arrive: try epoch(manifest.date, stop.arrive, manifest.timeZone),
             depart: try epoch(manifest.date, stop.depart, manifest.timeZone))
        }

        let segments = newSegments(manifest, times: times)
        let stops = newStops(manifest, times: times)

        let tripId = try repository.saveImportedTrip(
            TripRepository.ImportedTrip(
                title: text(manifest.titles, localizations: localizations),
                startedAt: times.first?.arrive ?? 0,
                endedAt: times.last?.depart ?? 0,
                source: TripSource.sample.rawValue,
                segments: segments,
                stopsWithPhotos: stops,
                routeAttachedPhotos: []
            )
        )
        do {
            guard let detail = try repository.detail(tripId: tripId),
                  detail.segments.count == manifest.legs.count,
                  detail.stops.count == manifest.stops.count
            else { throw Failure.manifestUnreadable }
            // Stored in trip order: segments by start, stops by arrival.
            let segmentsInOrder = detail.segments.map(\.segment).sorted { $0.startedAt < $1.startedAt }
            for (segment, leg) in zip(segmentsInOrder, manifest.legs) {
                try repository.setMatchedPolyline(segmentId: segment.id, encodedPolyline: leg.polyline)
                try repository.setRoutability(segmentId: segment.id, .road)
            }
            // Named here, never looked up: the sample asks nobody where it is.
            let stopsInOrder = detail.stops.sorted { $0.arrivedAt < $1.arrivedAt }
            for (record, stop) in zip(stopsInOrder, manifest.stops) {
                try repository.setStopName(stopId: record.id, name: text(stop.names, localizations: localizations))
            }
            try repository.setTripVehicle(tripId: tripId, vehicleId: vehicleId)
        } catch {
            _ = try? repository.deleteTrip(tripId: tripId)
            throw error
        }
        return tripId
    }

    // MARK: - Its film

    enum FilmFailure: Error, Equatable {
        case noFilmInManifest
        /// No film ships in the app's language: only the Chinese one does
        /// (Chiu 2026-10-10). Expected in an English app, not a fault.
        case noFilmForLanguage
        case filmMissing(String)
    }

    /// **The sample arrives with its film** (Chiu 2026-10-10, #285): 「先看一支
    /// 範例影片」 promised a film, and the person got a map, a form and a
    /// three-minute render. The film is this app's own render of this trip,
    /// shipped in the bundle, so it plays the moment it is asked for. **Only the
    /// Chinese film ships** (Chiu 2026-10-10: 12 MB for two was too much): an
    /// English app gets none rather than a Chinese film beside English names.
    /// It is stored like any film — copied into `Films/` with its own row — so
    /// it plays, saves, shares and deletes like one, and a new export from the
    /// sample still renders from scratch.
    ///
    /// No render time is recorded: nothing was rendered on this phone.
    @discardableResult
    static func attachFilm(
        tripId: String,
        repository: TripRepository,
        bundle: Bundle = .main,
        localizations: [String] = Bundle.main.preferredLocalizations,
        filmsDirectory: () throws -> URL = FilmStore.filmsDirectory
    ) throws -> FilmRecord {
        guard let film = try manifest(bundle: bundle).film else { throw FilmFailure.noFilmInManifest }
        // Exactly the app's language, never `text`'s fallback to another one.
        let language = localizations.first?.hasPrefix("zh") == true ? "zh-Hant" : "en"
        guard let name = film.files[language] else { throw FilmFailure.noFilmForLanguage }
        guard let source = bundle.url(forResource: name, withExtension: "mp4") else {
            throw FilmFailure.filmMissing(name)
        }
        let fileName = "kamome-sample-\(UUID().uuidString).mp4"
        let destination = try filmsDirectory().appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: source, to: destination)
        let record = FilmRecord(
            id: UUID().uuidString,
            tripId: tripId,
            relativePath: "\(FilmStore.directoryName)/\(fileName)",
            format: "mp4",
            createdAt: Date.now.timeIntervalSince1970,
            durationS: film.durationS,
            renderSeconds: nil,
            appearance: film.appearance,
            recapMode: film.recapMode,
            fileBytes: FilmStore.fileSize(at: destination)
        )
        do {
            try repository.saveFilm(record)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return record
    }

    private typealias Visit = (arrive: Double, depart: Double)

    /// One leg per pair of stops: its two ends as trackpoints, its road added
    /// after the save as `matched_polyline`.
    private static func newSegments(_ manifest: Manifest, times: [Visit]) -> [TripRepository.NewSegment] {
        manifest.legs.indices.map { index in
            let from = manifest.stops[index], to = manifest.stops[index + 1]
            return TripRepository.NewSegment(
                mode: "drive",
                startedAt: times[index].depart,
                endedAt: times[index + 1].arrive,
                points: [
                    TripRepository.NewTrackpoint(ts: times[index].depart, lat: from.lat, lon: from.lon),
                    TripRepository.NewTrackpoint(ts: times[index + 1].arrive, lat: to.lat, lon: to.lon)
                ],
                source: SegmentSource.sample.rawValue
            )
        }
    }

    private static func newStops(_ manifest: Manifest, times: [Visit]) -> [TripRepository.NewStopWithPhotos] {
        zip(manifest.stops, times).map { stop, time in
            TripRepository.NewStopWithPhotos(
                stop: TripRepository.NewStop(lat: stop.lat, lon: stop.lon, arrivedAt: time.arrive, departedAt: time.depart),
                photos: stop.photos.enumerated().map { offset, name in
                    TripRepository.NewPhoto(
                        assetId: assetPrefix + name,
                        // Inside the visit, a quarter-hour apart, so the deck keeps their order.
                        takenAt: time.arrive + Double(offset + 1) * 900,
                        lat: stop.lat, lon: stop.lon
                    )
                }
            )
        }
    }

    /// `2025-11-15` + `08:30` in `Asia/Taipei`, as seconds since 1970.
    static func epoch(_ date: String, _ time: String, _ zone: String) throws -> Double {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let parsed = formatter.date(from: "\(date) \(time)") else { throw Failure.badTime("\(date) \(time)") }
        return parsed.timeIntervalSince1970
    }
}
