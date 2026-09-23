import KamomeExportEngine
import KamomePersistence
import SwiftUI

/// The trip's latest film as a poster floating on the map (Chiu 2026-09-23).
/// It replaced a full-width row that spent its space on format and file size,
/// which nobody decides anything by; what is left is the frame, a play mark and
/// the running time. Format, date and size moved to the player sheet.
///
/// With more than one film the badge counts them, and the caller opens the list
/// instead of the player.
struct FilmPosterButton: View {
    let latest: FilmRecord
    let count: Int
    let action: () -> Void

    @State private var poster: UIImage?

    var body: some View {
        Button(action: action) {
            ZStack {
                if let poster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.thinMaterial)
                }
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                if let duration = latest.durationS {
                    Text(Duration.seconds(duration), format: .time(pattern: .minuteSecond))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 4)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text("\(count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: 6, y: -6)
                }
            }
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("film_poster_play"))
        .task(id: latest.id) { poster = await Self.firstFrame(of: latest) }
    }

    /// The film's first frame. Nil for a GIF (only MP4 is read back) or a
    /// missing file, which leaves the material placeholder — the play mark
    /// still says what the button does.
    private static func firstFrame(of film: FilmRecord) async -> UIImage? {
        guard film.format == "mp4",
              let url = FilmStore.resolvedURL(relativePath: film.relativePath),
              // Poster-sized; decoding a full 1080×1920 frame for a 64 pt tile is waste.
              let frame = await RecapVideoEncoder.firstFrame(of: url, maxSidePx: 256) else { return nil }
        return UIImage(cgImage: frame)
    }
}
