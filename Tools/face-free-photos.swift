#!/usr/bin/env swift
import Foundation
import Vision

// Copies the photos of a trip folder that show no face into a second folder, so a
// real trip can be rendered into a promo film without showing anyone.
//
//   ./Tools/face-free-photos.swift ~/Pictures/trip ~/Kamome-promo/footage/trip-photos
//   ./Tools/face-free-photos.swift <in> <out> --faces-only   # keep photos of people
//                                                         # whose face is not seen
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
// tune, because a missed face is the failure that matters here.
//
// Vision looks at a downscaled image, so a person who fills a small part of the
// frame goes unseen: VERIFIED 2026-11-03, a standing person with a visible face
// and a passer-by were both missed on the whole frame and both found once
// cropped. So each photo is scanned whole and again as a 3 × 3 grid of
// half-size tiles that overlap by half, and any detected person drops it too:
// the face detector missed that small face even tiled, and the person detector
// found it. Vision still misses some, so look at the kept photos before
// publishing anything. Files are copied with
// their EXIF intact, which exif-to-fixture.sh needs; strip it from anything
// published on its own.

let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let people = !CommandLine.arguments.contains("--faces-only")
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: face-free-photos.swift <in-folder> <out-folder> [--faces-only]\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: args[args.startIndex])
let output = URL(fileURLWithPath: args[args.startIndex + 1])
let fm = FileManager.default
try fm.createDirectory(at: output, withIntermediateDirectories: true)

let photos = try fm.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
    .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

// The whole image, then half-size tiles at 0, ¼ and ½ of each side (normalized).
let regions = [CGRect(x: 0, y: 0, width: 1, height: 1)]
    + [0.0, 0.25, 0.5].flatMap { x in [0.0, 0.25, 0.5].map { y in CGRect(x: x, y: y, width: 0.5, height: 0.5) } }

enum Finding { case face, person }

func scan(_ photo: URL) throws -> Finding? {
    let handler = VNImageRequestHandler(url: photo)
    for region in regions {
        let faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.regionOfInterest = region
        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.upperBodyOnly = false
        humanRequest.regionOfInterest = region
        try handler.perform(people ? [faceRequest, humanRequest] : [faceRequest])
        if !(faceRequest.results ?? []).isEmpty { return .face }
        if people, !(humanRequest.results ?? []).isEmpty { return .person }
    }
    return nil
}

var kept = 0, faces = 0, persons = 0, unreadable = 0
for photo in photos {
    let finding: Finding?
    do {
        finding = try scan(photo)
    } catch {
        unreadable += 1
        print("skip (unreadable)  \(photo.lastPathComponent)")
        continue
    }
    switch finding {
    case .face:
        faces += 1
        print("drop (face)        \(photo.lastPathComponent)")
        continue
    case .person:
        persons += 1
        print("drop (person)      \(photo.lastPathComponent)")
        continue
    case nil: break
    }
    let target = output.appendingPathComponent(photo.lastPathComponent)
    if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: photo, to: target) }
    kept += 1
}
print("\nkept \(kept) of \(photos.count) · face \(faces) · person \(persons) · unreadable \(unreadable)")
print("→ \(output.path)")
