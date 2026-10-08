import SwiftUI

/// **One journey, as a journal entry.** It replaced a photo-cover card on
/// 2026-09-18: the card led with a large image and hung the facts on it, which
/// made Home read as a photo library sorted by trip.
///
/// **Two lines, and a drawer** (Chiu, 2026-09-23). Collapsed, an entry is
/// *where and when* — flag, destination, which visit, dates — then *how it
/// went* — the route, the days, the kilometres on the ground. The chevron opens
/// the drawer in place: photographs, the whole route, the counts, the visit
/// said in full, and the way into the diary. Tapping the entry itself still
/// opens the diary, so the drawer is a look, not a step.
///
/// **Provenance is marked by exception** (ADR 2026-09-23 (e)): nearly every
/// journey here is rebuilt from photographs, so a recorded one carries a
/// location glyph and a photo one carries nothing.
struct JourneyEntry: View {
    let journey: JourneySummary
    /// Which visit to its country this was, when abroad and the country is known.
    let visit: JourneyChronicle.Visit?
    let isExpanded: Bool
    let isOpening: Bool
    let isLast: Bool
    let namespace: Namespace.ID
    let onToggle: () -> Void
    let action: () -> Void

    /// How many named places the collapsed route lists before it counts the rest.
    private let milestoneLimit = 2
    /// Room the chevron takes at the end of the second line.
    private let chevronWidth: CGFloat = 28
    /// The chevron's hit area: Apple's minimum target, centred on the glyph.
    private let chevronTarget: CGFloat = 44

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineRow(
            marker: .journey, connectsDown: !isLast, markerOffset: 13, bottomPadding: 20
        ) {
            VStack(alignment: .leading, spacing: 0) {
                summary
                if isExpanded {
                    JourneyDrawer(journey: journey, visit: visit, action: action)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - Collapsed

    private var summary: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                headline
                routeLine
                    .padding(.trailing, chevronWidth)
            }
            .opacity(isOpening ? 0.4 : 1)
            .overlay(alignment: .leading) {
                if isOpening { ProgressView().padding(.leading, 4) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EntryPress())
        .modifier(EntrySource(id: journey.id, namespace: namespace))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(isExpanded ? "journey_collapse" : "journey_expand"), onToggle)
        .overlay(alignment: .bottomTrailing) { chevron }
    }

    /// The glyph keeps its 28 × 20 place at the end of the route line; the
    /// target around it is 44 pt (Chiu 2026-10-07 — it was the glyph's own
    /// size, beside the much larger target that opens the diary).
    private var chevron: some View {
        Button(action: onToggle) {
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(width: chevronWidth, height: 20)
                .frame(width: chevronTarget, height: chevronTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: (chevronTarget - chevronWidth) / 2, y: (chevronTarget - 20) / 2)
        .accessibilityLabel(Text(isExpanded ? "journey_collapse" : "journey_expand"))
    }

    /// Destination and dates on one line (Chiu, 2026-09-23). A long name
    /// wraps to a second line beside the dates rather than pushing them under
    /// it — `ViewThatFits` measured the name unwrapped, so one long album name
    /// both lost its end and moved its dates where no other entry has them
    /// (2026-10-07). At an accessibility text size the line stacks, so the
    /// range never breaks mid-range ("APR 6 / – 10" reads as two dates).
    @ViewBuilder
    private var headline: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                destination
                datePart
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                destination
                Spacer(minLength: 8)
                datePart
            }
        }
    }

    private var destination: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let flag = journey.name?.flag {
                Text(flag).font(.headline)
            }
            Text(journey.headline)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let visit, JourneyChronicle.showsPill(visit) {
                VisitPill(text: JourneyChronicle.pillText(visit))
            }
            if journey.name == nil, journey.nameLookupLat != nil {
                ProgressView().controlSize(.mini)
            }
        }
    }

    private var datePart: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if journey.provenance == .recorded {
                Image(systemName: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(JourneyDateText.range(from: journey.startedAt, to: journey.endedAt))
                .font(.caption.weight(.semibold))
                .modifier(SmallCaps(tracking: 0.6))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The route gives way first: it truncates, and the days and kilometres
    /// after it always print whole.
    private var routeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            JourneyRouteText.text(
                milestones: journey.milestones, legModes: journey.legModes,
                stopCount: journey.stopCount, limit: milestoneLimit
            )
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .layoutPriority(0)
            Spacer(minLength: 0)
            Text(JourneyFiguresText.text(days: journey.dayCount, distanceM: journey.distanceM))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .font(.footnote)
    }

    private var accessibilityText: String {
        var parts = [
            JourneyDateText.range(from: journey.startedAt, to: journey.endedAt),
            journey.headline,
            JourneyFiguresText.text(days: journey.dayCount, distanceM: journey.distanceM)
        ]
        if let visit { parts.append(JourneyChronicle.visitText(visit)) }
        if journey.provenance == .recorded { parts.append(String(localized: "provenance_recorded")) }
        if !journey.milestones.isEmpty {
            parts.append(journey.milestones.prefix(milestoneLimit).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}

/// 「初訪」 / 「第2次」 beside the destination — the short form of the visit
/// line; the drawer says it in full (Chiu chose this form, 2026-09-23).
private struct VisitPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(.tint.opacity(0.5), lineWidth: 0.5))
            .fixedSize()
    }
}

