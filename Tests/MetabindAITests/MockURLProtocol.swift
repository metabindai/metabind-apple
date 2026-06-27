import Foundation

/// URLProtocol-based stub for intercepting HTTP calls made by a test-injected
/// `URLSession`. Each test installs a handler, runs the code under test, then
/// reads back `capturedRequest()` / `capturedBody()` to assert on the request.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data

        static func sse(_ text: String, status: Int = 200) -> Response {
            Response(
                status: status,
                headers: ["Content-Type": "text/event-stream"],
                body: Data(text.utf8)
            )
        }

        static func json(_ text: String, status: Int) -> Response {
            Response(
                status: status,
                headers: ["Content-Type": "application/json"],
                body: Data(text.utf8)
            )
        }
    }

    typealias Handler = @Sendable (URLRequest) -> Response

    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var captured: URLRequest?
    nonisolated(unsafe) private static var capturedData: Data?
    private static let lock = NSLock()

    /// Installs a handler and returns a session configured to use this protocol.
    /// Call `uninstall()` at the end of each test (prefer `defer`).
    static func install(_ handler: @escaping Handler) -> URLSession {
        lock.lock(); defer { lock.unlock() }
        Self.handler = handler
        captured = nil
        capturedData = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func uninstall() {
        lock.lock(); defer { lock.unlock() }
        handler = nil
        captured = nil
        capturedData = nil
    }

    static func capturedRequest() -> URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    static func capturedBody() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return capturedData
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lock.lock()
        let handler = MockURLProtocol.handler
        MockURLProtocol.captured = request
        MockURLProtocol.capturedData = Self.readBody(from: request)
        MockURLProtocol.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        let response = handler(request)
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // URLSession strips httpBody and exposes only httpBodyStream; read it fully.
    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufSize = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: bufSize)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
