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
}