/// "9 days · 1,240 km" — the km only when it is known (`JourneySummary.distanceM`),
/// and only from a kilometre up, the rule the diary's figures line uses.
enum JourneyFiguresText {
    static func text(days: Int, distanceM: Double?) -> String {
        var parts = [String.localizedStringWithFormat(String(localized: "journey_days"), days)]
        if let distanceM, distanceM >= 1000 {
            parts.append(String.localizedStringWithFormat(String(localized: "journey_km"), distanceM / 1000))
        }
        return parts.joined(separator: " · ")
    }
}

/// **The drawer** — what the entry keeps folded: the photographs, the whole
/// route, the counts, the visit said in full, and the way into the diary.
/// Photographs sit *under* the story they belong to, which is the hierarchy
/// ADR 2026-09-18 set; opening the drawer never turns the row into a cover.
private struct JourneyDrawer: View {
    let journey: JourneySummary
    let visit: JourneyChronicle.Visit?
    let action: () -> Void

    private let photoSide: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !journey.coverAssetIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    MemoryRow(assetIds: journey.coverAssetIds, total: journey.photoCount, side: photoSide)
                }
                .scrollClipDisabled()
            }
            VStack(alignment: .leading, spacing: 5) {
                fact("mappin.and.ellipse", route)
                fact("photo.on.rectangle", counts)
                if let visit {
                    fact("clock.arrow.circlepath", visitLine(visit))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button(action: action) {
                Label("journey_open", systemImage: "arrow.right")
                    .labelStyle(TrailingIcon())
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
                .foregroundStyle(.tertiary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Every named place in order, then how many there are. Without names
    /// (a journey not yet opened) just the count, which is true.
    private var route: String {
        let places = String.localizedStringWithFormat(String(localized: "journey_places"), journey.stopCount)
        let named = JourneyRouteText.collapsingRepeats(journey.milestones)
        guard !named.isEmpty else { return places }
        return named.joined(separator: " → ") + " · " + places
    }

    private var counts: String {
        var parts = [String.localizedStringWithFormat(String(localized: "journey_photos"), journey.photoCount)]
        if journey.filmCount > 0 {
            parts.append(String.localizedStringWithFormat(String(localized: "journey_films"), journey.filmCount))
        }
        return parts.joined(separator: " · ")
    }

    private func visitLine(_ visit: JourneyChronicle.Visit) -> String {
        var line = JourneyChronicle.visitText(visit)
        if let previous = visit.previous {
            line += " · " + JourneyChronicle.previousText(previous, country: visit.country)
        }
        return line
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// "2 months at home" — the time between two journeys, drawn on the rail
/// between them so the page reads as a life passing rather than a list
/// (Chiu, 2026-09-23). Hidden with `discovery.show_home_gaps`.
struct HomeGapRow: View {
    let days: Int

    var body: some View {
        TimelineRow(marker: .none, markerOffset: 0, bottomPadding: 18) {
            Text(String.localizedStringWithFormat(
                String(localized: "journey_home_gap"), JourneyChronicle.durationText(days: days)
            ))
            .font(ScriptTypography.isLatin ? .caption.italic() : .caption)
            .foregroundStyle(.tertiary)
        }
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
        guard named.count > shown.count else { return result }
        return result + Text(verbatim: "  +\(named.count - shown.count)")
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
