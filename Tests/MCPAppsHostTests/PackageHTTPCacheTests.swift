import Foundation
import Network
import Testing
@testable import MCPAppsHost

/// A real loopback HTTP server: URLProtocol mocks do not exercise Foundation's
/// HTTP freshness, conditional requests, or 304 response handling.
private final class CacheHTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "PackageHTTPCacheTests.server")
    private let listener: NWListener
    private let cacheControl: String
    private var received: [String] = []
    let body = Data("verified package bytes".utf8)

    init(cacheControl: String) throws {
        self.cacheControl = cacheControl
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/package")!)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: queue)
                receive(connection, accumulated: Data())
            }
            listener.start(queue: queue)
        }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            var request = accumulated
            if let data { request.append(data) }
            let text = String(decoding: request, as: UTF8.self)
            if text.contains("\r\n\r\n") {
                received.append(text)
                let conditional = text.lowercased().contains("if-none-match: \"package-v1\"")
                let date = DateFormatter()
                date.locale = Locale(identifier: "en_US_POSIX")
                date.timeZone = TimeZone(secondsFromGMT: 0)
                date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
                let status = conditional ? "304 Not Modified" : "200 OK"
                var response = Data("HTTP/1.1 \(status)\r\nDate: \(date.string(from: Date()))\r\nCache-Control: \(cacheControl)\r\nETag: \"package-v1\"\r\nContent-Type: application/bindjs-package+json\r\nConnection: close\r\n".utf8)
                if !conditional { response.append(Data("Content-Length: \(body.count)\r\n".utf8)) }
                response.append(Data("\r\n".utf8))
                if !conditional { response.append(body) }
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else if complete || error != nil {
                connection.cancel()
            } else {
                receive(connection, accumulated: request)
            }
        }
    }

    var requests: [String] { queue.sync { received } }
    func stop() { listener.cancel() }
}

@Suite("Package HTTP cache")
struct PackageHTTPCacheTests {
    @Test(arguments: ["public, max-age=3600", "no-cache", "max-age=0", "no-store"])
    func nativeHTTPHeadersControlReuse(cacheControl: String) async throws {
        let server = try CacheHTTPServer(cacheControl: cacheControl)
        let url = try await server.start()
        defer { server.stop() }
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            cache.removeAllCachedResponses()
        }
        let first = try await PackageHTTPTransport.fetch(url, session: session)
        #expect(first.data == server.body)
        // Foundation may finish storing just after the data task completes.
        if cacheControl != "no-store" {
            for _ in 0..<100 {
                if cache.cachedResponse(for: URLRequest(url: url)) != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let second = try await PackageHTTPTransport.fetch(url, session: session)
        #expect(second.data == server.body)
        switch cacheControl {
        case "public, max-age=3600":
            #expect(server.requests.count == 1, "Fresh bytes come from URLCache without an origin request")
        case "no-cache", "max-age=0":
            #expect(server.requests.count == 2)
            #expect(server.requests.last?.lowercased().contains("if-none-match: \"package-v1\"") == true)
            #expect(second.response.statusCode == 200, "Foundation combines the 304 with the cached body")
        default:
            #expect(server.requests.count == 2)
            #expect(cache.cachedResponse(for: URLRequest(url: url)) == nil)
            #expect(!second.mayCacheDecoded)
        }
    }
}
