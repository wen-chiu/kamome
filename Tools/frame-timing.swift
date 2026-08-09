#!/usr/bin/env swift
import AVFoundation
import CoreImage
import Foundation

// Measures what a rendered recap actually contains, so "it stutters" can be
// answered from the file instead of from whatever played it back.
//
//   ./Tools/frame-timing.swift ~/Downloads/kamome-recap.mp4
//
// Three different faults look identical when you watch a video on a phone, and
// they have nothing to do with each other:
//
//   1. Irregular presentation timestamps — the encoder wrote uneven frame times.
//      Reported as "PTS gaps".
//   2. Repeated pictures — timing is perfect but the renderer produced the same
//      image several frames running, so motion moves in steps. Reported as
//      "repeated frames" and "longest freeze". This is what a map that only
//      re-snapshots every `keyframe_interval_frames` looks like.
//   3. Neither — the file is clean and the stutter was playback: AirDrop into
//      Photos re-encodes nothing, but QuickLook previews, Files' inline player
//      and a Mac still decoding a 1080×1920 portrait H.264 can all drop frames.
//
// Reads the file only; nothing is written and nothing leaves the machine.

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: frame-timing.swift <video> [sample-stride]\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: arguments[1])
/// Decoding every frame of a 90 s film to hash it is slow; 1 = exhaustive.
let stride = Int(arguments.count > 2 ? arguments[2] : "1") ?? 1

let asset = AVURLAsset(url: url)
guard let track = try await asset.loadTracks(withMediaType: .video).first else {
    FileHandle.standardError.write(Data("no video track in \(url.lastPathComponent)\n".utf8))
    exit(1)
}
let nominalFPS = try await track.load(.nominalFrameRate)
let duration = try await asset.load(.duration).seconds
let size = try await track.load(.naturalSize)

let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(
    track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
)
output.alwaysCopiesSampleData = false
reader.add(output)
reader.startReading()

var timestamps: [Double] = []
var hashes: [Int] = []
var index = 0
while let sample = output.copyNextSampleBuffer() {
    timestamps.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
    if index % stride == 0, let pixels = CMSampleBufferGetImageBuffer(sample) {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        // A coarse content fingerprint: sparse samples across the frame. Enough
        // to tell "same picture again" from "the picture moved a little".
        var hasher = Hasher()
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
            let height = CVPixelBufferGetHeight(pixels)
            let width = CVPixelBufferGetWidth(pixels)
            for row in Swift.stride(from: 0, to: height, by: 16) {
                for column in Swift.stride(from: 0, to: width * 4, by: 64) {
                    hasher.combine(bytes[row * rowBytes + column])
                }
            }
        }
        hashes.append(hasher.finalize())
    }
    index += 1
}

guard timestamps.count > 1 else {
    FileHandle.standardError.write(Data("only \(timestamps.count) frames decoded\n".utf8))
    exit(1)
}

let deltas = zip(timestamps.dropFirst(), timestamps).map(-)
let expected = 1.0 / Double(nominalFPS)
let irregular = deltas.enumerated().filter { abs($0.element - expected) > expected * 0.5 }

var repeated = 0
var longestFreeze = 1
var currentFreeze = 1
for (previous, next) in zip(hashes, hashes.dropFirst()) {
    if previous == next {
        repeated += 1
        currentFreeze += 1
        longestFreeze = max(longestFreeze, currentFreeze)
    } else {
        currentFreeze = 1
    }
}

print("""
\(url.lastPathComponent)
  \(Int(size.width))×\(Int(size.height)) · \(String(format: "%.2f", nominalFPS)) fps nominal · \
\(String(format: "%.2f", duration))s · \(timestamps.count) frames
  measured fps      \(String(format: "%.3f", Double(timestamps.count - 1) / (timestamps.last! - timestamps.first!)))
  PTS gaps          \(irregular.count) frame intervals off nominal by >50%
  repeated frames   \(repeated)/\(max(hashes.count - 1, 1)) sampled\(stride > 1 ? " (stride \(stride))" : "")
  longest freeze    \(longestFreeze) identical frames in a row \
(\(String(format: "%.2f", Double(longestFreeze) * expected))s)
""")

if let worst = irregular.max(by: { $0.element < $1.element }) {
    print("  worst gap         \(String(format: "%.3f", worst.element))s at frame \(worst.offset + 1)")
}

// The verdict, so the number does not have to be interpreted.
if irregular.isEmpty && longestFreeze <= 2 {
    print("\n  → The file is clean: even timing, no held pictures. Stutter was playback.")
} else if !irregular.isEmpty {
    print("\n  → Uneven presentation timestamps: the encoder wrote a bad timeline.")
} else {
    print("""

      → Timing is even but pictures repeat for up to \(longestFreeze) frames. Motion will read as \
    stepping. Suspect the render, not the player — a static camera legitimately repeats the *map*, \
    so check whether the car and trail are moving in those frames too.
    """)
}
