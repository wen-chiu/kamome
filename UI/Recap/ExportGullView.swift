import SwiftUI
import UIKit

/// The gull as the export form's first section while rendering, on the form's
/// own background rather than a card.
struct ExportGullSection: View {
    let progress: Double?

    var body: some View {
        Section { ExportGullView(progress: progress) }
            .listRowBackground(Color.clear)
    }
}

/// **The wait has a gull in it** (Chiu 2026-10-03). The app icon come alive:
/// the brand's double-arc gull over a dotted route between three stops, filling
/// the screen the export's settings fold away from.
///
/// Two signals, kept apart. **The wings always beat**, so a slow export and a
/// frozen screen stop looking alike. **Where the gull is** is the export's own
/// frame progress — the number the bar beneath it shows — and nothing else:
/// before the first frame (roads, photos) it waits over the first stop, and it
/// never runs ahead of the bar. A beating wing says the app is alive, not that
/// the render is; only the position says that.
///
/// Decorative: the bar carries the number for VoiceOver. With Reduce Motion the
/// wings hold the brand pose.
///
/// **Cost: no app code runs per display frame.** The main queue is not free
/// during a render — `MapLibreSnapshotProvider` drives its snapshotter there —
/// so the flap is a Core Animation keyframe animation, interpolated by the
/// render server, not a SwiftUI animation evaluated on the main actor. The
/// gull and route move only when progress does (~10/s,
/// `RecapExportJob.progressInterval`), and without easing: one step is a
/// fraction of a point.
struct ExportGullView: View {
    /// Frames drawn, 0…1; nil before the drawing stage.
    let progress: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 190
    private static let maxWidth: CGFloat = 340
    private static let gullSize = CGSize(width: 70, height: 58)
    /// How far above the route the gull flies, in points.
    private static let altitude: CGFloat = 44
    private static let flapPeriodS = 0.8
    /// Tilt follows the route's slope, but never further than this.
    private static let maxTilt = Angle.degrees(7)
    private static let dotSpacing: CGFloat = 11

    var body: some View {
        GeometryReader { geometry in
            let route = GullRoute(size: geometry.size)
            let travelled = min(max(progress ?? 0, 0), 1)
            let place = route.place(at: travelled)
            ZStack(alignment: .topLeading) {
                routeCanvas(route, travelled: travelled)
                GullFlap(beats: !reduceMotion, periodS: Self.flapPeriodS)
                    .frame(width: Self.gullSize.width, height: Self.gullSize.height)
                    .rotationEffect(clampedTilt(place.slope))
                    .position(x: place.point.x, y: place.point.y - Self.altitude)
            }
        }
        .frame(maxWidth: Self.maxWidth)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// The dotted route and its three stops: behind the gull in the tint, ahead
    /// of it faint. Redrawn when progress moves, never per flap.
    private func routeCanvas(_ route: GullRoute, travelled: Double) -> some View {
        Canvas { context, _ in
            let reached = route.length * travelled
            var distance: CGFloat = 0
            while distance <= route.length {
                let point = route.place(at: distance / route.length).point
                let dot = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
                let behind = distance <= reached
                context.fill(dot, with: behind ? .style(TintShapeStyle.tint) : .style(HierarchicalShapeStyle.tertiary))
                distance += Self.dotSpacing
            }
            for stop in [0.0, 0.5, 1.0] {
                let point = route.place(at: stop).point
                let disc = Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
                if stop <= travelled {
                    context.fill(disc, with: .style(TintShapeStyle.tint))
                } else {
                    context.fill(disc, with: .style(BackgroundStyle.background))
                    context.stroke(disc, with: .style(HierarchicalShapeStyle.tertiary), lineWidth: 2)
                }
            }
        }
    }

    private func clampedTilt(_ slope: Angle) -> Angle {
        .radians(min(max(slope.radians, -Self.maxTilt.radians), Self.maxTilt.radians))
    }
}

/// The route the gull flies: the icon's dotted smile — dipping past the middle
/// stop and rising to the last — sampled once so a fraction is a fraction of
/// its *length*, and the gull's pace matches the bar's.
private struct GullRoute {
    struct Place {
        let point: CGPoint
        let slope: Angle
    }

    private static let samples = 64
    private let points: [CGPoint]
    private let cumulative: [CGFloat]

    var length: CGFloat { cumulative.last ?? 0 }

    init(size: CGSize) {
        func at(_ across: CGFloat, _ down: CGFloat) -> CGPoint { CGPoint(x: across * size.width, y: down * size.height) }
        // Endpoints inset by half a gull, so the bird is never clipped.
        let start = at(0.11, 0.80), control1 = at(0.38, 0.97), control2 = at(0.64, 0.98), end = at(0.89, 0.66)
        let sampled = (0...Self.samples).map { index in
            let along = CGFloat(index) / CGFloat(Self.samples)
            let rest = 1 - along
            let first = rest * rest * rest, second = 3 * rest * rest * along
            let third = 3 * rest * along * along, fourth = along * along * along
            return CGPoint(
                x: first * start.x + second * control1.x + third * control2.x + fourth * end.x,
                y: first * start.y + second * control1.y + third * control2.y + fourth * end.y
            )
        }
        var running: CGFloat = 0
        cumulative = sampled.indices.map { index in
            if index > 0 { running += hypot(sampled[index].x - sampled[index - 1].x, sampled[index].y - sampled[index - 1].y) }
            return running
        }
        points = sampled
    }

