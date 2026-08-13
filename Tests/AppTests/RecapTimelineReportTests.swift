@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// Where the film's beats land, measured rather than watched.
///
/// The pacing bugs this exists for — a frozen opening, a stop that arrives long
/// after the camera settled — are all *timing*, and a rendered MP4 is a slow and
/// lossy way to read timing off a screen. This prints the numbers directly from
/// the timeline the renderer consumes, against a real imported fixture, so a
/// regression shows up as a second rather than as a feeling.
///
///     TEST_RUNNER_KAMOME_TIMELINE_REPORT=iceland \
///     TEST_RUNNER_KAMOME_TILES_PATH=$HOME/kamome-osrm/tiles \
///     xcodebuild -scheme Kamome test \
///       -only-testing:KamomeTests/RecapTimelineReportTests/testReportTimeline \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
final class RecapTimelineReportTests: XCTestCase {
    /// The moments worth naming in a finished film.
    private struct Report {
        var carAt: Double?
        var firstStopAt: Double?
        var firstDeckAt: Double?
        /// The longest run in which *nothing* on screen changes — no camera
        /// move, no vehicle move, no overlay change, not even the photograph in
        /// the deck. This is the number a viewer feels as dead air.
        var longestStill: (start: Double, length: Double) = (0, 0)
    }

    func testReportTimeline() async throws {
        let requested = ProcessInfo.processInfo.environment["KAMOME_TIMELINE_REPORT"] ?? ""
        try XCTSkipUnless(
            !requested.isEmpty,
            "Manual measurement — set KAMOME_TIMELINE_REPORT to a fixture name (e.g. iceland)."
        )
        let (recap, config) = try await RecapDemoFilmTests.importedRecap(named: requested)
        let bounds = try XCTUnwrap(GeoBox.enclosing(recap.route.map { (lat: $0.lat, lon: $0.lon) }))
        let establishing = RecapMapRegionResolver.resolve(covering: bounds).map {
            RecapBounds(
                minLat: $0.bounds.minLat, minLon: $0.bounds.minLon,
                maxLat: $0.bounds.maxLat, maxLon: $0.bounds.maxLon
            )
        }
        let line = try XCTUnwrap(LinearTimeline(trip: recap, config: config, establishing: establishing))
        let report = Self.scan(line, fps: config.fps)

        func fmt(_ value: Double?) -> String { value.map { String(format: "%.2fs", $0) } ?? "never" }
        print("""
        KAMOME_TIMELINE_REPORT \(requested)
          total          \(fmt(line.durationS))
          opening ends   \(fmt(line.openingS))
          car appears    \(fmt(report.carAt))
          first stop     \(fmt(report.firstStopAt))
          first photo    \(fmt(report.firstDeckAt))
          longest still  \(fmt(report.longestStill.length)) starting \(fmt(report.longestStill.start))
        """)

        // The camera's two spans and the zoom between them, which nothing else
        // prints — the figures in HANDOFF.md were derived when a region was
        // sized, never measured off a film. `established` is the picture at
        // t=0, which is exactly what `RecapDurationPlan` divides by
        // `target_zoom_ratio` to get the body.
        //
        // Kilometres only. A span is a scale; a bbox or a centre would be a
        // record of where someone was, and this prints to a console (CLAUDE.md
        // §0).
        let establishedSpanM = line.cameraFrame(atTime: 0).spanM
        print(String(
            format: "  established    %6.1f km\n  body           %6.1f km\n  zoom ratio     %6.2fx",
            establishedSpanM / 1000, line.path.bodySpanM / 1000, establishedSpanM / line.path.bodySpanM
        ))

        // Which legs draw dashed, and roughly where. The provider logs a reason
        // per leg (`NoSegment`, detour gate, thinning) but no identity, and
        // `RouteMatchService.matchTrip` awaits them in order — so this list, in
        // the same order, is what makes a reason attributable to a place.
        // Named by nearest stop; still no coordinates.
        for (index, leg) in recap.legs.enumerated() where leg.provenance.isInferred {
            guard let start = leg.coordinates.first, let end = leg.coordinates.last else { continue }
            print("  dashed leg \(index) \(leg.mode.rawValue): "
                + "\(Self.nearestStopName(to: start, in: recap)) → \(Self.nearestStopName(to: end, in: recap))")
        }
    }

    /// Names a point by the stop it sits closest to. Equirectangular on purpose:
    /// this only has to pick the right stop out of a handful, not measure.
    private static func nearestStopName(to point: RecapCoordinate, in trip: RecapTrip) -> String {
        trip.stops.min {
            Self.squaredDegrees(point, $0.coordinate) < Self.squaredDegrees(point, $1.coordinate)
        }?.name ?? "unnamed stop"
    }

    private static func squaredDegrees(_ lhs: RecapCoordinate, _ rhs: RecapCoordinate) -> Double {
        let deltaLat = lhs.lat - rhs.lat
        let deltaLon = (lhs.lon - rhs.lon) * cos(lhs.lat * .pi / 180)
        return deltaLat * deltaLat + deltaLon * deltaLon
    }

    private static func scan(_ line: LinearTimeline, fps: Int) -> Report {
        let step = 1.0 / Double(fps)
        var report = Report()
        var stillSince = 0.0
        // Overlays are compared by value, not by count: a deck still holding the
        // same photograph at the same size is a frozen frame, and counting
        // overlays would have called it motion.
        struct Frame: Equatable {
            let span: Double
            let subject: SubjectState
            let overlays: [OverlayContent]
        }
        var previous: Frame?

        for frame in 0..<line.frameCount {
            let time = Double(frame) * step
            let camera = line.cameraFrame(atTime: time)
            let subject = line.subjectState(atTime: time)
            let overlays = line.overlayContents(atTime: time)

            if report.carAt == nil, subject.isVisible, subject.emphasis > 0.01 { report.carAt = time }
            for overlay in overlays {
                if case .stopLabel(_, _, _, let opacity) = overlay, opacity > 0.01, report.firstStopAt == nil {
                    report.firstStopAt = time
                }
                if case .photoDeck = overlay, report.firstDeckAt == nil { report.firstDeckAt = time }
            }

            let now = Frame(span: camera.spanM, subject: subject, overlays: overlays)
            if let previous, abs(previous.span - now.span) < 1,
               previous.subject == now.subject, previous.overlays == now.overlays {
                if time - stillSince > report.longestStill.length {
                    report.longestStill = (stillSince, time - stillSince)
                }
            } else {
                stillSince = time
            }
            previous = now
        }
        return report
    }
}
