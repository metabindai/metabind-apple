import Testing
import Foundation
@testable import MCPAppsHost

// MARK: - Mock URLProtocol

/// Intercepts all HTTP requests and returns preconfigured responses.
/// Register handlers before each test, unregister after.
/// Captured request with the body already read from the stream.
struct CapturedRequest {
    let urlRequest: URLRequest
    let body: Data
    var json: [String: Any]? { try? JSONSerialization.jsonObject(with: body) as? [String: Any] }
    var method: String { json?["method"] as? String ?? "unknown" }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handlers: [String: (CapturedRequest) -> (Int, [String: String], Data)] = [:]
    nonisolated(unsafe) static var requestLog: [CapturedRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = readBody(from: request)
        let captured = CapturedRequest(urlRequest: request, body: body)
        Self.requestLog.append(captured)

        let handler = Self.handlers[captured.method] ?? Self.handlers["*"]

        let (status, headers, data): (Int, [String: String], Data)
        if let handler {
            (status, headers, data) = handler(captured)
        } else {
            (status, headers, data) = (404, [:], Data("Not Found".utf8))
        }

        var headerFields = headers
        headerFields["content-type"] = headerFields["content-type"] ?? "application/json"

        let response = HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: headerFields
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func readBody(from request: URLRequest) -> Data {
        if let httpBody = request.httpBody { return httpBody }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    static func reset() {
        handlers = [:]
        requestLog = []
    }
}

/// Creates a URLSession that uses MockURLProtocol.
private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

/// Standard initialize + initialized handlers. Returns the given session ID.
private func registerInitHandlers(sessionId: String = "test-session-123", version: String = "2025-03-26") {
    MockURLProtocol.handlers["initialize"] = { req in
        let id = req.json?["id"] ?? 1
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": id,
            "result": [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "mock-server", "version": "1.0.0"]
            ]
        ]
        return (200, ["Mcp-Session-Id": sessionId], try! JSONSerialization.data(withJSONObject: body))
    }
    MockURLProtocol.handlers["notifications/initialized"] = { _ in
        (202, [:], Data())
    }
}

/// Standard MCP 2026-07-28 discovery handler.
private func registerModernDiscoverHandler(supportedVersions: [String] = ["2026-07-28"]) {
    MockURLProtocol.handlers["server/discover"] = { req in
        let id = req.json?["id"] ?? 1
        let result: [String: Any] = [
            "resultType": "complete",
            "supportedVersions": supportedVersions,
            "capabilities": ["tools": [:], "resources": [:]],
            "ttlMs": 0,
            "cacheScope": "private",
            "_meta": [
                "io.modelcontextprotocol/serverInfo": [
                    "name": "modern-mock-server",
                    "version": "2.0.0"
                ]
            ]
        ]
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
        return (200, [:], try! JSONSerialization.data(withJSONObject: body))
    }
}

private let mockURL = URL(string: "https://mock-mcp.test/mcp")!

// MARK: - Tests

@Suite("MCPAppsClient", .serialized)
struct MCPAppsClientTests {

    init() {
        MockURLProtocol.reset()
    }

    // MARK: - OrderedCache

    @Suite("OrderedCache")
    struct OrderedCacheTests {
        @Test func basicSetAndGet() {
            var cache = OrderedCache<String, Int>(maxEntries: 3)
            cache.set("a", 1)
            cache.set("b", 2)
            cache.set("c", 3)
            #expect(cache.get("a") == 1)
            #expect(cache.get("b") == 2)
            #expect(cache.get("c") == 3)
        }

        @Test func evictsLeastRecentlyUsed() {
            var cache = OrderedCache<String, Int>(maxEntries: 3)
            cache.set("a", 1)
            cache.set("b", 2)
            cache.set("c", 3)
            cache.set("d", 4)
            #expect(cache.get("a") == nil)
            #expect(cache.get("b") == 2)
            #expect(cache.get("c") == 3)
            #expect(cache.get("d") == 4)
        }

        @Test func accessPromotesEntry() {
            var cache = OrderedCache<String, Int>(maxEntries: 3)
            cache.set("a", 1)
            cache.set("b", 2)
            cache.set("c", 3)
            _ = cache.get("a")
            cache.set("d", 4)
            #expect(cache.get("a") == 1)
            #expect(cache.get("b") == nil)
        }

        @Test func overwriteUpdatesValue() {
            var cache = OrderedCache<String, Int>(maxEntries: 3)
            cache.set("a", 1)
            cache.set("a", 99)
            #expect(cache.get("a") == 99)
        }

        @Test func removeAllClears() {
            var cache = OrderedCache<String, Int>(maxEntries: 3)
            cache.set("a", 1)
            cache.set("b", 2)
            cache.removeAll()
            #expect(cache.get("a") == nil)
            #expect(cache.get("b") == nil)
        }

        @Test func missReturnsNil() {
            var cache = OrderedCache<String, Int>(maxEntries: 3)
            #expect(cache.get("nonexistent") == nil)
        }
    }

    // MARK: - Configuration

    @Suite("Configuration")
    struct ConfigurationTests {
        @Test func defaultValues() {
            let config = MCPAppsClient.Configuration()
            #expect(config.requestTimeout == 30)
            #expect(config.maxCacheEntries == 50)
            #expect(config.maxRetries == 2)
            #expect(config.retryBaseDelay == 0.5)
        }

        @Test func customValues() {
            let config = MCPAppsClient.Configuration(
                requestTimeout: 60,
                maxCacheEntries: 100,
                maxRetries: 5,
                retryBaseDelay: 1.0
            )
            #expect(config.requestTimeout == 60)
            #expect(config.maxCacheEntries == 100)
            #expect(config.maxRetries == 5)
            #expect(config.retryBaseDelay == 1.0)
        }
    }

    // MARK: - MCPClientError

