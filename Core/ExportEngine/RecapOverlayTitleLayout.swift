import CoreGraphics
import Foundation

/// How the trip's name sits on the title and end cards: one line, or two.
///
/// **A name the person typed can be long** (trip rename, Chiu 2026-09-27). One
/// line scaled to fit put a 30-character name *under* the 40 px date line —
/// read as a caption, not a title. So a name shrinks as before only down to
/// `RecapStyle.titleMinFontPx`; past that it takes two lines of even width.
/// Text in a film is on screen for seconds, so it is never cut off: a name
/// that needs more than two lines at the floor keeps shrinking across two.
struct RecapTitleLayout: Equatable {
    let lines: [String]
    let fontPx: CGFloat
}

extension RecapOverlayRenderer {
    func titleLayout(_ title: String, maxWidth: CGFloat, in surface: RenderSurface) -> RecapTitleLayout {
        let preferred = style.titleFontPx
        let oneLine = fittedFontPx(title, preferred: preferred, maxWidth: maxWidth, in: surface)
        guard oneLine < style.titleMinFontPx, let split = evenSplit(title, fontPx: preferred, in: surface) else {
            return RecapTitleLayout(lines: [title], fontPx: oneLine)
        }
        let widest = max(
            textWidth(split.0, fontPx: preferred, in: surface),
            textWidth(split.1, fontPx: preferred, in: surface)
        )
        return RecapTitleLayout(lines: [split.0, split.1], fontPx: min(preferred, preferred * maxWidth / widest))
    }

    /// The block's height in pixels: one line's size plus a line advance per
    /// extra line.
    func titleBlockHeight(_ layout: RecapTitleLayout, in surface: RenderSurface) -> CGFloat {
        let size = layout.fontPx * surface.scale
        return size + size * style.titleLineSpacing * CGFloat(layout.lines.count - 1)
    }

    /// Draws the block with its bottom edge at `bottomY`, lines centred. One
    /// line lands exactly where the single-line title always did.
    func drawTitleBlock(
        _ layout: RecapTitleLayout, centerX: CGFloat, bottomY: CGFloat, in surface: RenderSurface
    ) {
        let size = layout.fontPx * surface.scale
        let top = bottomY + titleBlockHeight(layout, in: surface)
        for (index, line) in layout.lines.enumerated() {
            let lineBottom = top - size - size * style.titleLineSpacing * CGFloat(index)
            drawCenteredText(
                line, centerX: centerX, baselineY: lineBottom + size * 0.22,
                fontPx: layout.fontPx, color: style.chromeTitleColor, in: surface
            )
        }
    }

    /// The break that makes the two lines most nearly equal in width, nil when
    /// the name has nowhere it may break.
    private func evenSplit(_ title: String, fontPx: CGFloat, in surface: RenderSurface) -> (String, String)? {
        struct Candidate { let first: String, second: String, widest: CGFloat }
        let characters = Array(title)
        var best: Candidate?
        for index in 1..<max(characters.count, 1) where Self.mayBreak(before: index, in: characters) {
            let first = String(characters[..<index]).trimmingCharacters(in: .whitespaces)
            let second = String(characters[index...]).trimmingCharacters(in: .whitespaces)
            guard !first.isEmpty, !second.isEmpty else { continue }
            let widest = max(
                textWidth(first, fontPx: fontPx, in: surface),
                textWidth(second, fontPx: fontPx, in: surface)
            )
            if widest < best?.widest ?? .infinity { best = Candidate(first: first, second: second, widest: widest) }
        }
        return best.map { ($0.first, $0.second) }
    }

    /// Latin breaks after a space; Chinese, Japanese and Korean between any two
    /// characters — except that no line starts with closing punctuation or ends
    /// with an opening mark.
    static func mayBreak(before index: Int, in characters: [Character]) -> Bool {
        let previous = characters[index - 1]
        let next = characters[index]
        if previous.isWhitespace { return true }
        if next.isWhitespace { return false }
        if Self.closing.contains(next) || Self.opening.contains(previous) { return false }
        return isCJK(previous) || isCJK(next)
    }

    private static let closing: Set<Character> = Set("，。、：；！？）」』》〉】,.:;!?)]}…")
    private static let opening: Set<Character> = Set("（「『《〈【([{")

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF: true
            default: false
            }
        }
    }
}
