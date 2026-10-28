import SwiftUI

/// The Journey Discovery beta's states that are not a list of journeys: before
/// access, while looking, when refused, when nothing was found, and the
/// Selected Photos reminder. Each is a conversation, not an alert
/// (`DESIGNER.md` rule 5).
///
/// None of them offers import: adding a journey the library cannot see is the
/// home screen's job, and this beta deliberately does not duplicate it.

/// First launch: what Kamome does, and one button that lets it. Shown twice:
/// in 足跡 before access is asked, and as 旅程's empty state, where its button
/// opens 足跡 and asks there (#290, ADR 2026-10-26-home-shows-a-newcomer-the-next-step).
struct WelcomeCard: View {
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            KamomeGull(size: 56)
            VStack(alignment: .leading, spacing: 8) {
                Text("welcome_title")
                    .font(.title.weight(.bold))
                Text("welcome_body")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Button(action: action) {
                HStack {
                    if isWorking { ProgressView().tint(.white) }
                    Text("welcome_find")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.prominent)
            .controlSize(.large)
            .disabled(isWorking)
            // Secondary, not tertiary (#295 item 4): it was the faintest text
            // in the app, on the screen where the privacy promise is made.
            Text("welcome_privacy")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A quiet line while the library is read. No spinner in the title bar, no
/// modal: the journeys already known stay on screen underneath it.
struct ScanningRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("scanning_photos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Access was refused. Recoverable in Settings; the manual import still works
/// for anything already shared in.
struct AccessDeniedCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KamomeGull(size: 44)
            Text("access_denied_title")
                .font(.title3.weight(.semibold))
            Text("access_denied_body")
                .font(.body)
                .foregroundStyle(.secondary)
            if let settings = URL(string: UIApplication.openSettingsURLString) {
                Link("access_denied_settings", destination: settings)
                    .font(.headline)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// The scan found nothing — usually a library with no geotagged photographs
/// away from home. Says what it looked for, and offers the manual path.
struct NothingFoundCard: View {
    let access: PhotoReadAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KamomeGull(size: 44)
            Text("nothing_found_title")
                .font(.title3.weight(.semibold))
            Text(access == .limited ? "nothing_found_limited" : "nothing_found_body")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Selected Photos: the library Kamome sees is a subset, and the way to grow it
/// is the system picker (a Replay MVP gate item).
struct LimitedLibraryRow: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Text("limited_photos_notice")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("limited_photos_manage", action: action)
                .font(.footnote.weight(.semibold))
                // In Footprints' list a default-style button takes the whole row's tap.
                .buttonStyle(.borderless)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// **The gull of the app icon and of the export's wait** (#295 item 3): the
/// brand's double arc (`GullPose`), in `BrandTeal`. It was SF Symbols' `bird`,
/// a songbird. `size` is its wingspan in points.
///
/// **It beats its wings once as its card appears, then rests** (Chiu
/// 2026-10-27): the wait's own wingbeat, one `GullPose.beatS`, ending on the
/// brand pose. Standing still, the double arc reads as the letter "m"; one
/// beat says it is a bird. With Reduce Motion it never moves. The flap is
/// drawn past the resting frame, so the card's layout does not move with it.
///
/// Not `VehicleMarker.seagull`: that one is the film's and the wordmark's,
/// drawn into a `CGContext` by `ExportEngine`, and is never restyled in place
/// (`HANDOFF.md`). The recording HUD's head marker is still SF Symbols'
/// `bird.fill` — a marker on a map, not this illustration.
struct KamomeGull: View {
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 → 1 over one beat; both ends are the brand pose.
    @State private var phase = 0.0

    var body: some View {
        let height = size * GullPose.restingBox.height / GullPose.restingBox.width
        GullStroke(phase: phase)
            .stroke(
                Color(.brandTeal),
                style: StrokeStyle(
                    lineWidth: GullPose.strokeWidth(
                        in: CGSize(width: size, height: height), fitting: GullPose.restingBox
                    ),
                    lineCap: .round, lineJoin: .round
                )
            )
            .frame(width: size, height: height)
            .accessibilityHidden(true)
            .onAppear {
                phase = 0
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: GullPose.beatS)) { phase = 1 }
            }
    }
}

/// The gull at one phase of its beat; SwiftUI animates the phase, and the
/// path is the wait's own pose at each frame.
private struct GullStroke: Shape {
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(GullPose.path(phase: phase, in: rect, fitting: GullPose.restingBox))
    }
}
