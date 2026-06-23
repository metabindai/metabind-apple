import Foundation
import os

private let log = Logger(subsystem: "MCPAppsHost", category: "MCPAppsClient")

/// Ready-to-use MCP client with automatic initialization and MIME type negotiation.
///
/// Handles the full MCP lifecycle — the consuming app just provides a URL and auth:
///
///     let client = MCPAppsClient(
///         url: serverURL,
///         headers: ["authorization": "Bearer \(key)"]
///     )
///     // .mcpServer(client)  — that's it
///
/// On first use, the client automatically:
/// 1. Sends `initialize` with protocol version, capabilities, and supported MIME types
/// 2. Negotiates with the server
/// 3. Sends `notifications/initialized`
/// 4. Proceeds with the requested operation
///
public actor MCPAppsClient: MCPServer {
    private let url: URL
    private let resolvers: [any ContentResolver]
    private let configuration: Configuration
    private let headerProvider: @Sendable () async -> [String: String]

    private var isInitialized = false
    private var initializationTask: Task<Void, any Error>?
    private var sessionId: String?
    private var nextRequestId = 1

    /// LRU resource cache keyed by URI.
    private var resourceCache: OrderedCache<String, ResourceContent>

    /// Protocol versions this client can accept.
    private static let supportedVersions: Set<String> = ["2025-03-26", "2024-11-05"]
    private static let preferredVersion = "2025-03-26"

    /// Client configuration.
    public struct Configuration: Sendable {
        /// Timeout for HTTP requests.
        public var requestTimeout: TimeInterval
        /// Maximum entries in the resource cache.
        public var maxCacheEntries: Int
        /// Maximum retry attempts for transient failures (excludes session expiry retries).
        public var maxRetries: Int
        /// Base delay for exponential backoff. Doubled on each retry.
        public var retryBaseDelay: TimeInterval
        /// Custom URLSession. Provide your own for cert pinning, proxy, etc.
        public var urlSession: URLSession

        public init(
            requestTimeout: TimeInterval = 30,
            maxCacheEntries: Int = 50,
            maxRetries: Int = 2,
            retryBaseDelay: TimeInterval = 0.5,
            urlSession: URLSession = .shared
        ) {
            self.requestTimeout = requestTimeout
            self.maxCacheEntries = maxCacheEntries
            self.maxRetries = maxRetries
            self.retryBaseDelay = retryBaseDelay
            self.urlSession = urlSession
        }
    }

    /// Creates a client that connects to an MCP server over HTTP.
    ///
    /// - Parameters:
    ///   - url: The MCP server endpoint.
    ///   - headers: Static HTTP headers (e.g. authorization). Applied to every request.
    ///   - resolvers: Content resolvers. Defaults to BindJS + HTML. MIME types are
    ///     derived from these and advertised to the server during initialization.
    ///   - configuration: Timeouts, cache sizes, retry behavior.
    public init(
        url: URL,
        headers: [String: String] = [:],
        resolvers: [any ContentResolver] = defaultResolvers,
        configuration: Configuration = Configuration()
    ) {
        self.url = url
        let captured = headers
        self.headerProvider = { captured }
        self.resolvers = resolvers
        self.configuration = configuration
        self.resourceCache = OrderedCache(maxEntries: configuration.maxCacheEntries)
    }

    /// Creates a client with a dynamic header provider for token refresh.
    ///
    /// The provider is called before every request, allowing OAuth token refresh,
    /// request signing, or dynamic header injection.
    ///
    ///     let client = MCPAppsClient(url: serverURL) {
    ///         let token = try await auth.freshToken()
    ///         return ["authorization": "Bearer \(token)"]
    ///     }
    ///
    public init(
        url: URL,
        headerProvider: @escaping @Sendable () async -> [String: String],
        resolvers: [any ContentResolver] = defaultResolvers,
        configuration: Configuration = Configuration()
    ) {
        self.url = url
        self.headerProvider = headerProvider
        self.resolvers = resolvers
        self.configuration = configuration
        self.resourceCache = OrderedCache(maxEntries: configuration.maxCacheEntries)
    }

    // MARK: - MCPServer

    public func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
        try await ensureInitialized()

        log.info("tools/call → \(name)")
        let params: [String: Any] = [
            "name": name,
            "arguments": arguments.toAny()
        ]
        let response = try await sendRequest(method: "tools/call", params: params)

        guard let result = response["result"] as? [String: Any] else {
            throw MCPClientError.invalidResponse("Missing result in tools/call response")
        }

        let isError = result["isError"] as? Bool ?? false
        let contentArray = result["content"] as? [[String: Any]] ?? []
        let contentData = try JSONSerialization.data(withJSONObject: contentArray)
        let blocks = (try? JSONDecoder().decode([ContentBlock].self, from: contentData)) ?? []

        let toolResult = ToolResult(content: blocks.isEmpty ? [.text("")] : blocks, isError: isError)
        log.info("tools/call ← \(name): \(blocks.count) block(s), isError=\(isError)")
        return toolResult
    }

    public func readResource(uri: String) async throws -> ResourceContent {
        try await ensureInitialized()

        if let cached = resourceCache.get(uri) {
            log.info("resources/read → \(uri) (cached)")
            return cached
        }

        log.info("resources/read → \(uri)")
        let params: [String: Any] = ["uri": uri]
        let response = try await sendRequest(method: "resources/read", params: params)

        guard let result = response["result"] as? [String: Any],
              let contents = result["contents"] as? [[String: Any]],
              let first = contents.first else {
            throw MCPClientError.invalidResponse("Missing contents in resources/read response")
        }

        let mimeType = first["mimeType"] as? String ?? "application/octet-stream"
        let textLen = (first["text"] as? String)?.count ?? 0
        let hasBlob = first["blob"] != nil
        log.info("resources/read ← \(uri): mimeType=\(mimeType), text=\(textLen) chars, blob=\(hasBlob)")

        let resource = ResourceContent(
            uri: first["uri"] as? String ?? uri,
            mimeType: mimeType,
            text: first["text"] as? String,
            blob: (first["blob"] as? String).flatMap { Data(base64Encoded: $0) }
        )

        resourceCache.set(uri, resource)
        return resource
    }

    // MARK: - Tool Discovery

    /// Lists available tools from the server. Handles pagination automatically.
    public func listTools() async throws -> [MCPToolDefinition] {
        try await ensureInitialized()

        log.info("tools/list →")
        var allDefs: [MCPToolDefinition] = []
        var cursor: String? = nil

        repeat {
            var params: [String: Any] = [:]
            if let cursor { params["cursor"] = cursor }

            let response = try await sendRequest(method: "tools/list", params: params)

            guard let result = response["result"] as? [String: Any],
                  let tools = result["tools"] as? [[String: Any]] else {
                break
            }

            let defs = tools.compactMap { tool -> MCPToolDefinition? in
                guard let name = tool["name"] as? String else { return nil }

                let schemaDict = tool["inputSchema"] as? [String: Any] ?? ["type": "object", "properties": [:]]
                let schema = JSONValue.from(schemaDict)
                let ui = MCPToolDefinition.uiMetadata(from: JSONValue.from(tool["_meta"] as Any))

                let hasUI = ui?.resourceUri != nil
                log.info("  tool: \(name)\(hasUI ? " (ui: \(ui!.resourceUri))" : "")")

                return MCPToolDefinition(
                    name: name,
                    description: tool["description"] as? String,
                    inputSchema: schema,
                    ui: ui
                )
            }

            allDefs.append(contentsOf: defs)
            cursor = result["nextCursor"] as? String
        } while cursor != nil

        log.info("tools/list ← \(allDefs.count) tool(s)")
        return allDefs
    }

    /// Clears the resource cache. Call when the server notifies that resources have changed.
    public func clearResourceCache() {
        resourceCache.removeAll()
    }

    // MARK: - Initialization

    /// Ensures the MCP handshake has completed. Safe to call multiple times —
    /// subsequent calls are no-ops. Concurrent callers coalesce on a single task.
    private func ensureInitialized() async throws {
        if isInitialized { return }

        if let task = initializationTask {
            try await task.value
            return
        }

        let task = Task { try await performInitialize() }
        initializationTask = task

        do {
            try await task.value
        } catch {
            // Clear the failed task so the next call retries instead of
            // returning the same failed result forever.
            initializationTask = nil
            throw error
        }
    }

    private func performInitialize() async throws {
        let mimeTypes = resolvers.flatMap(\.supportedMimeTypes)

        log.info("Initializing MCP connection to \(self.url.absoluteString)")
        log.info("  protocol: \(Self.preferredVersion)")
        log.info("  mimeTypes: \(mimeTypes)")
        log.info("  resolvers: \(self.resolvers.map { String(describing: type(of: $0)) })")

        var capabilities: [String: Any] = [:]
        if !mimeTypes.isEmpty {
            capabilities["extensions"] = [
                "io.modelcontextprotocol/ui": [
                    "mimeTypes": mimeTypes
                ]
            ]
        }

        let params: [String: Any] = [
            "protocolVersion": Self.preferredVersion,
            "capabilities": capabilities,
            "clientInfo": [
                "name": "MCPAppsHost",
                "version": "1.0.0"
            ]
        ]

        log.info("initialize →")
        let (response, initHTTP) = try await sendRequestRaw(method: "initialize", params: params)

        guard let result = response["result"] as? [String: Any] else {
            throw MCPClientError.invalidResponse("Missing result in initialize response")
        }

        if let sid = initHTTP.value(forHTTPHeaderField: "Mcp-Session-Id") {
            sessionId = sid
            log.info("  session: \(sid)")
        }

        guard let version = result["protocolVersion"] as? String else {
            throw MCPClientError.invalidResponse("Server did not return protocolVersion")
        }
        guard Self.supportedVersions.contains(version) else {
            throw MCPClientError.versionMismatch(requested: Self.preferredVersion, returned: version)
        }

        if let info = result["serverInfo"] as? [String: Any] {
            let name = info["name"] as? String ?? "unknown"
            let ver = info["version"] as? String
            log.info("Connected to \(name) \(ver ?? "")")
        }

        log.info("notifications/initialized →")
        try await sendNotification(method: "notifications/initialized")

        isInitialized = true
        log.info("MCP initialization complete (protocol: \(version), mimeTypes: \(mimeTypes))")
    }

    // MARK: - JSON-RPC Transport

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        // Retry with exponential backoff for transient failures
        var lastError: any Error = MCPClientError.invalidResponse("No attempts made")
        var delay = configuration.retryBaseDelay

        for attempt in 0...configuration.maxRetries {
            do {
                let (json, _) = try await sendRequestRaw(method: method, params: params)
                return json
            } catch MCPClientError.serverError(let status, _) where status == 404 || status == 410 {
                // Session expired — re-initialize and retry once (no backoff).
                log.info("Session expired (HTTP \(status)), re-initializing...")
                resetSession()
                try await ensureInitialized()
                let (json, _) = try await sendRequestRaw(method: method, params: params)
                return json
            } catch MCPClientError.serverError(let status, _) where status >= 500 && attempt < configuration.maxRetries {
                // Transient server error — retry with backoff
                log.info("Server error \(status), retrying in \(delay)s (attempt \(attempt + 1)/\(self.configuration.maxRetries))")
                lastError = MCPClientError.serverError(status: status, body: "")
                try await Task.sleep(for: .seconds(delay))
                delay *= 2
            } catch let error as URLError where isTransient(error) && attempt < configuration.maxRetries {
                log.info("Network error \(error.code.rawValue), retrying in \(delay)s (attempt \(attempt + 1)/\(self.configuration.maxRetries))")
                lastError = error
                try await Task.sleep(for: .seconds(delay))
                delay *= 2
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .dnsLookupFailed, .cannotConnectToHost, .cannotFindHost:
            true
        default:
            false
        }
    }

    /// Resets session state so the next request triggers re-initialization.
    private func resetSession() {
        isInitialized = false
        initializationTask = nil
        sessionId = nil
        resourceCache.removeAll()
    }

    private func sendRequestRaw(method: String, params: [String: Any]) async throws -> ([String: Any], HTTPURLResponse) {
        let requestId = nextRequestId
        nextRequestId += 1
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": method,
            "params": params
        ]

        let (data, http) = try await send(body: body)
        log.debug("HTTP \(http.statusCode) for \(method) (id: \(requestId), \(data.count) bytes)")

        let json: [String: Any]
        let contentType = http.value(forHTTPHeaderField: "content-type") ?? ""

        if contentType.contains("text/event-stream") {
            json = try parseSSEResponse(data: data)
        } else {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPClientError.invalidResponse("Could not parse JSON-RPC response")
            }
            json = parsed
        }

        // Validate response ID matches request
        if let responseId = json["id"] as? Int, responseId != requestId {
            log.warning("Response ID \(responseId) does not match request ID \(requestId)")
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            let code = error["code"] as? Int ?? -1
            let errorData: String? = if let d = error["data"] {
                (try? JSONSerialization.data(withJSONObject: d))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: d)
            } else {
                nil
            }
            log.error("JSON-RPC error for \(method): [\(code)] \(message)")
            throw MCPClientError.rpcError(code: code, message: message, data: errorData)
        }

        return (json, http)
    }

    /// Parse SSE response by extracting all `data:` events and returning the final JSON-RPC message.
    private func parseSSEResponse(data: Data) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPClientError.invalidResponse("SSE response is not valid UTF-8")
        }

        // Extract all data: lines, ignoring event types and comments
        let dataLines = text
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("data:") }
            .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }

        // The last data line is the final JSON-RPC response
        guard let lastLine = dataLines.last, !lastLine.isEmpty else {
            throw MCPClientError.invalidResponse("No data events in SSE response")
        }

        guard let json = try? JSONSerialization.jsonObject(with: Data(lastLine.utf8)) as? [String: Any] else {
            throw MCPClientError.invalidResponse("Could not parse SSE data event as JSON")
        }

        return json
    }

    private func sendNotification(method: String, params: [String: Any] = [:]) async throws {
        var body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if !params.isEmpty {
            body["params"] = params
        }
        _ = try await send(body: body)
    }

    private func send(body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "accept")
        request.timeoutInterval = configuration.requestTimeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let headers = await headerProvider()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // MCP HTTP transport: include session ID in all requests after init
        if let sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        let (data, httpResponse) = try await configuration.urlSession.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse else {
            throw MCPClientError.invalidResponse("Not an HTTP response")
        }

        guard http.statusCode == 200 || http.statusCode == 202 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw MCPClientError.serverError(status: http.statusCode, body: responseBody)
        }

        return (data, http)
    }

}

