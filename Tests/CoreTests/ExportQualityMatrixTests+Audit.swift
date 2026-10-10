import CoreGraphics
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// The audit `ExportQualityMatrixTests` runs on every film — the nine
/// invariants its header lists, each violation named by its number.
extension ExportQualityMatrixTests {
    struct Measured {
        var durationS = 0.0
        var frames = 0
        var stations = 0
        var buildS = 0.0
        var planS = 0.0
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func audit(_ test: Case, config: TrackingConfig.Export, measured: inout Measured) -> [String] {
        var violations: [String] = []
        let fps = Double(config.fps)
        let band = MercatorBand(
            maxLatitudeDeg: MercatorBand.webMercatorMaxLatitudeDeg,
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )

        // 1. It builds, the way the export builds it.
        let built = ContinuousClock.now
        guard let line = LinearTimeline(
            trip: test.trip, config: config, establishing: nil,
            substrateMaxLongitudeDeg: nil, locale: Locale(identifier: "en")
        )?.fitted(into: band) else {
            return ["1. the timeline did not build — the export would fail with no film plan"]
        }
        measured.buildS = Self.seconds(since: built)
        measured.durationS = line.durationS
        measured.frames = line.frameCount
        if !line.durationS.isFinite || line.durationS <= 0 {
            violations.append("1. length \(line.durationS) s")
        }
        if line.frameCount <= 0 || abs(Double(line.frameCount) - line.durationS * fps) > 1 {
            violations.append("1. \(line.frameCount) frames for \(line.durationS) s")
        }

        // 8. The form.
        switch test.form {
        case .local:
            if line.opensOnTheFlight { violations.append("8. a local film opens on a flight") }
        case .departure:
            if !line.filmType.hasDestinationAbroad {
                violations.append("8. classified \(line.filmType), not a journey abroad")
            }
            if line.opensOnTheFlight != test.drawsTheFlight {
                violations.append(test.drawsTheFlight
                    ? "8. a departure film does not open on the flight"
                    : "8. a flight past the drawn-flight limit opens on the flight")
            }
        }

        var lastTravelled = 0.0
        var sawPass = false, sawEnds = false
        var badCamera = 0, badSubject = 0, deckUnderEndCard = 0, backwards = 0
        for frame in 0..<line.frameCount {
            let time = Double(frame) / fps
            // 2. The camera.
            let camera = line.cameraFrame(atTime: time)
            if !(camera.centerLat.isFinite && camera.centerLon.isFinite && camera.spanM.isFinite)
                || camera.spanM <= 0 || abs(camera.centerLat) > band.maxLatitudeDeg + 1e-6 {
                badCamera += 1
            }
            // 3. The vehicle.
            let subject = line.subjectState(atTime: time)
            if !(subject.lat.isFinite && subject.lon.isFinite && subject.heading.isFinite) { badSubject += 1 }

            let contents = line.overlayContents(atTime: time)
            // 9. Title first, end card last.
            if frame == 0, !contents.contains(where: { if case .titleChrome = $0 { return true }; return false }) {
                violations.append("9. the first frame has no title card")
            }
            if frame == line.frameCount - 1,
               !contents.contains(where: { if case .endChrome = $0 { return true }; return false }) {
                violations.append("9. the last frame has no end card")
            }
            var endCard = false, deck = false
            for content in contents {
                switch content {
                case .journeyCard: sawPass = true
                case .flightEnds: sawEnds = true
                case .endChrome: endCard = true
                case .photoDeck: deck = true
                case let .hud(_, _, travelledM):
                    // 6. The odometer.
                    if !travelledM.isFinite || travelledM < 0 { backwards += 1 }
                    if travelledM < lastTravelled - 1 { backwards += 1 }
                    lastTravelled = max(lastTravelled, travelledM)
                default: break
                }
            }
            // 7. Never a deck under the end card.
            if endCard, deck { deckUnderEndCard += 1 }
        }
        if badCamera > 0 { violations.append("2. \(badCamera) frames with a non-finite or out-of-world camera") }
        if badSubject > 0 { violations.append("3. \(badSubject) frames with a non-finite vehicle") }
        if backwards > 0 { violations.append("6. the odometer ran backwards or left the numbers on \(backwards) frames") }
        if deckUnderEndCard > 0 { violations.append("7. \(deckUnderEndCard) frames with a photo deck under the end card") }

        // 6. …and ends on the local journey the film drew.
        let filmed = test.trip.unwrappedAcrossTheAntimeridian()
        let journey = line.opensOnTheFlight
            ? RecapTypeTwoFilm.trimmedToTheDestination(filmed, config: config) : filmed
        let expectedM = RecapTrip.localRouteDistanceM(legs: journey.legs)
        if expectedM > 1_000, abs(lastTravelled - expectedM) > expectedM * 0.02 {
            violations.append(String(
                format: "6. the odometer ends on %.1f km where the journey is %.1f km",
                lastTravelled / 1000, expectedM / 1000
            ))
        }

        // 8. …and what each form shows.
        switch test.form {
        case .local:
            if sawPass { violations.append("8. a local film shows a boarding pass") }
            if sawEnds { violations.append("8. a local film marks flight ends") }
        case .departure:
            let passExpected = test.pass && test.drawsTheFlight
            if passExpected, !sawPass { violations.append("8. no boarding pass on screen") }
            if !passExpected, sawPass { violations.append("8. a pass where none is owed") }
            if sawEnds != test.drawsTheFlight {
                violations.append(sawEnds ? "8. a frozen card marks flight ends" : "8. the flight's two ends are never marked")
            }
        }

        // 4 and 5. The stations.
        let planned = ContinuousClock.now
        let stations = Self.stations(line, config: config)
        measured.planS = Self.seconds(since: planned)
        measured.stations = stations.count
        var expected = 0
        for station in stations {
            if station.frames.lowerBound != expected || station.frames.isEmpty {
                violations.append("4. station frames \(station.frames) after frame \(expected)")
                break
            }
            expected = station.frames.upperBound
        }
        if expected != line.frameCount { violations.append("4. the stations end at \(expected) of \(line.frameCount)") }
        let uncontained = Self.containmentFailures(line, stations: stations, config: config, band: band)
        if uncontained > 0 {
            violations.append("5. \(uncontained) frames their station does not contain — the export would fail")
        }
        return violations
    }

