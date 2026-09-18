#if DEBUG
import Foundation
import KamomeImportKit
import Photos

/// A photo library with five journeys in it, for the Journey Discovery home's
/// simulator render (`-demo-discover`; debug only).
///
/// Positions and times are **invented**: a home in one place, photographed
/// across many weeks, and five trips whose coordinates are city centres typed
/// in by hand — no real trip's data (§0). The photographs themselves are
/// whatever images the simulator's library holds, so the cards can show real
/// pixels; with no library access every tile draws the placeholder, which is
/// also a state worth seeing.
final class DemoJourneyLibrary: ImportPhotoProviding, PhotoAccessProviding {
    /// A throwaway defaults suite, so a demo run never hides or names a real
    /// journey and a real run never sees demo names.
    let defaults = UserDefaults(suiteName: "kamome.demo.discovery") ?? .standard

    static func ifRequested() -> DemoJourneyLibrary? {
        ProcessInfo.processInfo.arguments.contains("-demo-discover") ? DemoJourneyLibrary() : nil
    }

    // MARK: - PhotoAccessProviding

    var readAccess: PhotoReadAccess { .granted }

    func requestReadAccess() async -> PhotoReadAccess { .granted }

    func presentLimitedLibraryPicker(completion: @escaping () -> Void) { completion() }

    // MARK: - ImportPhotoProviding

    func albums() async -> [PhotoAlbum] { [] }

    func photos(matching query: ImportQuery) async -> [ImportPhoto] {
        let assets = await libraryAssetIds()
        var next = 0
        func asset() -> String {
            defer { next += 1 }
            return assets.isEmpty ? "demo-missing-\(next)" : assets[next % assets.count]
        }
        let calendar = Calendar(identifier: .gregorian)
        func day(_ year: Int, _ month: Int, _ day: Int) -> Double {
            let components = DateComponents(
                timeZone: TimeZone(identifier: "UTC"), year: year, month: month, day: day, hour: 10
            )
            return calendar.date(from: components)?.timeIntervalSince1970 ?? 0
        }
        var photos: [ImportPhoto] = []
        // Home: an invented suburb, one photograph a week for two years.
        for week in 0..<100 {
            let ts = day(2024, 9, 1) + Double(week) * 7 * 86_400
            photos.append(ImportPhoto(assetId: asset(), timestamp: ts, lat: 25.04 + Double(week % 3) * 0.002, lon: 121.56))
        }
        struct Stop { let lat: Double; let lon: Double; let dayOffset: Int; let count: Int }
        func stop(_ lat: Double, _ lon: Double, day: Int, _ count: Int) -> Stop {
            Stop(lat: lat, lon: lon, dayOffset: day, count: count)
        }
        func trip(start: Double, stops: [Stop]) {
            for place in stops {
                for index in 0..<place.count {
                    let ts = start + Double(place.dayOffset) * 86_400 + Double(index) * 1_800
                    let jitter = Double(index % 4) * 0.0008
                    photos.append(ImportPhoto(
                        assetId: asset(), timestamp: ts, lat: place.lat + jitter, lon: place.lon + jitter,
                        isFavorite: index == 1
                    ))
                }
            }
        }
        // 2026 — Whitehorse (one place), Japan (Tokyo → Kyoto), Finland (Helsinki → Rovaniemi).
        trip(start: day(2026, 8, 3), stops: [
            stop(60.7212, -135.0568, day: 0, 6), stop(60.7300, -135.0400, day: 1, 5), stop(60.7150, -135.0700, day: 2, 4)
        ])
        trip(start: day(2026, 4, 6), stops: [
            stop(35.6762, 139.6503, day: 0, 8), stop(35.3606, 138.7274, day: 2, 5), stop(35.0116, 135.7681, day: 4, 9)
        ])
        trip(start: day(2026, 2, 9), stops: [
            stop(60.1699, 24.9384, day: 0, 6), stop(61.4978, 23.7610, day: 2, 4), stop(66.5039, 25.7294, day: 4, 7)
        ])
        // 2025 — Italy (Rome → Florence), New Zealand (Queenstown → Wanaka → Tekapo).
        trip(start: day(2025, 10, 6), stops: [stop(41.9028, 12.4964, day: 0, 9), stop(43.7696, 11.2558, day: 2, 6)])
        trip(start: day(2025, 3, 10), stops: [
            stop(-45.0312, 168.6626, day: 0, 7), stop(-44.7032, 169.1321, day: 2, 5), stop(-44.0046, 170.4771, day: 4, 6)
        ])
        return photos
    }

    /// Whatever images the simulator's library holds, oldest first — nothing
    /// about them is read but their identifiers. Empty without access.
    private func libraryAssetIds() async -> [String] {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var ids: [String] = []
        assets.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
    }
}
#endif
