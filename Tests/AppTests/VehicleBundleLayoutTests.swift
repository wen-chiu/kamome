@testable import Kamome
import KamomeExportEngine
import XCTest

/// What actually reaches the app — the layout, not the intention.
///
/// `Package.swift` uses `.copy` so the vehicle folder structure survives:
/// `.process` flattens, and `car-red/n.png` would then collide with a future
/// `car-blue/n.png`, with the build system rather than the manifest picking the
/// winner. This reads the app's **own** resource bundle, so it fails if that
/// ever silently changes.
///
/// There is deliberately no `.DS_Store` assertion here. Xcode's resource copying
/// already drops those, so such a test passed with the strip disabled — it could
/// not fail, and a test that cannot fail is worse than none. The guarantee is the
/// unconditional post-build strip in `project.yml` instead.
final class VehicleBundleLayoutTests: XCTestCase {
    private func vehiclesDirectory() throws -> URL {
        let bundle = try XCTUnwrap(VehicleResourceBundle.resolved, "the vehicle resource bundle was not found")
        let manifest = try XCTUnwrap(
            bundle.url(forResource: "vehicles", withExtension: "json", subdirectory: "Vehicles")
        )
        return manifest.deletingLastPathComponent()
    }

    /// The structure `.copy` exists to preserve: one folder per subject, each
    /// holding its own drawings. Flattening would put every set's `n.png` in one
    /// place, and the manifest would stop meaning anything.
    func testEverySubjectKeepsItsOwnFolder() throws {
        let root = try vehiclesDirectory()
        for subject in VehicleCatalog.subjects {
            var isDirectory: ObjCBool = false
            let folder = root.appendingPathComponent(subject.id)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                "\(subject.id) has no folder in the bundle — the tree was flattened"
            )
            XCTAssertTrue(isDirectory.boolValue, "\(subject.id) must be a directory")
        }
    }
}
