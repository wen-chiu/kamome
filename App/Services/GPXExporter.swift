#if DEBUG
import Foundation
import KamomePersistence

/// Debug-only: serializes a stored trip back to GPX 1.1 in the same shape as
/// Tests/Fixtures (one <trk> per segment, <ele>/<time> per point, <wpt> per
/// stop), so a real drive can become a replay fixture directly.
enum GPXExporter {
    static func gpx(for detail: TripRepository.TripDetail) -> String {
        let formatter = ISO8601DateFormatter()
        func time(_ epoch: Double) -> String {
            formatter.string(from: Date(timeIntervalSince1970: epoch))
        }
        func escape(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"Kamome debug export\" xmlns=\"http://www.topografix.com/GPX/1/1\">",
            "  <metadata><name>\(escape(detail.trip.title))</name></metadata>"
        ]
        for stop in detail.stops {
            let name = escape(stop.name ?? "stop")
            lines.append(
                "  <wpt lat=\"\(stop.lat)\" lon=\"\(stop.lon)\">" +
                "<name>\(name)</name><time>\(time(stop.arrivedAt))</time></wpt>"
            )
        }
        for (segment, points) in detail.segments {
            lines.append("  <trk><name>\(escape(segment.mode))</name><trkseg>")
            for point in points {
                let ele = point.altitude.map { "<ele>\($0)</ele>" } ?? ""
                lines.append(
                    "    <trkpt lat=\"\(point.lat)\" lon=\"\(point.lon)\">" +
                    "\(ele)<time>\(time(point.ts))</time></trkpt>"
                )
            }
            lines.append("  </trkseg></trk>")
        }
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }
}
#endif
