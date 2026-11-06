import Foundation
import OSLog

/// **A log line as it may leave the phone: only the values marked public**
/// (#366, Chiu 2026-11-05).
///
/// Whether `composedMessage` redacts depends on where the app runs: on the iOS
/// 26.5 simulator it returned `.private` values in full (VERIFIED, #366), while a
/// phone's diagnostics showed an unmarked string as `<private>` (VERIFIED, ADR
/// 2026-10-03-the-boarding-pass-names-its-countries-from-the-stops). So the
/// diagnostics and the kept export history never copy it. Each line is rebuilt
/// from its format string — the literal text between the values, and each
/// value's privacy as its call site wrote it — and a value is kept only when its
/// placeholder says `public`. Every other value reads `<private>`, **a number
/// too**: a count or a duration meant to be read is marked `.public` where it is
/// logged. The result is the same on a simulator and a phone.
///
/// The system keeps one thing back: the precision of `.fixed(precision:)`, which
/// `%.*f` passes as an argument it never returns. It is recovered by finding which
/// rendering of the public number itself appears in `composedMessage`. The text
/// written is always that number's own rendering, so a wrong match can change only
/// how many decimals a public number shows, never reveal another value.
enum LogRedaction {
    static let redacted = "<private>"

    /// One value and the text before it, as `OSLogMessageComponent` has them.
    struct Piece: Equatable {
        enum Value: Equatable {
            case string(String?)
            case signed(Int64)
            case unsigned(UInt64)
            case double(Double)
            case unreadable
        }

        /// The text before the value, as the format string has it (`%%` doubled).
        let literal: String
        /// `%{public}s`, `%ld`, `%{public}.*f`… — empty for the text after the last value.
        let placeholder: String
        let value: Value
    }

    /// `log`'s message with every value not marked public replaced by `<private>`.
    static func message(_ log: OSLogEntryLog) -> String {
        rebuild(format: log.formatString, pieces: log.components.map(Piece.init), composed: log.composedMessage)
    }

    /// Pure, so the rule is testable without a log store. `composed` is read only
    /// to recover a public number's precision.
    static func rebuild(format: String, pieces: [Piece], composed: String) -> String {
        // Never observed — a message without values still has its one trailing
        // piece. The format string holds no value, so it is what can be shown.
        guard !pieces.isEmpty else { return format }
        let specs = pieces.map { Placeholder($0.placeholder) }
        let precisions = PrecisionSearch(pieces: pieces, specs: specs).precisions(in: composed)
        return pieces.indices.map { index in
            let literal = pieces[index].literal.replacingOccurrences(of: "%%", with: "%")
            guard let spec = specs[index] else { return literal }
            return literal + (spec.isPublic ? spec.render(pieces[index].value, precision: precisions[index]) : redacted)
        }.joined()
    }
}

extension LogRedaction.Piece {
    init(_ component: OSLogMessageComponent) {
        let value: Value
        switch component.argumentCategory {
        case .string: value = .string(component.argumentStringValue)
        case .int64: value = .signed(component.argumentInt64Value)
        case .uInt64: value = .unsigned(component.argumentUInt64Value)
        case .double: value = .double(component.argumentDoubleValue)
        // `.undefined` is what a value the system redacted reads as (OSLog's
        // header); `.data` Kamome never logs.
        default: value = .unreadable
        }
        self.init(literal: component.formatSubstring, placeholder: component.placeholder, value: value)
    }
}

extension LogRedaction {
    /// One placeholder as the unified log writes it:
    /// `%` `{annotations}` flags width `.precision` length conversion.
    struct Placeholder {
        let annotations: Set<String>
        let flags: String
        /// Digits, `*` (an argument the reader never returns) or empty.
        let width: String
        /// nil for none; `*` (an argument the reader never returns) or digits.
        let precision: String?
        let conversion: Character?

        /// nil for an empty placeholder: the text after the last value.
        init?(_ placeholder: String) {
            guard !placeholder.isEmpty else { return nil }
            var rest = Substring(placeholder).drop { $0 == "%" }
            var annotations: Set<String> = []
            if rest.first == "{", let close = rest.firstIndex(of: "}") {
                annotations = Set(rest[rest.index(after: rest.startIndex)..<close]
                    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                rest = rest[rest.index(after: close)...]
            }
            self.annotations = annotations
            flags = String(rest.prefix { "-+ #0".contains($0) })
            rest = rest.dropFirst(flags.count)
            width = String(rest.prefix { $0 == "*" || $0.isASCII && $0.isNumber })
            rest = rest.dropFirst(width.count)
            if rest.first == "." {
                rest = rest.dropFirst()
                let digits = String(rest.prefix { $0 == "*" || $0.isASCII && $0.isNumber })
                precision = digits
                rest = rest.dropFirst(digits.count)
            } else {
                precision = nil
            }
            conversion = rest.drop { "hlLqjzt".contains($0) }.first
        }

        /// The whitelist: `public` named, nothing that narrows it.
        var isPublic: Bool {
            annotations.contains("public") && annotations.isDisjoint(with: ["private", "sensitive"])
        }

        /// A precision the unified log keeps to itself, which the search recovers.
        var hidesPrecision: Bool { precision == "*" }

        func render(_ value: Piece.Value, precision recovered: Int?) -> String {
            switch value {
            case .string(let text):
                return text ?? LogRedaction.redacted
            case .signed(let number):
                return word(number != 0) ?? integer(number, precision: recovered)
            case .unsigned(let number):
                return word(number != 0) ?? integer(number, precision: recovered)
            case .double(let number):
                guard let conversion, "fFeEgGaA".contains(conversion) else { return "\(number)" }
                return String(format: cFormat(length: "", precision: recovered), number)
            case .unreadable:
                return LogRedaction.redacted
            }
        }

        /// How the unified log spells a `Bool`.
        private func word(_ flag: Bool) -> String? {
            if annotations.contains("bool") { return flag ? "true" : "false" }
            if annotations.contains("BOOL") { return flag ? "YES" : "NO" }
            return nil
        }

        private func integer(_ number: some CVarArg & FixedWidthInteger, precision recovered: Int?) -> String {
            guard let conversion, "diouxX".contains(conversion) else { return "\(number)" }
            return String(format: cFormat(length: "ll", precision: recovered), number)
        }

        /// The placeholder as `String(format:)` reads it. A hidden width is
        /// dropped (Kamome aligns no value); a hidden precision takes `recovered`.
        private func cFormat(length: String, precision recovered: Int?) -> String {
            let shownWidth = width == "*" ? "" : width
            let shownPrecision: String
            switch precision {
            case nil: shownPrecision = ""
            case "*": shownPrecision = recovered.map { ".\($0)" } ?? ""
            case let digits?: shownPrecision = ".\(digits)"
            }
            return "%" + flags + shownWidth + shownPrecision + length + String(conversion ?? "s")
        }
    }
}
