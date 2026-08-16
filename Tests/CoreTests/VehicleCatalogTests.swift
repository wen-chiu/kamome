import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import XCTest

/// The catalogue contract: a folder is one selectable subject, `vehicles.json`
/// carries what a filename cannot, and the two kinds are not interchangeable.
/// The reasoning behind every rule asserted here lives in
/// `Core/ExportEngine/Resources/Vehicles/README.md`.
final class VehicleCatalogTests: XCTestCase {
    func testTheManifestLoadsAndDeclaresBothKinds() throws {
        let subjects = VehicleCatalog.subjects
        XCTAssertFalse(subjects.isEmpty, "vehicles.json did not load from the resource bundle")

        let car = try XCTUnwrap(VehicleCatalog.subject(id: "car-red"))
        XCTAssertEqual(car.kind, .directional)
        let seagull = try XCTUnwrap(VehicleCatalog.subject(id: "seagull"))
        XCTAssertEqual(seagull.kind, .omni, "the seagull is a mark, not a car with one frame")
    }

    /// The kind decides how many drawings load, and a partial set is no set.
    func testEachKindLoadsTheArtworkItsShapeImplies() throws {
        guard case let .directional(car)? = VehicleCatalog.artwork(id: "car-red") else {
            return XCTFail("car-red must load as eight drawings")
        }
        XCTAssertEqual(car.count, SpriteDirection.allCases.count)
        // The shared-canvas rule, which is what stops a sprite pulsing as it turns.
        XCTAssertEqual(Set(car.values.map { "\($0.width)x\($0.height)" }).count, 1)

        guard case .omni? = VehicleCatalog.artwork(id: "seagull") else {
            return XCTFail("seagull must load as one drawing")
        }
    }

    func testAnUnknownSubjectHasNoArtwork() {
        XCTAssertNil(VehicleCatalog.artwork(id: "no-such-folder"))
        XCTAssertNil(VehicleCatalog.subject(id: "no-such-folder"))
    }

    /// **A car is a better failure than a dot.** An unknown subject falls back to
    /// the shipped car rather than skipping to the vector marker.
    func testAnUnknownSubjectFallsBackToTheCarRatherThanTheMarker() throws {
        let resolved = try XCTUnwrap(VehicleCatalog.resolve(id: "no-such-folder"))
        XCTAssertEqual(resolved.subject.id, VehicleCatalog.defaultSubjectId)

        let renderer = VehicleSubjectRenderer.make(
            style: RecapStyle(), subjectId: "no-such-folder", lengthPx: 250
        )
        guard case .rasterSprite = renderer.visual else {
            return XCTFail("the fallback must be the car, got \(renderer.visual)")
        }
    }

    /// Nil means "this trip never chose", which is every trip predating schema v3.
    func testNoChoiceResolvesToTheDefaultSubject() throws {
        let resolved = try XCTUnwrap(VehicleCatalog.resolve(id: nil))
        XCTAssertEqual(resolved.subject.id, VehicleCatalog.defaultSubjectId)
    }

    // MARK: - Size

    /// Size is a tunable, and a mark and a car cannot share one number — so the
    /// manifest may override it per subject.
    func testTheManifestOverridesTheConfiguredSizePerSubject() {
        let configured: CGFloat = 250
        let car = VehicleSubjectRenderer.make(style: RecapStyle(), subjectId: "car-red", lengthPx: configured)
        XCTAssertEqual(car.lengthPx, configured, "car-red declares no override, so it takes the configured size")

        let seagull = VehicleSubjectRenderer.make(style: RecapStyle(), subjectId: "seagull", lengthPx: configured)
        XCTAssertEqual(seagull.lengthPx, 170, "the seagull's manifest override wins over config")
    }

    // MARK: - Omni

    /// An omni mark must read the same travelling in any direction — a bird
    /// facing left looks like it is flying backwards on an eastbound leg. So the
    /// renderer must not consult the heading at all.
    func testAnOmniMarkRendersIdenticallyWhateverTheHeading() throws {
        let renderer = VehicleSubjectRenderer.make(style: RecapStyle(), subjectId: "seagull", lengthPx: 120)
        guard case .omniSprite = renderer.visual else {
            return XCTFail("seagull must select the omni visual")
        }

        func draw(heading: Double) throws -> Data {
            let side = 256
            let context = try XCTUnwrap(CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let surface = RenderSurface(
                context: context, widthPx: side, heightPx: side, scale: CGFloat(side) / 1080
            ) { _, _ in CGPoint(x: side / 2, y: side / 2) }
            renderer.render(
                SubjectState(lat: -32, lon: 115.75, heading: heading),
                camera: CameraFrame(centerLat: -32, centerLon: 115.75, spanM: 1500, bearing: 0),
                into: surface
            )
            return try XCTUnwrap(context.makeImage()?.dataProvider?.data as Data?)
        }

        let north = try draw(heading: 0)
        for heading in [45.0, 90, 135, 180, 225, 270, 315] {
            XCTAssertEqual(try draw(heading: heading), north, "an omni mark must not turn at \(heading)°")
        }
    }
}