    @Suite("MCPClientError")
    struct ErrorTests {
        @Test func errorDescriptions() {
            let cases: [(MCPClientError, String)] = [
                (.invalidResponse("bad"), "Invalid MCP response: bad"),
                (.serverError(status: 500, body: "oops"), "MCP server error 500: oops"),
                (.rpcError(code: -32600, message: "Invalid Request"), "MCP error -32600: Invalid Request"),
                (.versionMismatch(requested: "2025-03-26", returned: "2024-01-01"), "MCP version mismatch: requested 2025-03-26, server returned 2024-01-01"),
            ]
            for (error, expected) in cases {
                #expect(error.errorDescription == expected)
            }
        }

        @Test func rpcErrorPreservesData() {
            let error = MCPClientError.rpcError(code: -1, message: "fail", data: "{\"detail\":\"more info\"}")
            if case .rpcError(_, _, let data) = error {
                #expect(data == "{\"detail\":\"more info\"}")
            } else {
                Issue.record("Expected rpcError")
            }
        }
    }

    // MARK: - Initialization

    @Suite("Initialization")
    struct InitializationTests {
        init() { MockURLProtocol.reset() }

        @Test func initializesOnFirstUse() async throws {
            registerInitHandlers()
            MockURLProtocol.handlers["tools/list"] = { _ in
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": ["tools": []]]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(
                url: mockURL,
                configuration: .init(urlSession: mockSession())
            )

            let tools = try await client.listTools()
            #expect(tools.isEmpty)

            // A legacy server is probed once, then uses the original initialization flow.
            #expect(MockURLProtocol.requestLog.count == 4)
            let methods = MockURLProtocol.requestLog.map(\.method)
            #expect(methods == ["server/discover", "initialize", "notifications/initialized", "tools/list"])
        }

        @Test func sendsSessionIdAfterInit() async throws {
            registerInitHandlers(sessionId: "my-session-42")
            MockURLProtocol.handlers["tools/list"] = { req in
                // Verify session ID header is present
                let sid = req.urlRequest.value(forHTTPHeaderField: "Mcp-Session-Id")
                // Encode the session ID in the response so we can check it
                var result: [String: Any] = ["tools": []]
                result["_testSessionId"] = sid
                let fullBody: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": result]
                return (200, [:], try! JSONSerialization.data(withJSONObject: fullBody))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            // The tools/list request should have the session ID
            let toolsReq = MockURLProtocol.requestLog.last!
            #expect(toolsReq.urlRequest.value(forHTTPHeaderField: "Mcp-Session-Id") == "my-session-42")
        }

        @Test func initFailureAllowsRetry() async throws {
            var attemptCount = 0
            MockURLProtocol.handlers["initialize"] = { _ in
                attemptCount += 1
                if attemptCount == 1 {
                    return (500, [:], Data("Server down".utf8))
                }
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": 1,
                    "result": [
                        "protocolVersion": "2025-03-26",
                        "capabilities": [:],
                        "serverInfo": ["name": "mock", "version": "1.0"]
                    ]
                ]
                return (200, ["Mcp-Session-Id": "retry-session"], try! JSONSerialization.data(withJSONObject: body))
            }
            MockURLProtocol.handlers["notifications/initialized"] = { _ in (202, [:], Data()) }
            MockURLProtocol.handlers["tools/list"] = { _ in
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": ["tools": []]]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            // No retries on init — first attempt fails
            let client = MCPAppsClient(
                url: mockURL,
                configuration: .init(maxRetries: 0, urlSession: mockSession())
            )

            // First call should fail
            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch {
                // Expected
            }

            // Second call should retry init and succeed
            let tools = try await client.listTools()
            #expect(tools.isEmpty)
        }

        @Test func acceptsOlderProtocolVersion() async throws {
            registerInitHandlers(version: "2024-11-05")
            MockURLProtocol.handlers["tools/list"] = { _ in
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": ["tools": []]]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let tools = try await client.listTools()
            #expect(tools.isEmpty)
        }

        @Test func sendsVersionHeaderForNewerLegacyProtocol() async throws {
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 4, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            let followups = MockURLProtocol.requestLog.filter {
                $0.method == "notifications/initialized" || $0.method == "tools/list"
            }
            #expect(followups.allSatisfy {
                $0.urlRequest.value(forHTTPHeaderField: "MCP-Protocol-Version") == "2025-11-25"
            })
        }

        @Test func rejectsUnsupportedVersion() async throws {
            registerInitHandlers(version: "1999-01-01")

            let client = MCPAppsClient(url: mockURL, configuration: .init(maxRetries: 0, urlSession: mockSession()))

            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch let error as MCPClientError {
                if case .versionMismatch(_, let returned) = error {
                    #expect(returned == "1999-01-01")
                } else {
                    Issue.record("Expected versionMismatch, got \(error)")
                }
            }
        }

        @Test func sendsCapabilitiesWithMimeTypes() async throws {
            var capturedInitBody: [String: Any]?
            MockURLProtocol.handlers["initialize"] = { req in
                capturedInitBody = req.json
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": 1,
                    "result": [
                        "protocolVersion": "2025-03-26",
                        "capabilities": [:],
                        "serverInfo": ["name": "mock", "version": "1.0"]
                    ]
                ]
                return (200, ["Mcp-Session-Id": "cap-session"], try! JSONSerialization.data(withJSONObject: body))
            }
            MockURLProtocol.handlers["notifications/initialized"] = { _ in (202, [:], Data()) }
            MockURLProtocol.handlers["tools/list"] = { _ in
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": ["tools": []]]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            // Verify capabilities include MIME types
            let params = capturedInitBody?["params"] as? [String: Any]
            let caps = params?["capabilities"] as? [String: Any]
            let extensions = caps?["extensions"] as? [String: Any]
            let ui = extensions?["io.modelcontextprotocol/ui"] as? [String: Any]
            let mimeTypes = ui?["mimeTypes"] as? [String]
            #expect(mimeTypes?.contains("application/vnd.bindjs+json") == true)
        }
    }

    // MARK: - MCP 2026-07-28

    @Suite("MCP 2026-07-28")
    struct ModernProtocolTests {
        init() { MockURLProtocol.reset() }

