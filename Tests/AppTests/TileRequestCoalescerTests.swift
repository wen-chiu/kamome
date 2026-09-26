@testable import Kamome
import XCTest

/// `TileRequestCoalescer` changes how many times a tile crosses the network and
/// never what MapLibre receives. These pin both halves against a stub server —
/// no real host is contacted.
final class TileRequestCoalescerTests: XCTestCase {
    /// A server that answers after a short delay, so a second ask can arrive
    /// while the first is still in flight, and counts what reached it.
    private final class StubServer: URLProtocol {
        struct Reply {
            var status = 200
            var headers: [String: String] = [:]
            var body = Data("tile".utf8)
            var failure: URLError?
        }

        private static let lock = NSLock()
        nonisolated(unsafe) private static var hits: [String] = []
        nonisolated(unsafe) static var reply = Reply()

        static func reset(_ reply: Reply = Reply()) {
            lock.withLock {
                hits = []
                self.reply = reply
            }
        }

        static var requests: [String] { lock.withLock { hits } }

        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let reply = Self.lock.withLock {
                Self.hits.append(request.value(forHTTPHeaderField: "If-None-Match") ?? "-")
                return Self.reply
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers
            )!
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
                if let failure = reply.failure {
                    client?.urlProtocol(self, didFailWithError: failure)
                    return
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: reply.body)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    private let vector = URL(string: "https://tiles.openfreemap.org/planet/v/1/2/3.pbf")!
    private let terrain = URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/1/2/3.png")!

    private func hub(memoryMb: Int = 8, terrainMaxAgeS: Int = 600) -> TileRequestCoalescer.Hub {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        let hub = TileRequestCoalescer.Hub(session: URLSession(configuration: configuration))
        hub.configure(terrainMaxAgeS: terrainMaxAgeS, hosts: ["openfreemap.org", "amazonaws.com"], memoryMb: memoryMb)
        return hub
    }

