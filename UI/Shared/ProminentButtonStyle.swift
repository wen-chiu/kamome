import SwiftUI

/// The filled button: the system's `.borderedProminent`, with its label in
/// `OnAccent` — white in light mode, deep teal `#0B2E33` in dark (ADR
/// 2026-10-26-text-and-controls-take-a-deeper-teal, #294). The dark accent
/// `#42C5D6` is too light for white type (2.06 : 1); the dark label reads
/// 7.01 : 1 on it. Light mode is unchanged: white on `#1B727E` is 5.59 : 1.
///
/// A disabled button keeps the system's own label, so it still reads as
/// disabled rather than as white on grey.
struct ProminentButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProminentButton(configuration: configuration)
    }
}

private struct ProminentButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(role: configuration.role, action: configuration.trigger) {
            if isEnabled {
                configuration.label.foregroundStyle(Color(.onAccent))
            } else {
                configuration.label
            }
        }
        .buttonStyle(.borderedProminent)
    }
}

extension PrimitiveButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
}
