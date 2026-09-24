import KamomeTrackingEngine
import MapKit
import SwiftUI

/// S2 Recording HUD (minimal Phase 1 cut): live map with traveled polyline,
/// mode icon, elapsed / distance / stops, End Trip. Live Activity is a
/// Phase 2 nice-to-have.
struct RecordingView: View {
    @Environment(TrackingSession.self) private var session
    @State private var now = Date.now
    @State private var confirmingEnd = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var session = session
        return ZStack(alignment: .bottom) {
            map
            hud
        }
        .onReceive(clock) { now = $0 }
        .sheet(isPresented: $session.needsAlwaysPriming) {
            AlwaysPrimingView()
                .presentationDetents([.medium])
        }
    }

    private var map: some View {
        Map {
            if session.traveledPath.count >= 2 {
                MapPolyline(coordinates: session.traveledPath)
                    .stroke(.tint, lineWidth: 4)
            }
            if let head = session.traveledPath.last {
                Annotation("", coordinate: head) {
                    Image(systemName: "bird.fill") // the seagull head marker
                        .foregroundStyle(.tint)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
            }
        }
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }

    private var hud: some View {
        VStack(spacing: 12) {
            if let interruption = session.interruption {
                resumedNotice(interruption)
            }
            HStack(spacing: 24) {
                Image(systemName: modeSymbol)
                    .font(.title2)
                stat(value: elapsedText, label: "stat_elapsed")
                stat(value: distanceText, label: "stat_distance")
                stat(value: "\(session.stopCount)", label: "stat_stops")
            }
            // One tap used to end the trip. On a phone in a car mount that is
            // a brushed screen, and an ended recording cannot be continued —
            // so End Trip asks first (2026-09-24).
            Button(role: .destructive) {
                confirmingEnd = true
            } label: {
                Text("end_trip")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .confirmationDialog("end_trip_confirm_title", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("end_trip", role: .destructive) { session.end() }
                Button("end_trip_keep_recording", role: .cancel) {}
            } message: {
                Text("end_trip_confirm_message")
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    /// Said once after a recording was recovered: the app had been closed,
    /// recording carried on by itself, and this long has no track.
    private func resumedNotice(_ interruption: TrackingSession.Interruption) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.tint)
            Text(Self.resumedText(gapS: interruption.gapS))
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                session.interruption = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("recording_resumed_dismiss"))
        }
    }

    static func resumedText(gapS: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = [.day, .hour, .minute]
        // Under a minute still reads as a minute: "0 min" would claim no gap.
        let gap = formatter.string(from: max(gapS, 60)) ?? ""
        return String.localizedStringWithFormat(String(localized: "recording_resumed_notice"), gap)
    }

    private func stat(value: String, label: LocalizedStringKey) -> some View {
        VStack {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var modeSymbol: String {
        switch session.currentMode {
        case .drive: return "car.fill"
        case .scooter: return "scooter"
        case .walk: return "figure.walk"
        case .cycle: return "bicycle"
        case .transit: return "tram.fill"
        case .unknown: return "location.fill"
        }
    }

    private var elapsedText: String {
        // `now` ticks once a second to keep this fresh.
        _ = now
        let seconds = Int(session.elapsed)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    private var distanceText: String {
        String(format: "%.1f km", session.distanceM / 1000)
    }
}
