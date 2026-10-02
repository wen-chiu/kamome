import KamomePersistence
import KamomeTripComposer
import MapKit
import SwiftUI

/// Trip Detail's map, its overlays, the day chips and the stats strip. Split out
/// of `TripDetailView` (arch review 2026-09-26, round 2) when `UI/` came under
/// SwiftLint: the struct body was 340 lines against a 250-line rule. Moved as
/// written; only `private` is gone, which a separate file needs.
extension TripDetailView {
    var map: some View {
        Map {
            ForEach(model.visibleSegments, id: \.segment.id) { item in
                let coords = model.displayPolyline(for: item.segment)
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

    func stopPin(_ stop: StopRecord) -> some View {
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

    var dayChips: some View {
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
    func dayChipLabel(_ day: Int) -> String {
        guard let date = model.date(ofDay: day) else {
            return String.localizedStringWithFormat(String(localized: "day_chip"), day + 1)
        }
        return String.localizedStringWithFormat(
            String(localized: "day_chip_dated"), day + 1, date.formatted(.dateTime.month(.defaultDigits).day())
        )
    }

    func chip(label: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.2)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
    }

    /// Four figures in a row; two rows of two when a row does not fit. At the
    /// largest text sizes one row broke its labels inside words ("Dis-tanc-e")
    /// and cut its values ("72 k…", #191).
    func statsStrip(_ stats: TripStats) -> some View {
        let distance = stat(value: String(format: "%.0f km", stats.distanceM / 1000), label: "stat_distance")
        let driving = stat(value: hours(stats.driveS), label: "stat_drive_time")
        let stops = stat(value: "\(stats.stopCount)", label: "stat_stops")
        let topSpeed = stat(value: String(format: "%.0f km/h", stats.topSpeedKmh), label: "stat_top_speed")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                distance
                driving
                stops
                topSpeed
            }
            Grid(horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    distance
                    driving
                }
                GridRow {
                    stops
                    topSpeed
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    /// One line each, never wrapped: `ViewThatFits` measures the row at this
    /// width, and the two-by-two shrinks a label rather than break it.
    func stat(value: String, label: LocalizedStringKey) -> some View {
        VStack {
            Text(value).font(.subheadline.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// What floats on the map's bottom-right corner — bottom-right because
    /// Apple's Maps logo and Legal link hold the bottom-left, and they must stay
    /// visible. Both used to be full-width rows under the map (Chiu 2026-09-23:
    /// too much page for too little information).
    var mapOverlays: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if model.isSample { sampleChip } else if model.isReconstructed { provenanceChip }
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
    var provenanceChip: some View {
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

    /// The sample says what it is, in the place a real trip says how it was
    /// made — never "rebuilt from your photos" (ADR 2026-09-28-sample-trip).
    var sampleChip: some View {
        Button {
            showingProvenance = true
        } label: {
            Label("sample_badge", systemImage: "sparkles")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.thinMaterial))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingProvenance) {
            Text("sample_note")
                .font(.footnote)
                .padding()
                .frame(idealWidth: 280)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }

    func hours(_ seconds: Double) -> String {
        String(format: "%.1f h", seconds / 3600)
    }

    func color(for mode: String) -> Color {
        switch mode {
        case "drive", "scooter": return .accentColor
        case "walk": return .green
        case "cycle": return .mint
        case "transit": return .purple
        default: return .gray
        }
    }

    func strokeStyle(for mode: String) -> StrokeStyle {
        // Drive = solid, on-foot = dotted (§5 S3).
        mode == "walk" || mode == "cycle"
            ? StrokeStyle(lineWidth: 3, dash: [4, 6])
            : StrokeStyle(lineWidth: 4)
    }
}
