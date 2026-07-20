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
nonisolated final class LocalStreamProxy: @unchecked Sendable {
    private let originURL: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "radio.streamproxy")
    /// One relay per accepted connection — AVPlayer may open more than one.
    private var relays: [ObjectIdentifier: Relay] = [:]
    private var stopped = false

    /// The URL to hand AVPlayer. Nil if the listener couldn't be created.
    private(set) var localURL: URL?

    init?(originURL: URL) {
        self.originURL = originURL
        guard let listener = try? NWListener(using: .tcp) else { return nil }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state, let port = self.listener.port {
                // The path is cosmetic — the proxy always serves `originURL` — but keeping the
                // real extension helps AVPlayer pick its parser.
                self.localURL = URL(string: "http://127.0.0.1:\(port.rawValue)/stream.mp3")
                proxyLog.notice("proxy ready on port \(port.rawValue, privacy: .public)")
            }
        }
        listener.start(queue: queue)

        // The listener needs a moment to bind; the caller needs `localURL` right away.
        let deadline = Date().addingTimeInterval(2)
        while localURL == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard localURL != nil else {
            listener.cancel()
            return nil
        }
    }

    /// Tears down the listener and every in-flight relay. Safe to call more than once.
    func stop() {
        queue.async {
            guard !self.stopped else { return }
            self.stopped = true
            self.listener.cancel()
            for relay in self.relays.values { relay.stop() }
            self.relays.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        queue.async {
            guard !self.stopped else { connection.cancel(); return }
            let relay = Relay(connection: connection, originURL: self.originURL) { [weak self] relay in
                self?.queue.async { self?.relays.removeValue(forKey: ObjectIdentifier(relay)) }
            }
            self.relays[ObjectIdentifier(relay)] = relay
            relay.start()
        }
    }
}

// MARK: - Relay

/// Pumps one client connection: reads its request, fetches the origin stream without a `Range`
/// header, and relays the response back rewritten as a plain streaming `200`.
private final class Relay: NSObject, @unchecked Sendable {
    private let connection: NWConnection
    private let originURL: URL
    private let onFinish: (Relay) -> Void
    private let queue = DispatchQueue(label: "radio.streamproxy.relay")

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var requestBytes = Data()
    private var sentHeaders = false
    private var finished = false
    /// Bytes waiting on the socket. Bounded so a stalled client can't grow this without limit.
    private var backlog = 0
    private let maxBacklog = 4 << 20

    init(connection: NWConnection, originURL: URL, onFinish: @escaping (Relay) -> Void) {
        self.connection = connection
        self.originURL = originURL
        self.onFinish = onFinish
        super.init()
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.finish()
            default: break
            }
        }
        connection.start(queue: queue)
        readRequest()
    }

    func stop() {
        queue.async { self.finish() }
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
            guard let self else { return }
            if let error {
                proxyLog.error("client read failed: \(String(describing: error), privacy: .public)")
                self.finish()
                return
            }
            if let data { self.requestBytes.append(data) }
            if let range = self.requestBytes.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: self.requestBytes[..<range.lowerBound], as: UTF8.self)
                self.openOrigin(wantsICYMetadata: head.lowercased().contains("icy-metadata: 1"))
            } else if isComplete {
                self.finish()
            } else {
                self.readRequest()
            }
        }
    }

    // MARK: Origin

    private func openOrigin(wantsICYMetadata: Bool) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: originURL)
        // No Range header, ever — that request is what makes these servers misdescribe the stream.
        if wantsICYMetadata { request.setValue("1", forHTTPHeaderField: "Icy-MetaData") }
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    /// Rewrites the origin's response into a plain streaming 200 and sends it to the client.
    private func sendHeaders(for response: HTTPURLResponse) {
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
        send(Data(head.utf8))
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
            guard let self else { return }
            self.queue.async {
                self.backlog -= data.count
                if let error {
                    proxyLog.error("client write failed: \(String(describing: error), privacy: .public)")
                    self.finish()
                }
            }
        })
    }
}

extension Relay: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                                didReceive response: URLResponse,
                                completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        queue.async {
            guard !self.finished, let http = response as? HTTPURLResponse else {
                completionHandler(.cancel)
                return
            }
            if !self.sentHeaders {
                self.sentHeaders = true
                self.sendHeaders(for: http)
            }
            completionHandler(.allow)
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.async {
            guard !self.finished else { return }
            self.send(data)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async {
            // A live broadcast should never end cleanly either; closing the client connection lets
            // the player's reconnect logic notice and rebuild. A cancellation is routine — AVPlayer
            // opens a probe connection and drops it as soon as it has sniffed the format.
            if let error, (error as? URLError)?.code != .cancelled {
                proxyLog.error("origin ended: \(String(describing: error), privacy: .public)")
            }
            self.finish()
        }
    }
}
