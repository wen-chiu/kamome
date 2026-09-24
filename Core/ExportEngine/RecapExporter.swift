import CoreGraphics
import Foundation
import KamomeConfig

/// §4.5 steps 2+5 wired together: one render pass feeds both encoders, so S5
/// never renders the trip twice. Cancellation (user backs out of S5) stops
/// the loop at the next frame and leaves partial files for the caller to
/// clean up.
public struct RecapExporter {
    public struct Output {
        /// nil for a GIF-only export (`exportGIF`), which writes no MP4 at all.
        public let videoURL: URL?
        public let gifURL: URL?
        /// What the pass cost, stage by stage. `deliverS` is this pipeline's
        /// encoding — both encoders are fed from the loop's deliver closure — and
        /// `finishS` is the writer's final flush, which happens after the last
        /// frame and is therefore outside it.
        public let stats: RecapRenderLoop.RenderStats
        public let finishS: Double

        public init(
            videoURL: URL?, gifURL: URL?,
            stats: RecapRenderLoop.RenderStats = RecapRenderLoop.RenderStats(), finishS: Double = 0
        ) {
            self.videoURL = videoURL
            self.gifURL = gifURL
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

    /// Renders the recap into `videoURL` (H.264 MP4) and, when given, `gifURL`.
    /// `progress` gets 0…1 per frame; return false from `shouldContinue` to
    /// cancel. Returns nil if cancelled.
    public func export(
        videoURL: URL,
        gifURL: URL? = nil,
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
        let gif = try gifURL.map {
            try RecapGIFEncoder(outputURL: $0, config: config, sourceFrameCount: timeline.frameCount)
        }
        return try await run(
            video: video, gif: gif, videoURL: videoURL, gifURL: gifURL,
            progress: progress, shouldContinue: shouldContinue
        )
    }

    /// Renders the recap into `gifURL` alone — **only the frames the GIF keeps**.
    ///
    /// A GIF keeps one frame in `fps / gif_fps` (`RecapGIFEncoder.keeps`), and
    /// the S5 GIF export used to composite and H.264-encode every frame of the
    /// film, then delete the MP4 (`Docs/handoff-export-performance.md` §7). The
    /// frames it keeps come from the same station plan a full render uses
    /// (`RecapRenderLoop.renderFrames(only:)`), so the GIF is the same file the
    /// two-encoder pass wrote. `progress` reaches 1 on completion even though the
    /// last kept frame may not be the film's last.
    public func exportGIF(
        gifURL: URL,
        progress: ((Double) -> Void)? = nil,
        shouldContinue: @escaping () -> Bool = { true }
    ) async throws -> Output? {
        let gif = try RecapGIFEncoder(outputURL: gifURL, config: config, sourceFrameCount: timeline.frameCount)
        let output = try await run(
            video: nil, gif: gif, videoURL: nil, gifURL: gifURL,
            progress: progress, shouldContinue: shouldContinue
        )
        if output != nil { progress?(1) }
        return output
    }

    private func run(
        video: RecapVideoEncoder?, gif: RecapGIFEncoder?, videoURL: URL?, gifURL: URL?,
        progress: ((Double) -> Void)?, shouldContinue: @escaping () -> Bool
    ) async throws -> Output? {
        var cancelled = false
        let loop = RecapRenderLoop(timeline: timeline, compositor: compositor, provider: provider, config: config)
        // With an MP4 every frame is used; without one, only the GIF's.
        let wanted: (Int) -> Bool = video != nil ? { _ in true } : { gif?.keeps(frame: $0) ?? false }
        let stats = try await loop.renderFrames(only: wanted) { frame, image in
            guard shouldContinue() else {
                cancelled = true
                return false
            }
            try video?.append(image, frame: frame)
            try gif?.append(image, frame: frame)
            progress?(Double(frame + 1) / Double(timeline.frameCount))
            return true
        }
        guard !cancelled else { return nil }

        let finishStarted = ContinuousClock.now
        try await video?.finish()
        try gif?.finish()
        let elapsed = ContinuousClock.now - finishStarted
        return Output(
            videoURL: videoURL, gifURL: gifURL, stats: stats,
            finishS: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        )
    }
}
