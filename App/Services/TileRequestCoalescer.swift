import Foundation

/// **One network request per tile, however many snapshots ask for it at once**
/// (2026-09-26, the 942 s Iceland export).
///
/// The export keeps up to nine MapLibre snapshotters in flight, and neighbouring
/// stations cover nearly the same tiles. Each snapshotter asks for a tile the
/// moment it needs it; if the first download has not reached MapLibre's cache
/// yet, the other eight download it again. On device that was 17,216 requests
/// for 1,908 distinct tiles (`MapSubstrateMeter`); on the desk bench, vector
/// tiles that carry a ten-year `max-age` were still fetched ~4× each.
///
/// This `URLProtocol` sits in MapLibre's own session configuration and does two
/// things, **neither of which changes a byte MapLibre receives**:
///
/// 1. **Coalesces.** Identical requests in flight at the same time share one
///    download; every asker gets the same status, headers and body. "Identical"
///    includes the conditional headers, so a revalidation never hands a 304 to
///    a request that needs the body.
/// 2. **Gives terrain a lifetime.** AWS's terrain tiles answer with an ETag and
///    no `Cache-Control` or `Expires` (VERIFIED by curl, 2026-09-26), and
///    MapLibre re-checks them on every use — a round trip to us-east per tile
///    per snapshot. The response it is handed carries `Cache-Control: max-age`
///    of `export.pipeline.terrain_max_age_s`, so its own cache keeps them. The
///    data is the Mapzen/Tilezen DEM, last modified 2017.
///
/// Only the tile and style hosts the export already talks to are touched
/// (§0: no new host, no new data leaves the device; fewer requests reach AWS).
/// Everything else passes through to the system untouched.
final class TileRequestCoalescer: URLProtocol {
    /// What the coalescer did — counts only, like the meter it feeds.
    struct Reading: Equatable {
        /// Downloads actually sent to the network.
        var downloads = 0
        /// Requests that joined a download already in flight.
        var joined = 0
        /// Terrain responses handed on with a lifetime they did not carry.
        var terrainAged = 0
        /// Requests answered from tiles this export already downloaded.
        var remembered = 0
    }

    /// Process-wide, because MapLibre's session is. Set once per export by
    /// `configure`; read back by the export's log line.
    static let shared = Hub()