    /// Joins `requests` back to back and waits for every answer.
    private func answers(_ hub: TileRequestCoalescer.Hub, _ requests: [URLRequest]) -> [TileRequestCoalescer.Outcome] {
        var results: [Int: TileRequestCoalescer.Outcome] = [:]
        let lock = NSLock()
        let done = expectation(description: "answers")
        done.expectedFulfillmentCount = requests.count
        for (index, request) in requests.enumerated() {
            _ = hub.join(request) { outcome in
                lock.withLock { results[index] = outcome }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
        return (0..<requests.count).compactMap { results[$0] }
    }

    private func body(_ outcome: TileRequestCoalescer.Outcome) -> Data? {
        if case let .success(_, data) = outcome { return data }
        return nil
    }

    private func response(_ outcome: TileRequestCoalescer.Outcome) -> HTTPURLResponse? {
        if case let .success(response, _) = outcome { return response }
        return nil
    }

    // MARK: - Coalescing

    func testIdenticalAsksInFlightShareOneDownloadAndTheSameBytes() {
        StubServer.reset(.init(headers: ["Cache-Control": "max-age=60"], body: Data("the tile".utf8)))
        let hub = hub()
        let results = answers(hub, Array(repeating: URLRequest(url: vector), count: 5))
        XCTAssertEqual(StubServer.requests.count, 1, "five simultaneous asks must be one download")
        XCTAssertEqual(results.compactMap(body), Array(repeating: Data("the tile".utf8), count: 5))
        XCTAssertEqual(hub.read().downloads, 1)
        XCTAssertEqual(hub.read().joined, 4)
    }

    func testARevalidationNeverSharesADownloadWithAnAskThatNeedsTheBody() {
        StubServer.reset(.init(headers: ["Cache-Control": "max-age=60"]))
        var conditional = URLRequest(url: vector)
        conditional.setValue("\"abc\"", forHTTPHeaderField: "If-None-Match")
        _ = answers(hub(), [URLRequest(url: vector), conditional])
        XCTAssertEqual(StubServer.requests.sorted(), ["\"abc\"", "-"], "each must reach the server as asked")
    }

    /// A failed download reaches **every** asker as a failure, so the export
    /// fails as it did before (`TileFailureTests`) instead of waiting — and a
    /// failure is never remembered.
    func testAFailedDownloadFailsEveryWaiterAndIsNotRemembered() {
        StubServer.reset(.init(failure: URLError(.cannotFindHost)))
        let hub = hub()
        let results = answers(hub, Array(repeating: URLRequest(url: terrain), count: 3))
        XCTAssertEqual(results.count, 3)
        for result in results {
            guard case let .failure(error) = result else { return XCTFail("a failed download was handed on as a tile") }
            XCTAssertEqual((error as? URLError)?.code, .cannotFindHost)
        }
        StubServer.reset(.init(headers: ["Cache-Control": "max-age=60"]))
        _ = answers(hub, [URLRequest(url: terrain)])
        XCTAssertEqual(StubServer.requests.count, 1, "after a failure the next ask goes back to the network")
    }

    // MARK: - Remembering

    func testALaterAskIsAnsweredFromTheExportsOwnDownload() {
        StubServer.reset(.init(headers: ["Cache-Control": "max-age=60"], body: Data("kept".utf8)))
        let hub = hub()
        _ = answers(hub, [URLRequest(url: vector)])
        let later = answers(hub, [URLRequest(url: vector)])
        XCTAssertEqual(StubServer.requests.count, 1, "a landed tile must not be downloaded again")
        XCTAssertEqual(later.compactMap(body), [Data("kept".utf8)])
        XCTAssertEqual(hub.read().remembered, 1)
    }

    func testNothingIsRememberedWhenTheBudgetIsZero() {
        StubServer.reset(.init(headers: ["Cache-Control": "max-age=60"]))
        let hub = hub(memoryMb: 0)
        _ = answers(hub, [URLRequest(url: vector)])
        _ = answers(hub, [URLRequest(url: vector)])
        XCTAssertEqual(StubServer.requests.count, 2)
    }

    func testAResponseThatForbidsStorageIsNotRemembered() {
        StubServer.reset(.init(headers: ["Cache-Control": "no-store"]))
        let hub = hub()
        _ = answers(hub, [URLRequest(url: vector)])
        _ = answers(hub, [URLRequest(url: vector)])
        XCTAssertEqual(StubServer.requests.count, 2)
    }

    func testANewExportForgetsWhatTheLastOneDownloaded() {
        StubServer.reset(.init(headers: ["Cache-Control": "max-age=60"]))
        let hub = hub()
        _ = answers(hub, [URLRequest(url: vector)])
        hub.configure(terrainMaxAgeS: 600, hosts: ["openfreemap.org", "amazonaws.com"], memoryMb: 8)
        _ = answers(hub, [URLRequest(url: vector)])
        XCTAssertEqual(StubServer.requests.count, 2)
    }

    // MARK: - What MapLibre is handed

    func testTerrainWithNoLifetimeGetsOneAndKeepsItsBodyAndValidators() throws {
        StubServer.reset(.init(headers: ["ETag": "\"e\"", "Content-Encoding": "gzip"], body: Data("dem".utf8)))
        let hub = hub(terrainMaxAgeS: 600)
        let result = try XCTUnwrap(answers(hub, [URLRequest(url: terrain)]).first)
        let handed = try XCTUnwrap(response(result))
        XCTAssertEqual(handed.value(forHTTPHeaderField: "Cache-Control"), "max-age=600")
        XCTAssertEqual(handed.value(forHTTPHeaderField: "ETag"), "\"e\"")
        XCTAssertNil(handed.value(forHTTPHeaderField: "Content-Encoding"), "the body is already decoded")
        XCTAssertEqual(handed.statusCode, 200)
        XCTAssertEqual(body(result), Data("dem".utf8))
        XCTAssertEqual(hub.read().terrainAged, 1)
    }

    func testALifetimeTheServerSentIsNeverOverwritten() throws {
        StubServer.reset(.init(headers: ["Cache-Control": "max-age=315360000"]))
        let result = try XCTUnwrap(answers(hub(), [URLRequest(url: vector)]).first)
        XCTAssertEqual(response(result)?.value(forHTTPHeaderField: "Cache-Control"), "max-age=315360000")
        StubServer.reset(.init(headers: ["Cache-Control": "max-age=5"]))
        let dem = try XCTUnwrap(answers(hub(), [URLRequest(url: terrain)]).first)
        XCTAssertEqual(response(dem)?.value(forHTTPHeaderField: "Cache-Control"), "max-age=5")
    }

    func testTerrainLifetimeZeroLeavesTerrainAsTheServerSentIt() throws {
        StubServer.reset(.init(headers: ["ETag": "\"e\""]))
        let result = try XCTUnwrap(answers(hub(terrainMaxAgeS: 0), [URLRequest(url: terrain)]).first)
        XCTAssertNil(response(result)?.value(forHTTPHeaderField: "Cache-Control"))
    }

    // MARK: - Scope

    func testOnlyTheExportsTileHostsAreHandled() {
        let hub = hub()
        XCTAssertTrue(hub.handles(host: "tiles.openfreemap.org"))
        XCTAssertTrue(hub.handles(host: "s3.amazonaws.com"))
        XCTAssertFalse(hub.handles(host: "kamome-routing.kamome-site.workers.dev"))
        XCTAssertFalse(hub.handles(host: "evilopenfreemap.org"), "a suffix match must be on a label boundary")
        hub.configure(terrainMaxAgeS: 600, hosts: [], memoryMb: 8)
        XCTAssertFalse(hub.handles(host: "tiles.openfreemap.org"), "switched off, everything passes through")
    }
}
