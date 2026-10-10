import CoreGraphics
import Foundation
import KamomeConfig

/// §4.5 steps 2+5 wired together: one render pass feeds the H.264 encoder.
/// Cancellation (user backs out of S5) stops the loop at the next frame and
/// leaves the partial file for the caller to clean up.
///
/// **MP4 only** (Chiu 2026-10-10, ADR file 2026-10-10): the GIF encoder is gone.
/// ImageIO built the whole GIF in `CGImageDestinationFinalize`, measured at
/// +2.6 GB for a 40 s film — a render the phone would kill after the user had
/// waited for all of it.
public struct RecapExporter {
    public struct Output {
        public let videoURL: URL
        /// What the pass cost, stage by stage. `deliverS` is this pipeline's
        /// encoding — the encoder is fed from the loop's deliver closure — and
        /// `finishS` is the writer's final flush, which happens after the last
        /// frame and is therefore outside it.
        public let stats: RecapRenderLoop.RenderStats
        public let finishS: Double

        public init(videoURL: URL, stats: RecapRenderLoop.RenderStats = RecapRenderLoop.RenderStats(), finishS: Double = 0) {
            self.videoURL = videoURL
            self.stats = stats
            self.finishS = finishS
        }
    }

    private let timeline: LinearTimeline
    private let compositor: FrameCompositor
    private let provider: MapRenderer
    private let config: TrackingConfig.Export

    public init(
        timeline: LinearTimeline,
        compositor: FrameCompositor,
        provider: MapRenderer,
        config: TrackingConfig.Export
    ) {
        self.timeline = timeline
        self.compositor = compositor
        self.provider = provider
        self.config = config
    }

    /// Renders the recap into `videoURL` (H.264 MP4). `progress` gets 0…1 per
    /// frame; return false from `shouldContinue` to cancel. Returns nil if
    /// cancelled.
    public func export(
        videoURL: URL,
        progress: ((Double) -> Void)? = nil,
        shouldContinue: @escaping () -> Bool = { true }
    ) async throws -> Output? {
        let video = try RecapVideoEncoder(
            outputURL: videoURL,
            widthPx: config.frameWidthPx,
            heightPx: config.frameHeightPx,
            fps: config.fps,
            bitrateMbps: config.videoBitrateMbps
        )
        var cancelled = false
        let loop = RecapRenderLoop(timeline: timeline, compositor: compositor, provider: provider, config: config)
        let stats: RecapRenderLoop.RenderStats
        do {
            stats = try await loop.renderFrames { frame, image in
                guard shouldContinue() else {
                    cancelled = true
                    return false
                }
                try video.append(image, frame: frame)
                progress?(Double(frame + 1) / Double(timeline.frameCount))
                return true
            }
        } catch {
            // Let the writer go on purpose; the caller deletes the partial file.
            video.cancel()
            throw error
        }
        guard !cancelled else {
            video.cancel()
            return nil
        }

        let finishStarted = ContinuousClock.now
        try await video.finish()
        let elapsed = ContinuousClock.now - finishStarted
        return Output(
            videoURL: videoURL, stats: stats,
            finishS: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        )
    }
}
