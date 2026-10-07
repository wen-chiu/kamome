import SwiftUI

/// **Letter-spacing and italics are Latin habits** (2026-10-07). A tracked,
/// upper-cased date reads as a small-caps label in English; in Chinese the
/// same tracking only spreads 「8月3日」 apart, and `.italic()` slants hanzi
/// that have no italic, which reads as a rendering fault. Both are kept for
/// Latin-script languages and dropped elsewhere.
enum ScriptTypography {
    /// The language the app is showing — its strings', not the phone's region.
    static let isLatin: Bool = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return isLatin(language: language)
    }()

    /// Languages Kamome may be read in that are not written in Latin script.
    static func isLatin(language: String) -> Bool {
        !["zh", "ja", "ko"].contains { language.hasPrefix($0) }
    }
}

/// Tracked upper case for a Latin-script label; the plain text otherwise.
struct SmallCaps: ViewModifier {
    let tracking: CGFloat

    func body(content: Content) -> some View {
        if ScriptTypography.isLatin {
            content.tracking(tracking).textCase(.uppercase)
        } else {
            content
        }
    }
}
