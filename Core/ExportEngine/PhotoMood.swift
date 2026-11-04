import Foundation
import KamomeConfig

/// **What the film's photographs feel like** (`Docs/handoff-music-in-the-film.md`
/// §2.4): scene labels and colour, aggregated over the photographs the film
/// shows. The analyser measures each photograph once, on the device, in the
/// pass that already loads its pixels; the soundtrack picker reads only this
/// aggregate. Labels and colour are personal data but not location data, and
/// they never leave the device either.
public struct PhotoMood: Equatable, Sendable {
    /// The scene labels kept from `VNClassifyImageRequest`, by their Vision
    /// identifiers. **The order is a storage format**: a label's bit is its
    /// index, and rows store the bits. Append only — never reorder or remove.
    public enum Label: String, CaseIterable, Sendable {
        case mountain, beach, ocean, shore, snow, sky, forest, waterfall, lake, glacier, desert
        case sunsetSunrise = "sunset_sunrise"
        case cityscape
        case nightSky = "night_sky"
        case food, people, street, restaurant

        /// Which signal the label feeds.
        public enum Group: Sendable {
            case landscape, people, night
        }

        public var group: Group {
            switch self {
            case .mountain, .beach, .ocean, .shore, .snow, .sky, .forest, .waterfall, .lake, .glacier,
                 .desert, .sunsetSunrise:
                return .landscape
            case .cityscape, .food, .people, .street, .restaurant:
                return .people
            case .nightSky:
                return .night
            }
        }

        public var bit: Int64 { Int64(1) << Int64(Self.allCases.firstIndex(of: self) ?? 0) }

        /// The bitmask a row stores for these labels.
        public static func mask(_ labels: some Sequence<Label>) -> Int64 {
            labels.reduce(0) { $0 | $1.bit }
        }

        /// The labels a stored bitmask holds; bits no label owns are ignored.
        public static func labels(in mask: Int64) -> Set<Label> {
            Set(allCases.filter { mask & $0.bit != 0 })
        }
    }

    /// One photograph's measurements, as the analyser stores them.
    public struct Photo: Equatable, Sendable {
        public let labels: Int64
        /// Mean luminance, 0…1.
        public let luminance: Double
        /// Mean saturation, 0…1.
        public let saturation: Double
        /// Mean red minus blue, −1 (cool) … 1 (warm).
        public let warmth: Double

        public init(labels: Int64, luminance: Double, saturation: Double, warmth: Double) {
            self.labels = labels
            self.luminance = luminance
            self.saturation = saturation
            self.warmth = warmth
        }
    }

    /// How many photographs carried measurements. 0 is the neutral mood: a film
    /// with no photographs, or only rows from the version-1 analyser.
    public let photoCount: Int
    public let landscapeShare: Double
    public let peopleShare: Double
    public let nightShare: Double
    public let luminance: Double
    public let saturation: Double
    public let warmth: Double

    /// No photographs measured: the picker falls back to the film's shape.
    public static let neutral = PhotoMood(photos: [], nightLuminanceMax: 0)

    public init(photos: [Photo], nightLuminanceMax: Double) {
        photoCount = photos.count
        guard !photos.isEmpty else {
            (landscapeShare, peopleShare, nightShare, luminance, saturation, warmth) = (0, 0, 0, 0, 0, 0)
            return
        }
        let count = Double(photos.count)
        func share(_ test: (Photo) -> Bool) -> Double { Double(photos.filter(test).count) / count }
        func has(_ photo: Photo, _ group: Label.Group) -> Bool {
            Label.labels(in: photo.labels).contains { $0.group == group }
        }
        landscapeShare = share { has($0, .landscape) }
        peopleShare = share { has($0, .people) }
        nightShare = share { has($0, .night) || $0.luminance < nightLuminanceMax }
        luminance = photos.map(\.luminance).reduce(0, +) / count
        saturation = photos.map(\.saturation).reduce(0, +) / count
        warmth = photos.map(\.warmth).reduce(0, +) / count
    }
}

extension PhotoMood {
    /// **Luminance, saturation and warmth of an RGBA image**, averaged over its
    /// pixels (§2.4). Pure, so the arithmetic is tested without Vision or a
    /// photograph; the analyser hands it the 32 × 32 downsample it draws.
    /// `rgba` is 8-bit, premultiplied or not (alpha is ignored), row-major.
    public static func colour(rgba: [UInt8]) -> Colour? {
        let pixels = rgba.count / 4
        guard pixels > 0 else { return nil }
        var luminance = 0.0, saturation = 0.0, warmth = 0.0
        for index in 0..<pixels {
            let red = Double(rgba[index * 4]) / 255
            let green = Double(rgba[index * 4 + 1]) / 255
            let blue = Double(rgba[index * 4 + 2]) / 255
            // Rec. 709 weights on the encoded values: a photograph's look, not
            // its light — what "a dark photo" means to the eye.
            luminance += 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let high = max(red, green, blue)
            saturation += high > 0 ? (high - min(red, green, blue)) / high : 0
            warmth += red - blue
        }
        let count = Double(pixels)
        return Colour(luminance: luminance / count, saturation: saturation / count, warmth: warmth / count)
    }

    /// One photograph's colour, averaged over its pixels.
    public struct Colour: Equatable, Sendable {
        public let luminance: Double
        public let saturation: Double
        public let warmth: Double
    }
}
