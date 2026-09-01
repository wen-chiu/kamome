import CoreGraphics
import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **Crop-scaling: one snapshot serves a run of frames by reprojection**
/// (`Docs/camera-arcs.md` §7).
///
/// The defect this replaces (`HANDOFF.md` 2026-08-30 finding 1, Chiu's P0):
/// between keyframes the loop alpha-blended two snapshots of the same map *at
/// two different geographic positions*, so every coastline and label appeared
/// twice, offset, cross-dissolving — the 殘影 — and snapped forward twice a
/// second — the 晃動. The workaround was to snapshot every frame wherever the
/// camera moves, which is why 91% of a crossing film's snapshot budget was
/// camera movement.
///
/// Both go away together, because both come from the same wrong operation.
/// Between two cameras the correct operation is not to blend, it is to
/// **reproject**: translate the picture, and scale it when the span changes.
/// A frame produced that way is geometrically *exact* — it is the same ground
/// the camera asks for, resampled — so there is no mismatch to bound, and the
/// only thing that degrades with distance from the snapshot is sharpness.
///
/// Which is why a station's length is budgeted in **zoom**, not in frames.
///
/// ## The invariant everything here rests on
///
/// > A station is correct for a frame exactly when the station's footprint
/// > **contains** that frame's footprint.
///
/// Contained means the frame is a sub-rectangle: every pixel it needs exists in
/// the station. Not contained means the frame would show ground the station
/// never held, and the honest answer is a new station — never a blank edge and
/// never a silent stretch (`Arch.md` §6).
public enum RecapSnapshotStations {
    /// One snapshot and the frames it serves.
    public struct Station: Equatable {
        /// What to hand the provider — the containing frame of `frames`.
        public let camera: CameraFrame
        public let map: MapState
        /// The film frames this station is reprojected onto.
        public let frames: Range<Int>

        public init(camera: CameraFrame, map: MapState, frames: Range<Int>) {
            self.camera = camera
            self.map = map
            self.frames = frames
        }
    }

    /// Plans the stations for a whole film.
    ///
    /// Greedy and pure: walk forward from the first unserved frame, extending the
    /// run while the containing frame stays within the magnification budget, then
    /// close the station and start again. Pure because it takes the camera and
    /// map as functions of time — it needs no provider, so the snapshot count of
    /// a film is measurable without rendering one.
    ///
    /// **Three things close a station**, and each is a correctness boundary
    /// rather than a tuning choice:
    ///
    /// - the budget: extending further would magnify some frame beyond
    ///   `snapshot_station_max_magnification`;
    /// - `MapState` changes — the snapshot is a function of it, so a station
    ///   cannot span two values of it;
    /// - a frame in `mustStartAt` — see `splitFrames`, which is how a parked stop
    ///   beat keeps its own station and therefore its own exact snapshot;
    /// - `bearing` changes — reprojection is a similarity transform and cannot
    ///   rotate. On the shipped path (`follow_heading_up: false`, and MapKit
    ///   declares `supportsBearing: false`) bearing is constant 0 and this never
    ///   fires. On a heading-up substrate it would fire every frame, which costs
    ///   exactly what fine-sampling costs today — correct, expensive, and
    ///   `bearingBreaks` reports it rather than letting it be a silent bill.
    public static func plan(
        frameCount: Int,
        fps: Int,
        camera: (Double) -> CameraFrame,
        map: (Double) -> MapState,
        mustStartAt: Set<Int> = [],
        config: TrackingConfig.Export
    ) -> [Station] {
        guard frameCount > 0, fps > 0 else { return [] }
        let budget = max(config.snapshotStationMaxMagnification, 1)
        let padding = max(config.snapshotStationPadding, 1)
        var stations: [Station] = []
        var start = 0
        while start < frameCount {
            let startMap = map(Double(start) / Double(fps))
            let startCamera = camera(Double(start) / Double(fps))
            var run = [Self.path(startCamera)]
            var containing = CameraPath.containingFrame(run, padding: 1, config: config)
            var end = start + 1
            while end < frameCount {
                let time = Double(end) / Double(fps)
                guard !mustStartAt.contains(end) else { break }
                let next = camera(time)
                guard map(time) == startMap, next.bearing == startCamera.bearing else { break }
                // **Padding only when the run actually unions two framings.**
                // A held camera is the property this whole loop must not lose:
                // the old value cache gave a parked stop beat a snapshot at
                // exactly its own frame, and the falsification pair measured 103
                // consecutive frames of *zero* difference because of it
                // (`Docs/handoff-cross-region-crossing.md` finding 3). Padding a
                // degenerate union would magnify a held frame by 3% for nothing
                // and put a soft map under every stop in the film.
                let candidate = run + [Self.path(next)]
                let unions = candidate.contains { $0 != candidate[0] }
                let extended = CameraPath.containingFrame(
                    candidate, padding: unions ? padding : 1, config: config
                )
                // The budget is measured against the *tightest* frame in the run:
                // that is the one magnified most, so it is the one that decides.
                let tightest = min(run.map(\.spanM).min() ?? next.spanM, next.spanM)
                guard tightest > 0, extended.spanM <= tightest * budget else { break }
                run.append(Self.path(next))
                containing = extended
                end += 1
            }
            stations.append(
                Station(camera: Self.waist(containing, bearing: startCamera.bearing),
                        map: startMap, frames: start..<end)
            )
            start = end
        }
        return stations
    }

