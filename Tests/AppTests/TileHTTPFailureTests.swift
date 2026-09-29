#if canImport(MapLibre)
import Foundation
@testable import Kamome
import MapLibre
import Network
import XCTest

/// **Failure paths 4 and 5 of `RecapExportJob+Render.snapshotProvider`, measured**
/// (#125). `TileFailureTests` covers a host that cannot be reached; these cover
/// one that answers badly, and one that stops answering partway.
///
/// The vector tile source of the frozen dark style is pointed at a loopback
/// server in this process, which answers each tile request as the case says.
/// Sprites, glyphs and terrain still come from their real hosts, so the
/// `healthy` control is what says the failures below are the server's doing.
final class TileHTTPFailureTests: XCTestCase {
    /// The control: a server that answers every tile with an empty (valid) tile.
    func testAHealthyTileServerSnapshotsSuccessfully() async throws {
        let server = try TileServer { _, _ in .ok }
        defer { server.stop() }
        let outcome = try await snapshot(server: server, sizePx: 512)
        XCTAssertFalse(outcome.timedOut, "the control never finished: \(outcome)")
        XCTAssertNotNil(outcome.image, "the control failed, so the failures below prove nothing: \(outcome)")
        XCTAssertGreaterThan(server.tileRequests.count, 0, "the style never asked the loopback server for a tile")
    }

    /// Path 4: the host is reachable and answers 503.
    func testTileHost5xxIsAnErrorNotABlankFilm() async throws {
        let server = try TileServer { _, _ in .status(503) }
        defer { server.stop() }
        let outcome = try await snapshot(server: server, sizePx: 512)
        print("TILE_HTTP 503: \(outcome)")
        XCTAssertGreaterThan(server.tileRequests.count, 0)
        assertFailed(outcome, "a 503 tile host produced an image")
    }

    /// Path 4, the other half: a rate limit.
    func testTileHostRateLimitIsAnErrorNotABlankFilm() async throws {
        let server = try TileServer { _, _ in .status(429) }
        defer { server.stop() }
        let outcome = try await snapshot(server: server, sizePx: 512)
        print("TILE_HTTP 429: \(outcome)")
        XCTAssertGreaterThan(server.tileRequests.count, 0)
        assertFailed(outcome, "a 429 tile host produced an image")
    }

    /// Path 5: the first tile of a frame arrives, the others are refused.
    func testSomeTilesFailingWithinOneFrame() async throws {
        let server = try TileServer { index, _ in index < 1 ? .ok : .status(503) }
        defer { server.stop() }
        let outcome = try await snapshot(server: server, sizePx: 1_024)
        print("TILE_HTTP partial: \(outcome) requests=\(server.tileRequests.map(\.description))")
        XCTAssertGreaterThan(server.tileRequests.count, 1, "the frame needed no more than the one tile served")
        assertFailed(outcome, "a frame with refused tiles came back as an image")
    }

    /// Path 5, as written: the network drops during the export. The first
    /// tiles are served, every later request has its connection cut.
    func testTheNetworkDroppingAfterSomeTiles() async throws {
        let server = try TileServer { index, _ in index < 2 ? .ok : .drop }
        defer { server.stop() }
        let outcome = try await snapshot(server: server, sizePx: 1_024)
        print("TILE_HTTP drop: \(outcome) requests=\(server.tileRequests.count)")
        XCTAssertGreaterThan(server.tileRequests.count, 2, "the frame needed no more than the tiles served")
        assertFailed(outcome, "a frame with dropped tiles came back as an image")
    }

    /// Path 5's own wording: "renders cached tiles and leaves unfetched areas
    /// transparent". One tile is fetched and cached; the host then goes down; a
    /// wider frame needs that cached tile and its neighbours.
    func testACachedTileDoesNotHideAFailingNeighbour() async throws {
        let up = ServerSwitch()
        let server = try TileServer { _, _ in up.isUp ? .ok : .status(503) }
        defer { server.stop() }
        let first = try await snapshot(server: server, sizePx: 64)
        XCTAssertNotNil(first.image, "the warm-up frame failed: \(first)")
        let warmed = server.tileRequests.count

        up.isUp = false
        let second = try await snapshot(server: server, sizePx: 1_024)
        print("TILE_HTTP cached+down: \(second) warm=\(warmed) total=\(server.tileRequests.count)")
        XCTAssertGreaterThan(server.tileRequests.count, warmed, "the wider frame needed no new tile")
        assertFailed(second, "cached tiles hid a failing neighbour: the film would carry blank patches")
    }

