import CoreGraphics
import Foundation
import ImageIO

/// What kind of subject a folder holds. The two are **not interchangeable** —
/// see `Resources/Vehicles/README.md`, which is the specification for both the
/// art and this loader.
public enum VehicleKind: String, Decodable, Sendable {
    case directional
    case omni
}

/// One selectable subject, as declared in `vehicles.json`.
///
/// Everything here is what a filename cannot carry. `selectable` in particular
/// is load-bearing rather than cosmetic: the cross-region plane and ship will
/// exist as art before they are user-choosable, because the app picks them from
/// the journey rather than the user picking them.
public struct VehicleSubject: Decodable, Equatable, Sendable {
    /// The folder name, which is the id. No nesting, no second level.
    public let id: String
    public let kind: VehicleKind
    /// Presentation grouping only ("these are all cars"), so a set can be
    /// regrouped for the picker without moving a file.
    public let type: String
    public let selectable: Bool
    /// This subject's size as a **fraction of `export.subject_length_px`**, when
    /// it should not simply be the subject size. Absent means "take the
    /// configured size", which is what every vehicle does.
    ///
    /// A fraction rather than an absolute because the thing being expressed is
    /// relational: a mark is a pin sized *against* the vehicle, not at some fixed
    /// pixel count. An absolute would encode a consequence of that intent at one
    /// particular subject size and then silently stop meaning it —
    /// `subject_length_px` moved three times in a week — with nothing failing and
    /// the mark quietly drifting out of proportion.
    public let lengthFraction: Double?
    /// Display name per language code.
    public let names: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, kind, type, selectable, names
        case lengthFraction = "length_fraction"
    }

    /// The name to show, preferring the caller's language and falling back to
    /// English and then to the id — a subject with no name is still selectable
    /// rather than invisible.
    public func displayName(language: String) -> String {
        names[language] ?? names[String(language.prefix(2))] ?? names["en"] ?? id
    }
}

/// The drawings behind one subject, decoded.
public enum SubjectArtwork {
    /// Eight drawings; the renderer picks by heading and never rotates.
    case directional([SpriteDirection: CGImage])
    /// One drawing that never turns and implies no heading.
    case omni(CGImage)
}

/// `vehicles.json` itself. Top level rather than nested inside the loader only
/// because `CodingKeys` would otherwise sit three types deep.
private struct VehicleManifest: Decodable {
    let schemaVersion: Int
    let subjects: [VehicleSubject]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case subjects
    }
}

/// Reads `Vehicles/vehicles.json` and the folders beside it.
///
/// **Nothing here restates `Resources/Vehicles/README.md`** — that file is the
/// specification, it explains why each constraint exists, and duplicating it in
/// comments would let the two drift. What this type owes the spec is the two
/// guarantees it names: all-or-nothing per set, and decode once.
public enum VehicleCatalog {
    /// The id used when a trip does not name one, and the first fallback when a
    /// named subject cannot be loaded. A car is a better failure than a dot.
    public static let defaultSubjectId = "car-red"

    /// **What crosses a leg with no road**, when nothing has classified it —
    /// `Docs/cross-region-journeys.md` requirement 4, *"the load-bearing one"*.
    ///
    /// The seagull, because the honest answer to an unmodelled crossing is *we
    /// know you went from here to there; we do not know how*, and that answer has
    /// to be **cheap and good-looking rather than a failure state**. A plane drawn
    /// over a ferry route would be a fabrication of exactly the kind PD-1/PD-2
    /// exist to prevent.
    ///
    /// ⚠️ **Three gull objects exist and this is only one of them.** This is the
    /// `seagull` folder in `vehicles.json` — an **omni PNG sprite**, a choosable
    /// subject in its own right. It is *not* `VehicleMarker.seagull`, the bare
    /// vector that is also the end card's brand mark (`HANDOFF.md` 2026-08-29
    /// finding 5b — restyling it would silently turn the wordmark's bird into
    /// something else), and it is *not* `VehicleMarker.seagullBadge`, the fault
    /// marker, which must never narrate: using it would re-create the collision
    /// PR #23 closed, where one symbol meant both "we could not classify your
    /// crossing" and "the artwork failed to load".
    ///
    /// ⏳ **Open, and Chiu's:** this sprite is still `selectable: true`, i.e. a
    /// subject a user may pick for their whole trip. The precedent for crossing
    /// art is `plane` / `boat`, both `selectable: false`; the counter-precedent is
    /// the reindeer sets, which are choosable and are not crossing art (ADR
    /// 2026-08-20 (3d)). Nothing is changed here, because "does the seagull carry
    /// the brand or dilute it?" is an open question in
    /// `Docs/cross-region-journeys.md` and a brand decision, not an implementer's.
    public static let crossingSubjectId = "seagull"

