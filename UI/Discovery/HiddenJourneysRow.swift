import SwiftUI

/// **Hidden journeys**, one row at the foot of the list (Chiu 2026-10-03,
/// #167). Hiding used to be for good: a stray long-press lost a journey until
/// the app's data was cleared. The row opens in place, like an entry's drawer,
/// and each journey in it can be shown again. Absent when nothing is hidden.
struct HiddenJourneysRow: View {
    let journeys: [JourneySummary]
    @Binding var isExpanded: Bool
    let onUnhide: (JourneySummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash")
                    Text("discovery_hidden_title")
                    Text(verbatim: "\(journeys.count)")
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(Text(isExpanded ? "journey_collapse" : "journey_expand"))
            if isExpanded {
                ForEach(journeys) { journey in
                    Divider().padding(.vertical, 10)
                    HiddenJourneyLine(journey: journey) { onUnhide(journey) }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One hidden journey: what the card called it, its dates, and the way back.
private struct HiddenJourneyLine: View {
    let journey: JourneySummary
    let onUnhide: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: [journey.name?.flag, journey.headline].compactMap { $0 }.joined(separator: " "))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(verbatim: journey.dateRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("journey_unhide", action: onUnhide)
                .font(.footnote.weight(.semibold))
                // In Footprints' list a default-style button takes the whole row's tap.
                .buttonStyle(.borderless)
        }
    }
}
