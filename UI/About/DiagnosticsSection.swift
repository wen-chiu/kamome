import SwiftUI
import UIKit

/// About's "Export diagnostics" row (ADR 2026-09-24 (d)): this launch's Kamome
/// log lines as a text file, shared by the tester's own hand. What is in the
/// file and why it holds no place: `DiagnosticsLog`.
struct DiagnosticsSection: View {
    @State private var file: SharedFile?
    @State private var failed = false

    var body: some View {
        Section {
            Button("about_export_diagnostics") {
                if let url = DiagnosticsLog.export() {
                    file = SharedFile(url: url)
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
        .sheet(item: $file) { file in
            ShareSheet(url: file.url)
        }
    }

    private struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private struct ShareSheet: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: [url], applicationActivities: nil)
        }

        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    }
}