    private static let store = Store()

    /// Every declared subject, manifest order.
    public static var subjects: [VehicleSubject] { store.subjects }

    /// Those a user may choose. **`selectable` is the only gate**, deliberately.
    ///
    /// A missing `logo.png` used to remove a subject from this list, which made
    /// art a second, implicit source of truth about whether a feature works. It
    /// produced exactly the failure that pattern always produces: with car-red's
    /// thumbnail absent, a user who switched to a scooter could not switch back,
    /// and nothing on screen said why. Eligibility is a product decision, so it
    /// has one home — the flag — and missing art degrades how a row *looks*,
    /// never whether it is there.
    public static var selectableSubjects: [VehicleSubject] {
        store.subjects.filter(\.selectable)
    }

    /// The picker thumbnail, when one has been drawn. Callers must treat nil as
    /// "show something else", never as "hide the subject".
    ///
    /// Never drawn into a film and deliberately separate from `artwork` — it is
    /// not part of the set's canvas, carries no direction, and must not reach
    /// the renderer.
    public static func thumbnail(id: String) -> CGImage? {
        store.thumbnail(id: id)
    }

    public static func subject(id: String) -> VehicleSubject? {
        store.subjects.first { $0.id == id }
    }

    /// The decoded drawings for `id`, or nil if the set is missing or partial.
    /// Cached per subject: the render loop asks every frame.
    public static func artwork(id: String) -> SubjectArtwork? {
        store.artwork(id: id)
    }

    /// The subject to draw, and its artwork, after the fallback chain: the asked-for
    /// subject, then the car, then nil — at which point the caller draws a marker.
    public static func resolve(id: String?) -> (subject: VehicleSubject, artwork: SubjectArtwork)? {
        for candidate in [id, defaultSubjectId].compactMap({ $0 }) {
            if let subject = subject(id: candidate), let artwork = artwork(id: candidate) {
                return (subject, artwork)
            }
        }
        return nil
    }

    // MARK: - Loading

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var manifestLoaded = false
        private var cachedSubjects: [VehicleSubject] = []
        private var artworkCache: [String: SubjectArtwork?] = [:]
        private var thumbnailCache: [String: CGImage?] = [:]

        var subjects: [VehicleSubject] {
            lock.withLock {
                if !manifestLoaded {
                    manifestLoaded = true
                    cachedSubjects = Self.decodeManifest()
                }
                return cachedSubjects
            }
        }

        func artwork(id: String) -> SubjectArtwork? {
            _ = subjects
            return lock.withLock {
                if let cached = artworkCache[id] { return cached }
                let decoded = Self.decode(id: id, kind: cachedSubjects.first { $0.id == id }?.kind)
                artworkCache[id] = decoded
                return decoded
            }
        }

        func thumbnail(id: String) -> CGImage? {
            _ = subjects
            return lock.withLock {
                if let cached = thumbnailCache[id] { return cached }
                let decoded = VehicleResourceBundle.resolved
                    .flatMap { Self.image(named: "logo", in: "Vehicles/\(id)", bundle: $0) }
                thumbnailCache[id] = decoded
                return decoded
            }
        }

        private static func decodeManifest() -> [VehicleSubject] {
            guard let bundle = VehicleResourceBundle.resolved,
                  let url = bundle.url(forResource: "vehicles", withExtension: "json", subdirectory: "Vehicles"),
                  let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(VehicleManifest.self, from: data)
            else { return [] }
            return manifest.subjects
        }

        /// All-or-nothing: a partial directional set never renders, because a
        /// missing file is otherwise a silent visual bug.
        private static func decode(id: String, kind: VehicleKind?) -> SubjectArtwork? {
            guard let kind, let bundle = VehicleResourceBundle.resolved else { return nil }
            let folder = "Vehicles/\(id)"
            switch kind {
            case .directional:
                var images: [SpriteDirection: CGImage] = [:]
                for direction in SpriteDirection.allCases {
                    guard let image = image(named: direction.rawValue, in: folder, bundle: bundle) else { return nil }
                    images[direction] = image
                }
                return .directional(images)
            case .omni:
                guard let image = image(named: "omni", in: folder, bundle: bundle) else { return nil }
                return .omni(image)
            }
        }

        private static func image(named name: String, in folder: String, bundle: Bundle) -> CGImage? {
            guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: folder),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil)
            else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }
}
