# What a tester shares keeps only the values marked public

**Status:** Decided (Chiu, 2026-11-05, #366)
**Supersedes:** nothing. It changes how the diagnostics of ledger 2026-09-24 (d) and the export history of 2026-09-27 are written, not what they hold.

## Context
VERIFIED (iOS 26.5 simulator, Debug, no debugger, #366): `OSLogEntryLog.composedMessage` returned `.private` and unmarked values in full, and `ExportLogHistory` wrote it into `export-history.txt`, which About → Export diagnostics shares. An export's private error text can carry a tile URL, and z/x/y is a place (§0). VERIFIED (Chiu's phone, ADR 2026-10-03-the-boarding-pass-names-its-countries-from-the-stops): a phone showed an unmarked string as `<private>`, and its D2/D3 numbers (`render cost`, unmarked) in full. So what the file held depended on the device.

VERIFIED (simulator probe, 2026-11-05): `formatString` keeps each placeholder's privacy (`%{public}s`, `%s`, `%{private}s`, `%{bool,public}d`), and `components` give one value per placeholder with the text before it. The one thing withheld is a `.fixed(precision:)` precision (`%.*f` passes it as an argument the reader never returns).

## Decision
Chiu (#366): "fix at the desk before 1.0, without relying on what iOS does. The kept export history and the shared diagnostics redact every value not marked `.public` themselves, before writing, so the result is the same on a simulator and a phone."

- **A whitelist.** `LogRedaction` rebuilds each line from its components: the literal text, a value only where its placeholder names `public`, and `<private>` for every other value, **numbers included**. No pattern guesses what a coordinate looks like.
- **A public number's precision** is recovered by finding which of its own renderings appears in `composedMessage`. The text written is always that number's rendering, so a wrong match can change only its decimals, never reveal another value; with no match it is written at six decimals.
- **Counts and durations are marked `.public` at their call sites** (91 values), so the phone's file says what it said before. Every string and error stays private.
- **The file written before this** (`export-history.txt`) is deleted unread; the history is now `export-history-redacted.txt`.

## Rejected
- **Trusting the system's redaction on a phone:** the simulator does not redact, and Chiu chose not to rely on iOS.
- **Treating unmarked numbers as public, the system's own default:** it is not "every value not marked `.public`", and an unmarked `.latitude` would be shown.
- **Finding coordinates in `composedMessage` with a pattern:** a blacklist misses a shape nobody foresaw.

## Consequences
- `DiagnosticsLog.Line(_:)` reads `LogRedaction.message`; `DiagnosticsRedactionTests` pins the rule (red on the simulator before it).
- **A number logged without `privacy: .public` reads `<private>`** in a tester's file. A log line meant to be read marks each count and duration.
- A tester loses at most `kept_export_logs` (20) earlier exports once, the first time the new build opens diagnostics or exports.
- Owed: the same check on a TestFlight (Release) build, `Docs/device-runbook.md` §D (#112). VERIFIED on the simulator only.
