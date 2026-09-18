import SwiftUI

/// One journey on the home screen: its photographs, where it went, when, and
/// how much of it there is. The whole card is one button and one accessibility
/// element; at accessibility text sizes the words move below the photographs
/// instead of over them, so nothing is clipped.
struct JourneyCard: View {
    let journey: JourneySummary
    let isOpening: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    JourneyCover(assetIds: journey.coverAssetIds)
                        .aspectRatio(stacked ? 16 / 10 : 4 / 3, contentMode: .fit)
                    if !stacked {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.08), .black.opacity(0.72)],
                            startPoint: .top, endPoint: .bottom
                        )
                        words.foregroundStyle(.white).padding(20)
                    }
                    if isOpening {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.25))
                    }
                }
                if stacked {
                    words.padding(20)
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 14, y: 6)
        }
        .buttonStyle(CardPress())
        .modifier(CardSource(id: journey.id, namespace: namespace))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let flag = journey.name?.flag {
                    Text(flag).font(.title2)
                }
                Text(journey.headline)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                if journey.name == nil, journey.nameLookupLat != nil {
                    ProgressView().controlSize(.mini).opacity(0.7)
                }
            }
            Text(subtitle)
                .font(.subheadline)
                .opacity(0.85)
            HStack(spacing: 10) {
                Text(meta)
                    .font(.caption.weight(.medium))
                if journey.modes.contains("drive") || journey.modes.contains("scooter") {
                    Image(systemName: "car.fill").font(.caption)
                }
                if journey.modes.contains("walk") {
                    Image(systemName: "figure.walk").font(.caption)
                }
                if journey.filmCount > 0 {
                    Image(systemName: "film.fill").font(.caption)
                }
                Spacer(minLength: 0)
                provenanceChip
            }
            .opacity(0.9)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        let days = String.localizedStringWithFormat(String(localized: "journey_days"), journey.dayCount)
        return "\(journey.dateRangeText) · \(days)"
    }

    private var meta: String {
        var parts = [String.localizedStringWithFormat(String(localized: "journey_photos"), journey.photoCount)]
        if journey.stopCount > 0 {
            parts.append(String.localizedStringWithFormat(String(localized: "journey_stops"), journey.stopCount))
        }
        if let km = journey.distanceM, km >= 1000 {
            parts.append(String.localizedStringWithFormat(String(localized: "journey_km"), km / 1000))
        }
        return parts.joined(separator: " · ")
    }

    /// Honest provenance (§3): a reconstructed journey never reads as recorded.
    private var provenanceChip: some View {
        Text(journey.provenance == .recorded ? "provenance_recorded" : "provenance_badge")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(stacked ? 0 : 0.18)))
            .overlay(Capsule().stroke(.primary.opacity(stacked ? 0.25 : 0), lineWidth: 1))
    }

    private var accessibilityText: String {
        var parts = [journey.headline, subtitle, meta]
        parts.append(String(localized: journey.provenance == .recorded ? "provenance_recorded" : "provenance_badge"))
        return parts.joined(separator: ", ")
    }
}

/// Up to three photographs: one leading, two stacked beside it. With none, a
/// calm gradient and the gull — never a broken-image glyph.
struct JourneyCover: View {
    let assetIds: [String]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            HStack(spacing: 3) {
                tile(assetIds.first, px: Int(width))
                    .frame(width: assetIds.count > 1 ? width * 0.62 : width, height: height)
                if assetIds.count > 1 {
                    VStack(spacing: 3) {
                        tile(assetIds[1], px: Int(width * 0.4))
                        if assetIds.count > 2 {
                            tile(assetIds[2], px: Int(width * 0.4))
                        }
                    }
                }
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func tile(_ assetId: String?, px: Int) -> some View {
        if let assetId {
            PhotoThumbnail(assetId: assetId, targetPx: px, placeholder: .cinematic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            PhotoThumbnail.cinematicPlaceholder
        }
    }
}

/// A gentle press: the card sinks a little and comes back.
struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.25), value: configuration.isPressed)
    }
}

private struct CardSource: ViewModifier {
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