    func place(at fraction: Double) -> Place {
        guard length > 0 else { return Place(point: points.first ?? .zero, slope: .zero) }
        let target = length * CGFloat(min(max(fraction, 0), 1))
        let upper = max(1, cumulative.firstIndex { $0 >= target } ?? cumulative.count - 1)
        let (from, to) = (points[upper - 1], points[upper])
        let span = cumulative[upper] - cumulative[upper - 1]
        let along = span > 0 ? (target - cumulative[upper - 1]) / span : 0
        return Place(
            point: CGPoint(x: from.x + (to.x - from.x) * along, y: from.y + (to.y - from.y) * along),
            slope: .radians(atan2(to.y - from.y, to.x - from.x))
        )
    }
}

/// The beating wings, as a layer the render server animates: one
/// `CAKeyframeAnimation` over the path, built when the size or the setting
/// changes and never touched again while it runs.
private struct GullFlap: UIViewRepresentable {
    let beats: Bool
    let periodS: Double

    func makeUIView(context: Context) -> GullFlapView { GullFlapView() }

    func updateUIView(_ view: GullFlapView, context: Context) {
        view.configure(beats: beats, periodS: periodS)
    }
}

private final class GullFlapView: UIView {
    /// Path keyframes per beat; the render server interpolates between them.
    private static let keyframes = 24
    private static let maxFps: Float = 30
    private let gull = CAShapeLayer()
    private var beats = false
    private var periodS = 1.0
    private var builtSize: CGSize?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        gull.fillColor = nil
        gull.lineCap = .round
        gull.lineJoin = .round
        layer.addSublayer(gull)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(beats: Bool, periodS: Double) {
        guard beats != self.beats || periodS != self.periodS else { return }
        (self.beats, self.periodS) = (beats, periodS)
        rebuild()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != builtSize { rebuild() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        rebuild()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        gull.strokeColor = tintColor.cgColor
    }

    private func rebuild() {
        builtSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gull.frame = bounds
        gull.strokeColor = tintColor.cgColor
        gull.lineWidth = GullPose.strokeWidth(in: bounds.size)
        gull.path = GullPose.path(phase: 0, in: bounds)
        CATransaction.commit()
        gull.removeAnimation(forKey: "flap")
        guard beats, window != nil, !bounds.isEmpty else { return }
        let flap = CAKeyframeAnimation(keyPath: "path")
        flap.values = (0...Self.keyframes).map { GullPose.path(phase: Double($0) / Double(Self.keyframes), in: bounds) }
        flap.duration = periodS
        flap.repeatCount = .infinity
        flap.isRemovedOnCompletion = false
        // A wingbeat reads at 30 fps; ProMotion's 120 would composite four times the frames for nothing.
        flap.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: Self.maxFps, preferred: Self.maxFps)
        gull.add(flap, forKey: "flap")
    }
}

/// The brand gull (`VehicleMarker.seagull`'s double arc, in its SVG units:
/// wingtips at (±20, 5), head at (0, −2)) with its wings beating. `phase` runs
/// 0 → 1 once per beat; the pose eases between the brand's own shape, wings up
/// and wings down, and the body lifts a little on the downstroke. At phase 0
/// it *is* the brand mark, which is what Reduce Motion shows.
///
/// A copy of the path, not a call into `ExportEngine`: that one is a
/// `CGContext` drawing for the film and must not be restyled in place
/// (`HANDOFF.md`), and this one must be free to move.
private enum GullPose {
    /// One wing, in SVG units; the other is its mirror.
    private struct Pose {
        let tip: CGPoint
        let outer: CGPoint
        let inner: CGPoint

        func mixed(with other: Pose, _ amount: Double) -> Pose {
            func lerp(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
                CGPoint(x: lhs.x + (rhs.x - lhs.x) * amount, y: lhs.y + (rhs.y - lhs.y) * amount)
            }
            return Pose(tip: lerp(tip, other.tip), outer: lerp(outer, other.outer), inner: lerp(inner, other.inner))
        }
    }

    private static let brand = Pose(tip: CGPoint(x: 20, y: 5), outer: CGPoint(x: 11, y: -11), inner: CGPoint(x: 5, y: -11))
    private static let wingsUp = Pose(tip: CGPoint(x: 16, y: -14), outer: CGPoint(x: 12, y: -13), inner: CGPoint(x: 5, y: -9))
    private static let wingsDown = Pose(tip: CGPoint(x: 18, y: 12), outer: CGPoint(x: 12, y: -7), inner: CGPoint(x: 5, y: -9))
    /// The SVG box the bird and its lift fit in: ±22 wide, −19…17 tall.
    private static let box = CGRect(x: -22, y: -19, width: 44, height: 36)
    private static let lift = 2.0
    private static let head = CGPoint(x: 0, y: -2)

    static func strokeWidth(in size: CGSize) -> CGFloat {
        6.5 * min(size.width / box.width, size.height / box.height)
    }

    static func path(phase: Double, in rect: CGRect) -> CGPath {
        let beat = sin(2 * .pi * phase)
        let pose = beat >= 0 ? brand.mixed(with: wingsUp, beat) : brand.mixed(with: wingsDown, -beat)
        let bodyY = -lift * max(-beat, 0)
        let scale = min(rect.width / box.width, rect.height / box.height)
        func point(_ svg: CGPoint, mirrored: Bool = false) -> CGPoint {
            CGPoint(
                x: rect.midX + ((mirrored ? -svg.x : svg.x) - box.midX) * scale,
                y: rect.midY + (svg.y + bodyY - box.midY) * scale
            )
        }
        let path = CGMutablePath()
        path.move(to: point(pose.tip, mirrored: true))
        path.addCurve(
            to: point(head),
            control1: point(pose.outer, mirrored: true), control2: point(pose.inner, mirrored: true)
        )
        path.addCurve(to: point(pose.tip), control1: point(pose.inner), control2: point(pose.outer))
        return path
    }
}
