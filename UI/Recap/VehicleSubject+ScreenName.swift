import Foundation
import KamomeExportEngine

extension VehicleSubject {
    /// The subject's name in **the language the rest of the screen is in**.
    ///
    /// The pickers used to pass `Locale.current.language.languageCode` — "zh" on
    /// a Traditional Chinese phone — while `vehicles.json` keys its names
    /// "zh-Hant", so every chip fell through to English on an otherwise Chinese
    /// screen (2026-09-26). The bundle's chosen localization is the key the
    /// string catalog itself resolves with, so the chip can never disagree with
    /// the labels around it.
    var screenName: String {
        screenName(localizations: Bundle.main.preferredLocalizations)
    }

    /// `screenName`, with the bundle's choice passed in so a test can pin it.
    func screenName(localizations: [String]) -> String {
        displayName(language: localizations.first ?? "en")
    }
}
