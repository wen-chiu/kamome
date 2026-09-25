import ImageIO
import KamomeConfig
import SwiftUI
import UIKit

/// Plays a finished GIF film inline, frame by frame.
///
/// **Streamed, never decoded whole.** A film GIF is `export.gif_width_px` wide
/// at `export.gif_fps` for the length of the film — hundreds of frames, each
/// over a megabyte decoded — so `UIImage.animatedImage` (every frame in memory
/// at once) is the wrong tool. `CGAnimateImageAtURLWithBlock` decodes one frame
/// at a time, honours the file's own delays and loop count, and calls back on
/// the main queue.
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        // The frame comes from SwiftUI's aspect ratio, never from the image.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.start(url: url, in: view)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {}

    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the animation's lifetime: ImageIO keeps calling back until told to
    /// stop, and the only place to tell it is inside its own block.
    @MainActor
    final class Coordinator {
        private var isStopped = false

        func start(url: URL, in view: UIImageView) {
            let status = CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak self, weak view] _, image, stop in
                MainActor.assumeIsolated {
                    guard let self, !self.isStopped, let view else {
                        stop.pointee = true
                        return
                    }
                    view.image = UIImage(cgImage: image)
                }
            }
            if status != noErr {
                KamomeLog.recap.error("GIF preview could not start: status \(status, privacy: .public)")
            }
        }

        func stop() { isStopped = true }
    }
}
