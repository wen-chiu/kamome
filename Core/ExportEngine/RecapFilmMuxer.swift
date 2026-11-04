import AVFoundation
import Foundation

/// **Picture + soundtrack → film** (`Docs/handoff-music-in-the-film.md` §3.2).
///
/// The video track is copied, never re-encoded: an `AVMutableComposition` of the
/// video and the audio, exported with `AVAssetExportPresetPassthrough` to `.mp4`.
/// So putting music on a film, or changing it, costs the copy — seconds — and
/// never the minutes of drawing the map again.
///
/// **Changing the music reuses this file** (§3.2): the video is taken out of the
/// stored `film.mp4` instead of the silent master, and whatever audio that film
/// had is left behind. No silent master is kept, so storage does not double.
/// One of the three files allowed AVFoundation (`Config/architecture.json`).
public enum RecapFilmMuxer {
    public struct MuxError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Writes `outputURL` from the video track of `videoURL` and, when given,
    /// the audio of `soundtrackURL`, trimmed to the picture. With no soundtrack
    /// the film comes out silent — 無音樂. `outputURL` must not be `videoURL`:
    /// the export reads one while it writes the other.
    public static func mux(videoFrom videoURL: URL, soundtrack soundtrackURL: URL?, to outputURL: URL) async throws {
        guard videoURL.standardizedFileURL != outputURL.standardizedFileURL else {
            throw MuxError(description: "the film cannot be written over the file its picture is read from")
        }
        let composition = AVMutableComposition()
        let video = try await insertVideo(of: AVURLAsset(url: videoURL), into: composition)
        if let soundtrackURL {
            try await insertAudio(of: AVURLAsset(url: soundtrackURL), into: composition, length: video.duration)
        }
        try? FileManager.default.removeItem(at: outputURL)
        try await export(composition, to: outputURL)
    }

    /// The same mux, named for what the player's 「換音樂」 does with it: keep
    /// the film's picture, replace its music.
    public static func replaceMusic(in filmURL: URL, with soundtrackURL: URL?, to outputURL: URL) async throws {
        try await mux(videoFrom: filmURL, soundtrack: soundtrackURL, to: outputURL)
    }

    private static func insertVideo(of asset: AVURLAsset, into composition: AVMutableComposition) async throws -> CMTimeRange {
        guard let source = try await asset.loadTracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MuxError(description: "\(asset.url.lastPathComponent) has no video track") }
        let range = try await source.load(.timeRange)
        try track.insertTimeRange(range, of: source, at: .zero)
        track.preferredTransform = try await source.load(.preferredTransform)
        return CMTimeRange(start: .zero, duration: range.duration)
    }

    private static func insertAudio(
        of asset: AVURLAsset, into composition: AVMutableComposition, length: CMTime
    ) async throws {
        guard let source = try await asset.loadTracks(withMediaType: .audio).first,
              let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MuxError(description: "\(asset.url.lastPathComponent) has no audio track") }
        let range = try await source.load(.timeRange)
        try track.insertTimeRange(
            CMTimeRange(start: range.start, duration: CMTimeMinimum(range.duration, length)), of: source, at: .zero
        )
    }

    private static func export(_ composition: AVMutableComposition, to outputURL: URL) async throws {
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw MuxError(description: "passthrough export is not available for this composition")
        }
        if #available(iOS 18, macOS 15, *) {
            try await session.export(to: outputURL, as: .mp4)
            return
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        await session.export()
        guard session.status == .completed else {
            let why = String(describing: session.error)
            throw MuxError(description: "passthrough export ended \(session.status.rawValue): \(why)")
        }
    }
}
