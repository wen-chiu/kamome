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

    var startDate: Date
    var endDate: Date
    private(set) var phase: Phase = .idle
    /// Set once the import succeeds; the view observes it to dismiss and push S3.
    private(set) var completedTripId: String?

    private let config: TrackingConfig
    private let source: ImportPhotoProviding
    private let service: ImportService
    private let photoService: PhotoLibraryService

    init(
        config: TrackingConfig,
        repository: TripRepository,
        source: ImportPhotoProviding = PhotoLibraryImportSource(),
        now: Date = .now
    ) {
        self.config = config
        self.source = source
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

    /// Fetch geotagged photos in the picked range and reconstruct a trip.
    func runImport() async {
        phase = .importing
        let bounds = dayBounds()
        let photos = await source.photos(from: bounds.from, to: bounds.to)
        do {
            let tripId = try await service.importTrip(title: title(for: bounds), photos: photos)
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
