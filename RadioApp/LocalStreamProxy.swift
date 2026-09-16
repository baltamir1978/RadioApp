import Foundation
import Network
import os

private nonisolated let proxyLog = Logger(subsystem: "com.radioapp.playback", category: "proxy")

/// A loopback HTTP proxy that makes badly-described live streams playable by AVPlayer.
///
/// AVPlayer opens a stream with `Range: bytes=0-1` to sniff its format. A well-behaved live server
/// answers `200` with `accept-ranges: none` and simply starts streaming. Some servers
/// (AzuraCast/Icecast behind nginx — Cassette FM's `stream.costafm.es`) instead answer
/// `206 Partial Content` with `content-range: bytes 0-1/18446744073709550477`. That length is
/// 2^64-1139, an overflow. AVPlayer then treats an endless broadcast as a seekable 18-exabyte file:
/// it takes the 2 bytes it asked for, can't identify a format from so few, and fails the item with
/// `-11800 / -12876` in about 200ms. Reconnect logic rebuilds it, it fails again, and the station
/// sits there flipping between play and pause without ever producing audio.
///
/// `AVAssetResourceLoader` looks like the fix but isn't: for progressive (non-HLS) audio it
/// cancels the loading request after the first chunk and never opens another, so playback stalls
/// on the first buffer.
///
/// So we proxy instead. AVPlayer connects to `127.0.0.1`, we fetch the real stream ourselves
/// *without* a `Range` header, and relay it back as a plain `200` with `Accept-Ranges: none` and
/// no `Content-Length` — the shape AVPlayer already handles correctly for every station that
/// works today. Everything else, including the ICY metadata headers that carry song titles, is
/// passed through untouched.
///
/// Both types here are actors whose executor is their own serial dispatch queue. Network and
/// URLSession already call back on that queue, so each callback steps into the actor with
/// `assumeIsolated` — no extra hop, and events are handled in the order they arrived.
actor LocalStreamProxy {
    private let originURL: URL
    private let listener: NWListener
    private let queue = DispatchSerialQueue(label: "radio.streamproxy")
    /// One relay per accepted connection — AVPlayer may open more than one.
    private var relays: [ObjectIdentifier: Relay] = [:]
    private var stopped = false

    /// Set on the listener's queue once it binds; `init` doesn't return until it has been.
    private let boundURL = OSAllocatedUnfairLock<URL?>(initialState: nil)

    /// The URL to hand AVPlayer.
    nonisolated var localURL: URL {
        // Never nil on a proxy that exists: `init` fails unless the listener bound in time.
        boundURL.withLock { $0 }!
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init?(originURL: URL) {
        self.originURL = originURL
        guard let listener = try? NWListener(using: .tcp) else { return nil }
        self.listener = listener

        // Both handlers go in before `start`: a listener started without a connection handler
        // fails straight away.
        listener.newConnectionHandler = { [weak self] connection in
            self?.assumeIsolated { $0.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self, listener] state in
            if case .ready = state, let port = listener.port {
                // The path is cosmetic — the proxy always serves `originURL` — but keeping the
                // real extension helps AVPlayer pick its parser.
                self?.boundURL.withLock { $0 = URL(string: "http://127.0.0.1:\(port.rawValue)/stream.mp3") }
                proxyLog.notice("proxy ready on port \(port.rawValue, privacy: .public)")
            }
        }
        listener.start(queue: queue)

        // The listener needs a moment to bind; the caller needs `localURL` right away.
        let deadline = Date().addingTimeInterval(2)
        while boundURL.withLock({ $0 }) == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard boundURL.withLock({ $0 }) != nil else {
            listener.cancel()
            return nil
        }
    }

    /// Tears down the listener and every in-flight relay. Safe to call more than once.
    nonisolated func stop() {
        queue.async {
            self.assumeIsolated { proxy in
                guard !proxy.stopped else { return }
                proxy.stopped = true
                proxy.listener.cancel()
                for relay in proxy.relays.values { relay.stop() }
                proxy.relays.removeAll()
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped else { connection.cancel(); return }
        let relay = Relay(connection: connection, originURL: originURL) { [weak self] relay in
            guard let self else { return }
            self.queue.async {
                self.assumeIsolated { _ = $0.relays.removeValue(forKey: ObjectIdentifier(relay)) }
            }
        }
        relays[ObjectIdentifier(relay)] = relay
        relay.start()
    }
}

// MARK: - Relay

/// Pumps one client connection: reads its request, fetches the origin stream without a `Range`
/// header, and relays the response back rewritten as a plain streaming `200`.
private actor Relay {
    private let connection: NWConnection
    private let originURL: URL
    private let onFinish: @Sendable (Relay) -> Void
    private let queue = DispatchSerialQueue(label: "radio.streamproxy.relay")

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var requestBytes = Data()
    private var sentHeaders = false
    private var finished = false
    /// Bytes waiting on the socket. Bounded so a stalled client can't grow this without limit.
    private var backlog = 0
    private let maxBacklog = 4 << 20

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(connection: NWConnection, originURL: URL, onFinish: @escaping @Sendable (Relay) -> Void) {
        self.connection = connection
        self.originURL = originURL
        self.onFinish = onFinish
    }

    /// Called from the proxy's queue; the relay's own work starts on its queue.
    nonisolated func start() {
        queue.async {
            self.assumeIsolated { $0.begin() }
        }
    }

    nonisolated func stop() {
        queue.async {
            self.assumeIsolated { $0.finish() }
        }
    }

    private func begin() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.assumeIsolated { $0.finish() }
            default: break
            }
        }
        connection.start(queue: queue)
        readRequest()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        connection.cancel()
        onFinish(self)
    }

    // MARK: Client request

    /// Reads until the end of the HTTP headers. We only care about `Icy-MetaData`, which decides
    /// whether the origin interleaves song titles into the audio.
    private func readRequest() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            self?.assumeIsolated { relay in
                if let error {
                    proxyLog.error("client read failed: \(String(describing: error), privacy: .public)")
                    relay.finish()
                    return
                }
                if let data { relay.requestBytes.append(data) }
                if let range = relay.requestBytes.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(decoding: relay.requestBytes[..<range.lowerBound], as: UTF8.self)
                    relay.openOrigin(wantsICYMetadata: head.lowercased().contains("icy-metadata: 1"))
                } else if isComplete {
                    relay.finish()
                } else {
                    relay.readRequest()
                }
            }
        }
    }

    // MARK: Origin

    private func openOrigin(wantsICYMetadata: Bool) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        // Delegate callbacks run on the relay's queue, so they can step straight into the actor.
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: OriginDelegate(relay: self),
                                 delegateQueue: delegateQueue)
        self.session = session

        var request = URLRequest(url: originURL)
        // No Range header, ever — that request is what makes these servers misdescribe the stream.
        if wantsICYMetadata { request.setValue("1", forHTTPHeaderField: "Icy-MetaData") }
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    /// Rewrites the origin's response into a plain streaming 200 for the client.
    fileprivate nonisolated static func responseHead(for response: HTTPURLResponse) -> String {
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(response.value(forHTTPHeaderField: "Content-Type") ?? "audio/mpeg")\r\n"
        // The two lines that matter: never advertise range support, never advertise a length.
        // Together they tell AVPlayer "this is an open-ended live stream", which is the truth.
        head += "Accept-Ranges: none\r\n"
        head += "Connection: close\r\n"
        head += "Cache-Control: no-cache, no-store\r\n"
        // Pass ICY metadata through so song titles keep working.
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String, let value = value as? String else { continue }
            if key.lowercased().hasPrefix("icy-") {
                head += "\(key): \(value)\r\n"
            }
        }
        head += "\r\n"
        return head
    }

    private func send(_ data: Data) {
        guard !finished else { return }
        backlog += data.count
        if backlog > maxBacklog {
            proxyLog.error("client fell too far behind — dropping connection")
            finish()
            return
        }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            self?.assumeIsolated { relay in
                relay.backlog -= data.count
                if let error {
                    proxyLog.error("client write failed: \(String(describing: error), privacy: .public)")
                    relay.finish()
                }
            }
        })
    }

    // MARK: Origin callbacks

    /// `head` is nil when the origin didn't answer over HTTP.
    fileprivate func originResponded(head: String?) -> URLSession.ResponseDisposition {
        guard !finished, let head else { return .cancel }
        if !sentHeaders {
            sentHeaders = true
            send(Data(head.utf8))
        }
        return .allow
    }

    fileprivate func originSent(_ data: Data) {
        guard !finished else { return }
        send(data)
    }

    fileprivate func originEnded(_ error: Error?) {
        // A live broadcast should never end cleanly either; closing the client connection lets
        // the player's reconnect logic notice and rebuild. A cancellation is routine — AVPlayer
        // opens a probe connection and drops it as soon as it has sniffed the format.
        if let error, (error as? URLError)?.code != .cancelled {
            proxyLog.error("origin ended: \(String(describing: error), privacy: .public)")
        }
        finish()
    }
}

/// URLSession needs an `NSObject` delegate, which an actor can't be. It is called on the relay's
/// queue (see `openOrigin`) and forwards straight into the relay. The session keeps it — and so
/// the relay — alive until `finish()` invalidates the session.
private nonisolated final class OriginDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private let relay: Relay

    init(relay: Relay) {
        self.relay = relay
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let head = (response as? HTTPURLResponse).map(Relay.responseHead(for:))
        completionHandler(relay.assumeIsolated { $0.originResponded(head: head) })
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        relay.assumeIsolated { $0.originSent(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        relay.assumeIsolated { $0.originEnded(error) }
    }
}
