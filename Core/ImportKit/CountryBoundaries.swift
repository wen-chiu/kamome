import Foundation

/// **Which country is this photograph in**, answered on the phone (ADR
/// 2026-09-25). Journey discovery ends a journey at the first photograph back in
/// the home country after one taken abroad; §0 scopes Apple geocoding to stop
/// points, and a scan runs before any stop exists, so the answer comes from a
/// bundled file instead: Natural Earth v5.1.2 admin-0, public domain, built by
/// `Scripts/build-country-boundaries.py` (≈0.8 MB, ~1 km outlines).
///
/// **Taiwan and China are two countries** (Chiu 2026-09-25). Codes are
/// `ADM0_A3` — `TWN`, never Natural Earth's `ISO_A2` "CN-TW" — and Matsu,
/// Lieyu, Wuqiu and Xiaoliuqiu are added to Taiwan by name in the build.
///
/// Read only while a scan runs; nothing is loaded at launch. Codes are used to
/// compare, never shown.
public struct CountryBoundaries: Sendable {
    struct Ring: Sendable {
        let lons: [Float]
        let lats: [Float]
        let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
    }

    struct Country: Sendable {
        let code: String
        let rings: [Ring]
        let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
    }

    enum FormatError: Error { case badHeader, truncated }

    /// Storage unit of the file's coordinates (`UNIT_DEG` in the build script).
    static let unitDeg = 1e-4

    let countries: [Country]

    /// The file shipped in this module, or nil if it cannot be read — the
    /// country rule is then off and journeys are cut as before it.
    public static func bundled() -> CountryBoundaries? {
        guard let url = Bundle.module.url(forResource: "country-boundaries", withExtension: "bin"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CountryBoundaries(data: data)
    }

    public init(data: Data) throws {
        var reader = Reader(bytes: [UInt8](data))
        guard try reader.bytes(4) == Array("KCB2".utf8) else { throw FormatError.badHeader }
        var countries: [Country] = []
        for _ in 0..<(try reader.u32()) {
            guard let code = String(bytes: try reader.bytes(3), encoding: .ascii) else { throw FormatError.badHeader }
            var rings: [Ring] = []
            for _ in 0..<(try reader.u32()) {
                let count = Int(try reader.u32())
                var lons: [Float] = [], lats: [Float] = []
                lons.reserveCapacity(count)
                lats.reserveCapacity(count)
                var lon = 0, lat = 0
                for _ in 0..<count {
                    lon += try reader.zigzag()
                    lat += try reader.zigzag()
                    lons.append(Float(Double(lon) * Self.unitDeg))
                    lats.append(Float(Double(lat) * Self.unitDeg))
                }
                guard !lons.isEmpty else { continue }
                rings.append(Ring(
                    lons: lons, lats: lats,
                    minLat: Double(lats.min()!), maxLat: Double(lats.max()!),
                    minLon: Double(lons.min()!), maxLon: Double(lons.max()!)
                ))
            }
            guard !rings.isEmpty else { continue }
            countries.append(Country(
                code: code, rings: rings,
                minLat: rings.map(\.minLat).min()!, maxLat: rings.map(\.maxLat).max()!,
                minLon: rings.map(\.minLon).min()!, maxLon: rings.map(\.maxLon).max()!
            ))
        }
        self.countries = countries
    }

    /// The country containing the point; failing that, the nearest one whose
    /// border lies within `coastBufferM` — a beach, a harbour, a coastline the
    /// simplified outline cuts inside. nil at sea or where no outline reaches:
    /// the caller treats that as no evidence either way.
    public func country(lat: Double, lon: Double, coastBufferM: Double) -> String? {
        if let hit = countries.first(where: { contains($0, lat: lat, lon: lon) }) { return hit.code }
        guard coastBufferM > 0 else { return nil }
        let padLat = coastBufferM / 111_000
        let padLon = padLat / max(cos(lat * .pi / 180), 0.01)
        var best: (code: String, distance: Double)?
        for country in countries
        where lat >= country.minLat - padLat && lat <= country.maxLat + padLat
            && lon >= country.minLon - padLon && lon <= country.maxLon + padLon {
            for ring in country.rings
            where lat >= ring.minLat - padLat && lat <= ring.maxLat + padLat
                && lon >= ring.minLon - padLon && lon <= ring.maxLon + padLon {
                let distance = Self.distanceM(lat: lat, lon: lon, to: ring)
                if distance <= coastBufferM, distance < (best?.distance ?? .infinity) {
                    best = (country.code, distance)
                }
            }
        }
        return best?.code
    }

    // MARK: - Geometry

    /// Even-odd over every ring of the country, so a hole (Lesotho inside South
    /// Africa) is outside it.
    private func contains(_ country: Country, lat: Double, lon: Double) -> Bool {
        guard lat >= country.minLat, lat <= country.maxLat, lon >= country.minLon, lon <= country.maxLon else {
            return false
        }
        var inside = false
        for ring in country.rings
        where lat >= ring.minLat && lat <= ring.maxLat && lon >= ring.minLon && lon <= ring.maxLon {
            var previous = ring.lats.count - 1
            for index in 0..<ring.lats.count {
                let yi = Double(ring.lats[index]), yj = Double(ring.lats[previous])
                if (yi > lat) != (yj > lat) {
                    let xi = Double(ring.lons[index]), xj = Double(ring.lons[previous])
                    if lon < (xj - xi) * (lat - yi) / (yj - yi) + xi { inside.toggle() }
                }
                previous = index
            }
        }
        return inside
    }

    /// Distance to the ring's nearest edge, on a local flat projection — a few
    /// kilometres is all it is ever asked about.
    private static func distanceM(lat: Double, lon: Double, to ring: Ring) -> Double {
        let metresPerDegLat = 111_320.0
        let metresPerDegLon = metresPerDegLat * cos(lat * .pi / 180)
        var best = Double.infinity
        var previous = ring.lats.count - 1
        for index in 0..<ring.lats.count {
            let ax = (Double(ring.lons[previous]) - lon) * metresPerDegLon
            let ay = (Double(ring.lats[previous]) - lat) * metresPerDegLat
            let bx = (Double(ring.lons[index]) - lon) * metresPerDegLon
            let by = (Double(ring.lats[index]) - lat) * metresPerDegLat
            let dx = bx - ax, dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            let along = lengthSquared > 0 ? min(max(-(ax * dx + ay * dy) / lengthSquared, 0), 1) : 0
            best = min(best, hypot(ax + along * dx, ay + along * dy))
            previous = index
        }
        return best
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            guard offset + count <= bytes.count else { throw FormatError.truncated }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }

        mutating func u32() throws -> UInt32 {
            let raw = try bytes(4)
            return raw.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
        }

        /// A zigzag varint: seven bits a byte, low first, sign in the lowest bit.
        mutating func zigzag() throws -> Int {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard offset < bytes.count, shift < 64 else { throw FormatError.truncated }
                let byte = bytes[offset]
                offset += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            return Int(value >> 1) ^ -Int(value & 1)
        }
    }
}
