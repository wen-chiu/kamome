#!/usr/bin/env swift
import Foundation
import Vision

// Copies the photos of a trip folder that show no face into a second folder, so a
// real trip can be rendered into a promo film without showing anyone.
//
//   ./Tools/face-free-photos.swift ~/Pictures/trip ~/Kamome-promo/footage/trip-photos
//   ./Tools/face-free-photos.swift <in> <out> --people   # also drop any visible person
//
// Then build the fixture from the OUTPUT folder, so every stop is made only from
// photos that survived, and render with that folder as KAMOME_STOP_PHOTOS:
//
//   ./Tools/exif-to-fixture.sh ~/Kamome-promo/footage/trip-photos trip-promo
//
// Filtering the photo folder alone is not enough: the review harness deals an
// unmatched photo id from the remaining files, which would put one stop's photo
// on another stop.
//
// Detection is Apple Vision on this Mac; no image leaves it. Any detected face
// excludes the photo, however small. There is no size or confidence threshold to
// tune, because a missed face is the failure that matters here. Vision misses
// faces in profile, in shadow or far away, so look at the kept photos before
// publishing anything: `--people` is the stricter pass. Files are copied with
// their EXIF intact, which exif-to-fixture.sh needs; strip it from anything
// published on its own.

let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let people = CommandLine.arguments.contains("--people")
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: face-free-photos.swift <in-folder> <out-folder> [--people]\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: args[args.startIndex])
let output = URL(fileURLWithPath: args[args.startIndex + 1])
let fm = FileManager.default
try fm.createDirectory(at: output, withIntermediateDirectories: true)

let photos = try fm.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
    .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

var kept = 0, faces = 0, persons = 0, unreadable = 0
for photo in photos {
    let faceRequest = VNDetectFaceRectanglesRequest()
    let humanRequest = VNDetectHumanRectanglesRequest()
    humanRequest.upperBodyOnly = false
    let requests: [VNRequest] = people ? [faceRequest, humanRequest] : [faceRequest]
    do {
        try VNImageRequestHandler(url: photo).perform(requests)
    } catch {
        unreadable += 1
        print("skip (unreadable)  \(photo.lastPathComponent)")
        continue
    }
    if !(faceRequest.results ?? []).isEmpty {
        faces += 1
        print("drop (face)        \(photo.lastPathComponent)")
        continue
    }
    if people, !(humanRequest.results ?? []).isEmpty {
        persons += 1
        print("drop (person)      \(photo.lastPathComponent)")
        continue
    }
    let target = output.appendingPathComponent(photo.lastPathComponent)
    if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: photo, to: target) }
    kept += 1
}
print("\nkept \(kept) of \(photos.count) · face \(faces) · person \(persons) · unreadable \(unreadable)")
print("→ \(output.path)")
