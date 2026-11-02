import CoreGraphics
@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomePersistence
import KamomeTrackingEngine
import KamomeTripComposer
import XCTest

// The audit, apart from the scenarios it runs on (file length).
extension RoutePathScenarioProbeTests {
    // MARK: - The audit (the matrix's invariants, on the shipped plan)

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func audit(
        _ line: LinearTimeline, trip: RecapTrip, config: TrackingConfig.Export, band: MercatorBand
    ) -> [String] {
        var violations: [String] = []
        let fps = Double(config.fps)
        if !line.durationS.isFinite || line.durationS <= 0 { violations.append("1. length \(line.durationS) s") }
        if line.frameCount <= 0 || abs(Double(line.frameCount) - line.durationS * fps) > 1 {
            violations.append("1. \(line.frameCount) frames for \(line.durationS) s")
        }
        var lastTravelled = 0.0
        var badCamera = 0, badSubject = 0, deckUnderEndCard = 0, backwards = 0, offScreenStops = 0
        var sawTitle = false, sawEnd = false
        var offScreenSubject = 0, worstOffPx = 0.0
        var biggestStepM = 0.0
        for frame in 0..<line.frameCount {
            let time = Double(frame) / fps
            let camera = line.cameraFrame(atTime: time)
            if !(camera.centerLat.isFinite && camera.centerLon.isFinite && camera.spanM.isFinite)
                || camera.spanM <= 0 || abs(camera.centerLat) > band.maxLatitudeDeg + 1e-6 {
                badCamera += 1
            }
            let subject = line.subjectState(atTime: time)
            if !(subject.lat.isFinite && subject.lon.isFinite && subject.heading.isFinite) { badSubject += 1 }
            if subject.isVisible, subject.emphasis > 0.5 {
                let drawn = band.fitted(camera)
                let world = band.worldPx(drawn)
                var dx = (subject.lon - drawn.centerLon) / 360 * world
                dx -= (dx / world).rounded() * world
                let dy = (MercatorBand.mercatorY(subject.lat) - MercatorBand.mercatorY(drawn.centerLat)) * world
                let outX = abs(dx) - Double(config.frameWidthPx) / 2, outY = abs(dy) - Double(config.frameHeightPx) / 2
                let out = max(outX, outY)
                if out > 0 {
                    offScreenSubject += 1
                    worstOffPx = max(worstOffPx, out)
                }
            }
            var endCard = false, deck = false
            for content in line.overlayContents(atTime: time) {
                switch content {
                case .titleChrome: if frame == 0 { sawTitle = true }
                case .endChrome:
                    endCard = true
                    if frame == line.frameCount - 1 { sawEnd = true }
                case let .photoDeck(card):
                    deck = true
                    if let coordinate = card.coordinate, !(coordinate.lat.isFinite && coordinate.lon.isFinite) {
                        offScreenStops += 1
                    }
                case let .hud(_, _, travelledM):
                    if !travelledM.isFinite || travelledM < 0 { backwards += 1 }
                    if travelledM < lastTravelled - 1 { backwards += 1 }
                    if lastTravelled > 0 { biggestStepM = max(biggestStepM, travelledM - lastTravelled) }
                    lastTravelled = max(lastTravelled, travelledM)
                default: break
                }
            }
            if endCard, deck { deckUnderEndCard += 1 }
        }
        if badCamera > 0 { violations.append("2. \(badCamera) frames with a non-finite or out-of-world camera") }
        if badSubject > 0 { violations.append("3. \(badSubject) frames with a non-finite vehicle") }
        if backwards > 0 { violations.append("6. the odometer ran backwards on \(backwards) frames") }
        print(String(
            format: "KAMOME_PROBE_ODOMETER ends %.0f km, biggest one-frame step %.1f km",
            lastTravelled / 1000, biggestStepM / 1000
        ))
        let filmed = trip.unwrappedAcrossTheAntimeridian()
        let journey = line.opensOnTheFlight ? RecapTypeTwoFilm.trimmedToTheDestination(filmed, config: config) : filmed
        let cardM = RecapTrip.localRouteDistanceM(legs: journey.legs)
        if cardM > 1_000 || lastTravelled > 1_000, abs(lastTravelled - cardM) > max(cardM * 0.02, 1_000) {
            violations.append(String(
                format: "6. the HUD odometer ends on %.0f km where the end card's journey is %.0f km (card: %@)",
                lastTravelled / 1000, cardM / 1000, trip.endCardFigures.first?.value ?? "-"
            ))
        }
        if biggestStepM > 100_000 {
            violations.append(String(format: "6. the odometer jumps %.0f km in one frame", biggestStepM / 1000))
        }
        if deckUnderEndCard > 0 { violations.append("7. \(deckUnderEndCard) frames with a deck under the end card") }
        if offScreenSubject > 0 {
            violations.append(String(format: "the vehicle is off screen on %d frames (worst %.0f px past the edge)",
                                     offScreenSubject, worstOffPx))
        }
        if offScreenStops > 0 { violations.append("a deck with a non-finite coordinate on \(offScreenStops) frames") }
        if !sawTitle { violations.append("9. the first frame has no title card") }
        if !sawEnd { violations.append("9. the last frame has no end card") }

        // The stops play in the order they happened.
        let played = line.holds.sorted { $0.startS < $1.startS }.map(\.stopIndex)
        if played != played.sorted() {
            violations.append("the stops play out of order: \(played)")
        }

        let camera = { (time: Double) in line.cameraFrame(atTime: time) }
        let stations = RecapSnapshotStations.plan(
            frameCount: line.frameCount, fps: config.fps, camera: camera, map: { line.mapState(atTime: $0) },
            mustStartAt: RecapSnapshotStations.splitFrames(
                holds: line.holds, frameCount: line.frameCount, fps: config.fps, camera: camera
            ),
            config: config, band: line.substrateBand
        )
        var expected = 0
        for station in stations {
            if station.frames.lowerBound != expected || station.frames.isEmpty {
                violations.append("4. station frames \(station.frames) after frame \(expected)")
                break
            }
            expected = station.frames.upperBound
        }
        if expected != line.frameCount { violations.append("4. the stations end at \(expected) of \(line.frameCount)") }
        let uncontained = containmentFailures(line, stations: stations, config: config, band: band)
        if uncontained > 0 {
            violations.append("5. \(uncontained) frames their station does not contain — the export would fail")
        }
        return violations
    }

    /// Frames a station cannot serve, each station drawn the way MapLibre
    /// draws it — the matrix's own measure.
    private func containmentFailures(
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
}
