import SwiftUI

/// The Journey Discovery beta's states that are not a list of journeys: before
/// access, while looking, when refused, when nothing was found, and the
/// Selected Photos reminder. Each is a conversation, not an alert
/// (`DESIGNER.md` rule 5).
///
/// None of them offers import: adding a journey the library cannot see is the
/// home screen's job, and this beta deliberately does not duplicate it.

/// First launch: what Kamome does, and one button that lets it.
struct WelcomeCard: View {
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            KamomeGull(size: 44)
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)
            Text("welcome_privacy")
                .font(.footnote)
                .foregroundStyle(.tertiary)
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
            KamomeGull(size: 36)
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
            KamomeGull(size: 36)
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
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The gull, in the accent colour. SF Symbols' bird — the same glyph the
/// recording HUD already uses for the head marker, so the app has one bird.
struct KamomeGull: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "bird")
            .font(.system(size: size, weight: .light))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}
