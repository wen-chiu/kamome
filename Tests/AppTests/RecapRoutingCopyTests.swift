import XCTest

/// The routing notice's copy, read the way the screen reads it.
///
/// Moved out of `LocalizationTests` when the English strings became plural
/// entries (#181): a plural entry's stored value is the placeholder
/// `%#@value@`, not a sentence, so a rule about what the sentence says has to
/// be checked on the sentence — formatted with a leg count, as
/// `RecapRoutingNotice` formats it — or it passes on an empty read.
final class RecapRoutingCopyTests: XCTestCase {
    /// One leg and several: the two forms English has.
    private static let legCounts = [1, 5]

    private func sentence(_ key: String, locale: String, legs: Int) throws -> String {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: locale, ofType: "lproj"),
            "\(locale).lproj missing from app bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        let sentence = String.localizedStringWithFormat(
            bundle.localizedString(forKey: key, value: nil, table: nil), legs
        )
        XCTAssertFalse(sentence.contains("%"), "\(key) [\(locale)] left a placeholder unformatted: \(sentence)")
        return sentence
    }

    /// Only the time-budget case is Kamome's fault and may promise a retry.
    /// Connection, rate-limit, and no-road are someone else's — they state the
    /// situation and stop. Both languages must agree, for one leg and for several.
    func testRoutingCopyPromisesARetryOnlyWhereKamomeIsAtFault() throws {
        // Matched loosely on purpose: the copy will be reworded, and the rule
        // has to survive the rewording. Any phrasing that tells the user to
        // export again counts.
        func promisesRetry(_ key: String, legs: Int) throws -> (en: Bool, zh: Bool) {
            let english = try sentence(key, locale: "en", legs: legs).lowercased()
            let chinese = try sentence(key, locale: "zh-Hant", legs: legs)
            let en = english.contains("export again") || english.contains("try again")
            let zh = ["再輸出", "重新輸出", "再試", "重試"].contains { chinese.contains($0) }
            return (en, zh)
        }

        for legs in Self.legCounts {
            for key in ["recap_routing_unreachable_detail", "recap_routing_rate_limited_detail",
                        "recap_routing_no_road_detail"] {
                let promise = try promisesRetry(key, legs: legs)
                XCTAssertFalse(
                    promise.en || promise.zh,
                    "\(key) promises a retry Kamome cannot keep — that outcome is not ours to fix"
                )
            }

            // Ours, so it may promise — and must promise in both languages or neither.
            let budget = try promisesRetry("recap_routing_budget_detail", legs: legs)
            XCTAssertTrue(budget.en, "the budget case is Kamome's own limit and should offer the retry")
            XCTAssertEqual(
                budget.en, budget.zh,
                "a retry promise in one language and not the other is a defect, not a translation choice"
            )
        }
    }

    /// The count belongs to the headline in every case, so a missing specifier
    /// would silently print a headline with no number in it.
    func testEveryRoutingHeadlineCarriesTheLegCount() throws {
        for key in ["recap_routing_unreachable", "recap_routing_rate_limited",
                    "recap_routing_budget", "recap_routing_no_road"] {
            for locale in ["en", "zh-Hant"] {
                for legs in Self.legCounts {
                    let headline = try sentence(key, locale: locale, legs: legs)
                    XCTAssertTrue(
                        headline.contains("\(legs)"), "\(key) [\(locale)] must name how many legs: \(headline)"
                    )
                }
            }
        }
    }

    /// "1 legs have no road" (#181): English counts one leg as one leg, in the
    /// four headlines and in the one body that repeats the count.
    func testOneLegIsSingularInEnglish() throws {
        for key in ["recap_routing_unreachable", "recap_routing_rate_limited",
                    "recap_routing_budget", "recap_routing_no_road", "recap_routing_rate_limited_detail"] {
            let one = try sentence(key, locale: "en", legs: 1)
            let several = try sentence(key, locale: "en", legs: 5)
            for plural in ["legs", "stretches"] {
                XCTAssertFalse(one.contains(plural), "\(key) counts one leg as several: \(one)")
            }
            XCTAssertTrue(several.contains("legs") || several.contains("stretches"), several)
        }
    }
}
