import Foundation
import KamomeConfig
import KamomePersistence
import KamomeTripComposer
import Observation

/// Backs S3/S4: loads one trip, then lazily composes it — photo matching on
/// first open, reverse-geocoded names for unnamed stops.
@Observable
final class TripDetailModel {
    private(set) var detail: TripRepository.TripDetail?
    private(set) var selectedDay: Int?

    let tripId: String
    private let repository: TripRepository
    private let config: TrackingConfig
    private let photoService: PhotoLibraryService
    private let namer: StopNamer

    init(tripId: String, config: TrackingConfig, repository: TripRepository) {
        self.tripId = tripId
        self.config = config
        self.repository = repository
        photoService = PhotoLibraryService(config: config, repository: repository)
        namer = StopNamer(config: config, repository: repository)
    }

    func load() {
        detail = try? repository.detail(tripId: tripId)
        guard let detail else { return }

        if detail.photos.isEmpty, let endedAt = detail.trip.endedAt {
            photoService.matchPhotos(
                tripId: tripId,
                startedAt: detail.trip.startedAt,
                endedAt: endedAt,
                stops: detail.stops
            ) { [weak self] matched in
                if matched > 0 { self?.reload() }
            }
        }
        let unnamed = detail.stops.filter { $0.name == nil }
        if !unnamed.isEmpty {
            namer.nameUnnamedStops(unnamed)
            // Names land asynchronously; refresh shortly after.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.reload()
            }
        }
    }

    func reload() {
        detail = try? repository.detail(tripId: tripId)
    }

    // MARK: - Days (S3 filter chips)

    var dayCount: Int {
        guard let detail, let endedAt = detail.trip.endedAt else { return 1 }
        return max(1, Int((endedAt - detail.trip.startedAt) / 86_400) + 1)
    }

    func selectDay(_ day: Int?) {
        selectedDay = day
    }

    func dayIndex(of timestamp: Double) -> Int {
        guard let detail else { return 0 }
        return Int((timestamp - detail.trip.startedAt) / 86_400)
    }

    var visibleStops: [StopRecord] {
        guard let detail else { return [] }
        guard let selectedDay else { return detail.stops }
        return detail.stops.filter { dayIndex(of: $0.arrivedAt) == selectedDay }
    }

    var visibleSegments: [(segment: SegmentRecord, points: [TrackpointRecord])] {
        guard let detail else { return [] }
        guard let selectedDay else { return detail.segments }
        return detail.segments.filter { dayIndex(of: $0.segment.startedAt) == selectedDay }
    }

    /// Display polyline per segment, Douglas-Peucker-thinned (§4.4).
    func displayPolyline(for points: [TrackpointRecord]) -> [Simplifier.Point] {
        Simplifier.douglasPeucker(
            points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) },
            epsilonM: config.simplify.epsilonM
        )
    }

    var stats: TripStats? {
        TripStats.from(jsonString: detail?.trip.statsJson)
    }

    func photos(for stopId: String) -> [PhotoRefRecord] {
        detail?.photos.filter { $0.stopId == stopId } ?? []
    }

    /// §4.3 route-attached photos (stop_id NULL — taken mid-drive, away from
    /// any stop): they get their own timeline strip instead of a stop's.
    var routePhotos: [PhotoRefRecord] {
        detail?.photos.filter { $0.stopId == nil } ?? []
    }

    var photoAccessIsLimited: Bool {
        photoService.isLimitedAccess
    }

    /// Opens the system picker so a limited selection can grow, then
    /// re-matches: photos added there should land on this trip immediately.
    func manageLimitedPhotoSelection() {
        photoService.presentLimitedLibraryPicker { [weak self] in
            self?.rematchPhotos()
        }
    }

    private func rematchPhotos() {
        guard let detail, let endedAt = detail.trip.endedAt else { return }
        photoService.matchPhotos(
            tripId: tripId,
            startedAt: detail.trip.startedAt,
            endedAt: endedAt,
            stops: detail.stops
        ) { [weak self] _ in
            self?.reload()
        }
    }

    // MARK: - S4 editing

    func rename(stopId: String, to name: String) {
        try? repository.setStopName(stopId: stopId, name: name)
        reload()
    }

    func setNote(stopId: String, note: String) {
        try? repository.setStopNote(stopId: stopId, note: note.isEmpty ? nil : note)
        reload()
    }

    func deleteStop(stopId: String) {
        try? repository.deleteStop(stopId: stopId)
        reload()
    }

    func mergeWithPrevious(stopId: String) {
        guard let detail,
              let index = detail.stops.firstIndex(where: { $0.id == stopId }),
              index > 0 else { return }
        try? repository.mergeStops(keptId: detail.stops[index - 1].id, absorbedId: stopId)
        reload()
    }

    func toggleHighlight(photo: PhotoRefRecord) {
        try? repository.setPhotoHighlight(photoId: photo.id, isHighlight: photo.isHighlight == 0)
        reload()
    }
}
