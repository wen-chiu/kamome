@testable import Kamome
import KamomeExportEngine
import XCTest

/// **The picker's grid is presentation, never eligibility** (Chiu 2026-10-09).
/// `selectable` is the only gate on what a person may choose
/// (`VehicleCatalogTests`); the grouped grid must show exactly that set, each
/// subject once, and a subject its table does not name must still appear.
final class VehiclePickerLayoutTests: XCTestCase {
    func testEverySelectableSubjectAppearsExactlyOnce() {
        let layout = VehiclePickerLayout(subjects: VehicleCatalog.selectableSubjects)
        let shown = layout.tiles.flatMap(\.variants).map(\.id)
        XCTAssertEqual(shown.count, Set(shown).count, "a subject appears twice: \(shown)")
        XCTAssertEqual(Set(shown), Set(VehicleCatalog.selectableSubjects.map(\.id)))
    }

    /// Every shipped subject is placed by the table, so nothing sits in "Other"
    /// today. New art lands there until the table names it — this test then
    /// says so, which is the prompt to place it.
    func testEveryShippedSelectableSubjectHasAPlannedPlace() {
        let layout = VehiclePickerLayout(subjects: VehicleCatalog.selectableSubjects)
        XCTAssertFalse(layout.groups.contains { $0.id == "other" },
                       "unplaced: \(layout.groups.first { $0.id == "other" }?.tiles.map(\.id) ?? [])")
    }

    /// The agreed merge: red and white car, the two reindeer, the two carriages.
    func testSameThingDifferentStyleSharesATile() {
        let layout = VehiclePickerLayout(subjects: VehicleCatalog.selectableSubjects)
        let families = layout.tiles.filter { $0.variants.count > 1 }.map { $0.variants.map(\.id) }
        XCTAssertEqual(families, [["car-red", "car-white"], ["reindeer-cute", "reindeer-deer"],
                                  ["carriage", "carriage-navy"]])
        XCTAssertEqual(layout.tiles.count, 13)
        for tile in layout.tiles {
            XCTAssertEqual(tile.familyName == nil, tile.variants.count == 1, "\(tile.id) is named wrongly")
        }
    }

    /// A trip whose subject the app chose (a crossing's plane) must still find
    /// it in the picker — `pickableSubjects` offers it, and the grid shows it.
    func testAnUnplannedSubjectLandsInOtherRatherThanDisappearing() throws {
        let plane = try XCTUnwrap(VehicleCatalog.subject(id: VehicleCatalog.planeSubjectId))
        let layout = VehiclePickerLayout(subjects: [plane] + VehicleCatalog.selectableSubjects)
        XCTAssertEqual(layout.groups.last?.id, "other")
        XCTAssertEqual(layout.groups.last?.tiles.map(\.id), [plane.id])
    }

    /// A family missing a style shows the rest, as a one-style tile.
    func testAFamilyMissingAStyleShowsWhatIsOffered() throws {
        let white = try XCTUnwrap(VehicleCatalog.subject(id: "car-white"))
        let layout = VehiclePickerLayout(subjects: [white])
        XCTAssertEqual(layout.tiles.map(\.id), ["car-white"])
        XCTAssertNil(layout.tiles.first?.familyName)
    }
}
