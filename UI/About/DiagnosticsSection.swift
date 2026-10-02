import SwiftUI
import UIKit

/// About's "Export diagnostics" row (ADR 2026-09-24 (d)): this launch's Kamome
/// log lines as a text file, shared by the tester's own hand. What is in the
/// file and why it holds no place: `DiagnosticsLog`.
///
/// **The share sheet is presented by `AboutView`, not from this row** (#189).
/// Hung on the `Section` it was applied to every row in it, and hung on the
/// button it was still inside a `List` row: on iOS 26 the sheet appeared and
/// was taken down within a second, the first way taking About with it. The
/// row only says which file to share; `diagnosticsShareSheet` puts the sheet
/// on the list itself, where Home's debug menu has always had its own.
struct DiagnosticsSection: View {
    @Binding var file: DiagnosticsFile?
    @State private var failed = false

    var body: some View {
        Section {
            Button("about_export_diagnostics") {
                if let url = DiagnosticsLog.export() {
                    failed = false
                    file = DiagnosticsFile(url: url)
                } else {
                    failed = true
                }
            }
            if failed {
                Text("about_export_diagnostics_failed")
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("about_export_diagnostics_note")
        }
    }
}

/// The exported log, waiting to be shared.
struct DiagnosticsFile: Identifiable {
    let url: URL
    var id: URL { url }
}

extension View {
    /// The system share sheet for an exported diagnostics file. Goes on the
    /// screen's own content, never inside a `List` row (#189).
    func diagnosticsShareSheet(_ file: Binding<DiagnosticsFile?>) -> some View {
        sheet(item: file) { file in
            DiagnosticsShareSheet(url: file.url)
        }
    }
}

private struct DiagnosticsShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
