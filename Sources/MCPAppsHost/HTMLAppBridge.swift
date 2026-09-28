import Foundation
import Observation
import BindJS
import os

private let log = Logger(subsystem: "MCPAppsHost", category: "MCPAppContent")

/// The host side of the MCP Apps protocol for one HTML view.
///
/// An HTML MCP App talks to its host in JSON-RPC 2.0 over `postMessage`
/// ([SEP-1865](https://github.com/modelcontextprotocol/ext-apps)). The web view
/// relays each message from the view to ``receive(_:)``; replies and
/// notifications go back through ``deliver``. The bridge:
///
/// - answers `ui/initialize` with host capabilities and host context;
/// - sends `ui/notifications/tool-input-partial`, `ui/notifications/tool-input`,
///   and `ui/notifications/tool-result` once the view has sent
///   `ui/notifications/initialized`;
/// - proxies `tools/call` and `resources/read` to the session's MCP server;
/// - routes `ui/message`, `ui/update-model-context`, `ui/open-link`, and
///   `ui/request-display-mode` to the app;
/// - records the height the view reports in `ui/notifications/size-changed`,
///   or, until it reports one, the height the shell page measures.
@MainActor
@Observable
final class HTMLAppBridge {

    static let protocolVersion = "2026-01-26"
    /// Sent by the shell page, not the view: the view's measured height, used
    /// until the view sends `ui/notifications/size-changed` itself.
    nonisolated static let measuredHeightMethod = "mcpappshost/measured-height"

    /// Content height from the view's latest `ui/notifications/size-changed`.
    private(set) var contentHeight: Double?

    // MARK: - Inputs

    /// App-side handlers, taken from the SwiftUI environment.
    struct Host {
        var hostBridge: (any MCPHostBridge)?
        var onToolMessage: ((ToolMessage) -> Void)?
        var onModelContextUpdate: ((ModelContext) -> Void)?
        var onDisplayModeRequest: ((MCPAppSession.DisplayMode) -> MCPAppSession.DisplayMode)?
        var openURL: ((URL) async -> Bool)?
    }

    /// What the view has been told about the tool call, derived from the session.
    struct ToolState: Equatable {
        /// Arguments still streaming in.
        var partialArguments: JSONValue?
        /// Arguments that will not change again, or nil while they may.
        var completeArguments: JSONValue?
        var result: ToolResult?

        init(partialArguments: JSONValue? = nil, completeArguments: JSONValue? = nil, result: ToolResult? = nil) {
            self.partialArguments = partialArguments
            self.completeArguments = completeArguments
            self.result = result
        }

        @MainActor
        init(session: MCPAppSession, result: ToolResult?) {
            partialArguments = session.partialArguments
            if session.argumentsComplete {
                completeArguments = session.partialArguments ?? session.toolArguments
            } else if !(session is ManualMCPAppSession) || result != nil {
                // Framework-executed sessions start with their final arguments.
                // A manual session's are final once it has a result.
                completeArguments = session.partialArguments ?? session.toolArguments
            }
            self.result = result
        }
    }

    @ObservationIgnored let session: MCPAppSession
    @ObservationIgnored var host = Host()
    /// Sends a JSON-RPC message to the view.
    @ObservationIgnored var deliver: ((JSONValue) -> Void)?
    /// Width of the view's container, reported in `hostContext.containerDimensions`.
    @ObservationIgnored var containerWidth: () -> Double? = { nil }

    // MARK: - State

    @ObservationIgnored private(set) var isInitialized = false
    @ObservationIgnored private var toolState = ToolState()
    @ObservationIgnored private var sentPartialArguments: JSONValue?
    @ObservationIgnored private var sentToolInput = false
    @ObservationIgnored private var sentToolResult = false
    @ObservationIgnored private var theme: String?
    @ObservationIgnored private var viewReportsSize = false
    @ObservationIgnored private var appDisplayModes: Set<String>?
    @ObservationIgnored private var toolVisibility: Task<[String: Set<MCPToolDefinition.UIMetadata.Visibility>], Never>?
    @ObservationIgnored private var requests: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextRequestKey = 0

    init(session: MCPAppSession) {
        self.session = session
    }

    /// Cancels requests still in flight. Call when the view goes away.
    func close() {
        for task in requests.values { task.cancel() }
        requests.removeAll()
        deliver = nil
    }

    // MARK: - Session and host updates

    /// Pushes the tool's arguments and result to the view as they become available.
    func update(_ state: ToolState) {
        toolState = state
        flush()
    }

