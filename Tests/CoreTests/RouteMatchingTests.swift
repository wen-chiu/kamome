import KamomeConfig
@testable import KamomeRouteMatching
import XCTest

final class RouteMatchingTests: XCTestCase {
    // MARK: - Encoded polyline codec

    /// The worked example from Google's polyline-algorithm reference.
    func testDecodeGoogleReferenceExample() {
        let points = EncodedPolyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].lat, 38.5, accuracy: 1e-5)
        XCTAssertEqual(points[0].lon, -120.2, accuracy: 1e-5)
        XCTAssertEqual(points[1].lat, 40.7, accuracy: 1e-5)
        XCTAssertEqual(points[1].lon, -120.95, accuracy: 1e-5)
        XCTAssertEqual(points[2].lat, 43.252, accuracy: 1e-5)
        XCTAssertEqual(points[2].lon, -126.453, accuracy: 1e-5)
    }

    func testEncodeDecodeRoundTripAtPrecision5() {
        let original = [
            GeoPoint(lat: -31.9523, lon: 115.8613),  // Perth
            GeoPoint(lat: -33.9548, lon: 115.0630),  // Margaret River
            GeoPoint(lat: 24.1477, lon: 120.6736)   // Taichung
        ]
        let decoded = EncodedPolyline.decode(EncodedPolyline.encode(original))
        XCTAssertEqual(decoded.count, original.count)
        for (expected, actual) in zip(original, decoded) {
            XCTAssertEqual(expected.lat, actual.lat, accuracy: 1e-5)
            XCTAssertEqual(expected.lon, actual.lon, accuracy: 1e-5)
        }
    }

    // MARK: - OSRM provider (recorded responses, no live server)

    private let matchingConfig = TrackingConfig.Matching(
        baseURL: "http://127.0.0.1:5000",
        chunkSize: 100,
        confidenceMin: 0.5,
        radiusM: 25,
        timeoutS: 10,
        displayEpsilonM: 5
    )

    private func trace(count: Int) -> [RouteMatchPoint] {
        (0..<count).map {
            RouteMatchPoint(ts: 1_752_600_000 + Double($0 * 5), lat: -32.0 + Double($0) * 0.001, lon: 115.75, hAccM: 12)
        }
    }

    private func okBody(confidence: Double, geometry: [GeoPoint]) -> Data {
        let json: [String: Any] = [
            "code": "Ok",
            "matchings": [["confidence": confidence, "geometry": EncodedPolyline.encode(geometry)]]
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func httpOK(_ url: URL?) -> URLResponse {
        HTTPURLResponse(url: url ?? URL(fileURLWithPath: "/"), statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    func testConfidentMatchReturnsSnappedGeometryAndRequestCarriesTunables() async throws {
        let snapped = [GeoPoint(lat: -32.0, lon: 115.751), GeoPoint(lat: -31.95, lon: 115.752)]
        let seenURL = Locked<URL?>(nil)
        let provider = OSRMMatchProvider(config: matchingConfig) { request in
            seenURL.set(request.url)
            return (self.okBody(confidence: 0.92, geometry: snapped), self.httpOK(request.url))
        }

        let outcome = try await provider.match(trace(count: 3))
        XCTAssertEqual(outcome?.geometry, snapped)
        XCTAssertEqual(outcome?.confidence ?? 0, 0.92, accuracy: 1e-9)

        let url = try XCTUnwrap(seenURL.get()?.absoluteString)
        XCTAssertTrue(url.hasPrefix("http://127.0.0.1:5000/match/v1/driving/"))
        XCTAssertTrue(url.contains("geometries=polyline"))
        XCTAssertTrue(url.contains("tidy=true"))
        XCTAssertTrue(url.contains("timestamps=1752600000;1752600005;1752600010"))
        // h_acc 12 m is under the 25 m floor → floor wins.
        XCTAssertTrue(url.contains("radiuses=25;25;25"))
    }

    func testLowConfidenceFallsBackToNil() async throws {
        let provider = OSRMMatchProvider(config: matchingConfig) { request in
            (self.okBody(confidence: 0.2, geometry: [GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 1, lon: 1)]),
             self.httpOK(request.url))
        }
        let outcome = try await provider.match(trace(count: 3))
        XCTAssertNil(outcome, "confidence 0.2 < confidence_min 0.5 must keep raw geometry")
    }

    func testNoMatchResponseIsCleanFallbackNotError() async throws {
        let provider = OSRMMatchProvider(config: matchingConfig) { request in
            let body = try JSONSerialization.data(withJSONObject: ["code": "NoMatch"])
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil
            )!
            return (body, http)
        }
        let outcome = try await provider.match(trace(count: 3))
        XCTAssertNil(outcome)
    }

    func testLongTraceIsChunkedAndGeometriesStitched() async throws {
        let requestCount = Locked(0)
        let provider = OSRMMatchProvider(config: matchingConfig) { request in
            let index = requestCount.increment()
            // Each chunk answers with a 2-point stroke keyed to its order.
            let base = Double(index)
            let geometry = [GeoPoint(lat: base, lon: 0), GeoPoint(lat: base + 0.5, lon: 0)]
            return (self.okBody(confidence: 0.9, geometry: geometry), self.httpOK(request.url))
        }

        // 250 points → chunks of 100/100/50.
        let outcome = try await provider.match(trace(count: 250))
        XCTAssertEqual(requestCount.get(), 3)
        XCTAssertEqual(outcome?.geometry.count, 6, "three chunk geometries concatenate in order")
        XCTAssertEqual(outcome?.geometry.first?.lat, 1.0)
        XCTAssertEqual(outcome?.geometry.last?.lat, 3.5)
    }

    func testEmptyBaseURLDisablesMatchingWithoutNetwork() async throws {
        let disabled = TrackingConfig.Matching(
            baseURL: "", chunkSize: 100, confidenceMin: 0.5, radiusM: 25, timeoutS: 10, displayEpsilonM: 5
        )
        let provider = OSRMMatchProvider(config: disabled) { _ in
            XCTFail("disabled matching must never touch the transport")
            throw URLError(.badURL)
        }
        let outcome = try await provider.match(trace(count: 3))
        XCTAssertNil(outcome)
    }
}

/// Minimal thread-safe box: the transport closure is @Sendable, so test
/// observation has to be lock-protected.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }
}

extension Locked where Value == Int {
    /// Returns the incremented value.
    @discardableResult
    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
