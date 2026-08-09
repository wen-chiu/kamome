import Foundation

/// A lat/lon box. Used to ask "do these tiles cover this trip?" — the only
/// question the recap's tile lookup needs to answer.
struct GeoBox: Equatable {
    let minLat: Double
    let minLon: Double
    let maxLat: Double
    let maxLon: Double

    /// Area in squared degrees. Not a real area — it never needs to be. It only
    /// ranks candidate regions so the tightest one wins, and every candidate is
    /// compared at the same latitude, so the cos(lat) term would cancel.
    var degreeArea: Double { (maxLat - minLat) * (maxLon - minLon) }

    func contains(_ other: GeoBox) -> Bool {
        other.minLat >= minLat && other.maxLat <= maxLat
            && other.minLon >= minLon && other.maxLon <= maxLon
    }

    /// The box enclosing `coordinates`, or nil for an empty list.
    static func enclosing(_ coordinates: [(lat: Double, lon: Double)]) -> GeoBox? {
        guard let first = coordinates.first else { return nil }
        var box = GeoBox(minLat: first.lat, minLon: first.lon, maxLat: first.lat, maxLon: first.lon)
        for point in coordinates.dropFirst() {
            box = GeoBox(
                minLat: min(box.minLat, point.lat), minLon: min(box.minLon, point.lon),
                maxLat: max(box.maxLat, point.lat), maxLon: max(box.maxLon, point.lon)
            )
        }
        return box
    }
}

/// Reads a `.pmtiles` file's own header to find out what it covers.
///
/// **Why the header and not a manifest.** A side-loaded region has to announce
/// its own extent, and a sidecar JSON is one more thing to keep in sync — build
/// a new region, forget the manifest, and the app silently renders Apple's map
/// instead. PMTiles v3 already carries the bounds in a fixed 127-byte header, so
/// the file is self-describing and a region is a single artifact you can drag in.
///
/// Spec: <https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md>. Only
/// the fields the tile lookup needs are decoded; everything else in the header
/// is MapLibre's business.
enum PMTilesHeader {
    /// Bytes 0–6 spell `PMTiles`, byte 7 is the spec version.
    private static let magic = Array("PMTiles".utf8)
    private static let headerLength = 127
    /// Byte offsets of the four bounds int32s (E7 degrees, little-endian).
    private static let boundsOffset = 102

    /// The region a `.pmtiles` file covers, or nil when the file is missing,
    /// truncated, not PMTiles, a version this does not know how to read, or
    /// carries a degenerate (all-zero) bounds record — an unreadable header is
    /// never guessed at, because guessing wrong renders a blank map.
    static func bounds(ofFileAt url: URL) -> GeoBox? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headerLength), data.count == headerLength else { return nil }
        return bounds(inHeader: [UInt8](data))
    }

    /// Split out so the decoding is testable without a file on disk.
    static func bounds(inHeader bytes: [UInt8]) -> GeoBox? {
        guard bytes.count >= headerLength, Array(bytes[0..<magic.count]) == magic, bytes[7] == 3 else { return nil }

        func degrees(at offset: Int) -> Double {
            var raw: UInt32 = 0
            for byte in (0..<4).reversed() { raw = raw << 8 | UInt32(bytes[offset + byte]) }
            return Double(Int32(bitPattern: raw)) / 1e7
        }
        let minLon = degrees(at: boundsOffset)
        let minLat = degrees(at: boundsOffset + 4)
        let maxLon = degrees(at: boundsOffset + 8)
        let maxLat = degrees(at: boundsOffset + 12)

        guard minLat < maxLat, minLon < maxLon else { return nil }
        return GeoBox(minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon)
    }
}
