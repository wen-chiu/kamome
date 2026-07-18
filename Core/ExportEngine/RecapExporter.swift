import CoreGraphics
import Foundation
import KamomeConfig

/// §4.5 steps 2+5 wired together: one render pass feeds both encoders, so S5
/// never renders the trip twice. Cancellation (user backs out of S5) stops
/// the loop at the next frame and leaves partial files for the caller to
/// clean up.
public struct RecapExporter {
    public struct Output {
        public let videoURL: URL
        public let gifURL: URL?
    }

    private let path: CameraPath
    private let compositor: RecapFrameCompositor
    private let provider: RecapSnapshotProviding
    private let config: TrackingConfig.Export

    public init(
        path: CameraPath,
        compositor: RecapFrameCompositor,
        provider: RecapSnapshotProviding,
        config: TrackingConfig.Export
    ) {
        self.path = path
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
            fps: config.fps
        )
        let gif = try gifURL.map {
            try RecapGIFEncoder(outputURL: $0, config: config, sourceFrameCount: path.frameCount)
        }

        var cancelled = false
        let loop = RecapRenderLoop(path: path, compositor: compositor, provider: provider, config: config)
        try await loop.renderFrames { frame, image in
            guard shouldContinue() else {
                cancelled = true
                return false
            }
            try video.append(image, frame: frame)
            try gif?.append(image, frame: frame)
            progress?(Double(frame + 1) / Double(path.frameCount))
            return true
        }
        guard !cancelled else { return nil }

        try await video.finish()
        try gif?.finish()
        return Output(videoURL: videoURL, gifURL: gifURL)
    }
}
