import Foundation
import KamomeConfig
import KamomeExportEngine

// The rendering and finished screens' own shots, kept beside `RecapView` so the
// view stays inside SwiftLint's file and type-body limits.
extension RecapView {
    #if DEBUG
    /// Once per launch, so Export again returns to the form and stays there.
    @MainActor private static var didStartDemoExport = false
    #endif

    /// Demo screenshot automation: with `-demo-open-recap`, `-demo-start-export`
    /// starts the film without a tap, and `-demo-no-photo-cards` starts it
    /// without cards — the demo trips' photos dangle, so only a film without
    /// them finishes with nothing to report. Debug builds only.
    @MainActor
    static func startDemoExportIfAsked(_ model: RecapModel, _ appearance: RecapAppearance, _ length: FilmLength?) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard !didStartDemoExport, case .idle = model.phase, arguments.contains("-demo-start-export") else { return }
        didStartDemoExport = true
        if arguments.contains("-demo-no-photo-cards") { model.photosEnabled = false }
        model.startExport(appearance: appearance, length: length ?? FilmLengthChoice.current())
        #endif
    }
}
