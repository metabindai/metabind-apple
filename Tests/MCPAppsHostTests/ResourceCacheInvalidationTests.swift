import Foundation
import Testing
@testable import MCPAppsHost

/// Holds resource responses so invalidation can race a real URLSession request.
private final class HeldResourceProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: [HeldResourceProtocol] = []
    nonisolated(unsafe) private static var reads = 0
    private var stopped = false
    private var requestID: Any = NSNull()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        pending = []; reads = 0
    }
    static var readCount: Int {
        lock.lock(); defer { lock.unlock() }
        return reads
    }
    /// Answers the `number`th resource read, counting from 1.
    static func finish(read number: Int, text: String) {
        lock.lock()
        let request = pending[number - 1]
        let stopped = request.stopped
        lock.unlock()
        if !stopped {
            request.respond(["contents": [["uri": "ui://card", "mimeType": "text/html", "text": text]]])
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
        switch json?["method"] as? String {
        case "resources/read":
            Self.lock.lock()
            Self.reads += 1
            Self.pending.append(self)
            Self.lock.unlock()
        case "initialize": respond(["protocolVersion": "2025-03-26"])
        default: respond([:])
        }
    }
    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        stopped = true
    }
    private func respond(_ result: [String: Any]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": requestID, "result": result])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
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
}
