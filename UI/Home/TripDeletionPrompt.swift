import CoreGraphics
import KamomeConfig
import KamomePersistence
import Observation
import SwiftUI

/// Home's 「刪除旅程」 question: which trip it asks about, and where that trip's
/// row is on screen, so the dialog points at the row that was swiped (#295
/// item 8, Chiu 2026-10-28; ADR 2026-10-28-home-asks-about-a-trip-at-its-row).
///
/// On iOS 26 a confirmation dialog is a popover whose arrow points at the view
/// it hangs on. Hung on the `List`, that is the whole list, and the arrow
/// pointed at the import button at its foot. Hung on the row, the dialog is
/// taken down as it appears, like #189's share sheet (VERIFIED 2026-10-28,
/// simulator). So each row only reports where it is, and the dialog hangs on a
/// clear view laid over the list at that spot (`confirmationDialog(_:isPresented:pointingAt:actions:)`).
@MainActor
@Observable
final class TripDeletionPrompt {
    /// The trip being asked about; the dialog is up while this is set.
    var trip: TripRecord?
    /// Where that trip's row is, in global coordinates. Nil only for a row that
    /// never reported, which a swiped row has; the dialog then hangs on the
    /// whole list, as it did before.
    private(set) var anchor: CGRect?
    /// Every row's place, kept out of observation: rows report on every scroll
    /// frame, and only the row being asked about should redraw anything.
    @ObservationIgnored private var rowFrames: [TripRecord.ID: CGRect] = [:]

    func ask(about trip: TripRecord) {
        anchor = rowFrames[trip.id]
        if anchor == nil {
            KamomeLog.storage.notice("delete confirmation: the swiped row never reported its place; pointing at the list")
        }
        self.trip = trip
    }

    /// The asked-about row can still move under the dialog — the list settling
    /// after the swipe — and the arrow follows it.
    func row(_ id: TripRecord.ID, isAt frame: CGRect) {
        rowFrames[id] = frame
        if trip?.id == id, anchor != frame { anchor = frame }
    }
}

extension View {
    /// `confirmationDialog`, hung on a clear view laid over this one at
    /// `anchor` (global coordinates), so iOS 26's popover points there rather
    /// than at the whole view. A nil anchor hangs it on the whole view.
    func confirmationDialog<Actions: View>(
        _ title: LocalizedStringKey, isPresented: Binding<Bool>, pointingAt anchor: CGRect?,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        overlay {
            GeometryReader { proxy in
                let container = proxy.frame(in: .global)
                let spot = (anchor ?? container).offsetBy(dx: -container.minX, dy: -container.minY)
                Color.clear
                    .frame(width: spot.width, height: spot.height)
                    .confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible, actions: actions)
                    .position(x: spot.midX, y: spot.midY)
            }
            .allowsHitTesting(false)
        }
    }
}