    /// **Where a station must begin, so a stop beat is pixel-exact.**
    ///
    /// A station is sized to contain every frame it serves, so a station that
    /// spans both a travelling stretch and a parked one is wider than the parked
    /// frames need — and those are exactly the frames the film asks the viewer to
    /// *look* at, held still for seconds while a photo deck plays over them. The
    /// first crop-scaling render measured that as 0.585 mean difference during a
    /// stop beat where the old cross-fade scored 0.038, because a parked camera
    /// gets `previousKey == nextKey` and no blend at all.
    ///
    /// The fix is not a tighter global budget — that would pay for the stop beats
    /// everywhere in the film. It is to stop merging the two kinds of frame:
    ///
    /// - a station starts at each hold's **first** frame, and again at the frame
    ///   after its last, so a hold is never folded into a travelling run;
    /// - and again at the frame where the camera **settles** inside the hold. The
    ///   dead-zone dolly is still coasting when the hold opens (the 2026-08-30
    ///   pair saw it as a residue just after the beat began), so without this the
    ///   settle frames drag the whole hold's station wider.
    ///
    /// Everything after that settle point is one camera value, so its station is
    /// that value, magnified 1.0 — the identity, and the same pixels a snapshot
    /// taken at that frame would have given.
    ///
    /// **Threshold-free on purpose.** It would have been easy to write "a parked
    /// run longer than N frames earns a station" and to tune N. The holds are
    /// already a fact the story layer states (`CameraPath.holds`), and the settle
    /// point is *the last frame at which the camera changes* — measured, not
    /// chosen. A tunable here would be a number nobody could later justify.
    public static func splitFrames(
        holds: [CameraPath.Hold], frameCount: Int, fps: Int, camera: (Double) -> CameraFrame
    ) -> Set<Int> {
        guard frameCount > 0, fps > 0 else { return [] }
        var splits: Set<Int> = []
        for hold in holds {
            let first = max(Int((hold.startS * Double(fps)).rounded(.up)), 0)
            let last = min(Int((hold.endS * Double(fps)).rounded(.down)), frameCount - 1)
            guard first <= last else { continue }
            splits.insert(first)
            if last + 1 < frameCount { splits.insert(last + 1) }
            // The settle point: after this frame the camera does not move again
            // before the hold ends, so everything past it shares one value.
            var settled: Int?
            for frame in first..<last where camera(Double(frame) / Double(fps))
                != camera(Double(frame + 1) / Double(fps)) {
                settled = frame + 1
            }
            if let settled { splits.insert(settled) }
        }
        return splits
    }

    /// The camera math and the narrow waist name the same thing with two types
    /// (`CameraPath.CameraFrame` and `CameraFrame`). Converted here rather than
    /// unified: merging them is a refactor with no bug behind it, and it would
    /// touch every renderer (`Arch.md` §2).
    private static func path(_ frame: CameraFrame) -> CameraPath.CameraFrame {
        CameraPath.CameraFrame(
            centerLat: frame.centerLat, centerLon: frame.centerLon,
            spanM: frame.spanM, bearing: frame.bearing
        )
    }

    private static func waist(_ frame: CameraPath.CameraFrame, bearing: Double) -> CameraFrame {
        CameraFrame(
            centerLat: frame.centerLat, centerLon: frame.centerLon,
            spanM: frame.spanM, bearing: bearing
        )
    }

    /// How many stations were closed because the bearing changed — the cost of a
    /// heading-up substrate, named so it can never arrive silently.
    public static func bearingBreaks(_ stations: [Station], camera: (Double) -> CameraFrame, fps: Int) -> Int {
        guard fps > 0 else { return 0 }
        return zip(stations, stations.dropFirst()).count { previous, next in
            camera(Double(previous.frames.lowerBound) / Double(fps)).bearing
                != camera(Double(next.frames.lowerBound) / Double(fps)).bearing
        }
    }
}

