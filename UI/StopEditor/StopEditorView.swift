import KamomePersistence
import SwiftUI

/// S4 Stop Editor (Phase 2 cut): rename, note, which photographs the film
/// uses (`StopPhotoPickerView`, ADR 2026-09-24), delete. Merge lives on the timeline swipe action; photo reorder needs a
/// schema v2 order column and is deferred (Docs/decisions.md).
struct StopEditorView: View {
    let model: TripDetailModel
    let stop: StopRecord

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var note: String = ""
    @State private var choices: FilmPhotoChoices?

    var body: some View {
        NavigationStack {
            Form {
                Section("stop_editor_details") {
                    TextField("stop_name_placeholder", text: $name)
                    TextField("stop_note_placeholder", text: $note, axis: .vertical)
                }
                if !model.photos(for: stop.id).isEmpty, let choices {
                    Section("stop_editor_photos") {
                        NavigationLink {
                            StopPhotoPickerView(choices: choices, stop: stop)
                        } label: {
                            FilmDeckRow(choices: choices, stop: stop, showsName: false)
                        }
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
                if choices == nil { choices = model.filmPhotoChoices() }
                name = stop.name ?? ""
                note = stop.note ?? ""
            }
        }
    }
}
