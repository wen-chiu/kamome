@testable import Kamome
import KamomeImportKit
import KamomePersistence
import SwiftUI
import UIKit
import XCTest

/// **A trip of one place is refused before the film button** (Chiu
/// 2026-11-04, #350, ADR
/// 2026-11-04-a-trip-of-one-place-is-refused-before-the-film-button). Import
/// accepted it and the button was live, but the export failed with no film:
/// the camera has nowhere to go on a route of no length.
///
/// Synthetic photographs at public places (`CLAUDE.md` §0).
@MainActor
final class TripDetailFilmButtonTests: XCTestCase {
    private static let epoch = 1_777_593_600.0 // 2026-05-01 00:00 UTC
    private static let square = (lat: 38.7078, lon: -9.1365) // a public square
    /// ~25 km on, well past `photo_import.stop_radius_m`, so a second stop.
    private static let town = (lat: 38.8029, lon: -9.3817)

    private func model(_ photos: [ImportPhoto]) async throws -> TripDetailModel {
        let config = try AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: nil, photos: photos)
        let model = TripDetailModel(tripId: tripId, config: config, repository: repository)
        await model.refresh()
        return model
    }

    private func photos(_ count: Int, at place: (lat: Double, lon: Double), from startS: Double,
                        every stepS: Double = 1800, id: String) -> [ImportPhoto] {
        (0..<count).map {
            ImportPhoto(assetId: "\(id)\($0)", timestamp: startS + Double($0) * stepS, lat: place.lat, lon: place.lon)
        }
    }

    // MARK: - The rule

    /// The issue's own reproduction: three photographs given one location by
    /// hand, an hour apart.
    func testThreePhotographsAtOneHandSetLocationDisableTheButton() async throws {
        let model = try await model(photos(3, at: Self.square, from: Self.epoch, id: "s"))
        XCTAssertNotNil(model.detail?.trip.endedAt, "an import is a finished trip")
        XCTAssertTrue(model.filmHasOnePlace)
        XCTAssertFalse(model.canMakeFilm, "the button is live for a film that cannot be made")
        XCTAssertTrue(model.saysFilmHasOnePlace, "the disabled button does not say why")
    }

    /// Two stays at the same fix on two days are two stops, and still one place.
    func testTwoStaysAtOnePlaceOnTwoDaysDisableTheButton() async throws {
        let model = try await model(
            photos(2, at: Self.square, from: Self.epoch, every: 600, id: "a")
                + photos(2, at: Self.square, from: Self.epoch + 86_400, every: 600, id: "b")
        )
        XCTAssertTrue(model.filmHasOnePlace)
        XCTAssertFalse(model.canMakeFilm)
        XCTAssertTrue(model.saysFilmHasOnePlace)
    }

    /// Two places keep the button live and say nothing.
    func testTwoPlacesKeepTheButtonLive() async throws {
        let model = try await model(
            photos(3, at: Self.square, from: Self.epoch, every: 600, id: "a")
                + photos(3, at: Self.town, from: Self.epoch + 7200, every: 600, id: "b")
        )
        XCTAssertFalse(model.filmHasOnePlace)
        XCTAssertTrue(model.canMakeFilm, "a trip of two places lost its film button")
        XCTAssertFalse(model.saysFilmHasOnePlace)
    }

    /// The cut is the camera's (`CameraPath.goesSomewhere`), not a threshold
    /// of its own: photographs a centimetre apart make a film, so the button
    /// stays live for them (the path probe's D4e renders one).
    func testACentimetreApartIsNotOnePlace() async throws {
        let model = try await model((0..<3).map {
            ImportPhoto(assetId: "c\($0)", timestamp: Self.epoch + Double($0) * 1800,
                        lat: Self.square.lat + Double($0) * 0.000_000_09, lon: Self.square.lon)
        })
        XCTAssertFalse(model.filmHasOnePlace)
        XCTAssertTrue(model.canMakeFilm)
    }

    /// Before the read lands there is no trip to judge: no sentence.
    func testNothingIsSaidBeforeTheTripIsRead() throws {
        let model = TripDetailModel(
            tripId: "none", config: try AppConfig.loadOrDie(),
            repository: TripRepository(database: try AppDatabase.inMemory())
        )
        XCTAssertFalse(model.canMakeFilm)
        XCTAssertFalse(model.saysFilmHasOnePlace)
    }

    // MARK: - What VoiceOver reads

    /// The sentence is read as text, and the dimmed button carries it as its
    /// hint, so the reason reaches a VoiceOver user by either path.
    func testVoiceOverReadsWhyTheButtonIsDimmed() throws {
        let reason = String(localized: "make_film_one_place")
        let elements = try accessibilityElements(FilmButtonBar(canMakeFilm: false, onePlace: true) {})
        print("KAMOME_A11Y one place, in reading order: \(describe(elements))")

        let button = try XCTUnwrap(elements.first { $0.accessibilityTraits.contains(.button) }, describe(elements))
        XCTAssertEqual(button.accessibilityLabel, String(localized: "make_film"))
        XCTAssertTrue(button.accessibilityTraits.contains(.notEnabled), "VoiceOver does not say the button is dimmed")
        XCTAssertEqual(button.accessibilityHint, reason, "the dimmed button does not say why")
        XCTAssertTrue(
            elements.contains { $0.accessibilityLabel == reason && $0.accessibilityTraits.contains(.staticText) },
            "the sentence is not read as text: \(describe(elements))"
        )
    }

    func testVoiceOverHearsNothingExtraOnALiveButton() throws {
        let reason = String(localized: "make_film_one_place")
        let elements = try accessibilityElements(FilmButtonBar(canMakeFilm: true, onePlace: false) {})

        let button = try XCTUnwrap(elements.first { $0.accessibilityTraits.contains(.button) }, describe(elements))
        XCTAssertFalse(button.accessibilityTraits.contains(.notEnabled))
        XCTAssertTrue(button.accessibilityHint?.isEmpty ?? true)
        XCTAssertFalse(elements.contains { $0.accessibilityLabel == reason })
    }

    /// The bar's accessibility elements, as UIKit hands them to VoiceOver.
    ///
    /// ⚠️ SwiftUI builds them only while an assistive technology is attached,
    /// so a hosted view shows UIKit nothing until accessibility automation is
    /// switched on, the way XCUITest switches it on. Test-only; it never ships.
    private func accessibilityElements(_ view: some View) throws -> [NSObject] {
        try Self.enableAccessibilityAutomation()
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 240))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        defer { window.isHidden = true }
        return Self.leaves(of: host.view)
    }

    /// `libAccessibility`'s automation switch. Fails loudly if it is gone: a
    /// VoiceOver test that cannot see the tree must not pass by reading nothing.
    private static func enableAccessibilityAutomation() throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
                                    "libAccessibility did not load: this test cannot see VoiceOver's tree")
        let symbol = try XCTUnwrap(dlsym(library, "_AXSSetAutomationEnabled"),
                                   "_AXSSetAutomationEnabled is gone: this test cannot see VoiceOver's tree")
        typealias SetEnabled = @convention(c) (Int32) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(1)
    }

    private static func leaves(of node: NSObject) -> [NSObject] {
        if node.isAccessibilityElement { return [node] }
        var children: [NSObject] = (node.accessibilityElements as? [NSObject]) ?? []
        if children.isEmpty, case let count = node.accessibilityElementCount(), count != NSNotFound, count > 0 {
            children = (0..<count).compactMap { node.accessibilityElement(at: $0) as? NSObject }
        }
        if children.isEmpty, let view = node as? UIView { children = view.subviews }
        return children.flatMap(leaves(of:))
    }

    private func describe(_ elements: [NSObject]) -> String {
        elements.map { "[\($0.accessibilityLabel ?? "nil") · hint \($0.accessibilityHint ?? "nil")]" }
            .joined(separator: " ")
    }
}
