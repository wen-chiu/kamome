import CoreGraphics
import KamomeConfig
import KamomePersistence
import Observation
import SwiftUI

/// A swipe's delete question: which row it asks about, and where that row is
/// on screen, so the dialog points at the row that was swiped. Home's
/// 「刪除旅程」 (#295 item 8, ADR 2026-10-28-home-asks-about-a-trip-at-its-row)
/// and Trip Detail's 「刪除地點」 (#326, Chiu 2026-10-29) both ask this way.
///
/// On iOS 26 a confirmation dialog is a popover whose arrow points at the view
/// it hangs on. Hung on the `List`, that is the whole list, and the arrow
/// pointed at the import button at its foot. Hung on the row, the dialog is
/// taken down as it appears, like #189's share sheet (VERIFIED 2026-10-28,
/// simulator). So each row only reports where it is, and the dialog hangs on a
/// clear view laid over the list at that spot (`confirmationDialog(_:isPresented:pointingAt:actions:)`).
@MainActor
@Observable
final class RowDeletionPrompt<Item: Identifiable> {
    /// The row being asked about; the dialog is up while this is set.
    var item: Item?
    /// Where that row is, in global coordinates. Nil only for a row that
    /// never reported, which a swiped row has; the dialog then hangs on the
    /// whole list, as it did before.
    private(set) var anchor: CGRect?
    /// Every row's place, kept out of observation: rows report on every scroll
    /// frame, and only the row being asked about should redraw anything.
    @ObservationIgnored private var rowFrames: [Item.ID: CGRect] = [:]

    func ask(about item: Item) {
        anchor = rowFrames[item.id]
        if anchor == nil {
            KamomeLog.storage.notice("delete confirmation: the swiped row never reported its place; pointing at the list")
        }
        self.item = item
    }

    /// The asked-about row can still move under the dialog — the list settling
    /// after the swipe — and the arrow follows it.
    func row(_ id: Item.ID, isAt frame: CGRect) {
        rowFrames[id] = frame
        if item?.id == id, anchor != frame { anchor = frame }
    }
}

/// Home's: a trip.
typealias TripDeletionPrompt = RowDeletionPrompt<TripRecord>

extension RowDeletionPrompt where Item == TripRecord {
    var trip: TripRecord? {
        get { item }
        set { item = newValue }
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
