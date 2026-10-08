import SwiftUI
import UIKit

/// **A segment's glyph and its word, drawn as one image** (Chiu 2026-10-07).
/// A segmented control shows an image or a title, never both: a `Text` with
/// an `Image` in it lost the glyph, and a glyph alone left the page unnamed
/// once the large title went. A template image carries both and still takes
/// the control's own selected and unselected colours.
enum SegmentLabelImage {
    /// Drawn in the text style the control would use, at the person's current
    /// text size; the caller redraws when that size changes.
    static func make(symbol: String, title: String, textStyle: UIFont.TextStyle = .subheadline) -> UIImage {
        let base = UIFont.preferredFont(forTextStyle: textStyle)
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: .medium)
        let text = NSMutableAttributedString()
        if let glyph = UIImage(
            systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: font, scale: .small)
        ) {
            text.append(NSAttributedString(attachment: NSTextAttachment(image: glyph)))
            text.append(NSAttributedString(string: " "))
        }
        text.append(NSAttributedString(string: title))
        text.addAttributes([.font: font, .foregroundColor: UIColor.black], range: NSRange(location: 0, length: text.length))
        let size = text.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        ).integral.size
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            text.draw(with: CGRect(origin: .zero, size: size), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
