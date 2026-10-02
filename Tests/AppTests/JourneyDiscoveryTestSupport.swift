@testable import Kamome
import KamomeImportKit
import XCTest

// The stubs the Journey Discovery tests drive the model over. Moved out of
// `JourneyDiscoveryModelTests` on 2026-10-01, unchanged but for their names,
// when a second test file needed them and the first passed SwiftLint's limits.

final class DiscoveryStubLibrary: ImportPhotoProviding, PhotoAccessProviding {
    var photos: [ImportPhoto] = []
    var queries: [ImportQuery] = []
    var access: PhotoReadAccess = .granted
    var pickerPresented = 0

    func photos(matching query: ImportQuery) async -> [ImportPhoto] {
        queries.append(query)
        return photos
    }
    func albums() async -> [PhotoAlbum] { [] }
    var readAccess: PhotoReadAccess { access }
    func requestReadAccess() async -> PhotoReadAccess { access }
    func presentLimitedLibraryPicker(completion: @escaping () -> Void) {
        pickerPresented += 1
        completion()
    }
}

/// Answers instantly from a table; records every coordinate it was asked
/// about, because *which* coordinates leave the device is the property the
/// privacy test in `JourneyDiscoveryModelTests` holds.
final class DiscoveryStubGeocoder: PlaceGeocoding {
    var table: [(lat: Double, place: PlaceName)] = []
    private(set) var askedLatitudes: [Double] = []
    var lookups: Int { askedLatitudes.count }

    func place(lat: Double, lon: Double) async -> PlaceName? {
        askedLatitudes.append(lat)
        return table.first { abs($0.lat - lat) < 0.5 }?.place
    }
}
