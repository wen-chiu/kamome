import Foundation

/// **A trip that crosses 180° is one continuous journey** (#234, ADR
/// 2026-10-07-a-trip-across-180-is-framed-the-short-way).
///
/// The camera's arithmetic — bounds, spans, the follow cam, every lerp — takes
/// longitude as a plain number. Across the meridian that is wrong by a planet:
/// Tokyo (139.7°) to Vancouver (−123.1°) measured 263° the long way round
/// instead of 97° across the Pacific, and the film asked for frames 44,000 km
/// wide, centred on the wrong hemisphere (#234).
///
/// Rather than teach thirty call sites about the seam, the trip is **unwrapped
/// once**, before any of them see it: the seam is moved into the widest stretch
/// of longitude the trip never visits, so every distance downstream is the
/// short one. A trip that does not cross 180° already has its widest gap there,
/// and comes back as the identical value — every film that never crossed the
/// meridian is unchanged.
///
/// Unwrapped longitudes may run past ±180. Only the substrate needs them
/// normal, and only for the camera's centre: MapLibre projects any longitude
/// to the copy nearest that centre (VERIFIED on a real snapshot, #234), so the
/// route, the stops and every overlay land where they belong unchanged.
public enum Antimeridian {
    /// `longitude` in [−180, 180).
    public static func normalized(_ longitude: Double) -> Double {
        // In range already: returned exact, so a point that does not move keeps
        // its value to the last bit.
        if longitude >= -180, longitude < 180 { return longitude }
        let wrapped = (longitude + 180).truncatingRemainder(dividingBy: 360)
        return (wrapped < 0 ? wrapped + 360 : wrapped) - 180
    }

    /// Where a continuous window over these longitudes starts, or nil when
    /// ±180° already lies in their widest empty gap — every set that does not
    /// cross the meridian. Points west of the start move east by 360°.
    static func windowStart(of longitudes: [Double]) -> Double? {
        let sorted = Set(longitudes.map(normalized)).sorted()
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return nil }
        // The gap across the seam, from the easternmost point round to the
        // westernmost. While it is the widest, the trip is already continuous.
        var widest = first + 360 - last
        var start: Double?
        for (west, east) in zip(sorted, sorted.dropFirst()) where east - west > widest {
            widest = east - west
            start = east
        }
        return start
    }

    static func unwrapped(_ longitude: Double, from start: Double) -> Double {
        let normal = normalized(longitude)
        return normal < start ? normal + 360 : normal
    }
}

extension RecapTrip {
    /// This trip with its longitudes continuous across 180° — itself, exactly,
    /// when it never crosses the meridian (`Antimeridian`).
    public func unwrappedAcrossTheAntimeridian() -> RecapTrip {
        let longitudes = legs.flatMap { $0.coordinates.map(\.lon) } + stops.map(\.coordinate.lon)
        guard let start = Antimeridian.windowStart(of: longitudes) else { return self }
        func moved(_ point: RecapCoordinate) -> RecapCoordinate {
            RecapCoordinate(lat: point.lat, lon: Antimeridian.unwrapped(point.lon, from: start))
        }
        return RecapTrip(
            legs: legs.map { leg in
                Leg(
                    coordinates: leg.coordinates.map(moved), mode: leg.mode, provenance: leg.provenance,
                    isCrossing: leg.isCrossing, countryCodes: leg.countryCodes
                )
            },
            stops: stops.map { stop in
                Stop(
                    coordinate: moved(stop.coordinate), name: stop.name, dayLabel: stop.dayLabel,
                    detail: stop.detail, photos: stop.photos, dwellS: stop.dwellS,
                    locality: stop.locality, subLocality: stop.subLocality
                )
            },
            title: title, subtitle: subtitle, endCardFigures: endCardFigures, shareURL: shareURL,
            journeyDates: journeyDates, everyLegRoutabilityEstablished: everyLegRoutabilityEstablished
        )
    }
}

extension CameraPath {
    /// The extent of the country `point` is in, in `point`'s own window. The
    /// extents are stored in ordinary longitudes and a route may be unwrapped
    /// across 180°, so the country is looked up normal and framed back where
    /// the route is (`Antimeridian`).
    static func countryBounds(around point: Point) -> Bounds? {
        let normal = Antimeridian.normalized(point.lon)
        guard let country = CountryExtent.containing(lat: point.lat, lon: normal) else { return nil }
        let shift = point.lon - normal
        return Bounds(
            minLat: country.bounds.minLat, maxLat: country.bounds.maxLat,
            minLon: country.bounds.minLon + shift, maxLon: country.bounds.maxLon + shift
        )
    }
}