    /// An error, promptly: not an image, and not a snapshotter that never answered.
    private func assertFailed(_ outcome: Outcome, _ message: String, line: UInt = #line) {
        XCTAssertFalse(outcome.timedOut, "\(outcome)", line: line)
        XCTAssertNil(outcome.image, message, line: line)
        XCTAssertEqual(outcome.error?.domain, "MLNErrorDomain", line: line)
        XCTAssertEqual(outcome.error?.code, 6, line: line)
    }

    // MARK: - Snapshot

    static let timeoutS = 40.0

    private struct Outcome: CustomStringConvertible {
        let image: MLNMapSnapshot?
        let error: NSError?
        var timedOut = false
        var description: String {
            if timedOut { return "no answer in \(TileHTTPFailureTests.timeoutS) s" }
            return image != nil ? "image" : "error \(error?.domain ?? "?") \(error?.code ?? 0)"
        }
    }

    private func snapshot(server: TileServer, sizePx: Int) async throws -> Outcome {
        let styleURL = try style(pointingAt: server)
        let camera = MLNMapCamera()
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
        let options = MLNMapSnapshotOptions(
            styleURL: styleURL, camera: camera, size: CGSize(width: sizePx, height: sizePx)
        )
        options.zoomLevel = 10
        options.scale = 1
        // Answered once, by whichever comes first: the snapshotter or the clock. A
        // snapshot that never completes must fail the test, not hang the run.
        let box = OnceBox<Outcome>()
        return await withCheckedContinuation { continuation in
            box.onValue = { continuation.resume(returning: $0) }
            DispatchQueue.main.async {
                let snapshotter = MLNMapSnapshotter(options: options)
                let lease = MapLibreSnapshotProvider.snapshotters.hold(snapshotter)
                snapshotter.start { image, error in
                    MapLibreSnapshotProvider.snapshotters.end(lease)
                    box.put(Outcome(image: image, error: error as NSError?))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutS) {
                box.put(Outcome(image: nil, error: nil, timedOut: true))
            }
        }
    }

    private func style(pointingAt server: TileServer) throws -> URL {
        let name = "openfreemap-liberty-dark"
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"))
        let json = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(
            of: "\"https://tiles.openfreemap.org/planet\"",
            with: "\"http://127.0.0.1:\(server.port)/planet\""
        )
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-test-http-\(server.port).json")
        try json.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}

private final class OnceBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    var onValue: ((Value) -> Void)?
    func put(_ value: Value) {
        let first = lock.withLock { () -> Bool in defer { done = true }; return !done }
        if first { onValue?(value) }
    }
}

private final class ServerSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var up = true
    var isUp: Bool {
        get { lock.withLock { up } }
        set { lock.withLock { up = newValue } }
    }
}

/// A one-purpose HTTP server on loopback: a TileJSON at `/planet`, and tiles at
/// `/tiles/{z}/{x}/{y}` answered by `answer`.
private final class TileServer: @unchecked Sendable {
    enum Answer { case ok, status(Int), drop }
    struct TileRequest: CustomStringConvertible {
        let zoom: Int, column: Int, row: Int
        var description: String { "\(zoom)/\(column)/\(row)" }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "tile-server")
    private let lock = NSLock()
    private var requests: [TileRequest] = []
    private let answer: (Int, TileRequest) -> Answer
    private(set) var port: UInt16 = 0

    var tileRequests: [TileRequest] { lock.withLock { requests } }

    init(answer: @escaping (Int, TileRequest) -> Answer) throws {
        self.answer = answer
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [weak self] in self?.serve($0) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else {
            throw NSError(domain: "TileServer", code: 1)
        }
        self.port = port
    }

    func stop() { listener.cancel() }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self, let data, let head = String(data: data, encoding: .utf8) else { return connection.cancel() }
            let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            respond(to: path, on: connection)
        }
    }

    private func respond(to path: String, on connection: NWConnection) {
        if path.hasPrefix("/planet") {
            let tileJSON = """
            {"tilejson":"3.0.0","tiles":["http://127.0.0.1:\(port)/tiles/{z}/{x}/{y}"],"minzoom":0,"maxzoom":14}
            """
            return send(200, Data(tileJSON.utf8), "application/json", on: connection)
        }
        let parts = path.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return send(404, Data(), "text/plain", on: connection) }
        let request = TileRequest(zoom: parts[0], column: parts[1], row: parts[2])
        let index = lock.withLock { () -> Int in requests.append(request); return requests.count - 1 }
        switch answer(index, request) {
        case .ok: send(200, Data(), "application/x-protobuf", cache: "max-age=3600", on: connection)
        case .status(let code): send(code, Data(), "text/plain", on: connection)
        case .drop: connection.cancel()
        }
    }

    private func send(
        _ status: Int, _ body: Data, _ type: String, cache: String = "no-store", on connection: NWConnection
    ) {
        let head = "HTTP/1.1 \(status) X\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + "Cache-Control: \(cache)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
#endif
