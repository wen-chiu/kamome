import Foundation
import KamomeExportEngine

/// How the vehicle picker arranges the subjects: groups of tiles, where one tile
/// may carry several **styles** of the same thing (Chiu 2026-10-09).
///
/// Sixteen choices in one sideways-scrolling row of chips showed three at a
/// time and were hard to hit. The export sheet now says the choice in one row
/// and opens this grid; same-thing-different-colour sets share a tile, so the
/// grid is thirteen tiles rather than sixteen.
///
/// **Presentation only.** Which subjects a person may choose is still
/// `VehicleCatalog.selectableSubjects` alone (`selectable` is the only gate);
/// this table never adds or removes one. A subject the table does not name —
/// new art, or a trip's own non-selectable subject — lands in a trailing
/// "Other" group rather than disappearing (`VehiclePickerLayoutTests`).
struct VehiclePickerLayout {
    struct Tile: Identifiable {
        /// The family's name when the tile holds more than one style; a
        /// one-style tile is named by its subject.
        let familyName: String.LocalizationValue?
        let variants: [VehicleSubject]

        var id: String { variants[0].id }

        func contains(_ subjectId: String) -> Bool { variants.contains { $0.id == subjectId } }
    }

    struct Group: Identifiable {
        let id: String
        let title: String.LocalizationValue
        let tiles: [Tile]
    }

    let groups: [Group]

    /// One tile's ids, first id the style a tap on the tile chooses.
    private struct TileSpec {
        let ids: [String]
        var family: String.LocalizationValue?
    }

    private struct GroupSpec {
        let id: String
        let title: String.LocalizationValue
        let tiles: [TileSpec]
    }

    private static let plan: [GroupSpec] = [
        GroupSpec(id: "road", title: "vehicle_group_road", tiles: [
            TileSpec(ids: ["car-red", "car-white"], family: "vehicle_family_car"),
            TileSpec(ids: ["car-toy"]),
            TileSpec(ids: ["scooter"]),
            TileSpec(ids: ["camper"]),
            TileSpec(ids: ["bus"]),
            TileSpec(ids: ["train"])
        ]),
        GroupSpec(id: "animals", title: "vehicle_group_animals", tiles: [
            TileSpec(ids: ["reindeer-cute", "reindeer-deer"], family: "vehicle_family_reindeer"),
            TileSpec(ids: ["horse"]),
            TileSpec(ids: ["carriage", "carriage-navy"], family: "vehicle_family_carriage"),
            TileSpec(ids: ["sheep"]),
            TileSpec(ids: ["beaver"]),
            TileSpec(ids: ["seagull"])
        ]),
        GroupSpec(id: "air", title: "vehicle_group_air", tiles: [
            TileSpec(ids: ["drone"])
        ])
    ]

    /// Arranges `subjects` — what the picker offers — by the plan. Only offered
    /// subjects appear; a planned family missing a style shows the rest.
    init(subjects: [VehicleSubject]) {
        let byId = Dictionary(subjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var placed = Set<String>()
        var groups: [Group] = []
        for group in Self.plan {
            let tiles: [Tile] = group.tiles.compactMap { spec in
                let variants = spec.ids.compactMap { byId[$0] }
                guard !variants.isEmpty else { return nil }
                placed.formUnion(variants.map(\.id))
                return Tile(familyName: variants.count > 1 ? spec.family : nil, variants: variants)
            }
            if !tiles.isEmpty { groups.append(Group(id: group.id, title: group.title, tiles: tiles)) }
        }
        let others = subjects.filter { !placed.contains($0.id) }
        if !others.isEmpty {
            groups.append(Group(
                id: "other", title: "vehicle_group_other",
                tiles: others.map { Tile(familyName: nil, variants: [$0]) }
            ))
        }
        self.groups = groups
    }

    var tiles: [Tile] { groups.flatMap(\.tiles) }
}
