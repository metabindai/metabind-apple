import Foundation
import Testing
@testable import MCPAppsHost

/// Holds resource responses so invalidation can race a real URLSession request.
/// Hands out legacy session ids s1, s2, …; a request on an expired one gets 404.
private final class HeldResourceProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: [HeldResourceProtocol] = []
    nonisolated(unsafe) private static var reads = 0
    nonisolated(unsafe) private static var holdsReads = true
    nonisolated(unsafe) private static var sessions = 0
    nonisolated(unsafe) private static var expiredSessions: Set<String> = []
    private var stopped = false
    private var requestID: Any = NSNull()
    private var session: String?

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        pending = []; reads = 0; holdsReads = true; sessions = 0; expiredSessions = []
    }
    static var readCount: Int {
        lock.lock(); defer { lock.unlock() }
        return reads
    }
    /// Later resource reads answer "fresh" immediately.
    static func stopHoldingReads() {
        lock.lock(); defer { lock.unlock() }
        holdsReads = false
    }
    static func expire(session: String) {
        lock.lock(); defer { lock.unlock() }
        expiredSessions.insert(session)
    }
    /// Answers the `number`th held resource read, counting from 1.
    static func finish(read number: Int, text: String) {
        lock.lock()
        let request = pending[number - 1]
        let stopped = request.stopped
        let expired = request.session.map(expiredSessions.contains) ?? false
        lock.unlock()
        if stopped { return }
        if expired {
            request.send(status: 404, body: Data("Session not found".utf8))
        } else {
            request.respondResource(text)
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        requestID = json?["id"] ?? NSNull()
        session = request.value(forHTTPHeaderField: "Mcp-Session-Id")
        Self.lock.lock()
        let expired = session.map(Self.expiredSessions.contains) ?? false
        Self.lock.unlock()
        if expired { return send(status: 404, body: Data("Session not found".utf8)) }
        switch json?["method"] as? String {
        case "resources/read":
            Self.lock.lock()
            Self.reads += 1
            let hold = Self.holdsReads
            if hold { Self.pending.append(self) }
            Self.lock.unlock()
            if !hold { respondResource("fresh") }
        case "initialize":
            Self.lock.lock()
            Self.sessions += 1
            let session = "s\(Self.sessions)"
            Self.lock.unlock()
            respond(["protocolVersion": "2025-03-26"], headers: ["Mcp-Session-Id": session])
        default: respond([:])
        }
    }
    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        stopped = true
    }
    private func respondResource(_ text: String) {
        respond(["contents": [["uri": "ui://card", "mimeType": "text/html", "text": text]]])
    }
    private func respond(_ result: [String: Any], headers: [String: String] = [:]) {
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": requestID, "result": result])
        send(status: 200, body: data, headers: headers)
    }
    private func send(status: Int, body: Data, headers: [String: String] = [:]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: headers.merging(["Content-Type": "application/json"]) { $1 })!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Resource cache generations", .serialized)
struct ResourceCacheInvalidationTests {
    private func makeClient() -> MCPAppsClient {
        HeldResourceProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldResourceProtocol.self]
        return MCPAppsClient(url: URL(string: "https://resource-cache.test/mcp")!,
                             configuration: .init(urlSession: URLSession(configuration: configuration)))
    }

    private func waitForReads(_ count: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while HeldResourceProtocol.readCount < count && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(HeldResourceProtocol.readCount == count)
    }

    @Test func retiringReadCannotRemoveOrPopulateNewGeneration() async throws {
        let client = makeClient()
        let retired = Task { try await client.readResource(uri: "ui://card") }
        try await waitForReads(1)
        await client.clearResourceCache()
        let replacement = Task { try await client.readResource(uri: "ui://card") }
        try await waitForReads(2)
        let joined = Task { try await client.readResource(uri: "ui://card") }
        try await Task.sleep(for: .milliseconds(20))
        #expect(HeldResourceProtocol.readCount == 2, "Retired cleanup must not remove the replacement request")
        HeldResourceProtocol.finish(read: 2, text: "fresh")
        #expect(try await replacement.value.text == "fresh")
        #expect(try await joined.value.text == "fresh")
        HeldResourceProtocol.finish(read: 1, text: "stale")
        #expect(try await retired.value.text == "stale", "A retired read still answers its caller")
        #expect(try await client.readResource(uri: "ui://card").text == "fresh")
        #expect(HeldResourceProtocol.readCount == 2)
    }

    @Test(arguments: [false, true]) @MainActor
    func clearingCacheLeavesLoadingCardRendering(resultArrived: Bool) async throws {
        let client = makeClient()
        let session = ManualMCPAppSession(id: "card", toolName: "card", resourceUri: "ui://card", server: client)
        try await waitForReads(1)
        let result = ToolResult(text: "remote result")
        if resultArrived { session.complete(with: result) }
        await client.clearResourceCache()
        HeldResourceProtocol.finish(read: 1, text: "card")
        let deadline = Date().addingTimeInterval(2)
        while session.resolvedContent == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(session.resolvedContent == .html("card"))
        if resultArrived {
            #expect(session.phase.terminalResult == result)
        } else {
            #expect(session.phase.isActive)
        }
    }

    @Test func readRecoversFromExpiredSessionAndStaysCached() async throws {
        let client = makeClient()
        let read = Task { try await client.readResource(uri: "ui://card") }
        try await waitForReads(1)
        HeldResourceProtocol.expire(session: "s1")
        HeldResourceProtocol.stopHoldingReads()
        // The server answers the held read with 404; the client re-initializes and retries.
        HeldResourceProtocol.finish(read: 1, text: "stale")
        #expect(try await read.value.text == "fresh")
        #expect(HeldResourceProtocol.readCount == 2)
        // A new session is not a resource change, so the retried read is cached.
        #expect(try await client.readResource(uri: "ui://card").text == "fresh")
        #expect(HeldResourceProtocol.readCount == 2)
    }
}
