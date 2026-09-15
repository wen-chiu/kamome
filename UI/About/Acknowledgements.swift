import SwiftUI

/// One third-party package linked into the app, and the licence text it obliges
/// the app to reproduce (ADR 2026-09-12 (c)).
///
/// **The obligation is the text itself, not a link to it.** GRDB is MIT, which
/// requires its notice in every copy of the software; MapLibre Native is
/// BSD-2-Clause, which requires a binary redistribution to reproduce its notice
/// in the materials provided with it. Both are linked into every `Kamome.app`, and
/// until 2026-09-12 neither text appeared anywhere in it.
///
/// Distinct from `AboutView`'s attribution rows: those are data-provider
/// attributions (Geoapify, OpenStreetMap), owed for what the app *fetches*; these
/// are software licences, owed for what the app *contains*.
struct Acknowledgement: Identifiable {
    /// The package's identity in `Package.resolved`, and the resource name of its
    /// bundled licence text — `Scripts/release/check-attribution.sh` pairs the
    /// three by this string.
    let id: String
    let name: String
    let version: String
    let licence: String

    /// Every package `Package.resolved` pins, one line each.
    ///
    /// ⚠️ **Keep each entry on one line.** `check-attribution.sh` fails when a pin
    /// has no line naming both its identity and its pinned version, so a
    /// dependency cannot be added — or bumped, the moment a licence text can
    /// change — without this list and the bundled text being revisited with it.
    static let all: [Acknowledgement] = [
        Acknowledgement(id: "grdb.swift", name: "GRDB.swift", version: "6.29.3", licence: "MIT"),
        Acknowledgement(id: "maplibre-gl-native-distribution", name: "MapLibre Native", version: "6.27.0", licence: "BSD-2-Clause")
    ]

    /// The licence, verbatim, from `App/Resources/Acknowledgements/<id>.txt` in the
    /// built bundle. Nil only if the build lost the file, which
    /// `AcknowledgementsTests` fails on.
    var text: String? {
        Bundle.main.url(forResource: id, withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

/// One package's licence, verbatim. Monospaced and selectable: it is a legal text
/// a reader may want to copy, not copy to be styled.
struct LicenceTextView: View {
    let acknowledgement: Acknowledgement

    var body: some View {
        ScrollView {
            Text(verbatim: acknowledgement.text ?? "")
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(Text(verbatim: acknowledgement.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}