// MARK: - LRU Cache

/// Simple ordered cache with LRU eviction.
struct OrderedCache<Key: Hashable, Value>: Sendable where Key: Sendable, Value: Sendable {
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []
    private let maxEntries: Int

    init(maxEntries: Int) {
        self.maxEntries = maxEntries
    }

    mutating func get(_ key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        // Move to end (most recently used)
        order.removeAll { $0 == key }
        order.append(key)
        return value
    }

    mutating func set(_ key: Key, _ value: Value) {
        if storage[key] != nil {
            order.removeAll { $0 == key }
        } else if order.count >= maxEntries {
            // Evict least recently used
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
        storage[key] = value
        order.append(key)
    }

    mutating func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    mutating func remove(_ key: Key) {
        storage.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }
}

// MARK: - Errors

public enum MCPClientError: Error, LocalizedError, Sendable {
    case invalidResponse(String)
    case serverError(status: Int, body: String)
    case rpcError(code: Int, message: String, data: String? = nil)
    case versionMismatch(requested: String, returned: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let msg): "Invalid MCP response: \(msg)"
        case .serverError(let s, let b): "MCP server error \(s): \(b)"
        case .rpcError(let c, let m, _): "MCP error \(c): \(m)"
        case .versionMismatch(let req, let ret): "MCP version mismatch: requested \(req), server returned \(ret)"
        }
    }
}
