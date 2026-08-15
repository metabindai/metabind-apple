import Foundation
import os

private let log = Logger(subsystem: "MCPAppsHost", category: "MCPAppsClient")

/// Ready-to-use MCP client with automatic protocol negotiation and MIME type negotiation.
///
/// Handles the full MCP lifecycle — the consuming app just provides a URL and auth:
///
///     let client = MCPAppsClient(
///         url: serverURL,
///         headers: ["authorization": "Bearer \(key)"]
///     )
///     // .mcpServer(client)  — that's it
///
/// On first use, the client probes for the stateless MCP 2026-07-28 protocol. It
/// falls back to the legacy `initialize` handshake when the server does not support it.
///
public actor MCPAppsClient: MCPServer {
    private enum ProtocolEra {
        case modern
        case legacy
    }

    private enum ProbeDisposition {
        case retryModern
        case fallBackToLegacy
        case fail
    }

    private enum ToolHeaderValueType: String, Sendable {
        case string
        case integer
        case boolean
        // Compatibility with the released TypeScript v2 runtime, which
        // accepts annotated numbers in addition to the protocol's primitives.
        case number
    }

    private struct ToolHeaderMapping: Sendable {
        let name: String
        let propertyPath: [String]
        let valueType: ToolHeaderValueType
    }

    private struct ToolHeaderSchemaError: Error, Sendable {
        let reason: String
    }

    private struct ProbeResponseError: Error, LocalizedError, Sendable {
        let reason: String
        var errorDescription: String? { "Invalid server/discover response: \(reason)" }
    }

    private let url: URL
    private let resolvers: [any ContentResolver]
    private let configuration: Configuration
    private let headerProvider: @Sendable () async -> [String: String]

    private var isConnected = false
    private var connectionTask: Task<Void, any Error>?
    private var protocolEra: ProtocolEra?
    private var protocolVersion: String?
    private var sessionId: String?
    private var nextRequestId = 1
    private var toolHeaderMappings: [String: [ToolHeaderMapping]] = [:]

    /// LRU resource cache keyed by URI.
    private var resourceCache: OrderedCache<String, ResourceContent>

    private static let modernProtocolVersion = "2026-07-28"
    private static let supportedLegacyVersions: Set<String> = [
        "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"
    ]
    private static let preferredLegacyVersion = "2025-11-25"
    private static let clientInfo: [String: String] = [
        "name": "MCPAppsHost",
        "version": "1.0.0"
    ]

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
    ///     derived from these and advertised to the server during protocol negotiation.
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
        try await ensureConnected()

        log.info("tools/call → \(name)")
        let params: [String: Any] = [
            "name": name,
            "arguments": arguments.toAny()
        ]
        var customHeaders = try toolParameterHeaders(name: name, arguments: arguments)
        let response: [String: Any]
        do {
            response = try await sendRequest(
                method: "tools/call",
                params: params,
                customHeaders: customHeaders
            )
        } catch MCPClientError.rpcError(let code, _, _)
            where protocolEra == .modern && code == -32020 {
            // The server may have changed an x-mcp-header annotation since the
            // last tools/list. Refresh once and retry with the current schema.
            _ = try await listTools()
            customHeaders = try toolParameterHeaders(name: name, arguments: arguments)
            response = try await sendRequest(
                method: "tools/call",
                params: params,
                customHeaders: customHeaders
            )
        }

        guard let result = response["result"] as? [String: Any] else {
            throw MCPClientError.invalidResponse("Missing result in tools/call response")
        }
        try validateResultType(in: result, method: "tools/call")

        let isError = result["isError"] as? Bool ?? false
        guard let contentArray = result["content"] as? [[String: Any]] else {
            throw MCPClientError.invalidResponse("Missing content in tools/call response")
        }
        let contentData = try JSONSerialization.data(withJSONObject: contentArray)
        let blocks: [ContentBlock]
        do {
            blocks = try JSONDecoder().decode([ContentBlock].self, from: contentData)
        } catch where protocolEra == .modern {
            throw MCPClientError.invalidResponse("Invalid content in tools/call response")
        } catch {
            blocks = []
        }

        let toolResult = ToolResult(content: blocks.isEmpty ? [.text("")] : blocks, isError: isError)
        log.info("tools/call ← \(name): \(blocks.count) block(s), isError=\(isError)")
        return toolResult
    }

    public func readResource(uri: String) async throws -> ResourceContent {
        try await ensureConnected()

        if protocolEra == .legacy, let cached = resourceCache.get(uri) {
            log.info("resources/read → \(uri) (cached)")
            return cached
        }

        log.info("resources/read → \(uri)")
        let params: [String: Any] = ["uri": uri]
        let response = try await sendRequest(method: "resources/read", params: params)

        guard let result = response["result"] as? [String: Any] else {
            throw MCPClientError.invalidResponse("Missing result in resources/read response")
        }
        try validateResultType(in: result, method: "resources/read")

        guard let contents = result["contents"] as? [[String: Any]],
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

        if protocolEra == .legacy {
            resourceCache.set(uri, resource)
        }
        return resource
    }

    // MARK: - Tool Discovery

    /// Lists available tools from the server. Handles pagination automatically.
    public func listTools() async throws -> [MCPToolDefinition] {
        try await ensureConnected()

        log.info("tools/list →")
        var allDefs: [MCPToolDefinition] = []
        var discoveredHeaderMappings: [String: [ToolHeaderMapping]] = [:]
        var cursor: String? = nil

        repeat {
            var params: [String: Any] = [:]
            if let cursor { params["cursor"] = cursor }

            let response = try await sendRequest(method: "tools/list", params: params)

            guard let result = response["result"] as? [String: Any] else {
                break
            }
            try validateResultType(in: result, method: "tools/list")

            guard let tools = result["tools"] as? [[String: Any]] else {
                break
            }

            let defs = tools.compactMap { tool -> MCPToolDefinition? in
                guard let name = tool["name"] as? String else { return nil }

                let schemaDict = tool["inputSchema"] as? [String: Any] ?? ["type": "object", "properties": [:]]
                let schema = JSONValue.from(schemaDict)
                let ui = MCPToolDefinition.uiMetadata(from: JSONValue.from(tool["_meta"] as Any))

                if protocolEra == .modern {
                    do {
                        discoveredHeaderMappings[name] = try headerMappings(in: schema)
                    } catch let error as ToolHeaderSchemaError {
                        log.warning("Ignoring tool \(name) with invalid x-mcp-header: \(error.reason)")
                        return nil
                    } catch {
                        log.warning("Ignoring tool \(name) with invalid x-mcp-header")
                        return nil
                    }
                }

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

        if protocolEra == .modern {
            toolHeaderMappings = discoveredHeaderMappings
        }

        log.info("tools/list ← \(allDefs.count) tool(s)")
        return allDefs
    }

    /// Clears the resource cache. Call when the server notifies that resources have changed.
    public func clearResourceCache() {
        resourceCache.removeAll()
    }

    // MARK: - Protocol Negotiation

    /// Chooses the modern stateless protocol or completes the legacy handshake.
    /// Concurrent callers coalesce on a single negotiation task.
    private func ensureConnected() async throws {
        if isConnected { return }

        if let task = connectionTask {
            try await task.value
            return
        }

        let task = Task { try await negotiateProtocol() }
        connectionTask = task

        do {
            try await task.value
        } catch {
            connectionTask = nil
            protocolEra = nil
            protocolVersion = nil
            sessionId = nil
            throw error
        }
    }

    private func negotiateProtocol() async throws {
        log.info("Discovering MCP protocol support at \(self.url.absoluteString)")
        var performedCorrectiveRetry = false

        negotiation: while true {
            do {
                if try await discoverModernServer() {
                    adoptModernProtocol()
                    return
                }

                log.info("server/discover did not advertise MCP \(Self.modernProtocolVersion); using legacy initialization")
                break negotiation
            } catch let error as MCPClientError {
                switch probeDisposition(for: error) {
                case .retryModern:
                    // Retry exactly once. A second corrective rejection is
                    // modern evidence and must not silently downgrade.
                    guard !performedCorrectiveRetry else { throw error }
                    performedCorrectiveRetry = true
                    continue negotiation
                case .fallBackToLegacy:
                    log.info("Modern discovery was not recognized; using legacy initialization")
                    break negotiation
                case .fail:
                    throw error
                }
            }
        }

        try await performLegacyInitialize()
    }

    private func discoverModernServer() async throws -> Bool {
        let (response, _) = try await sendRequestRaw(
            method: "server/discover",
            params: [:],
            era: .modern
        )
        guard let result = response["result"] as? [String: Any],
              let versions = result["supportedVersions"] as? [String],
              !versions.isEmpty,
              validDiscoverCapabilities(result["capabilities"]) else {
            return false
        }
        if let resultType = result["resultType"], resultType as? String != "complete" {
            return false
        }
        if let instructions = result["instructions"], !(instructions is String) {
            return false
        }
        if let metadata = result["_meta"], !(metadata is [String: Any]) {
            return false
        }
        return versions.contains(Self.modernProtocolVersion)
    }

    private func validDiscoverCapabilities(_ value: Any?) -> Bool {
        guard let capabilities = value as? [String: Any] else { return false }

        for name in ["completions", "logging"] {
            if let capability = capabilities[name], !(capability is [String: Any]) {
                return false
            }
        }

        let booleanMembers: [(String, [String])] = [
            ("prompts", ["listChanged"]),
            ("resources", ["subscribe", "listChanged"]),
            ("tools", ["listChanged"])
        ]
        for (name, members) in booleanMembers {
            guard let value = capabilities[name] else { continue }
            guard let capability = value as? [String: Any] else { return false }
            for member in members {
                if let memberValue = capability[member], !isJSONBoolean(memberValue) {
                    return false
                }
            }
        }

        for name in ["experimental", "extensions"] {
            guard let value = capabilities[name] else { continue }
            guard let capabilityMap = value as? [String: Any],
                  capabilityMap.values.allSatisfy({ $0 is [String: Any] }) else {
                return false
            }
        }

        return true
    }

    private func isJSONBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func adoptModernProtocol() {
        protocolEra = .modern
        protocolVersion = Self.modernProtocolVersion
        sessionId = nil
        isConnected = true
        log.info("Connected with stateless MCP \(Self.modernProtocolVersion)")
    }

    private func probeDisposition(for error: MCPClientError) -> ProbeDisposition {
        switch error {
        case .rpcError(let code, _, let data):
            guard code == -32022 else { return .fallBackToLegacy }
            guard let supported = supportedVersions(in: data) else { return .fallBackToLegacy }

            if supported.contains(Self.modernProtocolVersion) {
                return .retryModern
            }
            if supported.contains(where: { $0 >= Self.modernProtocolVersion }) {
                return .fail
            }
            return .fallBackToLegacy
        case .serverError(let status, _):
            return (400..<500).contains(status) && status != 401 && status != 403 && status != 429
                ? .fallBackToLegacy
                : .fail
        case .invalidResponse:
            return .fallBackToLegacy
        case .versionMismatch:
            return .fail
        }
    }

    private func supportedVersions(in errorData: String?) -> [String]? {
        guard let errorData,
              let data = errorData.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let supported = object["supported"] as? [String] else {
            return nil
        }
        return supported
    }

    private func clientCapabilities() -> [String: Any] {
        let mimeTypes = resolvers.flatMap(\.supportedMimeTypes)
        guard !mimeTypes.isEmpty else { return [:] }

        return [
            "extensions": [
                "io.modelcontextprotocol/ui": [
                    "mimeTypes": mimeTypes
                ]
            ]
        ]
    }

    private func modernMetadata() -> [String: Any] {
        [
            "io.modelcontextprotocol/protocolVersion": Self.modernProtocolVersion,
            "io.modelcontextprotocol/clientCapabilities": clientCapabilities(),
            "io.modelcontextprotocol/clientInfo": Self.clientInfo
        ]
    }

    private func validateResultType(in result: [String: Any], method: String) throws {
        guard protocolEra == .modern else { return }
        guard let rawResultType = result["resultType"] else {
            throw MCPClientError.invalidResponse(
                "MCP 2026-07-28 resultType is required for \(method)"
            )
        }
        guard let resultType = rawResultType as? String else {
            throw MCPClientError.invalidResponse(
                "MCP 2026-07-28 resultType must be a string for \(method)"
            )
        }
        guard resultType != "complete" else { return }
        throw MCPClientError.invalidResponse(
            "MCP 2026-07-28 resultType '\(resultType)' is not supported for \(method)"
        )
    }

    private func performLegacyInitialize() async throws {
        let mimeTypes = resolvers.flatMap(\.supportedMimeTypes)

        log.info("Initializing legacy MCP connection to \(self.url.absoluteString)")
        log.info("  protocol: \(Self.preferredLegacyVersion)")
        log.info("  mimeTypes: \(mimeTypes)")
        log.info("  resolvers: \(self.resolvers.map { String(describing: type(of: $0)) })")

        let params: [String: Any] = [
            "protocolVersion": Self.preferredLegacyVersion,
            "capabilities": clientCapabilities(),
            "clientInfo": Self.clientInfo
        ]

        log.info("initialize →")
        let (response, initHTTP) = try await sendRequestRaw(
            method: "initialize",
            params: params,
            era: .legacy
        )

        guard let result = response["result"] as? [String: Any] else {
            throw MCPClientError.invalidResponse("Missing result in initialize response")
        }

        guard let version = result["protocolVersion"] as? String else {
            throw MCPClientError.invalidResponse("Server did not return protocolVersion")
        }
        guard Self.supportedLegacyVersions.contains(version) else {
            throw MCPClientError.versionMismatch(requested: Self.preferredLegacyVersion, returned: version)
        }

        protocolEra = .legacy
        protocolVersion = version
        if let sid = initHTTP.value(forHTTPHeaderField: "Mcp-Session-Id") {
            sessionId = sid
            log.info("  session: \(sid)")
        }

        if let info = result["serverInfo"] as? [String: Any] {
            let name = info["name"] as? String ?? "unknown"
            let ver = info["version"] as? String
            log.info("Connected to \(name) \(ver ?? "")")
        }

        log.info("notifications/initialized →")
        try await sendNotification(method: "notifications/initialized")

        isConnected = true
        log.info("MCP initialization complete (protocol: \(version), mimeTypes: \(mimeTypes))")
    }

    // MARK: - JSON-RPC Transport

    private func sendRequest(
        method: String,
        params: [String: Any],
        customHeaders: [String: String] = [:]
    ) async throws -> [String: Any] {
        // Retry with exponential backoff for transient failures
        var lastError: any Error = MCPClientError.invalidResponse("No attempts made")
        var delay = configuration.retryBaseDelay

        for attempt in 0...configuration.maxRetries {
            do {
                let (json, _) = try await sendRequestRaw(
                    method: method,
                    params: params,
                    customHeaders: customHeaders
                )
                return json
            } catch MCPClientError.serverError(let status, _)
                where protocolEra == .legacy && (status == 404 || status == 410) {
                // Session expired — re-initialize and retry once (no backoff).
                log.info("Session expired (HTTP \(status)), re-initializing...")
                resetConnection()
                try await ensureConnected()
                let (json, _) = try await sendRequestRaw(
                    method: method,
                    params: params,
                    customHeaders: customHeaders
                )
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

    /// Resets negotiated state so the next request reconnects.
    private func resetConnection() {
        isConnected = false
        connectionTask = nil
        protocolEra = nil
        protocolVersion = nil
        sessionId = nil
        toolHeaderMappings.removeAll()
        resourceCache.removeAll()
    }

    private func sendRequestRaw(
        method: String,
        params: [String: Any],
        era explicitEra: ProtocolEra? = nil,
        customHeaders: [String: String] = [:]
    ) async throws -> ([String: Any], HTTPURLResponse) {
        let requestId = nextRequestId
        nextRequestId += 1
        let era = explicitEra ?? protocolEra ?? .legacy
        var requestParams = params
        if era == .modern {
            var metadata = requestParams["_meta"] as? [String: Any] ?? [:]
            for (key, value) in modernMetadata() {
                metadata[key] = value
            }
            requestParams["_meta"] = metadata
        }

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": method,
            "params": requestParams
        ]

        let (data, http) = try await send(
            body: body,
            method: method,
            params: requestParams,
            era: era,
            customHeaders: customHeaders
        )
        log.debug("HTTP \(http.statusCode) for \(method) (id: \(requestId), \(data.count) bytes)")

        let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
        if http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 429 || http.statusCode >= 500 {
            throw MCPClientError.serverError(status: http.statusCode, body: responseBody)
        }
        if era == .legacy && (http.statusCode == 404 || http.statusCode == 410) {
            throw MCPClientError.serverError(status: http.statusCode, body: responseBody)
        }

        let json: [String: Any]
        let contentType = http.value(forHTTPHeaderField: "content-type") ?? ""

        if contentType.contains("text/event-stream") {
            do {
                json = try parseSSEResponse(data: data)
            } catch {
                throw responseEnvelopeError(
                    "Could not parse SSE JSON-RPC response",
                    method: method,
                    era: era,
                    httpStatus: http.statusCode,
                    responseBody: responseBody
                )
            }
        } else {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw responseEnvelopeError(
                    "Could not parse JSON-RPC response",
                    method: method,
                    era: era,
                    httpStatus: http.statusCode,
                    responseBody: responseBody
                )
            }
            json = parsed
        }

        if era == .modern {
            guard json["jsonrpc"] as? String == "2.0" else {
                throw responseEnvelopeError(
                    "Missing or invalid jsonrpc version",
                    method: method,
                    era: era,
                    httpStatus: http.statusCode,
                    responseBody: responseBody
                )
            }
            let hasResult = json.keys.contains("result")
            let hasError = json.keys.contains("error")
            guard hasResult != hasError else {
                throw responseEnvelopeError(
                    "JSON-RPC response must contain either result or error",
                    method: method,
                    era: era,
                    httpStatus: http.statusCode,
                    responseBody: responseBody
                )
            }
            if hasError {
                guard let error = json["error"] as? [String: Any],
                      error["code"] as? Int != nil,
                      error["message"] is String else {
                    throw responseEnvelopeError(
                        "Invalid JSON-RPC error object",
                        method: method,
                        era: era,
                        httpStatus: http.statusCode,
                        responseBody: responseBody
                    )
                }
            }
            // Deployed legacy servers commonly answer an unknown pre-initialize
            // probe with an HTTP 4xx and id:null. Preserve that error as
            // negotiation evidence; 2xx and established calls remain correlated.
            let isSuccessfulHTTP = http.statusCode == 200 || http.statusCode == 202
            let isUncorrelatedLegacyError = method == "server/discover" && hasError && !isSuccessfulHTTP
            if !isUncorrelatedLegacyError {
                guard let responseId = json["id"] as? Int, responseId == requestId else {
                    let reason = "Response ID does not match request ID \(requestId)"
                    if method == "server/discover" {
                        throw ProbeResponseError(reason: reason)
                    }
                    throw MCPClientError.invalidResponse(reason)
                }
            }
        } else if let responseId = json["id"] as? Int, responseId != requestId {
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

        guard http.statusCode == 200 || http.statusCode == 202 else {
            throw MCPClientError.serverError(status: http.statusCode, body: responseBody)
        }

        return (json, http)
    }

    private func responseEnvelopeError(
        _ reason: String,
        method: String,
        era: ProtocolEra,
        httpStatus: Int,
        responseBody: String
    ) -> any Error {
        guard httpStatus == 200 || httpStatus == 202 else {
            return MCPClientError.serverError(status: httpStatus, body: responseBody)
        }
        if era == .modern && method == "server/discover" {
            return ProbeResponseError(reason: reason)
        }
        return MCPClientError.invalidResponse(reason)
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
        let (data, http) = try await send(body: body, method: method, params: params, era: .legacy)
        guard http.statusCode == 200 || http.statusCode == 202 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw MCPClientError.serverError(status: http.statusCode, body: responseBody)
        }
    }

    private func send(
        body: [String: Any],
        method: String,
        params: [String: Any],
        era: ProtocolEra,
        customHeaders: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
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

        switch era {
        case .modern:
            let callerParameterHeaders = request.allHTTPHeaderFields?.keys.filter {
                $0.lowercased().hasPrefix("mcp-param-")
            } ?? []
            for key in callerParameterHeaders {
                request.setValue(nil, forHTTPHeaderField: key)
            }
            request.setValue(Self.modernProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
            request.setValue(method, forHTTPHeaderField: "Mcp-Method")
            request.setValue(nil, forHTTPHeaderField: "Mcp-Session-Id")
            if let name = routingName(for: method, params: params) {
                request.setValue(encodedRoutingHeaderValue(name), forHTTPHeaderField: "Mcp-Name")
            } else {
                request.setValue(nil, forHTTPHeaderField: "Mcp-Name")
            }
            for (key, value) in customHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        case .legacy:
            if let protocolVersion {
                request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
            }
            if let sessionId {
                request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
            }
        }

        let (data, httpResponse) = try await configuration.urlSession.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse else {
            throw MCPClientError.invalidResponse("Not an HTTP response")
        }

        return (data, http)
    }

    private func routingName(for method: String, params: [String: Any]) -> String? {
        switch method {
        case "tools/call", "prompts/get":
            params["name"] as? String
        case "resources/read":
            params["uri"] as? String
        default:
            nil
        }
    }

    /// Encodes values that are unsafe or ambiguous in an HTTP field value.
    private func encodedRoutingHeaderValue(_ value: String) -> String {
        let bytes = Array(value.utf8)
        let isPlainASCII = bytes.allSatisfy { byte in
            byte == 0x09 || (0x20...0x7E).contains(byte)
        }
        let hasBoundaryWhitespace = bytes.first == 0x09 || bytes.first == 0x20
            || bytes.last == 0x09 || bytes.last == 0x20
        let matchesSentinel = value.hasPrefix("=?base64?") && value.hasSuffix("?=")

        guard bytes.isEmpty || !isPlainASCII || hasBoundaryWhitespace || matchesSentinel else {
            return value
        }
        return "=?base64?\(Data(value.utf8).base64EncodedString())?="
    }

    private func headerMappings(in schema: JSONValue) throws -> [ToolHeaderMapping] {
        var mappings: [ToolHeaderMapping] = []
        var names: Set<String> = []
        try collectHeaderMappings(
            in: schema,
            propertyPath: [],
            mappings: &mappings,
            names: &names
        )
        return mappings
    }

    private func collectHeaderMappings(
        in schema: JSONValue,
        propertyPath: [String],
        mappings: inout [ToolHeaderMapping],
        names: inout Set<String>
    ) throws {
        guard case .object(let object) = schema else {
            if containsHeaderAnnotation(in: schema) {
                throw ToolHeaderSchemaError(reason: "annotation is not on an object schema")
            }
            return
        }

        if let annotation = object["x-mcp-header"] {
            guard !propertyPath.isEmpty else {
                throw ToolHeaderSchemaError(reason: "annotation is not reachable through properties")
            }
            guard let name = annotation.stringValue, isValidHeaderToken(name) else {
                throw ToolHeaderSchemaError(reason: "annotation name is not a valid HTTP token")
            }
            guard let rawType = object["type"]?.stringValue,
                  let valueType = ToolHeaderValueType(rawValue: rawType) else {
                throw ToolHeaderSchemaError(reason: "annotation must target a string, integer, boolean, or number")
            }
            guard names.insert(name.lowercased()).inserted else {
                throw ToolHeaderSchemaError(reason: "annotation names must be case-insensitively unique")
            }
            mappings.append(ToolHeaderMapping(
                name: name,
                propertyPath: propertyPath,
                valueType: valueType
            ))
        }

        if let properties = object["properties"]?.objectValue {
            for (propertyName, propertySchema) in properties {
                try collectHeaderMappings(
                    in: propertySchema,
                    propertyPath: propertyPath + [propertyName],
                    mappings: &mappings,
                    names: &names
                )
            }
        }

        for (key, value) in object where key != "properties" && key != "x-mcp-header" {
            if containsHeaderAnnotation(in: value) {
                throw ToolHeaderSchemaError(reason: "annotation is not reachable through properties")
            }
        }
    }

    private func containsHeaderAnnotation(in value: JSONValue) -> Bool {
        switch value {
        case .object(let object):
            object["x-mcp-header"] != nil || object.values.contains { containsHeaderAnnotation(in: $0) }
        case .array(let values):
            values.contains { containsHeaderAnnotation(in: $0) }
        default:
            false
        }
    }

    private func isValidHeaderToken(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.utf8.allSatisfy { byte in
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A,
                 0x21, 0x23...0x27, 0x2A, 0x2B, 0x2D, 0x2E,
                 0x5E, 0x5F, 0x60, 0x7C, 0x7E:
                true
            default:
                false
            }
        }
    }

    private func toolParameterHeaders(
        name: String,
        arguments: JSONValue
    ) throws -> [String: String] {
        guard protocolEra == .modern, let mappings = toolHeaderMappings[name] else {
            return [:]
        }

        var headers: [String: String] = [:]
        for mapping in mappings {
            var value: JSONValue? = arguments
            for component in mapping.propertyPath {
                value = value?[component]
            }
            guard let value, !value.isNull else { continue }

            let stringValue: String
            switch (mapping.valueType, value) {
            case (.string, .string(let string)):
                stringValue = string
            case (.boolean, .bool(let boolean)):
                stringValue = boolean ? "true" : "false"
            case (.integer, .number(let number)):
                let maximumSafeInteger = 9_007_199_254_740_991.0
                guard number.isFinite,
                      number.rounded(.towardZero) == number,
                      abs(number) <= maximumSafeInteger else {
                    throw MCPClientError.invalidResponse(
                        "x-mcp-header argument at \(mapping.propertyPath.joined(separator: ".")) must be a safe integer"
                    )
                }
                stringValue = String(Int64(number))
            case (.number, .number(let number)):
                let maximumSafeInteger = 9_007_199_254_740_991.0
                guard number.isFinite,
                      !number.rounded(.towardZero).isEqual(to: number) || abs(number) <= maximumSafeInteger,
                      let decimal = canonicalDecimalHeaderValue(number) else {
                    throw MCPClientError.invalidResponse(
                        "x-mcp-header argument at \(mapping.propertyPath.joined(separator: ".")) must be finite and safely representable"
                    )
                }
                stringValue = decimal
            default:
                throw MCPClientError.invalidResponse(
                    "x-mcp-header argument at \(mapping.propertyPath.joined(separator: ".")) has the wrong type"
                )
            }

            headers["Mcp-Param-\(mapping.name)"] = encodedRoutingHeaderValue(stringValue)
        }
        return headers
    }

    /// The v2 server compares canonical decimal headers numerically. Expanding
    /// Swift's exponent form avoids spelling differences such as `1e-07` versus
    /// JavaScript's `1e-7` while preserving the exact Double value.
    private func canonicalDecimalHeaderValue(_ number: Double) -> String? {
        guard number.isFinite else { return nil }
        let source = String(number)
        guard let marker = source.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
            return source
        }

        let mantissa = String(source[..<marker])
        guard let exponent = Int(source[source.index(after: marker)...]) else { return nil }
        let negative = mantissa.hasPrefix("-")
        let unsignedMantissa = negative ? String(mantissa.dropFirst()) : mantissa
        let parts = unsignedMantissa.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = parts.first, !whole.isEmpty else { return nil }

        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let digits = String(whole) + fraction
        let decimalIndex = whole.count + exponent
        let expanded: String
        if decimalIndex <= 0 {
            expanded = "0." + String(repeating: "0", count: -decimalIndex) + digits
        } else if decimalIndex >= digits.count {
            expanded = digits + String(repeating: "0", count: decimalIndex - digits.count)
        } else {
            let split = digits.index(digits.startIndex, offsetBy: decimalIndex)
            expanded = String(digits[..<split]) + "." + String(digits[split...])
        }
        return negative ? "-" + expanded : expanded
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