    /// Sets the color theme, notifying an initialized view when it changes.
    func setTheme(_ newTheme: String) {
        guard newTheme != theme else { return }
        theme = newTheme
        if isInitialized {
            notify("ui/notifications/host-context-changed", ["theme": .string(newTheme)])
        }
    }

    private func flush() {
        // The host must not message the view before `ui/notifications/initialized`.
        guard isInitialized else { return }

        if !sentToolInput {
            if let arguments = toolState.completeArguments {
                notify("ui/notifications/tool-input", ["arguments": Self.argumentsObject(arguments)])
                sentToolInput = true
            } else if let partial = toolState.partialArguments, partial != sentPartialArguments {
                notify("ui/notifications/tool-input-partial", ["arguments": Self.argumentsObject(partial)])
                sentPartialArguments = partial
            }
        }

        // tool-result must follow tool-input.
        if sentToolInput, !sentToolResult, let result = toolState.result {
            notify("ui/notifications/tool-result", Self.callToolResult(result))
            sentToolResult = true
        }
    }

    // MARK: - Receiving

    /// Handles one message from the view, as JSON text.
    func receive(_ json: String) {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else {
            log.warning("[\(self.session.toolName, privacy: .public)] HTML view sent a message that is not JSON")
            return
        }
        handle(message)
    }

    func handle(_ message: JSONValue) {
        guard message["jsonrpc"] == "2.0", let method = message["method"]?.stringValue else {
            // Responses: the host sends the view no requests, so there is nothing to match.
            return
        }
        let params = message["params"] ?? .object([:])
        if let id = message["id"], !id.isNull {
            handleRequest(id: id, method: method, params: params)
        } else {
            handleNotification(method: method, params: params)
        }
    }

    private func handleRequest(id: JSONValue, method: String, params: JSONValue) {
        switch method {
        case "ui/initialize":
            respond(to: id, result: initializeResult(params))
        case "ping":
            respond(to: id, result: .object([:]))
        case "tools/call":
            run(id) { try await $0.callTool(params) }
        case "resources/read":
            run(id) { try await $0.readResource(params) }
        case "ui/open-link":
            run(id) { try await $0.openLink(params) }
        case "ui/message":
            run(id) { try await $0.sendMessage(params) }
        case "ui/update-model-context":
            run(id) { try await $0.updateModelContext(params) }
        case "ui/request-display-mode":
            respond(to: id, result: requestDisplayMode(params))
        default:
            respond(to: id, error: .methodNotFound(method))
        }
    }

    private func handleNotification(method: String, params: JSONValue) {
        switch method {
        case "ui/notifications/initialized":
            isInitialized = true
            flush()
        case "ui/notifications/size-changed":
            viewReportsSize = true
            setContentHeight(params["height"])
        case Self.measuredHeightMethod:
            if !viewReportsSize { setContentHeight(params["height"]) }
        case "notifications/message":
            logFromView(params)
        default:
            break
        }
    }

    private func setContentHeight(_ value: JSONValue?) {
        guard let height = value?.numberValue, height.isFinite, height >= 0 else { return }
        contentHeight = height
    }

    // MARK: - Requests

    private func initializeResult(_ params: JSONValue) -> JSONValue {
        if let modes = params["appCapabilities"]?["availableDisplayModes"]?.arrayValue {
            appDisplayModes = Set(modes.compactMap(\.stringValue))
        }

        var hostContext: [String: JSONValue] = [
            "toolInfo": ["tool": toolJSON],
            "displayMode": .string(session.displayMode.rawValue),
            "availableDisplayModes": host.onDisplayModeRequest == nil
                ? ["inline"] : ["inline", "fullscreen", "pip"],
            "locale": .string(Locale.current.identifier(.bcp47)),
            "timeZone": .string(TimeZone.current.identifier),
            "platform": .string(Self.platform),
        ]
        if let theme { hostContext["theme"] = .string(theme) }
        if let width = containerWidth(), width > 0 {
            // Fixed width, and a height the view sets through size-changed.
            hostContext["containerDimensions"] = ["width": .number(width)]
        }

        return [
            "protocolVersion": .string(Self.protocolVersion),
            "hostInfo": ["name": "MCPAppsHost", "version": "1.0.0"],
            "hostCapabilities": [
                "serverTools": [:],
                "serverResources": [:],
                "logging": [:],
                "openLinks": [:],
            ],
            "hostContext": .object(hostContext),
        ]
    }

    private var toolJSON: JSONValue {
        var tool: [String: JSONValue] = [
            "name": .string(session.toolName),
            "inputSchema": session.toolDefinition?.inputSchema ?? ["type": "object"],
        ]
        if let description = session.toolDefinition?.description {
            tool["description"] = .string(description)
        }
        return .object(tool)
    }

