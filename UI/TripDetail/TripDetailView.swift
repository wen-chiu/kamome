import KamomeExportEngine
import KamomePersistence
import KamomeTripComposer
import MapKit
import SwiftUI

/// **A journey's diary** (redesigned 2026-09-18), and one action at the foot of
/// it: *Make this a Film*.
///
/// The screen reads top to bottom as the journey happened — masthead, figures,
/// the route as a supporting illustration, then day by day: the travel, the
/// place it reached, the photographs taken there. It used to open on a
/// full-bleed photo cover, which made a journey look like an album; the
/// photographs now sit inside the days they belong to, at the size of evidence.
///
/// Every editing affordance survives the redesign (stop editor, merge and
/// delete, the ride, stored films). None of them competes with the film button.
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
            VStack(alignment: .leading, spacing: 22) {
                JourneyMasthead(model: model)
                JourneyFigures(model: model)
                routeIllustration
                if model.photoAccessIsLimited {
                    LimitedLibraryRow { model.manageLimitedPhotoSelection() }
                }
                JourneyDiary(model: model) { editingStop = $0 }
                    .padding(.top, 2)
                rideRow
                filmsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
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

    // MARK: - The route, supporting

    /// A strip, not a screen. The map shows the shape of the journey beside the
    /// words that tell it; the film is where a route is watched.
    ///
    /// Not interactive on purpose: a pan inside the diary moved the map instead
    /// of the page (2026-09-17 render).
    private var routeIllustration: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(Text("story_map_label"))
            legend
        }
    }

    /// Solid is a line someone knows, dashed is a line inferred between two
    /// photographs (PD-1). Said under the map, where the convention is first
    /// seen, so the same convention in the film needs no explaining.
    @ViewBuilder
    private var legend: some View {
        let hasInferred = model.storyDays.flatMap(\.entries).contains { $0.leg?.provenance == .inferred }
        HStack(spacing: 12) {
            legendSwatch(dashed: false, text: model.isReconstructed ? "leg_matched" : "leg_recorded")
            if hasInferred { legendSwatch(dashed: true, text: "leg_inferred") }
            if routeCoordinator.isRunning(model.tripId) {
                ProgressView().controlSize(.mini)
                Text("story_roads_arriving")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func legendSwatch(dashed: Bool, text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 18, y: 0))
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [3, 3] : []))
            .frame(width: 18, height: 2.5)
            Text(text)
        }
    }

    private func strokeStyle(for segment: SegmentRecord) -> StrokeStyle {
        RecapComposer.provenance(for: segment) == .inferred
            ? StrokeStyle(lineWidth: 3, dash: [4, 6])
            : StrokeStyle(lineWidth: 3.5)
    }

    // MARK: - Secondary

    /// Which subject the film draws — a trip property (schema v3). The plane is
    /// absent on purpose: the app picks it for a crossing.
    @ViewBuilder
    private var rideRow: some View {
        let subjects = model.pickableSubjects
        if subjects.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "story_ride")
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
                SectionLabel(text: "films_section_title")
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

    /// *Make this a Film*, at the foot of the diary. Off while stops are still
    /// being named (Chiu 2026-08-04: exporting early bakes "Unnamed stop" into
    /// the film), and the line beneath says why. A running export shows here
    /// too, because the export outlives the sheet (ADR 2026-09-10).
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

/// The quiet heading the diary's two footnote sections share.
private struct SectionLabel: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
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
                    .frame(width: 24, height: 24)
            }
            Text(subject.displayName(language: language)).font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground))
        .overlay(Capsule().stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
        .clipShape(Capsule())
    }
}

private struct FilmChip: View {
    let film: FilmRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: film.format == "gif" ? "photo.on.rectangle" : "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(timeIntervalSince1970: film.createdAt), style: .date).font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(film.format.uppercased())
                    if let bytes = film.fileBytes {
                        Text(verbatim: "·")
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
