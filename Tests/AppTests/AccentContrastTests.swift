@testable import Kamome
import UIKit
import XCTest

/// **The accent reads as text in both appearances** (ADR
/// 2026-10-26-text-and-controls-take-a-deeper-teal, #294).
///
/// `#2DBDD0` was the accent until 2026-10-26, and white type on it measured
/// 2.26 : 1. Chiu chose two tones — `#1B727E` light, `#42C5D6` dark — with a dark
/// label on a dark-mode fill, and kept `#2DBDD0` as the brand colour for drawings
/// that carry no text. These tests read the colours out of the built asset
/// catalog and the backgrounds out of UIKit's own system colours, resolved per
/// appearance, so a later edit to either is measured rather than assumed.
///
/// The thresholds are WCAG 2's: 4.5 : 1 for body text, which every pair here is
/// held to, since the accent is used for footnote-sized text as well as titles.
final class AccentContrastTests: XCTestCase {
    private static let bodyText = 4.5

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)
    /// A sheet in dark mode: its backgrounds step up a level (About's rows
    /// are #2C2C2E, VERIFIED off a screenshot 2026-10-27). Light has no step.
    private let darkSheet = UITraitCollection { traits in
        traits.userInterfaceStyle = .dark
        traits.userInterfaceLevel = .elevated
    }
    private var appearances: [UITraitCollection] { [light, dark, darkSheet] }

    func testTheColoursAreTheOnesChiuChose() {
        XCTAssertEqual(hex(.accent, light), "1B727E")
        XCTAssertEqual(hex(.accent, dark), "42C5D6")
        XCTAssertEqual(hex(.onAccent, light), "FFFFFF")
        XCTAssertEqual(hex(.onAccent, dark), "0B2E33")
        XCTAssertEqual(hex(.brandTeal, light), "2DBDD0")
        XCTAssertEqual(hex(.brandTeal, dark), "2DBDD0")
    }

    /// **Warning text is `WarningText`, never the system orange** (#319, Chiu
    /// 2026-10-29). `#FF9500` measured 2.20 : 1 on white and 1.97 on the
    /// grouped grey. Light is Apple's increased-contrast orange `#C93400`;
    /// dark keeps the system orange, which reads there.
    func testWarningTextReadsOnPagesRowsAndSheets() {
        XCTAssertEqual(hex(.warningText, light), "C93400")
        XCTAssertEqual(hex(.warningText, dark), "FF9F0A")
        let grounds: [(String, UIColor)] = [
            ("systemBackground", .systemBackground),
            ("systemGroupedBackground", .systemGroupedBackground),
            ("secondarySystemGroupedBackground", .secondarySystemGroupedBackground)
        ]
        for traits in appearances {
            for (name, ground) in grounds {
                assertReads(rgb(.warningText, traits), on: Self.components(ground.resolvedColor(with: traits)).rgb,
                            "WarningText on \(name)", traits)
            }
        }
    }

    /// No sentence or label in the app is drawn in `.orange` any more; the
    /// pin's badge fill and a swipe button's tint are fills, not text.
    func testNoTextIsDrawnInTheSystemOrange() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ui = repoRoot.appendingPathComponent("UI")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("foregroundStyle") && line.contains("orange") {
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(offenders, [], "warning text goes through WarningText (#319)")
    }

    /// A filled button's label on its fill.
    func testTheLabelOnAFilledButtonReads() {
        for traits in appearances {
            assertReads(rgb(.onAccent, traits), on: rgb(.accent, traits), "OnAccent on AccentColor", traits)
        }
    }

    /// Tinted text — a link, a checkmark, a date being edited — on the page
    /// and the list row it sits on.
    func testAccentTextReadsOnPagesAndRows() {
        let grounds: [(String, UIColor)] = [
            ("systemBackground", .systemBackground),
            ("systemGroupedBackground", .systemGroupedBackground),
            ("secondarySystemGroupedBackground", .secondarySystemGroupedBackground)
        ]
        for traits in appearances {
            for (name, ground) in grounds {
                assertReads(rgb(.accent, traits), on: Self.components(ground.resolvedColor(with: traits)).rgb,
                            "AccentColor on \(name)", traits)
            }
        }
    }

    /// A `.bordered` button's label on its fill. The fill is
    /// `secondarySystemFill` over `systemBackground`, exactly: measured off
    /// Home's two bordered buttons (#E9E9EB light, #262629 dark) and the film
    /// player's 分享 in a dark sheet (#39393D), 2026-10-26 and -27.
    func testABorderedButtonsLabelReads() {
        for traits in appearances {
            let page = Self.components(UIColor.systemBackground.resolvedColor(with: traits)).rgb
            let fill = Self.components(UIColor.secondarySystemFill.resolvedColor(with: traits))
            assertReads(rgb(.accent, traits), on: Self.over(fill, page), "AccentColor on a bordered button", traits)
        }
    }

    /// The vehicle picker's chosen tile: its "2 styles" caption in the accent,
    /// on the accent at 14 % laid over the tile's own surface
    /// (`VehiclePickerView`; #DFEBED light and #2F4146 in the dark sheet,
    /// VERIFIED off screenshots). Laid over the page's grey instead, as it was
    /// until 2026-10-26, the light caption measured 4.16 : 1.
    func testTheChosenVehicleTileCaptionReads() {
        for traits in appearances {
            let accent = rgb(.accent, traits)
            let surface = Self.components(UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)).rgb
            assertReads(accent, on: Self.over((accent, 0.14), surface), "AccentColor on the chosen tile", traits)
        }
    }

    /// **Trip Detail's stop pin is a button, so it is the accent** (#312, Chiu
    /// 2026-10-29). In `BrandTeal` it was 2.26 : 1 on its white disc and 1.07
    /// on Apple's light sea, under the 3 : 1 a control needs; the accent's
    /// contrast on the page is held above. The pin's code, comments dropped.
    func testTheStopPinIsTheAccent() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(
            contentsOf: repoRoot.appendingPathComponent("UI/TripDetail/TripDetailView+Map.swift"), encoding: .utf8
        )
        let start = try XCTUnwrap(file.range(of: "func stopPin("))
        let end = try XCTUnwrap(file.range(of: "var dayChips", range: start.upperBound..<file.endIndex))
        let pin = file[start.lowerBound..<end.lowerBound]
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(pin.contains("mappin.circle.fill"), "this is not the stop pin any more")
        XCTAssertTrue(pin.contains("Color.accentColor"), "the pin is a control: the accent (#312)")
        XCTAssertFalse(pin.contains("brandTeal"), "BrandTeal is for drawings with no text and no tap (ADR 2026-10-26)")
        // The photo count on its orange badge took the button's tint: 2.54 : 1
        // in light, 1.00 in dark. Black on the system orange is 9.55 and 10.22.
        XCTAssertTrue(pin.contains(".foregroundStyle(.black)"), "the badge's count is black on orange")
    }

    /// The badge's black count on the system orange, both appearances.
    func testThePinsPhotoCountReadsOnItsOrangeBadge() {
        for traits in appearances {
            let orange = Self.components(UIColor.systemOrange.resolvedColor(with: traits)).rgb
            assertReads(RGB(red: 0, green: 0, blue: 0), on: orange, "black on the pin's orange badge", traits)
        }
    }

    // MARK: - WCAG 2 relative luminance

    private struct RGB {
        let red: Double, green: Double, blue: Double
    }

    private func assertReads(_ text: RGB, on ground: RGB, _ pair: String, _ traits: UITraitCollection,
                             file: StaticString = #filePath, line: UInt = #line) {
        let ratio = Self.contrast(text, ground)
        let appearance = traits.userInterfaceStyle == .light ? "light"
            : traits.userInterfaceLevel == .elevated ? "dark sheet" : "dark"
        XCTAssertGreaterThanOrEqual(ratio, Self.bodyText,
                                    "\(appearance): \(pair) is \(String(format: "%.2f", ratio)) : 1",
                                    file: file, line: line)
    }

    private static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ color: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.040_45 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private static func over(_ top: (rgb: RGB, alpha: Double), _ ground: RGB) -> RGB {
        RGB(red: top.alpha * top.rgb.red + (1 - top.alpha) * ground.red,
            green: top.alpha * top.rgb.green + (1 - top.alpha) * ground.green,
            blue: top.alpha * top.rgb.blue + (1 - top.alpha) * ground.blue)
    }

    /// The colour's sRGB components and its alpha.
    private static func components(_ color: UIColor) -> (rgb: RGB, alpha: Double) {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count == 4 else {
            XCTFail("\(color) has no sRGB components")
            return (RGB(red: 0, green: 0, blue: 0), 0)
        }
        return (RGB(red: Double(parts[0]), green: Double(parts[1]), blue: Double(parts[2])), Double(parts[3]))
    }

    private func rgb(_ resource: ColorResource, _ traits: UITraitCollection) -> RGB {
        Self.components(UIColor(resource: resource).resolvedColor(with: traits)).rgb
    }

    private func hex(_ resource: ColorResource, _ traits: UITraitCollection) -> String {
        let color = rgb(resource, traits)
        return [color.red, color.green, color.blue].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }
}
