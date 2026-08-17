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

    /// Size is a real tunable, and every shipped subject takes it.
    ///
    /// **No subject overrides it today, and that is the tool's doing.**
    /// `center-sprites.py` sizes each set's canvas so its widest drawing fills
    /// the same proportion car-red does, which is what makes one
    /// `subject_length_px` produce comparable apparent sizes across a car, a
    /// scooter and a gull. The override existed to paper over exactly the
    /// difference the tool now removes, so declaring one would fight it.
    func testEveryShippedSubjectTakesTheConfiguredSize() {
        let configured: CGFloat = 250
        for subject in VehicleCatalog.subjects {
            XCTAssertNil(
                subject.lengthPx,
                "\(subject.id) declares a size override — the centring tool should make that unnecessary"
            )
            let renderer = VehicleSubjectRenderer.make(
                style: RecapStyle(), subjectId: subject.id, lengthPx: configured
            )
            XCTAssertEqual(renderer.lengthPx, configured, "\(subject.id) must take the configured size")
        }
    }

    /// The override mechanism still exists for the set that eventually needs it,
    /// so this drives it with a manifest entry rather than the shipped one.
    func testADeclaredSizeOverrideWinsOverConfig() throws {
        let declared = try JSONDecoder().decode(VehicleSubject.self, from: Data("""
        {"id": "oversized", "kind": "omni", "type": "mark",
         "selectable": true, "length_px": 90, "names": {"en": "Oversized"}}
        """.utf8))
        let artwork = try XCTUnwrap(VehicleCatalog.artwork(id: "seagull"))

        let renderer = VehicleSubjectRenderer.make(
            style: RecapStyle(), subjectId: "oversized", lengthPx: 250,
            resolve: { _ in (subject: declared, artwork: artwork) }
        )
        XCTAssertEqual(renderer.lengthPx, 90, "a declared override must win over the configured size")
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

    // MARK: - The picker's two gates

    /// **The plane must never be user-choosable.** The app picks it from the
    /// journey for a crossing; a user choosing "plane" for a road trip is not a
    /// feature, and the same will apply to a ship.
    func testThePlaneShipsAsArtButNeverAsAChoice() throws {
        let plane = try XCTUnwrap(VehicleCatalog.subject(id: "plane"))
        XCTAssertFalse(plane.selectable, "the plane is chosen from the journey, never by the user")
        XCTAssertNotNil(VehicleCatalog.artwork(id: "plane"), "it must still load as artwork")
        XCTAssertFalse(
            VehicleCatalog.pickableSubjects.contains { $0.id == "plane" },
            "the plane must not reach the picker"
        )
    }

    /// A subject with no `logo.png` is not an error — it works in a film and
    /// simply has nothing to show in a list yet. Adding the file makes it
    /// appear, with no code change.
    func testASubjectWithoutAThumbnailIsNotPickableButStillRenders() {
        for id in VehicleCatalog.subjects.map(\.id) where VehicleCatalog.thumbnail(id: id) == nil {
            XCTAssertNotNil(VehicleCatalog.artwork(id: id), "\(id) must still render without a thumbnail")
            XCTAssertFalse(
                VehicleCatalog.pickableSubjects.contains { $0.id == id },
                "\(id) has no thumbnail, so it cannot be offered in the picker yet"
            )
        }
        for subject in VehicleCatalog.pickableSubjects {
            XCTAssertNotNil(VehicleCatalog.thumbnail(id: subject.id))
            XCTAssertTrue(subject.selectable)
        }
    }

    /// The thumbnail is never part of the drawn set: it does not share the
    /// canvas and carries no direction, so it must not reach the renderer.
    func testTheThumbnailIsNotOneOfTheEightDrawings() throws {
        guard case let .directional(set)? = VehicleCatalog.artwork(id: "scooter") else {
            return XCTFail("scooter must load as eight drawings")
        }
        XCTAssertEqual(set.count, 8)
        let logo = try XCTUnwrap(VehicleCatalog.thumbnail(id: "scooter"))
        let canvas = try XCTUnwrap(set[.north])
        XCTAssertNotEqual(
            "\(logo.width)x\(logo.height)", "\(canvas.width)x\(canvas.height)",
            "this set's thumbnail happens to match the canvas — reassert the intent, not the coincidence"
        )
    }

    /// Every directional set the catalogue declares must be complete and share
    /// one square canvas. Centring is `Tools/center-sprites.py`'s job, and no
    /// code here compensates for it — that would mean content-bounds scaling,
    /// which is what makes a subject pulse as it turns.
    func testEveryDirectionalSetIsCompleteAndSquare() throws {
        for subject in VehicleCatalog.subjects where subject.kind == .directional {
            guard case let .directional(set)? = VehicleCatalog.artwork(id: subject.id) else {
                XCTFail("\(subject.id) declares eight drawings but did not load")
                continue
            }
            XCTAssertEqual(set.count, 8, "\(subject.id) is a partial set")
            let sizes = Set(set.values.map { "\($0.width)x\($0.height)" })
            XCTAssertEqual(sizes.count, 1, "\(subject.id) must share one canvas across all eight")
            let canvas = try XCTUnwrap(set[.north])
            XCTAssertEqual(canvas.width, canvas.height, "\(subject.id)'s canvas must be square")
        }
    }
}
