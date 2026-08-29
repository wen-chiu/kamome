import CoreGraphics
@testable import Kamome
import KamomeExportEngine

/// **The style a review render draws with — one rule, one place**, the same way
/// `ReviewSubstrate` is the one place that answers which base map it draws on.
///
/// Written as a shared type on purpose. The two review harnesses each built their
/// own `RecapStyle.modernMinimal` line, and the last session's finding 6 is what
/// that habit costs: a rule stated twice gets corrected once. Here the rule is
/// *"a review still is the film the app would render, plus exactly the overrides
/// the reviewer asked for"*, and both harnesses get it from this function.
///
/// The two overrides exist for the 2026-08-28 batch and answer questions that are
/// Chiu's, not the code's:
///
/// - `KAMOME_ROUTE_COLOR` — which orange the light base's trail takes. The dashed
///   leg follows automatically, because `modernMinimal(_:)` derives it; that is
///   the point of the sweep, since an inferred leg is a provenance claim and
///   cannot be judged apart from the solid one it weakens.
/// - `KAMOME_ROUTE_GLOW_ALPHA` — 0 vs 0.32 on the dark base. `a58942d` retired
///   the glow *because the base was light*, so dark reopens it.
///
/// Neither touches `Config/TrackingConfig.json` or `RecapStyle`, so a value tried
/// for one still can never be committed by accident. An unparseable value is
/// refused rather than ignored, for `ReviewSubstrate`'s reason: a render that
/// quietly used a different colour than the reviewer asked for looks exactly like
/// one that honoured it.
enum ReviewPalette {
    /// The shipped preset for `appearance`, plus the review overrides, announced
    /// on the console so a still is never judged against a value nobody rendered.
    static func style(_ appearance: RecapAppearance) throws -> RecapStyle {
        var style = RecapStyle.modernMinimal(appearance)

        if let raw = HarnessEnv.value("KAMOME_ROUTE_COLOR") {
            style.routeColor = try color(raw)
            // Re-derived here for the same reason `modernMinimal(_:)` derives it:
            // the dashed leg is the same claim made weaker, so it can never be
            // left behind pointing at the colour the trail used to be.
            style.routeInferredColor = style.routeColor.copy(alpha: RecapStyle.routeInferredAlpha)
                ?? style.routeColor
        }

        if let raw = HarnessEnv.value("KAMOME_ROUTE_INFERRED_ALPHA") {
            guard let alpha = Double(raw), (0...1).contains(alpha) else {
                throw HarnessError("KAMOME_ROUTE_INFERRED_ALPHA=\(raw) is not an alpha between 0 and 1")
            }
            // Applied *after* the derivation above, so it overrides the product
            // rule's alpha without breaking the rule's shape: the dashed leg is
            // still the trail's own hue, just a different amount of it. This is
            // the one lever the 2026-08-29 separation question turns on — see
            // `HANDOFF.md` finding 8.
            style.routeInferredColor = style.routeColor.copy(alpha: CGFloat(alpha)) ?? style.routeColor
        }

        if let raw = HarnessEnv.value("KAMOME_ROUTE_GLOW_ALPHA") {
            guard let alpha = Double(raw), (0...1).contains(alpha) else {
                throw HarnessError("KAMOME_ROUTE_GLOW_ALPHA=\(raw) is not an alpha between 0 and 1")
            }
            // Applied to whatever colour the preset holds for this appearance —
            // on dark that is `retiredGlowColor`, so alpha is genuinely the only
            // variable in the A/B and the pass restored is the one Chiu once
            // accepted, not a different blue.
            style.routeGlowColor = style.routeGlowColor.copy(alpha: CGFloat(alpha)) ?? style.routeGlowColor
        }

        print("KAMOME_REVIEW palette \(appearance.rawValue)"
            + " · trail \(describe(style.routeColor))"
            + " · dashed \(describe(style.routeInferredColor))"
            + " · glow alpha \(style.routeGlowColor.alpha) x\(style.routeGlowWidthMultiple)")
        return style
    }

    /// `#RRGGBB`, or three comma-separated 0…1 components — the form `RecapStyle`
    /// itself is written in, so a candidate can be pasted either way round.
    private static func color(_ raw: String) throws -> CGColor {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") {
            let digits = String(text.dropFirst())
            guard digits.count == 6, let packed = UInt32(digits, radix: 16) else {
                throw HarnessError("KAMOME_ROUTE_COLOR=\(raw) is not a #RRGGBB hex colour")
            }
            return CGColor(
                srgbRed: CGFloat((packed >> 16) & 0xFF) / 255,
                green: CGFloat((packed >> 8) & 0xFF) / 255,
                blue: CGFloat(packed & 0xFF) / 255,
                alpha: 1
            )
        }
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3, parts.allSatisfy({ (0...1).contains($0) }) else {
            throw HarnessError(
                "KAMOME_ROUTE_COLOR=\(raw) is neither #RRGGBB nor three 0-1 components (e.g. 0.95,0.55,0.32)"
            )
        }
        return CGColor(srgbRed: parts[0], green: parts[1], blue: parts[2], alpha: 1)
    }

    /// The rendered colour as both forms, so the console line can be pasted back
    /// into either `RecapStyle` or the next `KAMOME_ROUTE_COLOR`.
    static func describe(_ color: CGColor) -> String {
        guard let components = color.components, components.count >= 3 else { return "\(color)" }
        let floats = components.prefix(3).map { String(format: "%.3f", $0) }.joined(separator: ",")
        return "#\(hex(color)) (\(floats)) @\(String(format: "%.2f", color.alpha))"
    }

    private static func hex(_ color: CGColor) -> String {
        guard let components = color.components, components.count >= 3 else { return "unknown" }
        return components.prefix(3)
            .map { String(format: "%02X", Int((max(0, min(1, $0)) * 255).rounded())) }
            .joined()
    }

    /// A filename fragment naming what varies, so a colour sweep writing into one
    /// output directory cannot overwrite itself — the rule `RecapReviewScene`
    /// already applies to the subject and its size.
    ///
    /// Taken from the **resolved** style rather than from the raw environment
    /// string, so `#FF8A5B` and `1,0.541,0.357` cannot produce two differently
    /// named stills of the same colour.
    static func variantSuffix(_ style: RecapStyle) -> String {
        var parts: [String] = []
        if HarnessEnv.value("KAMOME_ROUTE_COLOR") != nil {
            parts.append("trail\(hex(style.routeColor))")
        }
        if HarnessEnv.value("KAMOME_ROUTE_INFERRED_ALPHA") != nil {
            parts.append("dash\(String(format: "%.2f", style.routeInferredColor.alpha))")
        }
        if HarnessEnv.value("KAMOME_ROUTE_GLOW_ALPHA") != nil {
            parts.append("glow\(String(format: "%.2f", style.routeGlowColor.alpha))")
        }
        if HarnessEnv.value("KAMOME_FORCE_FALLBACK_MARKER") != nil { parts.append("fallback") }
        return parts.joined(separator: "-")
    }
}