/// **The transform that puts a station's picture where a frame's camera wants
/// it** — the whole of crop-scaling, in one similarity.
///
/// Everything is expressed in the frame's own pixel space, which is the space
/// `MapSnapshot.point` already answers in. That is deliberate: it is what makes
/// the ⚠️ 2026-08-28 addendum to `Docs/camera-arcs.md` §7 come out right without
/// a second multiply anywhere. The two corrections that addendum names are
/// already applied on either side of this type —
/// `MapKitSnapshotProvider.pixel(_:displayScale:)` moves `point(for:)` out of
/// the point canvas, and `CGContext.draw(_:in:)` resamples whatever raster
/// MapKit returned onto the frame — so composing a third one here would be the
/// bug, not the fix.
public struct SnapshotReprojection: Equatable {
    /// The station's pixels per frame pixel. **Always ≥ 1**: below 1 the station
    /// is tighter than the frame and does not contain it.
    public let magnification: Double
    /// Where the frame's camera centre falls in the station's pixel space.
    let anchor: CGPoint
    let widthPx: Double
    let heightPx: Double

    /// A station that cannot serve this frame. Its own error type because the
    /// only honest responses are "take another snapshot" or "stop" — never draw
    /// it anyway and leave an edge of nothing.
    public struct ContainmentError: Error, CustomStringConvertible {
        public let magnification: Double
        public let shortfallPx: Double

        public var description: String {
            String(
                format: "a station magnified %.3f× misses the frame by %.1f px — "
                    + "the station does not contain it", magnification, shortfallPx
            )
        }
    }

    /// Builds the transform from the station's **camera** and its own
    /// **projection** — one of each, and which job goes to which matters.
    ///
    /// - The **anchor** is measured, through `station.point`. That is what makes
    ///   the translation exact whatever the provider actually framed.
    /// - The **magnification** is the ratio of the two nominal spans, and it must
    ///   NOT be measured. This cost a rendered comparison to learn: MapKit fits
    ///   an `MKCoordinateRegion` to the canvas it was handed and generally comes
    ///   back a little wider than the metres it was asked for. Measuring the
    ///   station's true pixels-per-metre and dividing it into `widthPx /
    ///   target.spanM` prices the station's delivered scale against the target's
    ///   *requested* one, so the fitting factor does not cancel — it lands in the
    ///   answer as a constant zoom of the base map. The falsification render
    ///   showed it as a uniform 1.07 mean difference at magnification 1.0, where
    ///   the transform is supposed to be the identity: no temporal structure, the
    ///   whole map very slightly the wrong size.
    ///
    ///   Both cameras go through the same provider and therefore the same fitting
    ///   rule, so the ratio of the spans it was *asked* for is the ratio of the
    ///   scales it *delivers*, and the unknown factor cancels. The station serving
    ///   its own camera is then the identity exactly, which is the property that
    ///   keeps a held stop beat pixel-identical to snapshotting it.
    public init(
        station: MapSnapshot, stationCamera: CameraFrame, target: CameraFrame,
        widthPx: Int, heightPx: Int
    ) throws {
        guard station.image.width > 0, target.spanM > 0, stationCamera.spanM > 0 else {
            throw ContainmentError(magnification: 0, shortfallPx: .infinity)
        }
        magnification = stationCamera.spanM / target.spanM
        anchor = station.point(lat: target.centerLat, lon: target.centerLon)
        self.widthPx = Double(widthPx)
        self.heightPx = Double(heightPx)

        // Containment, checked rather than trusted: once placed, the station's
        // image must overhang the frame on all four sides. Slack is how many
        // pixels to spare the worst side has; negative is a frame that would show
        // ground the station never held.
        let destination = destinationRect
        let slack = min(
            -destination.minX, -destination.minY,
            destination.maxX - self.widthPx, destination.maxY - self.heightPx
        )
        // Half a pixel of tolerance, for a station that contains the frame
        // exactly — the single-frame station, where the two rects coincide.
        guard magnification.isFinite, magnification > 0, slack >= -0.5 else {
            throw ContainmentError(magnification: magnification, shortfallPx: max(-slack, 0))
        }
    }

    /// Where to draw the station's whole image so its contained sub-rectangle
    /// lands exactly on the frame. In `CGContext` coordinates (origin
    /// bottom-left), which is why the vertical term is flipped once here and
    /// nowhere else.
    public var destinationRect: CGRect {
        let scaled = CGSize(width: widthPx * magnification, height: heightPx * magnification)
        let originX = -anchor.x * magnification + widthPx / 2
        let topLeftY = -anchor.y * magnification + heightPx / 2
        return CGRect(
            x: originX, y: heightPx - (topLeftY + scaled.height),
            width: scaled.width, height: scaled.height
        )
    }

    /// A station-space point moved into the frame's space — the projection half
    /// of the same transform, so overlays land on the map they are drawn over
    /// instead of between two of them.
    public func map(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - anchor.x) * magnification + widthPx / 2,
            y: (point.y - anchor.y) * magnification + heightPx / 2
        )
    }
}
