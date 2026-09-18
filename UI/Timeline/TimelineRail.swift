import KamomeTrackingEngine
import SwiftUI

/// **The line every Kamome timeline hangs from.** Home is a chronology of
/// journeys and a journey is a chronology of days; they are the same object at
/// two scales, so they are drawn by the same primitive and the product reads as
/// one thing rather than two screens.
///
/// **The rail is information, not decoration.** It is what makes a screen read
/// as *a journey that happened* instead of a gallery: the eye follows time down
/// the page, and place, event and photograph hang off it in that order. The
/// test this design is held to — take every photograph away, and the screen
/// must still say what happened, where, and when — is only passed because the
/// rail, the dates and the place names carry the story on their own.
struct TimelineRail: View {
    enum Marker: Equatable {
        /// A whole journey, on Home.
        case journey
        /// A place that was visited.
        case place
        /// Travel between two places, drawn as its mode.
        case transport(String)
        /// The line simply passes through — a year or a day heading.
        case none
    }

    let marker: Marker
    var connectsUp = true
    var connectsDown = true
    /// Distance from the top of the row to the marker's centre. Set by the
    /// caller so the marker sits on the first line of text beside it.
    var markerOffset: CGFloat = 9

    /// The rail's own column width. Every row on a screen uses the same one, or
    /// the line is not a line.
    static let width: CGFloat = 22

    private var lineColor: Color { Color.secondary.opacity(0.3) }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(connectsUp ? lineColor : .clear)
                .frame(width: 1, height: max(markerOffset - markerSize / 2, 0))
            glyph
            Rectangle()
                .fill(connectsDown ? lineColor : .clear)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: Self.width)
        // The rail restates what the row's text already says.
        .accessibilityHidden(true)
    }

    private var markerSize: CGFloat {
        switch marker {
        case .journey: return 12
        case .place: return 9
        case .transport: return 22
        case .none: return 0
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch marker {
        case .journey:
            Circle()
                .fill(Color.accentColor)
                .frame(width: markerSize, height: markerSize)
        case .place:
            Circle()
                .fill(Color.accentColor)
                .frame(width: markerSize, height: markerSize)
        case let .transport(symbol):
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: markerSize, height: markerSize)
                .background(Circle().fill(Color(.systemBackground)))
                .overlay(Circle().stroke(lineColor, lineWidth: 1))
        case .none:
            Color.clear.frame(width: 1, height: 0)
        }
    }
}

/// One row of a timeline: the rail, then whatever the row says.
struct TimelineRow<Content: View>: View {
    let marker: TimelineRail.Marker
    var connectsUp = true
    var connectsDown = true
    var markerOffset: CGFloat = 9
    var bottomPadding: CGFloat = 20
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            TimelineRail(
                marker: marker, connectsUp: connectsUp,
                connectsDown: connectsDown, markerOffset: markerOffset
            )
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, bottomPadding)
        }
    }
}

/// **Photographs as evidence inside a timeline** — small, in a row, never a
/// grid and never a cover. A journey with no photographs simply has no row,
/// which is the whole point: the story above it still stands.
struct MemoryRow: View {
    let assetIds: [String]
    /// How many photographs the stretch holds in total, so the row can say what
    /// it is not showing.
    let total: Int
    var side: CGFloat = 54

    var body: some View {
        if !assetIds.isEmpty {
            HStack(alignment: .center, spacing: 6) {
                ForEach(assetIds, id: \.self) { assetId in
                    PhotoThumbnail(assetId: assetId, targetPx: Int(side * 3))
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                if total > assetIds.count {
                    Text(verbatim: "+\(total - assetIds.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(
                String.localizedStringWithFormat(String(localized: "journey_photos"), total)
            ))
        }
    }
}

/// The glyph for a way of travelling. One table, so the home entry, the diary
/// and the map legend cannot disagree about what a drive looks like.
enum TransportGlyph {
    static func symbol(for mode: TransportMode) -> String {
        switch mode {
        case .drive: return "car.fill"
        case .scooter: return "scooter"
        case .walk: return "figure.walk"
        case .cycle: return "bicycle"
        case .transit: return "tram.fill"
        case .unknown: return "arrow.right"
        }
    }

    static func symbol(forRawMode raw: String) -> String {
        symbol(for: TransportMode(rawValue: raw) ?? .unknown)
    }

    /// A crossing has no road under it, so it is never drawn as a car.
    static let crossing = "airplane"
}
