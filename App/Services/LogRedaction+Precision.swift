import Foundation

extension LogRedaction {
    /// **Which precision each public `%.*f` was written with**, read off the
    /// system's own text (`LogRedaction`).
    ///
    /// `composedMessage` is matched piece by piece: each literal exactly, a
    /// public value as its own rendering, a public `%.*f` as one of its renderings
    /// at precision 0…`maxPrecision`, and any other value as any text — on a
    /// simulator that is the value itself, on a phone `<private>`. The first
    /// complete match names the precisions. No match leaves them unknown, and the
    /// number is written at the C default of six decimals. Nothing here is
    /// written out: only the precisions leave.
    struct PrecisionSearch {
        static let maxPrecision = 17

        private enum Matcher {
            case nothing
            case anyText
            case exactly([UInt16])
            case oneOf([(precision: Int, text: [UInt16])])
        }

        private let literals: [[UInt16]]
        private let matchers: [Matcher]
        private let searches: Bool
        private var text: [UInt16] = []
        private var failed = Set<Int>()
        private var found: [Int?]

        init(pieces: [Piece], specs: [Placeholder?]) {
            literals = pieces.map { Array($0.literal.replacingOccurrences(of: "%%", with: "%").utf16) }
            matchers = zip(pieces, specs).map { piece, spec in Self.matcher(piece.value, spec) }
            searches = matchers.contains { if case .oneOf = $0 { return true } else { return false } }
            found = Array(repeating: nil, count: pieces.count)
        }

        /// One entry per piece: the recovered precision, or nil.
        func precisions(in composed: String) -> [Int?] {
            guard searches else { return found }
            var search = self
            search.text = Array(composed.utf16)
            return search.match(0, at: 0) ? search.found : Array(repeating: nil, count: found.count)
        }

        private static func matcher(_ value: Piece.Value, _ spec: Placeholder?) -> Matcher {
            guard let spec else { return .nothing }
            guard spec.isPublic else { return .anyText }
            guard spec.hidesPrecision else { return .exactly(Array(spec.render(value, precision: nil).utf16)) }
            return .oneOf((0...maxPrecision).map { ($0, Array(spec.render(value, precision: $0).utf16)) })
        }

        private mutating func match(_ piece: Int, at position: Int) -> Bool {
            if piece == literals.count { return position == text.count }
            let key = piece * (text.count + 1) + position
            guard !failed.contains(key), starts(literals[piece], at: position) else { return false }
            let after = position + literals[piece].count
            if matchValue(piece, at: after) { return true }
            failed.insert(key)
            return false
        }

        private mutating func matchValue(_ piece: Int, at position: Int) -> Bool {
            switch matchers[piece] {
            case .nothing:
                return match(piece + 1, at: position)
            case .anyText:
                return (position...text.count).contains { match(piece + 1, at: $0) }
            case .exactly(let rendering):
                return starts(rendering, at: position) && match(piece + 1, at: position + rendering.count)
            case .oneOf(let renderings):
                for option in renderings
                where starts(option.text, at: position) && match(piece + 1, at: position + option.text.count) {
                    found[piece] = option.precision
                    return true
                }
                return false
            }
        }

        private func starts(_ part: [UInt16], at position: Int) -> Bool {
            position + part.count <= text.count && text[position..<(position + part.count)].elementsEqual(part)
        }
    }
}