    private static func stations(_ line: LinearTimeline, config: TrackingConfig.Export) -> [RecapSnapshotStations.Station] {
        let camera = { (time: Double) in line.cameraFrame(atTime: time) }
        return RecapSnapshotStations.plan(
            frameCount: line.frameCount, fps: config.fps, camera: camera, map: { line.mapState(atTime: $0) },
            mustStartAt: RecapSnapshotStations.splitFrames(
                holds: line.holds, frameCount: line.frameCount, fps: config.fps, camera: camera
            ),
            config: config, band: line.substrateBand
        )
    }

    /// Frames a station cannot serve, each station drawn the way MapLibre draws
    /// it — the same measure as `MercatorBandFilmTests`.
    private static func containmentFailures(
        _ line: LinearTimeline, stations: [RecapSnapshotStations.Station],
        config: TrackingConfig.Export, band: MercatorBand
    ) -> Int {
        let width = config.frameWidthPx, height = config.frameHeightPx
        guard let pixel = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage() else { return Int.max }
        var failures = 0
        for station in stations {
            let drawn = band.fitted(station.camera)
            let world = band.worldPx(drawn)
            let snapshot = MapSnapshot(image: pixel) { lat, lon in
                var dx = (lon - drawn.centerLon) / 360 * world
                dx -= (dx / world).rounded() * world
                return CGPoint(
                    x: dx + Double(width) / 2,
                    y: (MercatorBand.mercatorY(lat) - MercatorBand.mercatorY(drawn.centerLat)) * world
                        + Double(height) / 2
                )
            }
            for frame in station.frames where (try? SnapshotReprojection(
                station: snapshot, stationCamera: station.camera,
                target: line.cameraFrame(atTime: Double(frame) / Double(config.fps)),
                widthPx: width, heightPx: height
            )) == nil {
                failures += 1
            }
        }
        return failures
    }

    private static func seconds(since instant: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - instant
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }
}
