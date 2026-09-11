@testable import Kamome
import XCTest

/// **Every licence the app must reproduce is inside the built app** (ADR
/// 2026-09-12 (c)).
///
/// `Scripts/release/check-attribution.sh` pairs `Package.resolved` with
/// `Acknowledgement.all` and the committed texts — it reads the repository. This
/// reads the bundle the test is hosted by, which is what the licence is owed by: a
/// text that is committed but never copied into `Kamome.app` meets nothing.
final class AcknowledgementsTests: XCTestCase {
    func testEveryAcknowledgedLicenceTextIsBundledVerbatim() {
        XCTAssertFalse(Acknowledgement.all.isEmpty, "precondition: something is acknowledged")
        for library in Acknowledgement.all {
            let text = library.text ?? ""
            XCTAssertTrue(text.contains("Copyright"),
                          "\(library.id): its licence text, with its copyright notice, is not in the app bundle")
            // The operative clause of the licence the entry names, so a text
            // bundled under the wrong package's name cannot pass.
            switch library.licence {
            case "MIT":
                XCTAssertTrue(text.contains("Permission is hereby granted"), "\(library.id): not an MIT licence text")
            case "BSD-2-Clause":
                XCTAssertTrue(text.contains("Redistributions in binary form"), "\(library.id): not a BSD licence text")
            default:
                XCTFail("\(library.id): \(library.licence) has no check here — add its operative clause")
            }
        }
    }
}
