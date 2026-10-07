import SwiftUI

/// **Home's two segments: 旅程 | 足跡** (Footprints ADR draft
/// 2026-09-30-footprints-sits-beside-journeys). Journeys is where trips are
/// made, Footprints is where the library's journeys are read.
enum HomeSegment: Hashable, CaseIterable {
    case journeys
    case footprints

    /// **Every launch opens on 旅程** (Chiu 2026-10-07). The choice is kept
    /// while the app runs, never across launches: Footprints scans the library
    /// and looks places up when it is shown, and §0 says that never happens at
    /// launch. The ADR's "remembered per device" gave way to that.
    static let atLaunch: HomeSegment = .journeys

    /// The large title above the list.
    var title: LocalizedStringKey {
        switch self {
        case .journeys: "home_title"
        case .footprints: "footprints_title"
        }
    }

    /// The segment's own label in the control.
    var label: LocalizedStringKey {
        switch self {
        case .journeys: "home_segment_journeys"
        case .footprints: "home_segment_footprints"
        }
    }
}

/// A screen Home's one stack pushes, from either segment.
enum HomeRoute: Hashable {
    /// S3, by trip id.
    case trip(String)
    /// A Footprints journey's itinerary, by its entry's id.
    case itinerary(String)
}
