import CoreGraphics
import Foundation
import ImageIO
import KamomeConfig
import UniformTypeIdentifiers

/// §4.5 step 5: GIF export. Takes the same frame stream as the MP4 encoder,
/// keeps every Nth frame (nearest integer stride to `export.gif_fps`), scales
/// to `export.gif_width_px`, and lets ImageIO handle palette quantization.
/// Per-frame delay comes from the stride, so the GIF plays in real time even
/// when the integer stride can't hit gif_fps exactly.
public final class RecapGIFEncoder {
    public struct EncodeError: Error, CustomStringConvertible {
        public let description: String
    }

    private let destination: CGImageDestination
    private let frameStride: Int
    private let delayS: Double
    private let widthPx: Int
    private let heightPx: Int

    /// `sourceFrameCount` must be the exact number of frames that will be
    /// offered — CGImageDestination wants its image count up front.
    public init(outputURL: URL, config: TrackingConfig.Export, sourceFrameCount: Int) throws {
        frameStride = max(1, config.fps / config.gifFps)
        delayS = Double(frameStride) / Double(config.fps)
        widthPx = min(config.gifWidthPx, config.frameWidthPx)
        heightPx = Int(
            (Double(config.frameHeightPx) * Double(widthPx) / Double(config.frameWidthPx)).rounded()
        )
        let gifFrameCount = (sourceFrameCount + frameStride - 1) / frameStride
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.gif.identifier as CFString, gifFrameCount, nil
        ) else {
            throw EncodeError(description: "could not open GIF destination at \(outputURL.path)")
        }
        self.destination = destination
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
    }

    /// Offer every rendered frame; the encoder keeps the ones on its stride.
    public func append(_ image: CGImage, frame: Int) throws {
        guard frame % frameStride == 0 else { return }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: widthPx,
                  height: heightPx,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw EncodeError(description: "could not create scale context for frame \(frame)")
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: widthPx, height: heightPx))
        guard let scaled = context.makeImage() else {
            throw EncodeError(description: "could not scale frame \(frame)")
        }
        let properties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delayS,
                kCGImagePropertyGIFUnclampedDelayTime: delayS
            ]
        ] as CFDictionary
        CGImageDestinationAddImage(destination, scaled, properties)
    }

    public func finish() throws {
        guard CGImageDestinationFinalize(destination) else {
            throw EncodeError(description: "GIF finalize failed")
        }
    }
}
