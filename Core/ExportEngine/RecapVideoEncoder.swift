import AVFoundation
import CoreGraphics
import Foundation

/// §4.5 step 5: H.264 MP4 encoding via AVAssetWriter. Frames arrive in order
/// from `RecapRenderLoop`; presentation time is the frame index over fps, so
/// the file's duration equals `export.target_duration_s` exactly.
public final class RecapVideoEncoder {
    public struct EncodeError: Error, CustomStringConvertible {
        public let description: String
    }

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let widthPx: Int
    private let heightPx: Int
    private let fps: Int

    public init(outputURL: URL, widthPx: Int, heightPx: Int, fps: Int) throws {
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: widthPx,
                AVVideoHeightKey: heightPx
            ]
        )
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: widthPx,
                kCVPixelBufferHeightKey as String: heightPx
            ]
        )
        writer.add(input)
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.fps = fps
        guard writer.startWriting() else {
            throw EncodeError(description: "AVAssetWriter refused to start: \(String(describing: writer.error))")
        }
        writer.startSession(atSourceTime: .zero)
    }

    public func append(_ image: CGImage, frame: Int) throws {
        // Offline encode: the writer occasionally needs a beat to drain.
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard let pool = adaptor.pixelBufferPool else {
            throw EncodeError(description: "pixel buffer pool unavailable: \(String(describing: writer.error))")
        }
        var maybeBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
        guard let buffer = maybeBuffer else {
            throw EncodeError(description: "could not create pixel buffer for frame \(frame)")
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: CVPixelBufferGetBaseAddress(buffer),
                  width: widthPx,
                  height: heightPx,
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
              )
        else {
            throw EncodeError(description: "could not wrap pixel buffer for frame \(frame)")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: widthPx, height: heightPx))

        let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw EncodeError(description: "append failed at frame \(frame): \(String(describing: writer.error))")
        }
    }

    public func finish() async throws {
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw EncodeError(description: "finishWriting failed: \(String(describing: writer.error))")
        }
    }
}
