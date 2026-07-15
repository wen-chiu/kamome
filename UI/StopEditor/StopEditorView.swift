import KamomePersistence
import SwiftUI

/// S4 Stop Editor (Phase 2 cut): rename, note, per-photo highlight toggle,
/// delete. Merge lives on the timeline swipe action; photo reorder needs a
/// schema v2 order column and is deferred (Docs/decisions.md).
struct StopEditorView: View {
    let model: TripDetailModel
    let stop: StopRecord

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("stop_editor_details") {
                    TextField("stop_name_placeholder", text: $name)
                    TextField("stop_note_placeholder", text: $note, axis: .vertical)
                }
                let photos = model.photos(for: stop.id)
                if !photos.isEmpty {
                    Section("stop_editor_photos") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photos, id: \.id) { photo in
                                    Button {
                                        model.toggleHighlight(photo: photo)
                                    } label: {
                                        PhotoThumbnail(assetId: photo.phAssetId, isHighlight: photo.isHighlight == 1)
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        Text("stop_editor_highlight_hint")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        model.deleteStop(stopId: stop.id)
                        dismiss()
                    } label: {
                        Label("delete_stop", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(Text("stop_editor_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        if !name.isEmpty { model.rename(stopId: stop.id, to: name) }
                        model.setNote(stopId: stop.id, note: note)
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = stop.name ?? ""
                note = stop.note ?? ""
            }
        }
    }
}
