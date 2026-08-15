import Foundation
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import Observation

/// Backs the S1 "Import from photos" sheet (spec §4.7, Replay MVP): a date
/// range → geotagged photos (`PhotoLibraryImportSource`, PhotoKit confined
/// there) → `ImportService` → an `imported_photos` trip. The heavy lifting is
/// the engine's; this only maps the picked range onto it and tracks UI state.
@MainActor
@Observable
final class ImportFlowModel {
    enum Phase: Equatable {
        case idle
        case importing
        case failed(Failure)
    }

    /// Distinguished only for the friendly message — the engine throws one
    /// error (`notEnoughGeotaggedPhotos`); we look at photo-access state to
    /// tell "you denied access" from "no located photos in this range".
    enum Failure: Equatable {
        case noGeotaggedPhotos
        case accessDenied
    }

    /// Which set of photographs the trip is built from. **The date range is the
    /// default** — album import is additive (Chiu 2026-08-15), for the overseas
    /// case where a date range pulls in the departure country's photos and the
    /// film opens somewhere the trip never went.
    enum Source: String, CaseIterable, Identifiable {
        case dateRange
        case album
        var id: String { rawValue }
    }

    var source: Source = .dateRange
    var startDate: Date
    var endDate: Date
    /// Which album is selected, if any. Nil with `source == .album` means the user
    /// has not picked one yet, and the import button stays disabled.
    var selectedAlbumId: String?
    private(set) var albums: [PhotoAlbum] = []
    private(set) var isLoadingAlbums = false
    private(set) var phase: Phase = .idle
    /// Set once the import succeeds; the view observes it to dismiss and push S3.
    private(set) var completedTripId: String?

    private let config: TrackingConfig
    private let provider: ImportPhotoProviding
    private let service: ImportService
    private let photoService: PhotoLibraryService

    init(
        config: TrackingConfig,
        repository: TripRepository,
        source: ImportPhotoProviding = PhotoLibraryImportSource(),
        now: Date = .now
    ) {
        self.config = config
        provider = source
        service = ImportService(repository: repository, config: config)
        photoService = PhotoLibraryService(config: config, repository: repository)

        let calendar = Calendar.current
        endDate = now
        startDate = calendar.date(
            byAdding: .day, value: -config.photoImport.defaultRangeDays, to: now
        ) ?? now
    }

    var isImporting: Bool { phase == .importing }

    /// Limited Photo Library access — the fetch sees only the user-selected
    /// subset, so the sheet must offer the system picker (Replay MVP gate item).
    /// Only meaningful once authorization has been requested (first import).
    var isLimitedAccess: Bool { photoService.isLimitedAccess }

    /// The album the user picked, for the span the sheet shows before importing.
    var selectedAlbum: PhotoAlbum? {
        selectedAlbumId.flatMap { id in albums.first { $0.id == id } }
    }

    /// Whether the sheet can import: an album run needs an album chosen first.
    var canImport: Bool {
        switch source {
        case .dateRange: return true
        case .album: return selectedAlbumId != nil
        }
    }

    /// Loads the album list. Safe to call repeatedly — the sheet calls it when the
    /// user switches to the album tab, and again after the limited-library picker
    /// changes the selection, because under `.limited` that is exactly what
    /// changes which albums are visible at all.
    func loadAlbums() async {
        isLoadingAlbums = true
        albums = await provider.albums()
        if let selectedAlbumId, !albums.contains(where: { $0.id == selectedAlbumId }) {
            // The picked album vanished (limited selection changed, album deleted).
            // Dropping it keeps `canImport` honest rather than importing nothing.
            self.selectedAlbumId = nil
        }
        isLoadingAlbums = false
    }

    /// Fetch geotagged photos for the chosen source and reconstruct a trip.
    ///
    /// **Both sources land in the same call and therefore the same failure.** An
    /// album with no geotagged photographs must fail exactly as an empty date
    /// range does — same message, not a new dead end — so neither path returns
    /// early on an empty fetch; the engine's `notEnoughGeotaggedPhotos` is what
    /// decides, once, for both.
    func runImport() async {
        phase = .importing
        let bounds = dayBounds()
        let query: ImportQuery
        let tripTitle: String
        switch source {
        case .dateRange:
            query = .dateRange(from: bounds.from, to: bounds.to)
            tripTitle = title(for: bounds)
        case .album:
            guard let album = selectedAlbum else {
                phase = .failed(.noGeotaggedPhotos)
                return
            }
            query = .album(id: album.id)
            // The album's own name is the best title a reconstructed trip can
            // have — the user already named this journey.
            tripTitle = album.title.isEmpty ? title(for: bounds) : album.title
        }

        let photos = await provider.photos(matching: query)
        do {
            let tripId = try await service.importTrip(title: tripTitle, photos: photos)
            completedTripId = tripId
        } catch {
            // The only thrown error is `notEnoughGeotaggedPhotos`; an empty
            // fetch from denied access lands here too, so prefer the access
            // message when we can see permission is actually blocked.
            phase = .failed(photoService.isDenied ? .accessDenied : .noGeotaggedPhotos)
        }
    }

    /// System limited-library picker so the selection can grow, then let the
    /// user retry the import against the new set.
    func selectMorePhotos() {
        photoService.presentLimitedLibraryPicker { [weak self] in
            // A grown selection means the previous "not enough" verdict is
            // stale — reset so the Import button (not the error) shows.
            self?.phase = .idle
            // Under `.limited` the selection *is* what makes an album visible, so
            // the album list is stale for the same reason the error is.
            Task { await self?.loadAlbums() }
        }
    }

    /// Full-day bounds around the picked calendar days: a photo taken any time
    /// on the end day should be included, so widen to that day's last second.
    private func dayBounds() -> (from: Date, to: Date) {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: min(startDate, endDate))
        let lastDay = calendar.startOfDay(for: max(startDate, endDate))
        let to = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: lastDay) ?? lastDay
        return (from, to)
    }

    /// Same default-title shape as recorded trips (medium date, no time),
    /// anchored to the range start; the user can rename in S3/S4.
    private func title(for bounds: (from: Date, to: Date)) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: bounds.from)
    }
}
