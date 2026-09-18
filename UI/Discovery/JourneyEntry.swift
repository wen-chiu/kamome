import SwiftUI

/// **One journey, as a journal entry.** It replaced a photo-cover card on
/// 2026-09-18: the card led with a large image and hung the facts on top of it,
/// which made Home read as a photo library sorted by trip. This reads in the
/// order the journey happened — *when*, then *where*, then *what happened*,
/// then the photographs that prove it.
///
/// The hierarchy is load-bearing rather than stylistic. Cover the photographs
/// with your hand and the entry still says: these dates, this destination, this
/// long, through these places, by car. That is the test the old card failed.
struct JourneyEntry: View {
    let journey: JourneySummary
    let isOpening: Bool
    let isLast: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    /// How many named places the entry lists before it stops counting them out.
    private let milestoneLimit = 3

    var body: some View {
        Button(action: action) {
            TimelineRow(
                marker: .journey, connectsDown: !isLast, markerOffset: 10, bottomPadding: 30
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    dateline
                    destination
                    route
                    if !journey.coverAssetIds.isEmpty {
                        MemoryRow(assetIds: journey.coverAssetIds, total: journey.photoCount)
                            .padding(.top, 4)
                    }
                }
                .opacity(isOpening ? 0.4 : 1)
                .overlay(alignment: .leading) {
                    if isOpening { ProgressView().padding(.leading, 4) }
                }
            }
        }
        .buttonStyle(EntryPress())
        .modifier(EntrySource(id: journey.id, namespace: namespace))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Time

    /// The date is the anchor, so it comes first and shares its line only with
    /// how long the journey lasted and where it came from.
    ///
    /// At an accessibility text size those three stop fitting, and the date
    /// broke across two lines mid-range — "APR 6 / – 10" reads as two dates.
    /// The line stacks instead, so the range always stays whole.
    private var dateline: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                datePart
                durationPart
                Spacer(minLength: 4)
                provenanceLabel
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    datePart
                    durationPart
                }
                provenanceLabel
            }
        }
    }

    private var datePart: some View {
        Text(JourneyDateText.range(from: journey.startedAt, to: journey.endedAt))
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var durationPart: some View {
        Text(String.localizedStringWithFormat(String(localized: "journey_days"), journey.dayCount))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Honest provenance (§3), and it survives the photographs being gone —
    /// which is exactly why it is on the dateline and not on an image.
    private var provenanceLabel: some View {
        Text(journey.provenance == .recorded ? "provenance_recorded" : "provenance_badge")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Place

    private var destination: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let flag = journey.name?.flag {
                Text(flag).font(.title3)
            }
            Text(journey.headline)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            if journey.name == nil, journey.nameLookupLat != nil {
                ProgressView().controlSize(.mini)
            }
        }
    }

    // MARK: - What happened

    /// The route as milestones: the places, joined by how the journey moved
    /// between them. Concatenated into one `Text` so it wraps like a sentence
    /// and reads as one thing to VoiceOver.
    private var route: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            JourneyRouteText.text(
                milestones: journey.milestones, legModes: journey.legModes,
                stopCount: journey.stopCount, limit: milestoneLimit
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            if journey.filmCount > 0 {
                Image(systemName: "film.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
        }
    }

    private var accessibilityText: String {
        var parts = [
            JourneyDateText.range(from: journey.startedAt, to: journey.endedAt),
            journey.headline,
            String.localizedStringWithFormat(String(localized: "journey_days"), journey.dayCount),
            String.localizedStringWithFormat(String(localized: "journey_photos"), journey.photoCount),
            String(localized: journey.provenance == .recorded ? "provenance_recorded" : "provenance_badge")
        ]
        if !journey.milestones.isEmpty {
            parts.append(journey.milestones.prefix(milestoneLimit).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}

/// The journey's places and the travel between them, as one wrapping sentence.
enum JourneyRouteText {
    static func text(milestones: [String], legModes: [String], stopCount: Int, limit: Int) -> Text {
        let named = collapsingRepeats(milestones)
        guard !named.isEmpty else { return unnamed(legModes: legModes, stopCount: stopCount) }
        let shown = Array(named.prefix(limit))
        var result = Text(verbatim: shown[0])
        for index in 1..<shown.count {
            let mode = index - 1 < legModes.count ? legModes[index - 1] : "unknown"
            result = result
                + Text(verbatim: "  ")
                + Text(Image(systemName: TransportGlyph.symbol(forRawMode: mode)))
                + Text(verbatim: "  ")
                + Text(verbatim: shown[index])
        }
        if named.count > shown.count {
            result = result + Text(verbatim: "  +\(named.count - shown.count)")
        }
        return result
    }

    /// Three stops around one town all answer "Whitehorse", and a line reading
    /// "Whitehorse › Whitehorse › Whitehorse" says less than one that reads
    /// "Whitehorse". The stops are still three; only the naming repeats.
    static func collapsingRepeats(_ names: [String]) -> [String] {
        names.reduce(into: [String]()) { result, name in
            if result.last != name { result.append(name) }
        }
    }

    /// A journey nobody has opened yet has no geocoded stops. It says how many
    /// places it holds and how it moved between them, which is true, rather
    /// than inventing names it does not have.
    private static func unnamed(legModes: [String], stopCount: Int) -> Text {
        var result = Text(String.localizedStringWithFormat(String(localized: "journey_places"), stopCount))
        for mode in orderedDistinct(legModes) {
            result = result + Text(verbatim: "  ") + Text(Image(systemName: TransportGlyph.symbol(forRawMode: mode)))
        }
        return result
    }

    private static func orderedDistinct(_ modes: [String]) -> [String] {
        var seen: Set<String> = []
        return modes.filter { seen.insert($0).inserted }
    }
}

/// Compact, locale-aware date ranges for timeline anchors: "3 – 5 Aug" inside
/// one month, "28 Aug – 2 Sep" across two. The year is deliberately absent —
/// the section heading above already carries it.
enum JourneyDateText {
    static func range(from startedAt: Double, to endedAt: Double) -> String {
        let start = Date(timeIntervalSince1970: startedAt)
        let end = Date(timeIntervalSince1970: endedAt)
        let calendar = Calendar.current
        if calendar.isDate(start, equalTo: end, toGranularity: .day) {
            return dayAndMonth.string(from: start)
        }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            // The month sits on the opening date and the range runs from it —
            // "Aug 3 – 5". Putting it on the closing date reads as a typo.
            return "\(dayAndMonth.string(from: start)) – \(dayOnly.string(from: end))"
        }
        return "\(dayAndMonth.string(from: start)) – \(dayAndMonth.string(from: end))"
    }

    private static let dayAndMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    private static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()
}

/// A gentle press. The entry has no card to sink, so the text dims instead.
struct EntryPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

private struct EntrySource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
