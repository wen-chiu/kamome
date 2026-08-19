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

    /// **A vehicle takes the configured size — that is the centring tool's
    /// guarantee, and it is still worth guarding.**
    ///
    /// `center-sprites.py` sizes each set's canvas so its widest drawing fills
    /// the same proportion car-red does, precisely so one `subject_length_px`
    /// makes a car, a scooter and a camper look the same size. They are all the
    /// subject, so they should. A vehicle declaring an override would be fighting
    /// the tool, and this fails if one ever does.
    func testEveryDirectionalSubjectTakesTheConfiguredSize() {
        let configured: CGFloat = 225
        for subject in VehicleCatalog.subjects where subject.kind == .directional {
            XCTAssertNil(
                subject.lengthFraction,
                "\(subject.id) is a vehicle declaring a size override — the centring tool makes that unnecessary"
            )
            let renderer = VehicleSubjectRenderer.make(
                style: RecapStyle(), subjectId: subject.id, lengthPx: configured
            )
            XCTAssertEqual(renderer.lengthPx, configured, "\(subject.id) must take the configured size")
        }
    }

    /// **A mark is not the subject, so it does not take the subject's size.**
    ///
    /// The tool's equalisation answers "do these vehicles look the same size?",
    /// which is the right question for vehicles and the wrong one for a pin
    /// saying "you are here". Its correct size is a separate judgement, and the
    /// override is the mechanism for exactly that.
    ///
    /// The seagull's value is asserted rather than merely allowed, so changing it
    /// is a deliberate edit to this test and not a silent drift in a JSON file.
    /// It moved 0.5 → 0.7 on 2026-08-18, and this is the whole argument for a
    /// fraction earning its keep: the proportion changed and nothing else had to.
    func testAnOmniMarkMayDeclareItsOwnProportion() throws {
        let seagull = try XCTUnwrap(VehicleCatalog.subject(id: "seagull"))
        XCTAssertEqual(seagull.kind, .omni)
        XCTAssertEqual(
            seagull.lengthFraction, 0.7,
            "the mark is 0.7 of a vehicle — Chiu's call 2026-08-18, after 0.5 read too small"
        )

        // At the shipped 225 that is 157.5 px, and it tracks any later change.
        for configured in [CGFloat(225), 200, 300] {
            let renderer = VehicleSubjectRenderer.make(
                style: RecapStyle(), subjectId: "seagull", lengthPx: configured
            )
            XCTAssertEqual(
                renderer.lengthPx, configured * 0.7, accuracy: 0.001,
                "the mark must stay 0.7 of the subject size at \(configured)"
            )
        }
    }

    /// The override mechanism still exists for the set that eventually needs it,
    /// so this drives it with a manifest entry rather than the shipped one.
    func testADeclaredSizeOverrideWinsOverConfig() throws {
        let declared = try JSONDecoder().decode(VehicleSubject.self, from: Data("""
        {"id": "oversized", "kind": "omni", "type": "mark",
         "selectable": true, "length_fraction": 0.36, "names": {"en": "Oversized"}}
        """.utf8))
        let artwork = try XCTUnwrap(VehicleCatalog.artwork(id: "seagull"))

        let renderer = VehicleSubjectRenderer.make(
            style: RecapStyle(), subjectId: "oversized", lengthPx: 250,
            resolve: { _ in (subject: declared, artwork: artwork) }
        )
        XCTAssertEqual(renderer.lengthPx, 90, "a declared fraction must scale the configured size")
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

    /// **The crossing set ships as art and is never user-choosable.**
    ///
    /// The app derives a crossing from the journey; a user picking "boat" for a
    /// road trip is not a feature. They ship now so the crossing work later is an
    /// asset lookup rather than an art dependency — which is exactly why they
    /// must load as artwork while staying out of the picker.
    func testTheCrossingSetShipsAsArtButNeverAsAChoice() throws {
        let crossing = VehicleCatalog.subjects.filter { !$0.selectable }.map(\.id)
        XCTAssertEqual(
            Set(crossing), ["plane", "plane-3d", "boat"],
            "the crossing set is a product judgement — changing it is a deliberate edit here"
        )
        for id in crossing {
            XCTAssertNotNil(VehicleCatalog.artwork(id: id), "\(id) must still load as artwork")
            XCTAssertFalse(
                VehicleCatalog.selectableSubjects.contains { $0.id == id },
                "\(id) must not reach the picker"
            )
        }
    }

    /// **Who chooses, pinned.** A person picks how their trip looks; the app
    /// picks a crossing. Asserting the selectable set means flipping any
    /// `selectable` flag is a deliberate edit to this test rather than a silent
    /// change in a JSON file.
    func testTheSubjectsAUserMayChooseAreExactlyThese() {
        XCTAssertEqual(
            Set(VehicleCatalog.selectableSubjects.map(\.id)),
            ["car-red", "car-white", "car-toy", "scooter", "camper", "drone", "seagull"]
        )
    }

    /// **Missing art must never remove function** (Chiu 2026-08-17).
    ///
    /// A missing `logo.png` was briefly a second, implicit gate on eligibility,
    /// and it produced the failure that pattern always produces: with car-red's
    /// thumbnail absent the car left the picker, so a user who switched to a
    /// scooter could not switch back, and nothing on screen said why.
    ///
    /// **Stated so it cannot go vacuous.** The first version asserted the rule
    /// against a subject that happened to have no thumbnail, and guarded itself
    /// with "this is vacuous once every subject has a logo.png". That guard fired
    /// the day the last two logos landed — correctly, but it means shipped art
    /// can no longer exercise the path. So the rule is now asserted directly:
    /// eligibility is the flag, and nothing else may narrow it.
    func testEligibilityIsTheFlagAloneAndArtCannotNarrowIt() {
        XCTAssertEqual(
            VehicleCatalog.selectableSubjects.map(\.id),
            VehicleCatalog.subjects.filter(\.selectable).map(\.id),
            "something other than `selectable` is deciding who reaches the picker"
        )

        // The specific trap that second gate sprang: leave the default and you
        // could never come back to it.
        XCTAssertTrue(
            VehicleCatalog.selectableSubjects.contains { $0.id == VehicleCatalog.defaultSubjectId },
            "the default subject must always be reachable in the picker"
        )

        // And eligibility must never outrun what can actually be drawn.
        for subject in VehicleCatalog.selectableSubjects {
            XCTAssertNotNil(VehicleCatalog.artwork(id: subject.id), "\(subject.id) is offered but cannot render")
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