    private func callTool(_ params: JSONValue) async throws -> JSONValue {
        guard let server = session.server else { throw BridgeError.unavailable("No MCP server is connected") }
        guard let name = params["name"]?.stringValue, !name.isEmpty else {
            throw BridgeError.invalidParams("tools/call needs a tool name")
        }
        // Tools whose visibility leaves out "app" are for the model only.
        if let visibility = await visibility(of: name, on: server), !visibility.contains(.app) {
            throw BridgeError.invalidParams("Tool \(name) cannot be called from an app")
        }
        let arguments = params["arguments"] ?? .object([:])
        log.info("[\(self.session.toolName, privacy: .public)] HTML view tools/call → \(name, privacy: .public)")
        let result = try await server.callTool(name: name, arguments: arguments)
        return Self.callToolResult(result)
    }

    /// The tool's visibility, or nil if the server doesn't list it.
    private func visibility(
        of name: String,
        on server: any MCPServer
    ) async -> Set<MCPToolDefinition.UIMetadata.Visibility>? {
        if name == session.toolName, let ui = session.toolDefinition?.ui {
            return ui.visibility
        }
        let task = toolVisibility ?? Task {
            let tools = (try? await server.listTools()) ?? []
            return Dictionary(
                tools.map { ($0.name, $0.ui?.visibility ?? [.model, .app]) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        toolVisibility = task
        return await task.value[name]
    }

    private func readResource(_ params: JSONValue) async throws -> JSONValue {
        guard let server = session.server else { throw BridgeError.unavailable("No MCP server is connected") }
        guard let uri = params["uri"]?.stringValue else {
            throw BridgeError.invalidParams("resources/read needs a uri")
        }
        let resource = try await server.readResource(uri: uri)
        var item: [String: JSONValue] = [
            "uri": .string(resource.uri),
            "mimeType": .string(resource.mimeType),
        ]
        if let text = resource.text { item["text"] = .string(text) }
        if let blob = resource.blob { item["blob"] = .string(blob.base64EncodedString()) }
        if let meta = resource.meta { item["_meta"] = meta }
        return ["contents": [.object(item)]]
    }

    private func openLink(_ params: JSONValue) async throws -> JSONValue {
        guard let string = params["url"]?.stringValue,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else {
            throw BridgeError.denied("Invalid URL")
        }
        if let hostBridge = host.hostBridge {
            do {
                try await hostBridge.openLink(url)
            } catch {
                throw BridgeError.denied(error.localizedDescription)
            }
        } else if let openURL = host.openURL, await openURL(url) {
            // Opened.
        } else {
            throw BridgeError.denied("Link opening denied")
        }
        return .object([:])
    }

    private func sendMessage(_ params: JSONValue) async throws -> JSONValue {
        let content = Self.contentBlocks(params["content"])
        guard !content.isEmpty else { throw BridgeError.invalidParams("ui/message needs content") }
        if let onToolMessage = host.onToolMessage {
            onToolMessage(ToolMessage(role: .user, content: content))
        } else if let hostBridge = host.hostBridge {
            let text = content.compactMap { block -> String? in
                if case .text(let text) = block { return text }
                return nil
            }.joined(separator: "\n")
            try await hostBridge.sendMessage(text)
        } else {
            throw BridgeError.denied("This host does not accept messages")
        }
        return .object([:])
    }

    private func updateModelContext(_ params: JSONValue) async throws -> JSONValue {
        // The spec's `content` is a content-block array; some views send an object.
        let content = params["content"]
        let structured: JSONValue? = params["structuredContent"]
            ?? (content?.objectValue != nil && content?["type"] == nil ? content : nil)
        let blocks = Self.contentBlocks(content)

        if let onModelContextUpdate = host.onModelContextUpdate {
            onModelContextUpdate(ModelContext(content: blocks.isEmpty ? nil : blocks, structuredContent: structured))
        } else if let hostBridge = host.hostBridge {
            var context: [String: Any] = structured?.objectValue?.mapValues { $0.toAny() } ?? [:]
            if context.isEmpty, let content, content.arrayValue != nil {
                context["content"] = content.toAny()
            }
            try await hostBridge.updateModelContext(context)
        } else {
            throw BridgeError.denied("This host does not accept model context")
        }
        return .object([:])
    }

    private func requestDisplayMode(_ params: JSONValue) -> JSONValue {
        var mode = session.displayMode
        if let requested = params["mode"]?.stringValue.flatMap(MCPAppSession.DisplayMode.init(rawValue:)),
           appDisplayModes?.contains(requested.rawValue) ?? true,
           let onDisplayModeRequest = host.onDisplayModeRequest {
            mode = onDisplayModeRequest(requested)
        }
        return ["mode": .string(mode.rawValue)]
    }

    private func logFromView(_ params: JSONValue) {
        let level = params["level"]?.stringValue ?? "info"
        let data = params["data"]
        let message = data?.stringValue ?? params["message"]?.stringValue ?? ""
        if let hostBridge = host.hostBridge {
            hostBridge.log(level: level, message: message, data: data?.objectValue?.mapValues { $0.toAny() })
        } else {
            log.info("[\(self.session.toolName, privacy: .public)] HTML view [\(level, privacy: .public)] \(message, privacy: .public)")
        }
    }

    // MARK: - Sending

    private func run(_ id: JSONValue, _ operation: @escaping (HTMLAppBridge) async throws -> JSONValue) {
        let key = nextRequestKey
        nextRequestKey += 1
        requests[key] = Task { [weak self] in
            guard let self else { return }
            defer { self.requests[key] = nil }
            do {
                let result = try await operation(self)
                guard !Task.isCancelled else { return }
                self.respond(to: id, result: result)
            } catch {
                guard !Task.isCancelled else { return }
                self.respond(to: id, error: BridgeError(error))
            }
        }
    }

    private func respond(to id: JSONValue, result: JSONValue) {
        deliver?(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func respond(to id: JSONValue, error: BridgeError) {
        log.info("[\(self.session.toolName, privacy: .public)] HTML view request failed: \(error.message, privacy: .public)")
        deliver?(["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(error.code)), "message": .string(error.message)]])
    }

    private func notify(_ method: String, _ params: JSONValue) {
        deliver?(["jsonrpc": "2.0", "method": .string(method), "params": params])
    }

    // MARK: - Wire format

    private static var platform: String {
        #if os(iOS)
        "mobile"
        #else
        "desktop"
        #endif
    }

    /// Tool arguments must reach the view as an object.
    private static func argumentsObject(_ arguments: JSONValue) -> JSONValue {
        arguments.objectValue != nil ? arguments : .object([:])
    }

    /// A `CallToolResult` as the MCP wire format spells it.
    static func callToolResult(_ result: ToolResult) -> JSONValue {
        var object: [String: JSONValue] = [
            "content": .array(result.content.map(contentBlockJSON)),
            "isError": .bool(result.isError),
        ]
        if let structured = result.structuredContent { object["structuredContent"] = structured }
        if let meta = result.meta { object["_meta"] = meta }
        return .object(object)
    }

    private static func contentBlockJSON(_ block: ContentBlock) -> JSONValue {
        switch block {
        case .text(let text):
            return ["type": "text", "text": .string(text)]
        case .image(let data, let mimeType):
            return ["type": "image", "data": .string(data.base64EncodedString()), "mimeType": .string(mimeType)]
        case .resource(let uri, let mimeType, let text):
            var resource: [String: JSONValue] = ["uri": .string(uri), "mimeType": .string(mimeType)]
            if let text { resource["text"] = .string(text) }
            return ["type": "resource", "resource": .object(resource)]
        }
    }

    /// Content blocks from a view message: an array of blocks, or a single block.
    private static func contentBlocks(_ value: JSONValue?) -> [ContentBlock] {
        let items: [JSONValue] = switch value {
        case .array(let array): array
        case .object(let object) where object["type"] != nil: [.object(object)]
        default: []
        }
        return items.compactMap { item in
            guard let data = try? JSONEncoder().encode(item) else { return nil }
            return try? JSONDecoder().decode(ContentBlock.self, from: data)
        }
    }
}

// MARK: - Errors

/// A JSON-RPC error returned to the view.
struct BridgeError: Error, Equatable {
    let code: Int
    let message: String

    static func methodNotFound(_ method: String) -> BridgeError {
        BridgeError(code: -32601, message: "Method not found: \(method)")
    }

    static func invalidParams(_ message: String) -> BridgeError {
        BridgeError(code: -32602, message: message)
    }

    static func denied(_ message: String) -> BridgeError {
        BridgeError(code: -32000, message: message)
    }

    static func unavailable(_ message: String) -> BridgeError {
        BridgeError(code: -32603, message: message)
    }

    init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    /// Maps a failure to a JSON-RPC error, keeping an MCP server's own code.
    init(_ error: any Error) {
        switch error {
        case let error as BridgeError:
            self = error
        case MCPClientError.rpcError(let code, let message, _):
            self.init(code: code, message: message)
        default:
            self.init(code: -32603, message: error.localizedDescription)
        }
    }
}
