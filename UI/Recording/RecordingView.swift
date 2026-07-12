import KamomeTrackingEngine
import MapKit
import SwiftUI

/// S2 Recording HUD (minimal Phase 1 cut): live map with traveled polyline,
/// mode icon, elapsed / distance / stops, End Trip. Live Activity is a
/// Phase 2 nice-to-have.
struct RecordingView: View {
    @Environment(TrackingSession.self) private var session
    @State private var now = Date.now

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
            HStack(spacing: 24) {
                Image(systemName: modeSymbol)
                    .font(.title2)
                stat(value: elapsedText, label: "stat_elapsed")
                stat(value: distanceText, label: "stat_distance")
                stat(value: "\(session.stopCount)", label: "stat_stops")
            }
            Button(role: .destructive) {
                session.end()
            } label: {
                Text("end_trip")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
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
