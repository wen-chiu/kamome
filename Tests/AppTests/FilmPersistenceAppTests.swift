import XCTest

/// Static assertions for film persistence — things the compiler cannot check
/// but that cost a submission rejection when they are wrong.
final class FilmPersistenceAppTests: XCTestCase {
    /// `NSPhotoLibraryAddUsageDescription` must be present in the app's
    /// Info.plist; without it `PHPhotoLibrary.requestAuthorization(for: .addOnly)`
    /// crashes on first call. This is the `.addOnly` key — distinct from the
    /// `.readWrite` key `NSPhotoLibraryUsageDescription` the app already carries
    /// for the photo import path.
    func testNSPhotoLibraryAddUsageDescriptionIsPresent() throws {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") as? String
        XCTAssertNotNil(value, "NSPhotoLibraryAddUsageDescription missing from Info.plist — the Save to Photos button will crash")
        XCTAssertFalse(value?.isEmpty ?? true, "NSPhotoLibraryAddUsageDescription is empty")
    }
}