        @Test func discoversModernServerAndSendsSelfDescribingRequests() async throws {
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": [
                        "resultType": "complete",
                        "ttlMs": 0,
                        "cacheScope": "private",
                        "tools": []
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let tools = try await client.listTools()

            #expect(tools.isEmpty)
            #expect(MockURLProtocol.requestLog.map(\.method) == ["server/discover", "tools/list"])

            for request in MockURLProtocol.requestLog {
                #expect(request.urlRequest.value(forHTTPHeaderField: "MCP-Protocol-Version") == "2026-07-28")
                #expect(request.urlRequest.value(forHTTPHeaderField: "Mcp-Method") == request.method)
                #expect(request.urlRequest.value(forHTTPHeaderField: "Mcp-Session-Id") == nil)
                #expect(request.json?["_meta"] == nil)

                let params = request.json?["params"] as? [String: Any]
                let metadata = params?["_meta"] as? [String: Any]
                #expect(metadata?["io.modelcontextprotocol/protocolVersion"] as? String == "2026-07-28")

                let clientInfo = metadata?["io.modelcontextprotocol/clientInfo"] as? [String: Any]
                #expect(clientInfo?["name"] as? String == "MCPAppsHost")
                #expect(clientInfo?["version"] as? String == "1.0.0")

                let capabilities = metadata?["io.modelcontextprotocol/clientCapabilities"] as? [String: Any]
                let extensions = capabilities?["extensions"] as? [String: Any]
                let ui = extensions?["io.modelcontextprotocol/ui"] as? [String: Any]
                let mimeTypes = ui?["mimeTypes"] as? [String]
                #expect(mimeTypes?.contains("application/vnd.bindjs+json") == true)
            }
        }

