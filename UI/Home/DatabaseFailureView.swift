import SwiftUI

/// **What the app shows instead of crashing when its trips cannot be opened**
/// (ADR 2026-10-08; Chiu: 「改成顯示錯誤畫面」).
///
/// The likeliest cause is a full phone, so the screen says what to try and
/// offers one button that tries again. It promises only what is true: Kamome
/// deleted nothing. It never offers to delete or reset the file — that would
/// trade someone's trips for a working app without asking what they wanted.
///
/// `code` is the error's `domain · code`, the same shape the export's failure
/// line shows, so a tester's screenshot names the cause.
struct DatabaseFailureView: View {
    let code: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("database_failed_title", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 12) {
                Text("database_failed_body")
                Text(verbatim: code)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button("database_failed_retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
