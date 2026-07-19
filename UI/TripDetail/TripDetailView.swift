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

    init(tripId: String, session: TrackingSession) {
        _model = State(initialValue: TripDetailModel(
            tripId: tripId, config: session.config, repository: session.repository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            map.frame(minHeight: 280)
            if model.dayCount > 1 { dayChips }
            if let stats = model.stats { statsStrip(stats) }
            if model.photoAccessIsLimited { limitedPhotosBanner }
            timeline
        }
        .navigationTitle(model.detail?.trip.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // S5 entry: only completed trips have a recap to render.
                Button {
                    showingRecap = true
                } label: {
                    Label("recap_export", systemImage: "film")
                }
                .disabled(model.detail?.trip.endedAt == nil)
            }
        }
        .sheet(item: $editingStop) { stop in
            StopEditorView(model: model, stop: stop)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingRecap) {
            RecapView(tripId: model.tripId, session: session)
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
                        label: Text(String.localizedStringWithFormat(String(localized: "day_chip"), day + 1)),
                        selected: model.selectedDay == day
                    ) { model.selectDay(day) }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
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
}