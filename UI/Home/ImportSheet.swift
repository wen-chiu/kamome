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
                Picker("import_source", selection: $model.source) {
                    Text("import_source_range").tag(ImportFlowModel.Source.dateRange)
                    Text("import_source_album").tag(ImportFlowModel.Source.album)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(model.isImporting)

                switch model.source {
                case .dateRange: dateRangeSection
                case .album: albumSection
                }

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
                        // Under Limited access album membership is mostly
                        // invisible, so a short or empty list is PhotoKit working
                        // as designed. Saying so beats an unexplained empty list.
                        Text(model.source == .album ? "limited_photos_albums_notice" : "limited_photos_notice")
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
            .task(id: model.source) {
                guard model.source == .album, model.albums.isEmpty else { return }
                await model.loadAlbums()
            }
        }
        .interactiveDismissDisabled(model.isImporting)
    }

    /// The date-range path — unchanged, and still the default.
    @ViewBuilder
    private var dateRangeSection: some View {
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
    }

    /// The album path. Each row carries the album's **date span**, because an
    /// album is not necessarily one trip: `ImportService` builds a single trip
    /// from whatever it is given, so an album holding two holidays becomes one
    /// trip with an absurd leg between them. Showing the span is what stops that
    /// happening silently (Chiu 2026-08-15).
    @ViewBuilder
    private var albumSection: some View {
        Section {
            if model.isLoadingAlbums {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("import_albums_loading")
                }
            } else if model.albums.isEmpty {
                Text("import_albums_empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.albums) { album in
                    Button {
                        model.selectedAlbumId = album.id
                    } label: {
                        albumRow(album)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("import_albums_header")
        } footer: {
            Text("import_albums_footer")
        }
        .disabled(model.isImporting)
    }

    private func albumRow(_ album: PhotoAlbum) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .foregroundStyle(.primary)
                Text(spanText(album))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.selectedAlbumId == album.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// "12 Jul – 19 Jul 2026 · 160 photos" — the span first, because that is the
    /// number that tells the user whether this album is one journey.
    private func spanText(_ album: PhotoAlbum) -> String {
        let count = String.localizedStringWithFormat(
            String(localized: "import_album_photo_count"), album.photoCount
        )
        guard let earliest = album.earliest, let latest = album.latest else { return count }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let from = formatter.string(from: earliest)
        let to = formatter.string(from: latest)
        let span = from == to ? from : "\(from) – \(to)"
        return "\(span) · \(count)"
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
        .disabled(!model.canImport)
    }

    private func errorText(_ failure: ImportFlowModel.Failure) -> LocalizedStringKey {
        switch failure {
        case .noGeotaggedPhotos: return "import_error_no_photos"
        case .accessDenied: return "import_error_access"
        }
    }
}
