import KamomePersistence
import SwiftUI

/// The timeline's "Along the route" line: the photographs still on the trip,
/// and a tap opens the sheet where any of them is removed or put back.
struct RoutePhotosRow: View {
    let model: TripDetailModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                Text("route_photos_header")
                    .font(.headline)
                Spacer()
                PhotoStrip(photos: model.shownRoutePhotos, maxThumbnails: 3)
            }
        }
    }
}

/// Every photograph taken along the route on the selected day, and which of
/// them this trip keeps (Chiu 2026-10-09). Press and hold takes one off the
/// trip or puts it back; a removed one stays here, dimmed, so the removal can
/// be undone. Nothing in the photo library is touched.
struct RoutePhotosSheet: View {
    let model: TripDetailModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 4)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(model.routePhotos, id: \.id) { photo in
                            tile(photo)
                        }
                    }
                    .padding(.horizontal, 4)
                    Text("route_photos_hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
            .navigationTitle(Text("route_photos_header"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("route_photos_done") { dismiss() }
                }
            }
        }
    }

    private func tile(_ photo: PhotoRefRecord) -> some View {
        let removed = photo.isExcluded != 0
        // A square cell the thumbnail fills, as in the stop's photo picker.
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                PhotoThumbnail(assetId: photo.phAssetId, targetPx: 240)
                    .opacity(removed ? 0.35 : 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if removed {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 6))
            .contextMenu {
                if removed {
                    Button("route_photo_restore", systemImage: "arrow.uturn.backward") {
                        model.setRemovedFromTrip(photo, removed: false)
                    }
                } else {
                    Button("route_photo_remove", systemImage: "trash", role: .destructive) {
                        model.setRemovedFromTrip(photo, removed: true)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(removed ? "route_photo_a11y_removed" : "route_photo_a11y_kept"))
            .accessibilityAction(named: Text(removed ? "route_photo_restore" : "route_photo_remove")) {
                model.setRemovedFromTrip(photo, removed: !removed)
            }
    }
}
