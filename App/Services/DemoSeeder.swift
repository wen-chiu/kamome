#if DEBUG
import Foundation
import KamomePersistence

/// Seeds a deterministic demo trip for the Phase 2 gate screenshot
/// (`-demo-seed` launch argument; simulator/debug only).
///
/// Times are anchored to "now" so photos added to the simulator library
/// (`simctl addmedia`, creationDate ≈ import time) fall inside the final
/// stop's interval and flow through the real PhotoKit → matcher → DB path.
enum DemoSeeder {
    private struct DemoStop {
        let index: Int
        let name: String
        let dwellMin: Double
    }

    // Perth → Margaret River day 1, heavily thinned.
    private static let route: [(lat: Double, lon: Double)] = [
        (-31.9530, 115.8570), (-32.1200, 115.8200), (-32.3200, 115.7700),
        (-32.5290, 115.7220), (-32.8000, 115.7000), (-33.0500, 115.6800),
        (-33.3270, 115.6410), (-33.5000, 115.5000), (-33.6440, 115.3450),
        (-33.8000, 115.2000), (-33.9550, 115.0750)
    ]
    private static let stopInfo: [DemoStop] = [
        DemoStop(index: 3, name: "Mandurah", dwellMin: 25),
        DemoStop(index: 6, name: "Bunbury", dwellMin: 25),
        DemoStop(index: 8, name: "Busselton Jetty", dwellMin: 20),
        DemoStop(index: 10, name: "Margaret River", dwellMin: 30)
    ]

    static func seedIfRequested(repository: TripRepository) {
        guard ProcessInfo.processInfo.arguments.contains("-demo-seed") else { return }
        guard (try? repository.allTrips().isEmpty) == true else { return }

        // Final stop's window straddles "now": library photos land there.
        let end = Date.now.addingTimeInterval(15 * 60).timeIntervalSince1970
        let start = end - 6.5 * 3600
        let dwellTotalS = stopInfo.map(\.dwellMin).reduce(0, +) * 60
        let legStepS = (end - start - dwellTotalS) / Double(route.count - 1)

        var segments: [TripRepository.NewSegment] = []
        var stops: [TripRepository.NewStop] = []
        var previousIndex = 0
        var previousDepart = start
        for stop in stopInfo {
            let points = (previousIndex...stop.index).enumerated().map { offset, routeIndex in
                TripRepository.NewTrackpoint(
                    ts: previousDepart + Double(offset) * legStepS,
                    lat: route[routeIndex].lat,
                    lon: route[routeIndex].lon,
                    speed: 25
                )
            }
            let arrive = points.last?.ts ?? previousDepart
            let depart = min(arrive + stop.dwellMin * 60, end)
            segments.append(.init(
                mode: "drive",
                startedAt: points.first?.ts ?? previousDepart,
                endedAt: arrive,
                points: points
            ))
            stops.append(.init(
                lat: route[stop.index].lat,
                lon: route[stop.index].lon,
                arrivedAt: arrive,
                departedAt: depart
            ))
            previousIndex = stop.index
            previousDepart = depart
        }

        guard let tripId = try? repository.saveCompletedTrip(
            title: "Perth → Margaret River",
            startedAt: start,
            endedAt: end,
            segments: segments,
            stops: stops
        ) else { return }

        // Names skip the geocoder (deterministic screenshot, no network).
        if let detail = try? repository.detail(tripId: tripId) {
            for (record, info) in zip(detail.stops, stopInfo) {
                try? repository.setStopName(stopId: record.id, name: info.name)
            }
        }
    }
}
#endif
