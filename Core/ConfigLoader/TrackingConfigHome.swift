extension TrackingConfig {
    /// Home's 旅程 list (S1) (#295 item 1, ADR 2026-10-26-home-shows-a-newcomer-the-next-step).
    public struct Home: Decodable, Equatable {
        /// Up to this many trips, a line under the list says what to do next:
        /// below it the list fills enough of the screen to say so itself.
        public let nextStepMaxTrips: Int

        enum CodingKeys: String, CodingKey {
            case nextStepMaxTrips = "next_step_max_trips"
        }
    }
}