    static func configure(terrainMaxAgeS: Int, hosts: [String], memoryMb: Int) {
        shared.configure(terrainMaxAgeS: terrainMaxAgeS, hosts: hosts, memoryMb: memoryMb)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        guard request.httpMethod ?? "GET" == "GET", let host = request.url?.host else { return false }
        return shared.handles(host: host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var ticket: Hub.Ticket?
    /// The loading thread. A `URLProtocol` must answer its client on the
    /// thread that called `startLoading`, not on the download's queue.
    private var thread: Thread?
    private var pending: Outcome?

    override func startLoading() {
        thread = Thread.current
        ticket = Self.shared.join(request) { [weak self] outcome in
            guard let self, let thread = self.thread else { return }
            self.pending = outcome
            self.perform(#selector(self.deliver), on: thread, with: nil, waitUntilDone: false,
                         modes: [RunLoop.Mode.common.rawValue])
        }
    }

    @objc private func deliver() {
        guard let outcome = pending else { return }
        pending = nil
        switch outcome {
        case let .success(response, data):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        if let ticket { Self.shared.leave(ticket) }
        ticket = nil
    }

    // MARK: - The shared state

    enum Outcome {
        case success(HTTPURLResponse, Data)
        case failure(Error)
    }

    final class Hub: @unchecked Sendable {
        struct Ticket: Hashable {
            fileprivate let key: String
            fileprivate let id: UUID
        }

        private struct Flight {
            var task: URLSessionDataTask?
            var waiters: [UUID: (Outcome) -> Void] = [:]
        }

        /// One landed download, kept so a later identical ask is answered
        /// with the same bytes instead of a second download.
        private final class Landed {
            let response: HTTPURLResponse
            let data: Data

            init(response: HTTPURLResponse, data: Data) {
                self.response = response
                self.data = data
            }
        }

        private let lock = NSLock()
        private var flights: [String: Flight] = [:]
        /// **Why a second cache under MapLibre's.** MapLibre queues its own
        /// requests, so a repeat often leaves its queue *after* the first
        /// download has landed and left `flights` — the desk bench measured the
        /// median repeat six seconds later, still a miss in MapLibre's cache.
        /// Only full `200` bodies are kept, only for unconditional asks, and
        /// only for a response that says it may be cached (after the terrain
        /// lifetime is applied). Bounded by `export.pipeline.tile_memory_mb`;
        /// `NSCache` evicts under that and under memory pressure.
        private let landed = NSCache<NSString, Landed>()
        private var reading = Reading()
        private var terrainMaxAgeS = 0
        private var hosts: [String] = []
        private let session: URLSession

        /// `session` performs the real downloads. It must not itself carry this
        /// protocol, or every download would loop back into the hub.
        init(session: URLSession = Hub.downloadSession()) {
            self.session = session
        }

        /// No cache of its own: MapLibre's cache is the one that decides what is
        /// fresh, and a second cache under it would answer for the server.
        static func downloadSession() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: configuration)
        }

        func configure(terrainMaxAgeS: Int, hosts: [String], memoryMb: Int) {
            lock.withLock {
                self.terrainMaxAgeS = terrainMaxAgeS
                self.hosts = hosts
            }
            landed.totalCostLimit = max(0, memoryMb) * 1_048_576
            // A new export starts from what the network says, not from what the
            // last one remembered.
            landed.removeAllObjects()
        }

        func handles(host: String) -> Bool {
            lock.withLock { hosts.contains { host == $0 || host.hasSuffix("." + $0) } }
        }

        func resetReading() {
            lock.withLock { reading = Reading() }
        }

        func read() -> Reading {
            lock.withLock { reading }
        }

        func join(_ request: URLRequest, deliver: @escaping (Outcome) -> Void) -> Ticket {
            let key = Self.key(request)
            let ticket = Ticket(key: key, id: UUID())
            var start: URLSessionDataTask?
            if Self.isUnconditional(request), let url = request.url?.absoluteString,
               let hit = landed.object(forKey: url as NSString) {
                lock.withLock { reading.remembered += 1 }
                deliver(.success(hit.response, hit.data))
                return ticket
            }
            lock.withLock {
                if flights[key] != nil {
                    flights[key]?.waiters[ticket.id] = deliver
                    reading.joined += 1
                    return
                }
                let task = session.dataTask(with: request) { [weak self] data, response, error in
                    self?.land(key: key, data: data, response: response, error: error)
                }
                flights[key] = Flight(task: task, waiters: [ticket.id: deliver])
                reading.downloads += 1
                start = task
            }
            start?.resume()
            return ticket
        }

        /// The last asker leaving cancels the download; anyone else still
        /// waiting keeps it.
        func leave(_ ticket: Ticket) {
            var cancel: URLSessionDataTask?
            lock.withLock {
                guard var flight = flights[ticket.key],
                      flight.waiters.removeValue(forKey: ticket.id) != nil else { return }
                if flight.waiters.isEmpty {
                    cancel = flight.task
                    flights[ticket.key] = nil
                } else {
                    flights[ticket.key] = flight
                }
            }
            cancel?.cancel()
        }

        private func land(key: String, data: Data?, response: URLResponse?, error: Error?) {
            var waiters: [(Outcome) -> Void] = []
            var outcome: Outcome
            lock.lock()
            if let error {
                outcome = .failure(error)
            } else if let http = response as? HTTPURLResponse {
                let (handed, aged) = Self.handedOn(http, terrainMaxAgeS: terrainMaxAgeS)
                if aged { reading.terrainAged += 1 }
                let body = data ?? Data()
                outcome = .success(handed, body)
                if handed.statusCode == 200, Self.mayBeKept(handed), key.hasSuffix("\u{1F}\u{1F}"),
                   let url = handed.url?.absoluteString {
                    landed.setObject(Landed(response: handed, data: body), forKey: url as NSString, cost: body.count)
                }
            } else {
                outcome = .failure(URLError(.badServerResponse))
            }
            waiters = flights.removeValue(forKey: key).map { Array($0.waiters.values) } ?? []
            lock.unlock()
            waiters.forEach { $0(outcome) }
        }

        static func isUnconditional(_ request: URLRequest) -> Bool {
            request.value(forHTTPHeaderField: "If-None-Match") == nil
                && request.value(forHTTPHeaderField: "If-Modified-Since") == nil
        }

        /// A response is kept only if it names a positive lifetime and does not
        /// forbid storing it. `Expires` alone is not trusted: it would need the
        /// server's clock.
        static func mayBeKept(_ response: HTTPURLResponse) -> Bool {
            guard let control = response.value(forHTTPHeaderField: "Cache-Control")?.lowercased() else { return false }
            if control.contains("no-store") || control.contains("no-cache") { return false }
            guard let range = control.range(of: "max-age=") else { return false }
            let digits = control[range.upperBound...].prefix { $0.isNumber }
            return (Int(digits) ?? 0) > 0
        }

        /// The key two requests must share to share a download: the URL and the
        /// headers that change what the server answers.
        static func key(_ request: URLRequest) -> String {
            [
                request.url?.absoluteString ?? "",
                request.value(forHTTPHeaderField: "If-None-Match") ?? "",
                request.value(forHTTPHeaderField: "If-Modified-Since") ?? ""
            ].joined(separator: "\u{1F}")
        }

        /// The response MapLibre is handed. Status and body are the server's.
        /// Headers are the server's too, except:
        /// - `Content-Encoding` / `Content-Length` are dropped, because the
        ///   session has already decoded the body they describe;
        /// - a terrain response with no lifetime of its own gets one.
        static func handedOn(_ response: HTTPURLResponse, terrainMaxAgeS: Int) -> (HTTPURLResponse, aged: Bool) {
            var headers: [String: String] = [:]
            for (name, value) in response.allHeaderFields {
                guard let name = name as? String, let value = value as? String else { continue }
                let lower = name.lowercased()
                if lower == "content-encoding" || lower == "content-length" { continue }
                headers[name] = value
            }
            let hasLifetime = headers.keys.contains { ["cache-control", "expires"].contains($0.lowercased()) }
            let isTerrain = response.url.map { MapSubstrateMeter.TileKind($0) == .terrain } ?? false
            let aged = isTerrain && !hasLifetime && terrainMaxAgeS > 0
                && (response.statusCode == 200 || response.statusCode == 304)
            if aged {
                headers["Cache-Control"] = "max-age=\(terrainMaxAgeS)"
            }
            let url = response.url ?? URL(fileURLWithPath: "/")
            let handed = HTTPURLResponse(
                url: url, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: headers
            ) ?? response
            return (handed, aged)
        }
    }
}
