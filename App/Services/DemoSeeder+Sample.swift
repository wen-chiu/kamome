#if DEBUG
import Foundation
import KamomePersistence

/// Desk seeds built from **the sample's manifest** — public places and the road
/// between them from OpenStreetMap, never anyone's trip (§0) — so the in-app
/// maps can be shot without a tap (#195).
extension DemoSeeder {
    /// `-demo-seed-sample`: the sample as 「先看一支範例影片」 makes it, its film
    /// attached, without the tap. `-demo-open-trip` then opens it in S3 (the
    /// film does not play: that is the tap's route, not this one).
    static func seedSample(repository: TripRepository) {
        guard (try? repository.allTrips().isEmpty) == true,
              let tripId = try? SampleTrip.create(repository: repository, vehicleId: LastVehicleChoice.forNewTrip())
        else { return }
        _ = try? SampleTrip.attachFilm(tripId: tripId, repository: repository)
    }

    /// The leg `seedMixedLegs` leaves without a road: the second of four, so the diary shows both labels above the fold.
    private static let refusedLeg = 1

    /// `-demo-seed-mixed-legs`: the sample's places and roads stored as **a
    /// photo import**, so Footprints lists it (it never lists the sample), with
    /// one leg's road refused (`implausibleRoute`, no `matched_polyline`). One
    /// trip then carries both of #195's cases: legs drawn and labelled as
    /// matched roads, and one drawn as its two photographs and labelled inferred.
    static func seedMixedLegs(repository: TripRepository) {
        guard (try? repository.allTrips().isEmpty) == true,
              let manifest = try? SampleTrip.manifest(),
              let times = try? manifest.stops.map({ stop in
                  (arrive: try SampleTrip.epoch(manifest.date, stop.arrive, manifest.timeZone),
                   depart: try SampleTrip.epoch(manifest.date, stop.depart, manifest.timeZone))
              })
        else { return }
        let segments = manifest.legs.indices.map { index in
            let from = manifest.stops[index], to = manifest.stops[index + 1]
            return TripRepository.NewSegment(
                mode: "drive", startedAt: times[index].depart, endedAt: times[index + 1].arrive,
                points: [
                    TripRepository.NewTrackpoint(ts: times[index].depart, lat: from.lat, lon: from.lon),
                    TripRepository.NewTrackpoint(ts: times[index + 1].arrive, lat: to.lat, lon: to.lon)
                ],
                source: SegmentSource.exif.rawValue
            )
        }
        let stops = zip(manifest.stops, times).map { stop, time in
            TripRepository.NewStopWithPhotos(
                stop: TripRepository.NewStop(lat: stop.lat, lon: stop.lon, arrivedAt: time.arrive, departedAt: time.depart),
                photos: stop.photos.enumerated().map { offset, name in
                    TripRepository.NewPhoto(
                        assetId: SampleTrip.assetPrefix + name, takenAt: time.arrive + Double(offset + 1) * 900,
                        lat: stop.lat, lon: stop.lon
                    )
                }
            )
        }
        guard let tripId = try? repository.saveImportedTrip(TripRepository.ImportedTrip(
            title: "Desk · matched and refused legs", startedAt: times.first?.arrive ?? 0, endedAt: times.last?.depart ?? 0,
            source: TripSource.importedPhotos.rawValue, segments: segments, stopsWithPhotos: stops, routeAttachedPhotos: []
        )), let detail = try? repository.detail(tripId: tripId) else { return }

        let segmentsInOrder = detail.segments.map(\.segment).sorted { $0.startedAt < $1.startedAt }
        for (index, (segment, leg)) in zip(segmentsInOrder, manifest.legs).enumerated() {
            if index == refusedLeg {
                try? repository.setRoutability(segmentId: segment.id, .implausibleRoute)
            } else {
                try? repository.setMatchedPolyline(segmentId: segment.id, encodedPolyline: leg.polyline)
                try? repository.setRoutability(segmentId: segment.id, .road)
            }
        }
        for (record, stop) in zip(detail.stops.sorted { $0.arrivedAt < $1.arrivedAt }, manifest.stops) {
            try? repository.setStopName(stopId: record.id, name: SampleTrip.text(stop.names))
        }
    }
}
#endif
