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

    /// The glyph drawn before the word in the control (Chiu 2026-10-07): a
    /// map for the trips made here, footprints for the ones the library holds.
    var symbol: String {
        switch self {
        case .journeys: "map"
        case .footprints: "shoeprints.fill"
        }
    }

    /// The word, as a string, for the image the control draws.
    var labelText: String {
        switch self {
        case .journeys: String(localized: "home_segment_journeys")
        case .footprints: String(localized: "home_segment_footprints")
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
    /// S3 with its newest film already playing: the sample, which arrives with
    /// its film made (#285).
    case tripPlayingNewestFilm(String)
    /// A Footprints journey's itinerary, by its entry's id.
    case itinerary(String)
}

/// Home's 旅程 | 足跡 control. Each segment is its glyph and word drawn as one
/// image (`SegmentLabelImage`): the control would show only one of them.
struct HomeSegmentPicker: View {
    let segment: HomeSegment
    let choose: (HomeSegment) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Picker(selection: Binding(get: { segment }, set: choose)) {
            ForEach(HomeSegment.allCases, id: \.self) { choice in
                Image(uiImage: SegmentLabelImage.make(symbol: choice.symbol, title: choice.labelText))
                    .accessibilityLabel(Text(choice.label))
                    .tag(choice)
            }
        } label: {
            Text("home_segment_label")
        }
        .pickerStyle(.segmented)
        .fixedSize()
        // The image is drawn at one text size; a new size redraws it.
        .id(dynamicTypeSize)
    }
}
