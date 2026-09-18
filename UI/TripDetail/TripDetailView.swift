import KamomeExportEngine
import KamomePersistence
import KamomeTripComposer
import MapKit
import SwiftUI

/// **The journey's story** (Journey Discovery detail, 2026-09-17): where it
/// went, when, how, and the photographs — then one action, *Make this a Film*.
///
/// The map supports the story rather than leading it: a small card under the
/// hero, with the legend that says which lines are roads and which are guesses.
/// Every editing affordance that existed before is still here (stop editor,
/// merge and delete on the timeline rows, the ride, stored films); none of them
/// competes with the film button.
struct TripDetailView: View {
    @Environment(TrackingSession.self) private var session
    @State private var model: TripDetailModel
    @State private var editingStop: StopRecord?
    @State private var showingRecap = false
    @State private var playingFilm: FilmRecord?
    /// Read directly off the shared coordinators rather than mirrored: a mirror
    /// is a second place for the answer to be wrong (Chiu 2026-09-10).
    private let exportCoordinator = RecapExportCoordinator.shared
    private let routeCoordinator = RouteMatchCoordinator.shared

    init(tripId: String, session: TrackingSession) {
        _model = State(initialValue: TripDetailModel(
            tripId: tripId, config: session.config, repository: session.repository
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TripHero(model: model, coverCount: session.config.discovery.coverPhotos)
                VStack(alignment: .leading, spacing: 28) {
                    TripGlance(model: model)
                    mapCard
                    if model.photoAccessIsLimited { limitedPhotosRow }
                    TripStoryTimeline(model: model) { editingStop = $0 }
                    rideRow
                    filmsSection
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .top)
        // The bar's own automatic material: clear over the hero at the top, and
        // back once the story scrolls under it — hiding it left the legend
        // running under the status bar (2026-09-17 render).
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { filmBar }
        .onAppear { model.load() }
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
        // The film that landed while nobody was looking (ADR 2026-09-10), and
        // the roads that did: both arrive with this screen open or not.
        .onChange(of: exportCoordinator.outcome(tripId: model.tripId)) { model.reload() }
        .onChange(of: routeCoordinator.progress[model.tripId]) { model.reload() }
        .sheet(item: $playingFilm) { film in
            FilmPlayerSheet(film: film, onDelete: {
                model.deleteFilm(film)
                exportCoordinator.forget(film: film)
                playingFilm = nil
            })
        }
    }

    // MARK: - Map, supporting

    /// Not interactive: a pan inside the story scrolled the map instead of the
    /// page (seen on the 2026-09-17 render). The map is the illustration here;
    /// the film is where the route is watched.
    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Map(interactionModes: []) {
                ForEach(model.visibleSegments, id: \.segment.id) { item in
                    let coords = model.displayPolyline(for: item.points)
                        .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    if coords.count >= 2 {
                        MapPolyline(coordinates: coords)
                            .stroke(Color.accentColor, style: strokeStyle(for: item.segment))
                    }
                }
                ForEach(model.visibleStops, id: \.id) { stop in
                    Annotation(stop.name ?? "", coordinate: .init(latitude: stop.lat, longitude: stop.lon)) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel(Text("story_map_label"))
            mapLegend
        }
    }

    /// Solid is a known line, dashed is a guess (PD-1). Said under the map so
    /// the film's convention is taught where it is first seen.
    @ViewBuilder
    private var mapLegend: some View {
        let hasInferred = model.storyDays.flatMap(\.entries).contains { $0.leg?.provenance == .inferred }
        HStack(spacing: 14) {
            legendSwatch(dashed: false, text: model.isReconstructed ? "leg_matched" : "leg_recorded")
            if hasInferred { legendSwatch(dashed: true, text: "leg_inferred") }
            if routeCoordinator.isRunning(model.tripId) {
                ProgressView().controlSize(.mini)
                Text("story_roads_arriving").font(.caption2)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func legendSwatch(dashed: Bool, text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 22, y: 0))
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: dashed ? [4, 4] : []))
            .frame(width: 22, height: 3)
            Text(text)
        }
    }

    private func strokeStyle(for segment: SegmentRecord) -> StrokeStyle {
        RecapComposer.provenance(for: segment) == .inferred
            ? StrokeStyle(lineWidth: 3, dash: [4, 6])
            : StrokeStyle(lineWidth: 4)
    }

    // MARK: - Rows

    private var limitedPhotosRow: some View {
        LimitedLibraryRow { model.manageLimitedPhotoSelection() }
    }

    /// Which subject the film draws — a trip property (schema v3). The plane is
    /// absent on purpose: the app picks it for a crossing.
    @ViewBuilder
    private var rideRow: some View {
        let subjects = model.pickableSubjects
        if subjects.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Text("story_ride").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(subjects, id: \.id) { subject in
                            Button { model.chooseVehicle(subject.id) } label: {
                                RideChip(subject: subject, isSelected: subject.id == model.vehicleId)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filmsSection: some View {
        if !model.films.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("films_section_title").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.films) { film in
                            Button { playingFilm = film } label: { FilmChip(film: film) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - The one action

    /// *Make this a Film*, pinned to the bottom. Off while stops are still being
    /// named (Chiu 2026-08-04: exporting early bakes "Unnamed stop" into the
    /// film), and the line beneath says why. A running export shows here too,
    /// because the export outlives the sheet (ADR 2026-09-10).
    private var filmBar: some View {
        VStack(spacing: 8) {
            if let running = exportCoordinator.running(tripId: model.tripId) {
                HStack(spacing: 12) {
                    ProgressView(value: running.fraction)
                    Text(running.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("recap_cancel", role: .cancel) { exportCoordinator.cancel(tripId: model.tripId) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Button { showingRecap = true } label: {
                Label("make_film", systemImage: "film")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.detail?.trip.endedAt == nil || model.isNamingStops)
            if model.isNamingStops {
                Text(String.localizedStringWithFormat(
                    String(localized: "naming_stops_progress"), model.naming.completed, model.naming.total
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

private struct RideChip: View {
    let subject: VehicleSubject
    let isSelected: Bool

    var body: some View {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        HStack(spacing: 6) {
            if let thumbnail = VehicleCatalog.thumbnail(id: subject.id) {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
            }
            Text(subject.displayName(language: language)).font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
        .overlay(Capsule().stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
        .clipShape(Capsule())
    }
}

private struct FilmChip: View {
    let film: FilmRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: film.format == "gif" ? "photo.on.rectangle" : "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(timeIntervalSince1970: film.createdAt), style: .date).font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(film.format.uppercased())
                    if let bytes = film.fileBytes {
                        Text("·")
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
