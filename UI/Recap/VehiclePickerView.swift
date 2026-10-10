import KamomeExportEngine
import SwiftUI

/// The export sheet's vehicle row: what the film draws, one tap from changing
/// it (Chiu 2026-10-09). The row replaces the sideways chip strip; the choice
/// itself is `VehiclePickerView`, pushed inside the sheet.
struct VehicleRow: View {
    let model: RecapModel

    var body: some View {
        NavigationLink {
            VehiclePickerView(model: model)
        } label: {
            LabeledContent {
                if let subject = VehicleCatalog.subject(id: model.vehicleId) {
                    HStack(spacing: 6) {
                        VehicleThumbnail(id: subject.id, size: 24)
                        Text(subject.screenName)
                    }
                }
            } label: {
                Text("recap_vehicle_header")
            }
        }
    }
}

/// Every vehicle the film can draw, as a grid in groups (`VehiclePickerLayout`).
///
/// A tap chooses; the screen stays, so the choice is seen landing and a tile
/// with styles can show them. Back returns to the sheet — there is no Done,
/// because there is nothing to confirm: the choice is already written.
struct VehiclePickerView: View {
    let model: RecapModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        let layout = VehiclePickerLayout(subjects: model.pickableSubjects)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(layout.groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: group.title))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(group.tiles) { tile in
                                tileButton(tile)
                            }
                        }
                        // The styles of the chosen tile, under its own group —
                        // only once that tile is chosen, so the grid stays one
                        // decision deep until a second one is wanted.
                        if let tile = group.tiles.first(where: { $0.variants.count > 1 && $0.contains(model.vehicleId) }) {
                            styleRow(tile)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("recap_vehicle_header")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One tile. A tile with styles chooses its first style when it is not
    /// already chosen, and keeps the chosen style when it is.
    private func tileButton(_ tile: VehiclePickerLayout.Tile) -> some View {
        let isSelected = tile.contains(model.vehicleId)
        let shown = tile.variants.first { $0.id == model.vehicleId } ?? tile.variants[0]
        let name = tile.familyName.map { String(localized: $0) } ?? shown.screenName
        return Button {
            if !isSelected { withAnimation(.snappy) { model.chooseVehicle(tile.variants[0].id) } }
        } label: {
            VStack(spacing: 6) {
                VehicleThumbnail(id: shown.id, size: 52)
                Text(verbatim: name)
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if tile.variants.count > 1 {
                    Text(String.localizedStringWithFormat(
                        String(localized: "vehicle_style_count"), tile.variants.count
                    ))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The chosen tile's styles, each by its full name.
    private func styleRow(_ tile: VehiclePickerLayout.Tile) -> some View {
        HStack(spacing: 8) {
            ForEach(tile.variants, id: \.id) { subject in
                let isSelected = subject.id == model.vehicleId
                Button {
                    withAnimation(.snappy) { model.chooseVehicle(subject.id) }
                } label: {
                    HStack(spacing: 6) {
                        VehicleThumbnail(id: subject.id, size: 26)
                        Text(subject.screenName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemGroupedBackground),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .transition(.opacity)
    }
}

/// A subject's picker thumbnail. A subject with no thumbnail yet shows nothing
/// here, deliberately not a grey box or a "missing image" glyph: those read as
/// broken, and this is not broken — the set works in a film and simply has no
/// picture yet. Its name still says what it is.
struct VehicleThumbnail: View {
    let id: String
    let size: CGFloat

    var body: some View {
        if let thumbnail = VehicleCatalog.thumbnail(id: id) {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}
