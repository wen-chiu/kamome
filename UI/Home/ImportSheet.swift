import SwiftUI

/// S1 "Import from photos" flow (spec §4.7 / §5): pick a date range, reconstruct
/// a trip from geotagged photos, then hand the new trip id back so Home can push
/// S3. Progress, a friendly empty/denied error, and the Limited Photo Library
/// path (a Replay MVP gate item) all live here.
struct ImportSheet: View {
    @State private var model: ImportFlowModel
    private let onImported: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Which date row's calendar is expanded (one at a time); nil = both
    /// collapsed. Tapping a row toggles it; picking a day collapses it again.
    private enum DateField { case start, end }
    @State private var editing: DateField?

    init(session: TrackingSession, onImported: @escaping (String) -> Void) {
        _model = State(initialValue: ImportFlowModel(
            config: session.config, repository: session.repository
        ))
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    dateRow(.start, label: "import_from", date: model.startDate)
                    if editing == .start {
                        DatePicker(
                            "import_from",
                            selection: $model.startDate,
                            in: ...model.endDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: model.startDate) { _, newStart in
                            linkEndToStart(newStart)
                            withAnimation { editing = nil }
                        }
                    }
                    dateRow(.end, label: "import_to", date: model.endDate)
                    if editing == .end {
                        DatePicker(
                            "import_to",
                            selection: $model.endDate,
                            in: model.startDate...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: model.endDate) { _, _ in
                            withAnimation { editing = nil }
                        }
                    }
                } header: {
                    Text("import_range_header")
                } footer: {
                    Text("import_range_footer")
                }
                .disabled(model.isImporting)

                // Only visible once access is Limited (post first request) —
                // camera shots stay invisible until added via the system picker.
                if model.isLimitedAccess {
                    Section {
                        Button {
                            model.selectMorePhotos()
                        } label: {
                            Label("limited_photos_manage", systemImage: "photo.badge.plus")
                        }
                        .disabled(model.isImporting)
                    } footer: {
                        Text("limited_photos_notice")
                    }
                }

                Section {
                    switch model.phase {
                    case .idle:
                        importButton
                    case .importing:
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("import_running")
                        }
                    case let .failed(failure):
                        Label(errorText(failure), systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        importButton
                    }
                }
            }
            .navigationTitle("import_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("import_close") { dismiss() }
                        .disabled(model.isImporting)
                }
            }
            .onChange(of: model.completedTripId) { _, tripId in
                if let tripId { onImported(tripId) }
            }
        }
        .interactiveDismissDisabled(model.isImporting)
    }

    /// A tappable summary row: label + the currently-selected date. Tapping
    /// toggles this field's inline calendar (and collapses the other), so the
    /// user always sees what's selected and the calendar isn't left hanging open.
    private func dateRow(_ field: DateField, label: LocalizedStringKey, date: Date) -> some View {
        Button {
            withAnimation { editing = (editing == field) ? nil : field }
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Text(date, style: .date)
                    .foregroundStyle(editing == field ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// After the start date is picked, keep the end date sensible: if it now
    /// sits in a different month (or before the start), snap it onto the start
    /// so the "To" calendar opens on the trip's month instead of today's. An
    /// end already in the same month and after the start is left untouched.
    private func linkEndToStart(_ newStart: Date) {
        let calendar = Calendar.current
        let sameMonth = calendar.isDate(model.endDate, equalTo: newStart, toGranularity: .month)
        if model.endDate < newStart || !sameMonth {
            model.endDate = newStart
        }
    }

    private var importButton: some View {
        Button {
            Task { await model.runImport() }
        } label: {
            Text("import_start")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func errorText(_ failure: ImportFlowModel.Failure) -> LocalizedStringKey {
        switch failure {
        case .noGeotaggedPhotos: return "import_error_no_photos"
        case .accessDenied: return "import_error_access"
        }
    }
}
