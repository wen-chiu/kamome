import KamomePersistence

/// Taking a route photograph off this trip (Chiu 2026-10-09). "Removed" is the
/// photograph's existing `is_excluded` mark, not a deleted row: a re-match
/// rebuilds `photo_ref` and carries the mark across, where a deleted row would
/// come straight back. The photo library is never written. Footprints still
/// shows every route photograph — Chiu's call: only this screen hides them.
extension TripDetailModel {
    /// The route photographs the timeline strip shows: `routePhotos` without
    /// the removed ones. The sheet lists all of them, so a removal can be undone.
    var shownRoutePhotos: [PhotoRefRecord] {
        routePhotos.filter { $0.isExcluded == 0 }
    }

    func setRemovedFromTrip(_ photo: PhotoRefRecord, removed: Bool) {
        Stored.write("setPhotoFilmChoice") {
            try repository.setPhotoFilmChoice(photoId: photo.id, choice: removed ? .excluded : .auto)
        }
        reload()
    }
}
