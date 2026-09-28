import Foundation
import KamomeConfig

/// The film length the person chose last, so every trip's export sheet — and
/// the Stop Editor, which draws the same plan — opens on it (Chiu 2026-09-27).
///
/// **Short until they say otherwise** (Chiu 2026-09-27: 預設等級：精華). One
/// preference for the app, not a column per trip: the choice is about where
/// the film is going (a Reel, or the whole story), which is a habit of the
/// person's rather than a property of the trip. A stored value that is not a
/// `FilmLength` any more reads as the default.
enum FilmLengthChoice {
    private static let key = "kamome.filmLength"

    static func current(defaults: UserDefaults = .standard) -> FilmLength {
        defaults.string(forKey: key).flatMap(FilmLength.init(rawValue:)) ?? .short
    }

    static func remember(_ length: FilmLength, defaults: UserDefaults = .standard) {
        defaults.set(length.rawValue, forKey: key)
    }
}
