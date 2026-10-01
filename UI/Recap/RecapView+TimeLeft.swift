import Foundation

// The drawing stage's one line of text, kept beside `RecapView` rather than in
// it so the view stays inside SwiftLint's file and type-body limits.
extension RecapView {
    /// "42%", then "42% · About 5 minutes left" once the export has drawn long
    /// enough to know its own pace (Chiu 2026-09-30, issue #151). Before the
    /// warm-up the percentage stands alone: a guess at second ten would be
    /// off several-fold (`RecapExportTimeLeft`).
    static func drawingProgress(_ fraction: Double, timeLeft: RecapExportTimeLeft.Reading?) -> String {
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        guard let timeLeft else { return percent }
        let left: String
        switch timeLeft {
        case let .minutes(minutes):
            left = String.localizedStringWithFormat(String(localized: "recap_time_left_minutes"), minutes)
        case .underAMinute:
            left = String(localized: "recap_time_left_under_minute")
        }
        return "\(percent) · \(left)"
    }
}
