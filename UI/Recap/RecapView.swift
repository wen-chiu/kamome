import SwiftUI

/// S5 Export (P3 scope): photos toggle, MP4/GIF choice, progress, share.
/// The toggle copy must make clear it controls photo overlays only — title
/// and end cards always render (decisions.md 2026-07-18 recap-chrome, Chiu).
struct RecapView: View {
    @State private var model: RecapModel
    @Environment(\.dismiss) private var dismiss

    init(tripId: String, session: TrackingSession) {
        _model = State(initialValue: RecapModel(
            tripId: tripId, config: session.config, repository: session.repository
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("recap_photos_toggle", isOn: $model.photosEnabled)
                        .disabled(model.isRendering)
                    Picker("recap_format", selection: $model.format) {
                        Text("recap_format_mp4").tag(RecapModel.Format.mp4)
                        Text("recap_format_gif").tag(RecapModel.Format.gif)
                    }
                    .disabled(model.isRendering)
                } footer: {
                    // The load-bearing sentence: photos ≠ chrome.
                    Text("recap_photos_note")
                }

                if let shortfall = model.photoShortfall {
                    Section {
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

                routingSection

                Section {
                    switch model.phase {
                    case .idle:
                        Button("recap_export") { model.startExport() }

                    case let .rendering(progress):
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: progress) {
                                Text("recap_rendering")
                            }
                            Button("recap_cancel", role: .cancel) { model.cancel() }
                        }

                    case let .finished(shareURL, renderSeconds):
                        ShareLink(item: shareURL) {
                            Label("recap_share", systemImage: "square.and.arrow.up")
                        }
                        // Actual number, visible on device — this is the §4.5
                        // render-budget readout (< 90 s bar).
                        Text(String.localizedStringWithFormat(
                            String(localized: "recap_render_time"),
                            String(format: "%.1f", renderSeconds)
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        Button("recap_export_again") { model.startExport() }

                    case let .failed(message):
                        Label("recap_failed", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("recap_export") { model.startExport() }
                    }
                }
            }
            .navigationTitle("recap_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("recap_done") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.isRendering)
    }

    /// Why the film's legs draw dashed, when there is a reason worth giving.
    ///
    /// **Four causes, one symptom** (2026-08-15). A dashed leg can mean no road
    /// route exists, the provider could not be reached, it refused for load, or
    /// the trip budget ran out — and only the first is the journey being drawn
    /// honestly. The other three are worth a retry, and used to be
    /// indistinguishable from it in the finished film. A fully routed film and a
    /// disabled endpoint say nothing at all: there is nothing to act on.
    @ViewBuilder
    private var routingSection: some View {
        if let routing = model.routing, routing.isWorthReporting {
            let dashed = routing.attempted - routing.reconstructed
            Section {
                Label(routingHeadline(routing), systemImage: routingSymbol(routing))
                    .foregroundStyle(routing.headline == .someLegsHaveNoRoad ? Color.secondary : Color.orange)
                Text(String.localizedStringWithFormat(
                    String(localized: routingDetailKey(routing)), dashed, routing.attempted
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func routingHeadline(_ report: RouteMatchReport) -> LocalizedStringKey {
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
