import KamomeConfig
import SwiftUI

// What a run found, said on the export sheet while it renders and again on the
// finished film. Views of their own because both screens show them (split out
// of `RecapView`, arch review 2026-09-26).

/// Blank cards in the film, and why. Shown while rendering and again on the
/// finished film — the person who left the screen reads it there.
struct RecapPhotoShortfallNotice: View {
    let model: RecapModel

    @ViewBuilder
    var body: some View {
        if let shortfall = model.photoShortfall {
            Label("recap_photos_missing", systemImage: "icloud.slash")
                .foregroundStyle(.orange)
            Text(String.localizedStringWithFormat(
                String(localized: "recap_photos_missing_detail"),
                shortfall.missing, shortfall.requested
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

/// Why the film's legs draw dashed, when there is a reason worth giving.
///
/// **Four causes, one symptom** (2026-08-15). A dashed leg can mean no road
/// route exists, the provider could not be reached, it refused for load, or
/// the trip budget ran out — and only the first is the journey being drawn
/// honestly. The other three are worth a retry, and used to be
/// indistinguishable from it in the finished film. A fully routed film and a
/// disabled endpoint say nothing at all: there is nothing to act on.
struct RecapRoutingNotice: View {
    let model: RecapModel

    @ViewBuilder
    var body: some View {
        if let routing = model.routing, routing.isWorthReporting {
            // How many legs draw dashed — the one number the copy uses. It sits
            // in the *headline* ("有 X 段還沒畫"), and only the rate-limit body
            // repeats it, so both strings are formatted with it and the three
            // bodies that do not mention it simply ignore the argument.
            let dashed = routing.attempted - routing.reconstructed
            Label {
                Text(String.localizedStringWithFormat(
                    String(localized: routingHeadlineKey(routing)), dashed
                ))
            } icon: {
                Image(systemName: routingSymbol(routing))
            }
            .foregroundStyle(routing.headline == .someLegsHaveNoRoad ? Color.secondary : Color.orange)
            Text(String.localizedStringWithFormat(
                String(localized: routingDetailKey(routing)), dashed
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func routingHeadlineKey(_ report: RouteMatchReport) -> String.LocalizationValue {
        switch report.headline {
        case .providerUnreachable: return "recap_routing_unreachable"
        case .rateLimited: return "recap_routing_rate_limited"
        case .budgetExhausted: return "recap_routing_budget"
        case .someLegsHaveNoRoad, .disabled, .allRouted: return "recap_routing_no_road"
        }
    }

    private func routingDetailKey(_ report: RouteMatchReport) -> String.LocalizationValue {
        switch report.headline {
        case .providerUnreachable: return "recap_routing_unreachable_detail"
        case .rateLimited: return "recap_routing_rate_limited_detail"
        case .budgetExhausted: return "recap_routing_budget_detail"
        case .someLegsHaveNoRoad, .disabled, .allRouted: return "recap_routing_no_road_detail"
        }
    }

    /// A road that genuinely is not there is not a warning — it gets the map
    /// glyph and secondary colour, while the three retryable causes get the
    /// network glyph and the same orange the photo shortfall uses.
    private func routingSymbol(_ report: RouteMatchReport) -> String {
        switch report.headline {
        case .someLegsHaveNoRoad, .disabled, .allRouted: return "point.topleft.down.curvedto.point.bottomright.up"
        case .rateLimited, .budgetExhausted: return "clock.badge.exclamationmark"
        case .providerUnreachable: return "wifi.slash"
        }
    }
}