        @Test func sendsNameRoutingHeaderForNamedRequests() async throws {
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/call"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": [
                        "resultType": "complete",
                        "content": [["type": "text", "text": "sunny"]],
                        "isError": false
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            MockURLProtocol.handlers["resources/read"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 3,
                    "result": [
                        "resultType": "complete",
                        "ttlMs": 0,
                        "cacheScope": "private",
                        "contents": [[
                            "uri": "ui://weather/card",
                            "mimeType": "application/vnd.bindjs+json",
                            "text": "{}"
                        ]]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.callTool(name: "weather", arguments: .object([:]))
            _ = try await client.readResource(uri: "ui://weather/card")

            let call = try #require(MockURLProtocol.requestLog.first { $0.method == "tools/call" })
            #expect(call.urlRequest.value(forHTTPHeaderField: "Mcp-Name") == "weather")

            let read = try #require(MockURLProtocol.requestLog.first { $0.method == "resources/read" })
            #expect(read.urlRequest.value(forHTTPHeaderField: "Mcp-Name") == "ui://weather/card")
        }

        @Test func encodesUnsafeNameRoutingHeader() async throws {
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/call"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": [
                        "resultType": "complete",
                        "content": [["type": "text", "text": "ok"]]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let unsafeName = "weather 世界"
            let expected = "=?base64?\(Data(unsafeName.utf8).base64EncodedString())?="
            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.callTool(name: unsafeName, arguments: .object([:]))

            let call = try #require(MockURLProtocol.requestLog.first { $0.method == "tools/call" })
            #expect(call.urlRequest.value(forHTTPHeaderField: "Mcp-Name") == expected)
        }

        @Test func mirrorsAnnotatedToolArgumentsIntoHeaders() async throws {
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/list"] = { req in
                let tool: [String: Any] = [
                    "name": "execute_sql",
                    "inputSchema": [
                        "type": "object",
                        "properties": [
                            "region": ["type": "string", "x-mcp-header": "Region"],
                            "confirm": ["type": "boolean", "x-mcp-header": "Confirm"],
                            "options": [
                                "type": "object",
                                "properties": [
                                    "limit": ["type": "integer", "x-mcp-header": "Limit"]
                                ]
                            ],
                            "greeting": ["type": "string", "x-mcp-header": "Greeting"],
                            "optional": ["type": "string", "x-mcp-header": "Optional"]
                        ]
                    ]
                ]
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": ["resultType": "complete", "tools": [tool]]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            MockURLProtocol.handlers["tools/call"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 3,
                    "result": ["resultType": "complete", "content": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(
                url: mockURL,
                headers: ["Mcp-Param-Optional": "stale"],
                configuration: .init(urlSession: mockSession())
            )
            _ = try await client.listTools()
            _ = try await client.callTool(
                name: "execute_sql",
                arguments: .object([
                    "region": "us-west1",
                    "confirm": true,
                    "options": ["limit": 42],
                    "greeting": "Hello, 世界"
                ])
            )

            let call = try #require(MockURLProtocol.requestLog.first { $0.method == "tools/call" })
            #expect(call.urlRequest.value(forHTTPHeaderField: "Mcp-Param-Region") == "us-west1")
            #expect(call.urlRequest.value(forHTTPHeaderField: "Mcp-Param-Confirm") == "true")
            #expect(call.urlRequest.value(forHTTPHeaderField: "Mcp-Param-Limit") == "42")
            #expect(call.urlRequest.value(forHTTPHeaderField: "Mcp-Param-Greeting") ==
                "=?base64?SGVsbG8sIOS4lueVjA==?=")
            #expect(call.urlRequest.value(forHTTPHeaderField: "Mcp-Param-Optional") == nil)
        }

        @Test func refreshesToolSchemaAndRetriesHeaderMismatchOnce() async throws {
            registerModernDiscoverHandler()
            var callCount = 0
            MockURLProtocol.handlers["tools/call"] = { req in
                callCount += 1
                if req.urlRequest.value(forHTTPHeaderField: "Mcp-Param-Region") == nil {
                    let body: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": req.json?["id"] ?? 2,
                        "error": ["code": -32020, "message": "Missing Mcp-Param-Region"]
                    ]
                    return (400, [:], try! JSONSerialization.data(withJSONObject: body))
                }
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 4,
                    "result": [
                        "resultType": "complete",
                        "content": [["type": "text", "text": "ok"]]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            MockURLProtocol.handlers["tools/list"] = { req in
                let tool: [String: Any] = [
                    "name": "regional",
                    "inputSchema": [
                        "type": "object",
                        "properties": ["region": ["type": "string", "x-mcp-header": "Region"]]
                    ]
                ]
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 3,
                    "result": ["resultType": "complete", "tools": [tool]]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let result = try await client.callTool(
                name: "regional",
                arguments: .object(["region": "us-west1"])
            )

            #expect(result.isError == false)
            #expect(callCount == 2)
            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "tools/call", "tools/list", "tools/call"
            ])
            let retry = try #require(MockURLProtocol.requestLog.last)
            #expect(retry.urlRequest.value(forHTTPHeaderField: "Mcp-Param-Region") == "us-west1")
        }

        @Test func excludesInvalidHeaderAnnotationsAndRetainsV2NumberCompatibility() async throws {
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/list"] = { req in
                let valid: [String: Any] = [
                    "name": "valid",
                    "inputSchema": [
                        "type": "object",
                        "properties": ["region": ["type": "string", "x-mcp-header": "Region"]]
                    ]
                ]
                let invalidToken: [String: Any] = [
                    "name": "invalid_token",
                    "inputSchema": [
                        "type": "object",
                        "properties": ["region": ["type": "string", "x-mcp-header": "bad header"]]
                    ]
                ]
                let duplicate: [String: Any] = [
                    "name": "duplicate",
                    "inputSchema": [
                        "type": "object",
                        "properties": [
                            "first": ["type": "string", "x-mcp-header": "Region"],
                            "second": ["type": "string", "x-mcp-header": "region"]
                        ]
                    ]
                ]
                let number: [String: Any] = [
                    "name": "number",
                    "inputSchema": [
                        "type": "object",
                        "properties": ["ratio": ["type": "number", "x-mcp-header": "Ratio"]]
                    ]
                ]
                let arrayPath: [String: Any] = [
                    "name": "array_path",
                    "inputSchema": [
                        "type": "object",
                        "properties": [
                            "regions": [
                                "type": "array",
                                "items": ["type": "string", "x-mcp-header": "Region"]
                            ]
                        ]
                    ]
                ]
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": [
                        "resultType": "complete",
                        "tools": [valid, invalidToken, duplicate, number, arrayPath]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            MockURLProtocol.handlers["tools/call"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 3,
                    "result": ["resultType": "complete", "content": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let tools = try await client.listTools()
            _ = try await client.callTool(
                name: "number",
                arguments: .object(["ratio": .number(3.14159)])
            )

            #expect(tools.map(\.name) == ["valid", "number"])
            let decimalCall = try #require(MockURLProtocol.requestLog.last)
            #expect(decimalCall.urlRequest.value(forHTTPHeaderField: "Mcp-Param-Ratio") == "3.14159")

            _ = try await client.callTool(
                name: "number",
                arguments: .object(["ratio": .number(1e-7)])
            )
            let exponentCall = try #require(MockURLProtocol.requestLog.last)
            #expect(exponentCall.urlRequest.value(forHTTPHeaderField: "Mcp-Param-Ratio") == "0.0000001")
        }

        @Test func rejectsUnsafeIntegerHeaderValue() async throws {
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/list"] = { req in
                let tool: [String: Any] = [
                    "name": "bounded",
                    "inputSchema": [
                        "type": "object",
                        "properties": ["count": ["type": "integer", "x-mcp-header": "Count"]]
                    ]
                ]
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": ["resultType": "complete", "tools": [tool]]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            MockURLProtocol.handlers["tools/call"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 3,
                    "result": ["resultType": "complete", "content": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            do {
                _ = try await client.callTool(
                    name: "bounded",
                    arguments: .object(["count": .number(9_007_199_254_740_992)])
                )
                Issue.record("Should have thrown")
            } catch let error as MCPClientError {
                guard case .invalidResponse(let message) = error else {
                    Issue.record("Expected invalidResponse, got \(error)")
                    return
                }
                #expect(message.contains("safe integer"))
            }

            #expect(MockURLProtocol.requestLog.contains { $0.method == "tools/call" } == false)
        }

        @Test func malformedDiscoverResultFallsBackToLegacy() async throws {
            MockURLProtocol.handlers["server/discover"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 1,
                    "result": [
                        "resultType": "complete",
                        "supportedVersions": ["2026-07-28"]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 4, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "initialize", "notifications/initialized", "tools/list"
            ])
        }

        @Test func malformedDiscoverCapabilitiesFallBackToLegacy() async throws {
            MockURLProtocol.handlers["server/discover"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 1,
                    "result": [
                        "resultType": "complete",
                        "supportedVersions": ["2026-07-28"],
                        "capabilities": ["tools": "invalid"]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 4, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "initialize", "notifications/initialized", "tools/list"
            ])
        }

        @Test func malformedNestedDiscoverCapabilitiesFallBackToLegacy() async throws {
            MockURLProtocol.handlers["server/discover"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 1,
                    "result": [
                        "resultType": "complete",
                        "supportedVersions": ["2026-07-28"],
                        "capabilities": [
                            "resources": ["subscribe": "yes", "listChanged": false],
                            "tools": ["listChanged": true]
                        ]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 4, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "initialize", "notifications/initialized", "tools/list"
            ])
        }

        @Test func malformedDiscoverCapabilityMapFallsBackToLegacy() async throws {
            MockURLProtocol.handlers["server/discover"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 1,
                    "result": [
                        "resultType": "complete",
                        "supportedVersions": ["2026-07-28"],
                        "capabilities": [
                            "experimental": ["valid": ["enabled": true]],
                            "extensions": ["invalid": "must be an object"]
                        ]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 4, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "initialize", "notifications/initialized", "tools/list"
            ])
        }

        @Test func mismatchedDiscoverResponseFailsWithoutDowngrade() async throws {
            MockURLProtocol.handlers["server/discover"] = { _ in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": 999,
                    "result": [
                        "resultType": "complete",
                        "supportedVersions": ["2026-07-28"],
                        "capabilities": ["tools": [:]]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch {
                // A response for another request is not evidence of a legacy server.
            }

            #expect(MockURLProtocol.requestLog.map(\.method) == ["server/discover"])
        }

        @Test func malformedSuccessfulProbeEnvelopeFailsWithoutDowngrade() async throws {
            MockURLProtocol.reset()
            MockURLProtocol.handlers["server/discover"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "1.0",
                    "id": req.json?["id"] ?? 1,
                    "result": [
                        "resultType": "complete",
                        "supportedVersions": ["2026-07-28"],
                        "capabilities": ["tools": [:]]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 4, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch {
                // Expected: a malformed successful probe is not legacy evidence.
            }

            #expect(MockURLProtocol.requestLog.map(\.method) == ["server/discover"])
        }

        @Test func successfulProbeErrorWithNullIDFailsWithoutDowngrade() async throws {
            MockURLProtocol.reset()
            MockURLProtocol.handlers["server/discover"] = { _ in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": NSNull(),
                    "error": ["code": -32601, "message": "Method not found"]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 4, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch {
                // Expected: successful HTTP responses must correlate to the probe.
            }

            #expect(MockURLProtocol.requestLog.map(\.method) == ["server/discover"])
        }

        @Test func malformedSuccessfulSSEProbeFailsWithoutDowngrade() async throws {
            MockURLProtocol.reset()
            MockURLProtocol.handlers["server/discover"] = { _ in
                (200, ["content-type": "text/event-stream"], Data("event: message\n\n".utf8))
            }
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 4, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch {
                // Expected: malformed 2xx SSE is not legacy evidence.
            }

            #expect(MockURLProtocol.requestLog.map(\.method) == ["server/discover"])
        }

        @Test func rateLimitedProbeStopsWithoutLegacyFallback() async throws {
            MockURLProtocol.handlers["server/discover"] = { _ in
                (
                    429,
                    ["Retry-After": "60", "content-type": "text/event-stream"],
                    Data("event: error\n\n".utf8)
                )
            }
            let client = MCPAppsClient(
                url: mockURL,
                configuration: .init(maxRetries: 0, urlSession: mockSession())
            )

            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch let error as MCPClientError {
                guard case .serverError(let status, _) = error else {
                    Issue.record("Expected serverError, got \(error)")
                    return
                }
                #expect(status == 429)
            }

            #expect(MockURLProtocol.requestLog.map(\.method) == ["server/discover"])
        }

        @Test func fallsBackToLegacyInitializeWhenDiscoverIsUnknown() async throws {
            MockURLProtocol.handlers["server/discover"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 1,
                    "error": ["code": -32601, "message": "Method not found"]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(sessionId: "legacy-session", version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 3,
                    "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "initialize", "notifications/initialized", "tools/list"
            ])
            let list = try #require(MockURLProtocol.requestLog.last)
            #expect(list.urlRequest.value(forHTTPHeaderField: "Mcp-Session-Id") == "legacy-session")
        }

        @Test func fallsBackForNonNegotiationProtocolErrorDuringProbe() async throws {
            MockURLProtocol.handlers["server/discover"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 1,
                    "error": ["code": -32020, "message": "Mcp-Method header mismatch"]
                ]
                return (400, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(sessionId: "fallback-session", version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 3,
                    "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(
                url: mockURL,
                configuration: .init(maxRetries: 0, urlSession: mockSession())
            )
            _ = try await client.listTools()

            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "initialize", "notifications/initialized", "tools/list"
            ])
        }

        @Test func fallsBackForLegacyProbeErrorWithNullID() async throws {
            MockURLProtocol.handlers["server/discover"] = { _ in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": NSNull(),
                    "error": ["code": -32000, "message": "Server not initialized"]
                ]
                return (400, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 4, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "initialize", "notifications/initialized", "tools/list"
            ])
        }

        @Test func retriesDiscoverOnceWhenServerOffersRequestedModernVersion() async throws {
            var discoverCount = 0
            MockURLProtocol.handlers["server/discover"] = { req in
                discoverCount += 1
                if discoverCount == 1 {
                    let body: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": req.json?["id"] ?? 1,
                        "error": [
                            "code": -32022,
                            "message": "Select a supported protocol version",
                            "data": [
                                "supported": ["2026-07-28"],
                                "requested": "2026-07-28"
                            ]
                        ]
                    ]
                    return (400, [:], try! JSONSerialization.data(withJSONObject: body))
                }

                let result: [String: Any] = [
                    "resultType": "complete",
                    "supportedVersions": ["2026-07-28"],
                    "capabilities": ["tools": [:]],
                    "ttlMs": 0,
                    "cacheScope": "private"
                ]
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": result
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 3,
                    "result": ["resultType": "complete", "tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            #expect(discoverCount == 2)
            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "server/discover", "tools/list"
            ])
        }

        @Test func correctiveRetryCanStillClassifyServerAsLegacy() async throws {
            var discoverCount = 0
            MockURLProtocol.handlers["server/discover"] = { req in
                discoverCount += 1
                let body: [String: Any]
                if discoverCount == 1 {
                    body = [
                        "jsonrpc": "2.0",
                        "id": req.json?["id"] ?? 1,
                        "error": [
                            "code": -32022,
                            "message": "Select a supported protocol version",
                            "data": ["supported": ["2026-07-28"], "requested": "2026-07-28"]
                        ]
                    ]
                } else {
                    body = [
                        "jsonrpc": "2.0",
                        "id": NSNull(),
                        "error": ["code": -32601, "message": "Method not found"]
                    ]
                }
                return (400, [:], try! JSONSerialization.data(withJSONObject: body))
            }
            registerInitHandlers(version: "2025-11-25")
            MockURLProtocol.handlers["tools/list"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 5, "result": ["tools": []]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            _ = try await client.listTools()

            #expect(MockURLProtocol.requestLog.map(\.method) == [
                "server/discover", "server/discover", "initialize", "notifications/initialized", "tools/list"
            ])
        }

        @Test func doesNotFallBackWhenUnsupportedVersionHasNoLegacyAlternative() async throws {
            MockURLProtocol.handlers["server/discover"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 1,
                    "error": [
                        "code": -32022,
                        "message": "Unsupported protocol version",
                        "data": [
                            "supported": ["2027-01-01"],
                            "requested": "2026-07-28"
                        ]
                    ]
                ]
                return (400, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(
                url: mockURL,
                configuration: .init(maxRetries: 0, urlSession: mockSession())
            )

            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch let error as MCPClientError {
                guard case .rpcError(let code, _, _) = error else {
                    Issue.record("Expected rpcError, got \(error)")
                    return
                }
                #expect(code == -32022)
            }

            #expect(MockURLProtocol.requestLog.map(\.method) == ["server/discover"])
        }

        @Test func doesNotCacheModernResourceWhenServerSetsZeroTTL() async throws {
            registerModernDiscoverHandler()
            var readCount = 0
            MockURLProtocol.handlers["resources/read"] = { req in
                readCount += 1
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": [
                        "resultType": "complete",
                        "ttlMs": 0,
                        "cacheScope": "private",
                        "contents": [[
                            "uri": "ui://weather/live",
                            "mimeType": "application/vnd.bindjs+json",
                            "text": "{\"reading\":\(readCount)}"
                        ]]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let first = try await client.readResource(uri: "ui://weather/live")
            let second = try await client.readResource(uri: "ui://weather/live")

            #expect(readCount == 2)
            #expect(first.text == "{\"reading\":1}")
            #expect(second.text == "{\"reading\":2}")
        }

        @Test func rejectsUnsupportedMultiRoundTripResult() async throws {
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/call"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": [
                        "resultType": "input_required",
                        "inputRequests": [
                            "confirmation": [
                                "method": "elicitation/create",
                                "params": ["message": "Continue?"]
                            ]
                        ]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))

            do {
                _ = try await client.callTool(name: "needs_confirmation", arguments: .object([:]))
                Issue.record("Should have thrown")
            } catch let error as MCPClientError {
                guard case .invalidResponse(let message) = error else {
                    Issue.record("Expected invalidResponse, got \(error)")
                    return
                }
                #expect(message.contains("input_required"))
            }
        }

        @Test func rejectsMalformedModernToolResults() async throws {
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/call"] = { req in
                let name = (req.json?["params"] as? [String: Any])?["name"] as? String
                let result: [String: Any]
                if name == "bad_result_type" {
                    result = [
                        "resultType": 7,
                        "content": [["type": "text", "text": "not complete"]]
                    ]
                } else if name == "missing_result_type" {
                    result = [
                        "content": [["type": "text", "text": "missing discriminator"]]
                    ]
                } else {
                    result = ["resultType": "complete"]
                }
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": req.json?["id"] ?? 2, "result": result
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))

            for name in ["bad_result_type", "missing_result_type", "missing_content"] {
                do {
                    _ = try await client.callTool(name: name, arguments: .object([:]))
                    Issue.record("Should have rejected \(name)")
                } catch let error as MCPClientError {
                    guard case .invalidResponse = error else {
                        Issue.record("Expected invalidResponse, got \(error)")
                        continue
                    }
                }
            }
        }

        @Test func retainsStandardNestedEmbeddedResources() async throws {
            MockURLProtocol.reset()
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/call"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": [
                        "resultType": "complete",
                        "content": [
                            [
                                "type": "resource",
                                "resource": [
                                    "uri": "ui://recipe-card",
                                    "text": "<p>Recipe</p>"
                                ]
                            ],
                            [
                                "type": "resource",
                                "resource": [
                                    "uri": "data://thumbnail",
                                    "mimeType": "application/octet-stream",
                                    "blob": Data([0x01, 0x02, 0x03]).base64EncodedString()
                                ]
                            ],
                            [
                                "type": "audio",
                                "data": Data([0x04, 0x05]).base64EncodedString(),
                                "mimeType": "audio/mpeg"
                            ],
                            [
                                "type": "resource_link",
                                "name": "Recipe source",
                                "title": "Recipes",
                                "uri": "https://example.com/recipes",
                                "description": "Source material",
                                "mimeType": "text/html",
                                "size": 128
                            ]
                        ]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let result = try await client.callTool(name: "get_recipe", arguments: .object([:]))

            #expect(result.content.count == 4)
            if case .resource(let uri, let mimeType, let text) = result.content[0] {
                #expect(uri == "ui://recipe-card")
                #expect(mimeType == "application/octet-stream")
                #expect(text == "<p>Recipe</p>")
            } else {
                Issue.record("Expected a nested text resource")
            }
            if case .resourceBlob(let uri, let mimeType, let blob) = result.content[1] {
                #expect(uri == "data://thumbnail")
                #expect(mimeType == "application/octet-stream")
                #expect(blob == Data([0x01, 0x02, 0x03]))
            } else {
                Issue.record("Expected a nested blob resource")
            }
            if case .audio(let data, let mimeType) = result.content[2] {
                #expect(data == Data([0x04, 0x05]))
                #expect(mimeType == "audio/mpeg")
            } else {
                Issue.record("Expected audio content")
            }
            if case .resourceLink(
                let name, let title, let uri, let description, let mimeType, let size
            ) = result.content[3] {
                #expect(name == "Recipe source")
                #expect(title == "Recipes")
                #expect(uri == "https://example.com/recipes")
                #expect(description == "Source material")
                #expect(mimeType == "text/html")
                #expect(size == 128)
            } else {
                Issue.record("Expected resource link content")
            }
        }

        @Test func rejectsNestedEmbeddedResourceWithoutPayload() async throws {
            MockURLProtocol.reset()
            registerModernDiscoverHandler()
            MockURLProtocol.handlers["tools/call"] = { req in
                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": req.json?["id"] ?? 2,
                    "result": [
                        "resultType": "complete",
                        "content": [[
                            "type": "resource",
                            "resource": ["uri": "data://empty"]
                        ]]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            do {
                _ = try await client.callTool(name: "empty_resource", arguments: .object([:]))
                Issue.record("Should have thrown")
            } catch let error as MCPClientError {
                guard case .invalidResponse = error else {
                    Issue.record("Expected invalidResponse, got \(error)")
                    return
                }
            }
        }
    }

    // MARK: - Tool Operations

    @Suite("Tool Operations")
    struct ToolOperationTests {
        init() { MockURLProtocol.reset() }

        @Test func listToolsParsesResponse() async throws {
            registerInitHandlers()
            MockURLProtocol.handlers["tools/list"] = { _ in
                let tools: [[String: Any]] = [
                    [
                        "name": "gallery",
                        "description": "Render a gallery",
                        "inputSchema": ["type": "object", "properties": ["images": ["type": "array"]]],
                        "_meta": ["ui": ["resourceUri": "ui://metabind/render/abc123"]]
                    ],
                    [
                        "name": "weather_data",
                        "description": "Fetch weather"
                    ]
                ]
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": ["tools": tools]]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let tools = try await client.listTools()

            #expect(tools.count == 2)
            #expect(tools[0].name == "gallery")
            #expect(tools[0].description == "Render a gallery")
            #expect(tools[0].ui?.resourceUri == "ui://metabind/render/abc123")
            #expect(tools[1].name == "weather_data")
            #expect(tools[1].ui == nil)
        }

        @Test func listToolsHandlesPagination() async throws {
            registerInitHandlers()
            var page = 0
            MockURLProtocol.handlers["tools/list"] = { req in
                page += 1
                let json = req.json!
                let params = json["params"] as? [String: Any] ?? [:]

                if params["cursor"] == nil {
                    // Page 1
                    let tools: [[String: Any]] = [["name": "tool_a"]]
                    let result: [String: Any] = ["tools": tools, "nextCursor": "page2"]
                    return (200, [:], try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": json["id"]!, "result": result]))
                } else {
                    // Page 2
                    let tools: [[String: Any]] = [["name": "tool_b"]]
                    let result: [String: Any] = ["tools": tools]
                    return (200, [:], try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": json["id"]!, "result": result]))
                }
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let tools = try await client.listTools()

            #expect(tools.count == 2)
            #expect(tools[0].name == "tool_a")
            #expect(tools[1].name == "tool_b")
            #expect(page == 2)
        }

        @Test func callToolReturnsResult() async throws {
            registerInitHandlers()
            MockURLProtocol.handlers["tools/call"] = { _ in
                let result: [String: Any] = [
                    "content": [["type": "text", "text": "Hello from tool"]],
                    "isError": false
                ]
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 3, "result": result]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let result = try await client.callTool(name: "test_tool", arguments: ["input": "value"])

            #expect(result.isError == false)
            #expect(result.content.count == 1)
            if case .text(let text) = result.content[0] {
                #expect(text == "Hello from tool")
            } else {
                Issue.record("Expected text content")
            }
        }

        @Test func callToolHandlesErrorResult() async throws {
            registerInitHandlers()
            MockURLProtocol.handlers["tools/call"] = { _ in
                let result: [String: Any] = [
                    "content": [["type": "text", "text": "Something went wrong"]],
                    "isError": true
                ]
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 3, "result": result]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let result = try await client.callTool(name: "broken_tool", arguments: .object([:]))

            #expect(result.isError == true)
        }

        @Test func readResourceCachesResult() async throws {
            registerInitHandlers()
            var fetchCount = 0
            MockURLProtocol.handlers["resources/read"] = { _ in
                fetchCount += 1
                let result: [String: Any] = [
                    "contents": [["uri": "ui://test/res", "mimeType": "application/json", "text": "{\"data\":\"hello\"}"]]
                ]
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 3, "result": result]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))

            let r1 = try await client.readResource(uri: "ui://test/res")
            let r2 = try await client.readResource(uri: "ui://test/res")

            #expect(r1.mimeType == "application/json")
            #expect(r2.text == r1.text)
            #expect(fetchCount == 1) // Only one network call — second was cached
        }
    }

    // MARK: - SSE Parsing

    @Suite("SSE Parsing")
    struct SSETests {
        init() { MockURLProtocol.reset() }

        @Test func handlesSSEResponse() async throws {
            registerInitHandlers()
            MockURLProtocol.handlers["tools/list"] = { _ in
                let sseBody = """
                event: message
                data: {"jsonrpc":"2.0","id":2,"result":{"tools":[]}}

                """
                return (200, ["content-type": "text/event-stream"], Data(sseBody.utf8))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let tools = try await client.listTools()
            #expect(tools.isEmpty)
        }

        @Test func takesLastSSEDataLine() async throws {
            registerInitHandlers()
            MockURLProtocol.handlers["tools/list"] = { _ in
                let sseBody = """
                data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"early"}]}}

                data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"final"}]}}

                """
                return (200, ["content-type": "text/event-stream"], Data(sseBody.utf8))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let tools = try await client.listTools()
            #expect(tools.count == 1)
            #expect(tools[0].name == "final")
        }
    }

    // MARK: - Retry / Backoff

    @Suite("Retry")
    struct RetryTests {
        init() { MockURLProtocol.reset() }

        @Test func retriesOn5xxWithBackoff() async throws {
            registerInitHandlers()
            var attempts = 0
            MockURLProtocol.handlers["tools/list"] = { _ in
                attempts += 1
                if attempts <= 2 {
                    return (503, [:], Data("Service Unavailable".utf8))
                }
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": ["tools": []]]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(
                url: mockURL,
                configuration: .init(maxRetries: 2, retryBaseDelay: 0.01, urlSession: mockSession())
            )
            let tools = try await client.listTools()
            #expect(tools.isEmpty)
            #expect(attempts == 3) // 2 failures + 1 success
        }

        @Test func stopsRetryingAfterMaxRetries() async throws {
            registerInitHandlers()
            var attempts = 0
            MockURLProtocol.handlers["tools/list"] = { _ in
                attempts += 1
                return (500, [:], Data("Server Error".utf8))
            }

            let client = MCPAppsClient(
                url: mockURL,
                configuration: .init(maxRetries: 1, retryBaseDelay: 0.01, urlSession: mockSession())
            )

            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch {
                // Expected — exhausted retries
            }
            #expect(attempts == 2) // 1 initial + 1 retry
        }

        @Test func doesNotRetryOn4xx() async throws {
            registerInitHandlers()
            var attempts = 0
            MockURLProtocol.handlers["tools/list"] = { _ in
                attempts += 1
                return (400, [:], Data("Bad Request".utf8))
            }

            let client = MCPAppsClient(
                url: mockURL,
                configuration: .init(maxRetries: 3, retryBaseDelay: 0.01, urlSession: mockSession())
            )

            do {
                _ = try await client.listTools()
                Issue.record("Should have thrown")
            } catch {
                // Expected — 4xx is not retried
            }
            #expect(attempts == 1)
        }

        @Test func sessionExpiryReInitializes() async throws {
            var initCount = 0
            MockURLProtocol.handlers["initialize"] = { _ in
                initCount += 1
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": 1,
                    "result": [
                        "protocolVersion": "2025-03-26",
                        "capabilities": [:],
                        "serverInfo": ["name": "mock", "version": "1.0"]
                    ]
                ]
                return (200, ["Mcp-Session-Id": "session-\(initCount)"], try! JSONSerialization.data(withJSONObject: body))
            }
            MockURLProtocol.handlers["notifications/initialized"] = { _ in (202, [:], Data()) }

            var toolCallCount = 0
            MockURLProtocol.handlers["tools/list"] = { _ in
                toolCallCount += 1
                if toolCallCount == 1 {
                    // First call: session expired
                    return (404, [:], Data("Not Found".utf8))
                }
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": ["tools": []]]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))
            let tools = try await client.listTools()
            #expect(tools.isEmpty)
            #expect(initCount == 2) // Original init + re-init after 404
        }
    }

    // MARK: - JSON-RPC Error Handling

    @Suite("JSON-RPC Errors")
    struct RPCErrorTests {
        init() { MockURLProtocol.reset() }

        @Test func handlesRPCError() async throws {
            registerInitHandlers()
            MockURLProtocol.handlers["tools/call"] = { _ in
                let body: [String: Any] = [
                    "jsonrpc": "2.0", "id": 3,
                    "error": [
                        "code": -32602,
                        "message": "Invalid params",
                        "data": ["detail": "missing 'name' field"]
                    ]
                ]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(url: mockURL, configuration: .init(urlSession: mockSession()))

            do {
                _ = try await client.callTool(name: "bad_tool", arguments: .object([:]))
                Issue.record("Should have thrown")
            } catch let error as MCPClientError {
                if case .rpcError(let code, let message, let data) = error {
                    #expect(code == -32602)
                    #expect(message == "Invalid params")
                    #expect(data?.contains("missing") == true)
                } else {
                    Issue.record("Expected rpcError, got \(error)")
                }
            }
        }
    }

    // MARK: - Header Provider

    @Suite("Headers")
    struct HeaderTests {
        init() { MockURLProtocol.reset() }

        @Test func dynamicHeaderProviderCalledPerRequest() async throws {
            var callCount = 0
            registerInitHandlers()
            MockURLProtocol.handlers["tools/list"] = { _ in
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": ["tools": []]]
                return (200, [:], try! JSONSerialization.data(withJSONObject: body))
            }

            let client = MCPAppsClient(
                url: mockURL,
                headerProvider: {
                    callCount += 1
                    return ["authorization": "Bearer token-\(callCount)"]
                },
                configuration: .init(urlSession: mockSession())
            )

            _ = try await client.listTools()
            // Provider called for: discover, initialize, notifications/initialized, tools/list
            #expect(callCount == 4)
        }
    }
}

// MARK: - CSP Injection Tests

@Suite("CSP Injection")
struct CSPInjectionTests {

    @Test func injectsIntoHead() {
        let html = "<html><head><title>Test</title></head><body>Hello</body></html>"
        let result = injectCSP(html)
        #expect(result.contains("Content-Security-Policy"))
        // CSP should be right after <head>
        let headIndex = result.range(of: "<head>")!.upperBound
        let cspIndex = result.range(of: "Content-Security-Policy")!.lowerBound
        #expect(cspIndex > headIndex)
        // Title should still be there
        #expect(result.contains("<title>Test</title>"))
    }

    @Test func injectsAfterHtmlTagWhenNoHead() {
        let html = "<html><body>No head tag</body></html>"
        let result = injectCSP(html)
        #expect(result.contains("Content-Security-Policy"))
        #expect(result.contains("<head>"))
        #expect(result.contains("No head tag"))
    }

    @Test func prependsWhenNoHtmlOrHead() {
        let html = "<div>Just a fragment</div>"
        let result = injectCSP(html)
        #expect(result.hasPrefix("<meta"))
        #expect(result.contains("Content-Security-Policy"))
        #expect(result.contains("Just a fragment"))
    }

    @Test func cspBlocksConnectSrc() {
        let html = "<html><head></head><body></body></html>"
        let result = injectCSP(html)
        #expect(result.contains("connect-src 'none'"))
    }

    @Test func cspAllowsInlineScripts() {
        let html = "<html><head></head><body></body></html>"
        let result = injectCSP(html)
        #expect(result.contains("script-src 'unsafe-inline'"))
    }

    @Test func cspBlocksFormAction() {
        let html = "<html><head></head><body></body></html>"
        let result = injectCSP(html)
        #expect(result.contains("form-action 'none'"))
    }

    @Test func cspAllowsHttpsImages() {
        let html = "<html><head></head><body></body></html>"
        let result = injectCSP(html)
        #expect(result.contains("img-src https: data:"))
    }

    @Test func caseInsensitiveHeadDetection() {
        let html = "<HTML><HEAD></HEAD><BODY>Upper case</BODY></HTML>"
        let result = injectCSP(html)
        #expect(result.contains("Content-Security-Policy"))
        // Should inject after <HEAD>, not prepend
        let headIndex = result.range(of: "<HEAD>", options: .caseInsensitive)!.upperBound
        let cspIndex = result.range(of: "Content-Security-Policy")!.lowerBound
        #expect(cspIndex > headIndex)
    }
}
