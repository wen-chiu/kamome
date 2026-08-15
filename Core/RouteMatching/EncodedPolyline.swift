import Foundation

/// A WGS-84 coordinate as the matching layer sees it. Kept Foundation-only:
/// this module never imports CoreLocation or any renderer SDK.
public struct GeoPoint: Equatable, Sendable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// Google encoded-polyline codec, precision 5 — the format OSRM emits with
/// `geometries=polyline` and the format `segment.matched_polyline` stores
/// (schema v1, spec §3).
public enum EncodedPolyline {
    private static let precision = 1e5

    public static func decode(_ encoded: String) -> [GeoPoint] {
        var points: [GeoPoint] = []
        var lat = 0
        var lon = 0
        var index = encoded.utf8.makeIterator()

        func nextDelta() -> Int? {
            var result = 0
            var shift = 0
            while let byte = index.next() {
                let chunk = Int(byte) - 63
                result |= (chunk & 0x1F) << shift
                shift += 5
                if chunk < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }

        while let dLat = nextDelta(), let dLon = nextDelta() {
            lat += dLat
            lon += dLon
            points.append(GeoPoint(lat: Double(lat) / precision, lon: Double(lon) / precision))
        }
        return points
    }

    public static func encode(_ points: [GeoPoint]) -> String {
        var output = ""
        var previousLat = 0
        var previousLon = 0

        func append(_ delta: Int) {
            var value = delta < 0 ? ~(delta << 1) : (delta << 1)
            while value >= 0x20 {
                output.append(Character(UnicodeScalar(UInt8(((value & 0x1F) | 0x20) + 63))))
                value >>= 5
            }
            output.append(Character(UnicodeScalar(UInt8(value + 63))))
        }

        for point in points {
            let lat = Int((point.lat * precision).rounded())
            let lon = Int((point.lon * precision).rounded())
            append(lat - previousLat)
            append(lon - previousLon)
            previousLat = lat
            previousLon = lon
        }
        return output
    }
}
