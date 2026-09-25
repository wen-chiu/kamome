import AVKit
import KamomeExportEngine
import KamomePersistence
import KamomeTripComposer
import MapKit
import SwiftUI

/// S3 Trip Detail: mode-colored route (drive solid, walk dotted), stop pins
/// with photo badges, day filter chips, stats strip, timeline list.
struct TripDetailView: View {
    @Environment(TrackingSession.self) private var session
    @State private var model: TripDetailModel
    @State private var editingStop: StopRecord?
    @State private var showingRecap = false
    @State private var playingFilm: FilmRecord?
    @State private var showingAllFilms = false
    @State private var showingProvenance = false
    @State private var showingMerge = false
    /// Set when a merge folded this trip into an earlier one: the screen leaves
    /// once the sheet is gone, since two dismissals in one pass race.
    @State private var mergedAway = false
    @Environment(\.dismiss) private var dismiss
    /// The export outlives the sheet, so the trip screen has to be able to draw
    /// it (Chiu 2026-09-10). Read directly off the shared coordinator rather
    /// than mirrored onto `TripDetailModel`: a mirror is a second place for the
    /// answer to be wrong, and Observation tracks the reads in `body` either way.
    private let exportCoordinator = RecapExportCoordinator.shared

    init(tripId: String, session: TrackingSession) {
        _model = State(initialValue: TripDetailModel(
            tripId: tripId, config: session.config, repository: session.repository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(minHeight: 280)
                .overlay(alignment: .bottomTrailing) { mapOverlays }
            if model.dayCount > 1 { dayChips }
            if let stats = model.stats { statsStrip(stats) }
            if model.isNamingStops { namingBanner }
            if model.photoAccessIsLimited { limitedPhotosBanner }
            exportProgressRow
            timeline
        }
        .navigationTitle(model.detail?.trip.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.load()
            #if DEBUG
            // The export sheet's own shot (Chiu 2026-09-25): with
            // `-demo-open-trip`, straight on to the film's stops and photos.
            if ProcessInfo.processInfo.arguments.contains("-demo-open-recap") { showingRecap = true }
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // S5 entry: only completed trips have a recap to render.
                Button {
                    showingRecap = true
                } label: {
                    Label("recap_export", systemImage: "film")
                }
                // Naming is throttled and asynchronous; a film exported before it
                // finishes says "Unnamed stop" for every stop still in the queue
                // (Chiu 2026-08-04). The banner above says why the button is off.
                .disabled(model.detail?.trip.endedAt == nil || model.isNamingStops)
            }
            // The overflow menu, not a second trailing button: merging is rare,
            // and Home's two-trailing-items bug (2026-09-02) is not worth risking.
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingMerge = true
                } label: {
                    Label("trip_merge_action", systemImage: "arrow.triangle.merge")
                }
                .disabled(model.detail?.trip.endedAt == nil)
            }
        }
        .sheet(isPresented: $showingMerge) {
            TripMergeSheet(tripId: model.tripId, session: session) { keptId in
                // This trip survives when it is the earliest; otherwise it no
                // longer exists, and Home shows the merged one.
                if keptId == model.tripId {
                    model.reload()
                } else {
                    mergedAway = true
                }
            }
        }
        .onChange(of: showingMerge) {
            if !showingMerge, mergedAway { dismiss() }
        }
        .sheet(item: $editingStop) { stop in
            StopEditorView(model: model, stop: stop)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingRecap) {
            RecapView(tripId: model.tripId, session: session)
        }
        .onChange(of: showingRecap) {
            if !showingRecap { model.reload() }
        }
        // **The film that landed while nobody was looking.** An export now
        // finishes with the sheet closed, so the trip screen has to pick up the
        // new record itself — waiting for the sheet to be dismissed was the only
        // refresh there was, and it no longer happens at the right moment.
        .onChange(of: exportCoordinator.outcome(tripId: model.tripId)) {
            model.reload()
        }
        .sheet(isPresented: $showingAllFilms) {
            FilmsListSheet(films: model.films) { film in
                showingAllFilms = false
                playingFilm = film
            }
        }
        .sheet(item: $playingFilm) { film in
            FilmPlayerSheet(film: film, onDelete: {
                model.deleteFilm(film)
                // The export sheet remembers this trip's last finished film, and
                // that memory now outlives the sheet — so deleting the film here
                // has to clear it, or reopening the sheet plays a file that is
                // gone (ADR 2026-09-10).
                exportCoordinator.forget(film: film)
                playingFilm = nil
            })
        }
    }

    private var map: some View {
        Map {
            ForEach(model.visibleSegments, id: \.segment.id) { item in
                let coords = model.displayPolyline(for: item.points)
                    .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                if coords.count >= 2 {
                    MapPolyline(coordinates: coords)
                        .stroke(color(for: item.segment.mode), style: strokeStyle(for: item.segment.mode))
                }
            }
            ForEach(model.visibleStops, id: \.id) { stop in
                Annotation(stop.name ?? "", coordinate: .init(latitude: stop.lat, longitude: stop.lon)) {
                    stopPin(stop)
                }
            }
        }
    }

    private func stopPin(_ stop: StopRecord) -> some View {
        Button {
            editingStop = stop
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .background(Circle().fill(.background))
                let count = model.photos(for: stop.id).count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.bold())
                        .padding(3)
                        .background(Circle().fill(.orange))
                        .offset(x: 8, y: -8)
                }
            }
        }
    }

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip(label: Text("day_all"), selected: model.selectedDay == nil) { model.selectDay(nil) }
                ForEach(0..<model.dayCount, id: \.self) { day in
                    chip(
                        label: Text(dayChipLabel(day)),
                        selected: model.selectedDay == day
                    ) { model.selectDay(day) }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    /// "Day 5 · 8/26": the number the film uses, and the date it stands for, so
    /// a chip can be checked against the photos' own dates.
    private func dayChipLabel(_ day: Int) -> String {
        guard let date = model.date(ofDay: day) else {
            return String.localizedStringWithFormat(String(localized: "day_chip"), day + 1)
        }
        return String.localizedStringWithFormat(
            String(localized: "day_chip_dated"), day + 1, date.formatted(.dateTime.month(.defaultDigits).day())
        )
    }

    private func chip(label: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.2)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
    }

    private func statsStrip(_ stats: TripStats) -> some View {
        HStack(spacing: 24) {
            stat(value: String(format: "%.0f km", stats.distanceM / 1000), label: "stat_distance")
            stat(value: hours(stats.driveS), label: "stat_drive_time")
            stat(value: "\(stats.stopCount)", label: "stat_stops")
            stat(value: String(format: "%.0f km/h", stats.topSpeedKmh), label: "stat_top_speed")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private func stat(value: String, label: LocalizedStringKey) -> some View {
        VStack {
            Text(value).font(.subheadline.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// What floats on the map's bottom-right corner — bottom-right because
    /// Apple's Maps logo and Legal link hold the bottom-left, and they must stay
    /// visible. Both used to be full-width rows under the map (Chiu 2026-09-23:
    /// too much page for too little information).
    private var mapOverlays: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if model.isReconstructed { provenanceChip }
            if let latest = model.films.first {
                FilmPosterButton(latest: latest, count: model.films.count) {
                    if model.films.count == 1 {
                        playingFilm = latest
                    } else {
                        showingAllFilms = true
                    }
                }
            }
        }
        .padding(12)
    }

    /// Honest provenance (§3/§6): an imported trip's route is inferred from
    /// photo place+time, not recorded — say so, and never imply it is verified.
    ///
    /// **Compact, not removed** (Chiu 2026-09-23). The ADR of 2026-07-20 makes the
    /// S3 note a product rule, so it stays on screen; it is the S1 badge's two
    /// words now, and the full sentence is one tap away.
    private var provenanceChip: some View {
        Button {
            showingProvenance = true
        } label: {
            Label("provenance_badge", systemImage: "photo.on.rectangle")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.thinMaterial))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingProvenance) {
            Text("provenance_note")
                .font(.footnote)
                .padding()
                .frame(idealWidth: 280)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Stop naming is throttled (§4.2), so on an imported trip it runs for tens
    /// of seconds after this screen opens. Without this row the wait is invisible
    /// and the disabled film button looks broken rather than deliberate.
    private var namingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(String.localizedStringWithFormat(
                String(localized: "naming_stops_progress"),
                model.naming.completed, model.naming.total
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    /// Selected-Photos access hides camera shots taken during the trip until
    /// the user adds them; without this row they'd silently never appear.
    private var limitedPhotosBanner: some View {
        HStack {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Text("limited_photos_notice")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("limited_photos_manage") {
                model.manageLimitedPhotoSelection()
            }
            .font(.caption.bold())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var timeline: some View {
        List {
            ForEach(model.visibleStops, id: \.id) { stop in
                Button {
                    editingStop = stop
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name ?? String(localized: "stop_unnamed"))
                                .font(.headline)
                            Text(Date(timeIntervalSince1970: stop.arrivedAt), style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        PhotoStrip(photos: model.photos(for: stop.id), maxThumbnails: 3)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        model.deleteStop(stopId: stop.id)
                    } label: {
                        Label("delete_stop", systemImage: "trash")
                    }
                    if model.visibleStops.first?.id != stop.id {
                        Button {
                            model.mergeWithPrevious(stopId: stop.id)
                        } label: {
                            Label("merge_with_previous", systemImage: "arrow.triangle.merge")
                        }
                    }
                }
            }
            // §4.3 route-attached photos (no stop) — without this row they
            // exist in the DB but appear nowhere.
            if !model.routePhotos.isEmpty {
                HStack {
                    Text("route_photos_header")
                        .font(.headline)
                    Spacer()
                    PhotoStrip(photos: model.routePhotos, maxThumbnails: 3)
                }
            }
        }
        .listStyle(.plain)
    }

    private func hours(_ seconds: Double) -> String {
        String(format: "%.1f h", seconds / 3600)
    }

    private func color(for mode: String) -> Color {
        switch mode {
        case "drive", "scooter": return .accentColor
        case "walk": return .green
        case "cycle": return .mint
        case "transit": return .purple
        default: return .gray
        }
    }

    private func strokeStyle(for mode: String) -> StrokeStyle {
        // Drive = solid, on-foot = dotted (§5 S3).
        mode == "walk" || mode == "cycle"
            ? StrokeStyle(lineWidth: 3, dash: [4, 6])
            : StrokeStyle(lineWidth: 4)
    }

    /// The running export, on the trip screen rather than inside the sheet
    /// (Chiu 2026-09-10). Progress has to be visible from outside, or "you can
    /// leave this screen" means the film disappears the moment you do.
    ///
    /// Only this trip's export is drawn. One export runs app-wide, but a trip
    /// showing another trip's progress bar would read as its own.
    @ViewBuilder
    private var exportProgressRow: some View {
        if let running = exportCoordinator.running(tripId: model.tripId) {
            HStack(spacing: 12) {
                ProgressView(value: running.fraction)
                    .frame(maxWidth: .infinity)
                Text(running.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("recap_cancel", role: .cancel) {
                    exportCoordinator.cancel(tripId: model.tripId)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }
}
