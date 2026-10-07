import CoreGraphics
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **The film asks only for frames the map can draw** (#223, ADR 2026-10-07).
///
/// The fitted frames are pinned to what a real MapLibre snapshot did with the
/// same requests (1080×1920, OpenFreeMap, measured 2026-10-06 on #223), not to
/// this type's own arithmetic: a frame past 85°N came back 59.1 px lower, and
/// one taller than the world came back zoomed ×1.4477 with its centre at y
/// 726.9.
final class MercatorBandTests: XCTestCase {
    private let band = MercatorBand(
        maxLatitudeDeg: MercatorBand.webMercatorMaxLatitudeDeg, widthPx: 1080, heightPx: 1920
    )

    private func frame(_ lat: Double, _ lon: Double, km: Double) -> CameraFrame {
        CameraFrame(centerLat: lat, centerLon: lon, spanM: km * 1000, bearing: 0)
    }

    /// Where `point` lands in the picture the substrate draws for `drawn`.
    private func pixelY(of lat: Double, in drawn: CameraFrame) -> Double {
        (MercatorBand.mercatorY(lat) - MercatorBand.mercatorY(drawn.centerLat)) * band.worldPx(drawn) + 960
    }

    func testAFrameInsideTheBandIsReturnedUnchanged() {
        for asked in [frame(40, 0, km: 2_000), frame(64.15, -21.94, km: 5_000), frame(-45, 170, km: 3_000)] {
            XCTAssertEqual(band.fitted(asked), asked)
        }
    }

    /// MapLibre drew the requested centre at y 900.9 — 59.1 px above the
    /// middle, the frame moved that far south at the same zoom.
    func testAFramePastTheNorthEdgeMovesWhereMapLibreMovedIt() {
        let asked = frame(48.5, 120, km: 11_000)
        let drawn = band.fitted(asked)
        XCTAssertEqual(pixelY(of: asked.centerLat, in: drawn), 900.9, accuracy: 0.1)
        XCTAssertEqual(band.worldPx(drawn), band.worldPx(asked), accuracy: 1e-6, "the zoom is kept")
        XCTAssertEqual(pixelY(of: band.maxLatitudeDeg, in: drawn), 0, accuracy: 1e-6, "the edge meets the top")
    }

    /// A frame taller than the world: MapLibre zoomed in ×1.4477 and put the
    /// requested centre at y 726.9.
    func testAFrameTallerThanTheWorldZoomsInAsMapLibreDid() {
        let asked = frame(40, 60, km: 25_000)
        let drawn = band.fitted(asked)
        XCTAssertEqual(band.worldPx(drawn) / band.worldPx(asked), 1.4477, accuracy: 0.0005)
        XCTAssertEqual(pixelY(of: asked.centerLat, in: drawn), 726.9, accuracy: 0.5)
        XCTAssertEqual(drawn.centerLat, 0, accuracy: 1e-9)
    }

    func testAFramePastTheSouthEdgeMovesNorth() {
        let asked = frame(-60, 150, km: 8_000)
        let drawn = band.fitted(asked)
        XCTAssertGreaterThan(drawn.centerLat, asked.centerLat)
        XCTAssertEqual(pixelY(of: -band.maxLatitudeDeg, in: drawn), 1920, accuracy: 1e-6)
    }

    /// A fitted frame is one the substrate draws as asked: fitting it again
    /// changes nothing.
    func testFittingIsIdempotent() {
        for asked in [frame(48.5, 120, km: 11_000), frame(40, 60, km: 25_000), frame(-60, 150, km: 8_000)] {
            let once = band.fitted(asked)
            let twice = band.fitted(once)
            XCTAssertEqual(twice.centerLat, once.centerLat, accuracy: 1e-9)
            XCTAssertEqual(twice.spanM, once.spanM, accuracy: 1e-3)
        }
    }

    /// `contains` is the render loop's own test made in advance: over a spread
    /// of frames around a station, it agrees with `SnapshotReprojection` built
    /// on the projection the substrate draws.
    func testContainsAgreesWithTheRenderLoopsOwnTest() throws {
        let station = frame(55, 10, km: 3_300)
        let snapshot = MapSnapshot(image: try onePixel()) { lat, lon in
            CGPoint(
                x: (lon - station.centerLon) / 360 * self.band.worldPx(station) + 540,
                y: self.pixelY(of: lat, in: station)
            )
        }
        var agreed = 0, contained = 0
        for dLat in stride(from: -3.0, through: 3.0, by: 0.5) {
            for dLon in stride(from: -4.0, through: 4.0, by: 1.0) {
                for km in [3_000.0, 3_150, 3_300] {
                    let target = frame(55 + dLat, 10 + dLon, km: km)
                    let renders = (try? SnapshotReprojection(
                        station: snapshot, stationCamera: station, target: target, widthPx: 1080, heightPx: 1920
                    )) != nil
                    XCTAssertEqual(band.contains(station, target), renders, "Δlat \(dLat) Δlon \(dLon) \(km) km")
                    agreed += 1
                    if renders { contained += 1 }
                }
            }
        }
        XCTAssertGreaterThan(agreed, 300)
        XCTAssertGreaterThan(contained, 10, "the spread holds frames the station serves…")
        XCTAssertLessThan(contained, agreed - 10, "…and frames it does not")
    }

    private func onePixel() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}
