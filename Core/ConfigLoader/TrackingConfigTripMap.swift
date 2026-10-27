extension TrackingConfig {
    /// Trip Detail's map (S3), which frames the trip itself (#295 item 5,
    /// ADR 2026-10-26-the-in-app-map-draws-the-road-it-names).
    public struct TripMap: Decodable, Equatable {
        /// The frame's span over the extent of what the map draws — its lines
        /// and its stop pins. Above 1 so a pin at the edge is not cut in half.
        public let framePadding: Double
        /// The narrowest frame, for a trip whose stops are all in one place: a
        /// single stop would otherwise be framed at the street's own width.
        public let frameMinSpanM: Double

        enum CodingKeys: String, CodingKey {
            case framePadding = "frame_padding"
            case frameMinSpanM = "frame_min_span_m"
        }
    }
}
