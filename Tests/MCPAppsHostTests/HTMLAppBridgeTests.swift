import Testing
import Foundation
@testable import MCPAppsHost

/// Records the calls an HTML view makes through the host.
final class RecordingServer: MCPServer, @unchecked Sendable {
    private let lock = NSLock()
    private var _toolCalls: [(name: String, arguments: JSONValue)] = []
    private var _resourceReads: [String] = []
    private var _listToolsCount = 0

    var toolResult: ToolResult
    var toolError: (any Error)?
    var tools: [MCPToolDefinition]
    var resource: ResourceContent?

    init(
        toolResult: ToolResult = ToolResult(text: "ok"),
        tools: [MCPToolDefinition] = [],
        resource: ResourceContent? = nil
    ) {
        self.toolResult = toolResult
        self.tools = tools
        self.resource = resource
    }

    var toolCalls: [(name: String, arguments: JSONValue)] { lock.withLock { _toolCalls } }
    var resourceReads: [String] { lock.withLock { _resourceReads } }
    var listToolsCount: Int { lock.withLock { _listToolsCount } }

    func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
        lock.withLock { _toolCalls.append((name, arguments)) }
        if let toolError { throw toolError }
        return toolResult
    }

    func readResource(uri: String) async throws -> ResourceContent {
        lock.withLock { _resourceReads.append(uri) }
        return resource ?? ResourceContent(uri: uri, mimeType: "text/html;profile=mcp-app", text: "<html></html>")
    }

    func listTools() async throws -> [MCPToolDefinition] {
        lock.withLock { _listToolsCount += 1 }
        return tools
    }
}

@Suite("HTML app bridge")
@MainActor
struct HTMLAppBridgeTests {

    // MARK: - Harness

    @MainActor
    final class Harness {
        let bridge: HTMLAppBridge
        var sent: [JSONValue] = []
        private var nextId = 100

        init(session: MCPAppSession) {
            bridge = HTMLAppBridge(session: session)
            bridge.deliver = { [unowned self] in self.sent.append($0) }
        }

        var notifications: [String] {
            sent.compactMap { $0["id"] == nil ? $0["method"]?.stringValue : nil }
        }

        func notification(_ method: String) -> JSONValue? {
            sent.last { $0["method"]?.stringValue == method && $0["id"] == nil }?["params"]
        }

        @discardableResult
        func request(_ method: String, _ params: JSONValue = [:]) async throws -> JSONValue {
            nextId += 1
            let id = JSONValue.number(Double(nextId))
            bridge.handle(["jsonrpc": "2.0", "id": id, "method": .string(method), "params": params])
            for _ in 0..<200 {
                if let response = sent.first(where: { $0["id"] == id }) { return response }
                try await Task.sleep(for: .milliseconds(5))
            }
            Issue.record("No response to \(method)")
            return .null
        }

        func notify(_ method: String, _ params: JSONValue = [:]) {
            bridge.handle(["jsonrpc": "2.0", "method": .string(method), "params": params])
        }

        /// Runs the view's side of the handshake.
        func initialize() async throws {
            try await request("ui/initialize", [
                "protocolVersion": "2026-01-26",
                "appInfo": ["name": "test-view", "version": "1.0.0"],
                "appCapabilities": [:],
            ])
            notify("ui/notifications/initialized")
        }
    }

    func completedSession(
        arguments: JSONValue = ["city": "Albuquerque"],
        result: ToolResult = ToolResult(text: "sunny"),
        server: RecordingServer = RecordingServer(),
        definition: MCPToolDefinition? = nil
    ) -> MCPAppSession {
        let call = SimpleMCPToolCall(
            id: "call-1",
            name: "weather",
            arguments: arguments,
            toolDefinition: definition ?? MCPToolDefinition(
                name: "weather",
                description: "Current weather",
                inputSchema: ["type": "object", "properties": ["city": ["type": "string"]]]
            )
        )
        // Without a ui:// resource the session fetches nothing, so the server
        // sees only the calls the view makes.
        return MCPAppSession(toolCall: call, completedWith: result, server: server)
    }

    // MARK: - Handshake

    @Test func initializeReturnsCapabilitiesAndContext() async throws {
        let harness = Harness(session: completedSession())
        harness.bridge.setTheme("dark")
        let response = try await harness.request("ui/initialize", [
            "protocolVersion": "2026-01-26",
            "appInfo": ["name": "v", "version": "1"],
            "appCapabilities": [:],
        ])

        let result = try #require(response["result"])
        #expect(result["protocolVersion"] == "2026-01-26")
        #expect(result["hostInfo"]?["name"] == "MCPAppsHost")
        #expect(result["hostCapabilities"]?["serverTools"] != nil)
        #expect(result["hostCapabilities"]?["serverResources"] != nil)
        let context = try #require(result["hostContext"])
        #expect(context["toolInfo"]?["tool"]?["name"] == "weather")
        #expect(context["toolInfo"]?["tool"]?["description"] == "Current weather")
        #expect(context["toolInfo"]?["tool"]?["inputSchema"]?["properties"]?["city"] != nil)
        #expect(context["theme"] == "dark")
        #expect(context["displayMode"] == "inline")
    }

    @Test func sendsNothingBeforeInitialized() async throws {
        let session = completedSession()
        let harness = Harness(session: session)
        harness.bridge.update(.init(session: session, result: ToolResult(text: "sunny")))
        try await harness.request("ui/initialize", ["protocolVersion": "2026-01-26"])

        #expect(harness.notifications.isEmpty)
    }

    @Test func sendsToolInputThenResultAfterInitialized() async throws {
        let result = ToolResult(
            content: [.text("sunny")],
            structuredContent: ["temperature": 72],
            meta: ["source": "test"]
        )
        let session = completedSession(result: result)
        let harness = Harness(session: session)
        harness.bridge.update(.init(session: session, result: result))
        try await harness.initialize()

        #expect(harness.notifications == ["ui/notifications/tool-input", "ui/notifications/tool-result"])
        #expect(harness.notification("ui/notifications/tool-input")?["arguments"] == ["city": "Albuquerque"])
        let sentResult = try #require(harness.notification("ui/notifications/tool-result"))
        #expect(sentResult["content"] == [["type": "text", "text": "sunny"]])
        #expect(sentResult["structuredContent"] == ["temperature": 72])
        #expect(sentResult["_meta"] == ["source": "test"])
        #expect(sentResult["isError"] == false)
    }

    @Test func streamsPartialArgumentsForManualSession() async throws {
        let server = RecordingServer()
        let session = ManualMCPAppSession(id: "s", toolName: "card", server: server)
        let harness = Harness(session: session)
        harness.bridge.update(.init(session: session, result: nil))
        try await harness.initialize()
        #expect(harness.notifications.isEmpty)

        session.feed(["title": "Hel"])
        harness.bridge.update(.init(session: session, result: nil))
        session.feed(["title": "Hello"])
        harness.bridge.update(.init(session: session, result: nil))
        session.finalizeArguments(["title": "Hello", "count": 2])
        harness.bridge.update(.init(session: session, result: nil))
        let result = ToolResult(text: "done")
        session.complete(with: result)
        harness.bridge.update(.init(session: session, result: result))
        // A later update must not resend anything.
        harness.bridge.update(.init(session: session, result: result))

        #expect(harness.notifications == [
            "ui/notifications/tool-input-partial",
            "ui/notifications/tool-input-partial",
            "ui/notifications/tool-input",
            "ui/notifications/tool-result",
        ])
        #expect(harness.notification("ui/notifications/tool-input")?["arguments"] == ["title": "Hello", "count": 2])
    }

    // MARK: - Proxied requests

    @Test func toolsCallReachesTheServer() async throws {
        let server = RecordingServer(toolResult: ToolResult(
            content: [.text("{\"total\":3}")],
            structuredContent: ["total": 3]
        ))
        let harness = Harness(session: completedSession(server: server))
        try await harness.initialize()

        let response = try await harness.request("tools/call", ["name": "get_subscriptions", "arguments": ["view": "all"]])

        #expect(server.toolCalls.count == 1)
        #expect(server.toolCalls.first?.name == "get_subscriptions")
        #expect(server.toolCalls.first?.arguments == ["view": "all"])
        #expect(response["result"]?["structuredContent"] == ["total": 3])
        #expect(response["result"]?["content"] == [["type": "text", "text": "{\"total\":3}"]])
        #expect(response["error"] == nil)
    }

    @Test func toolsCallRejectsModelOnlyTools() async throws {
        let server = RecordingServer(tools: [
            MCPToolDefinition(name: "delete_account", ui: .init(resourceUri: "ui://x", visibility: [.model])),
        ])
        let harness = Harness(session: completedSession(server: server))
        try await harness.initialize()

        let response = try await harness.request("tools/call", ["name": "delete_account"])

        #expect(response["error"]?["code"] == -32602)
        #expect(server.toolCalls.isEmpty)
    }

    @Test func toolsCallChecksVisibilityOnce() async throws {
        let server = RecordingServer(tools: [MCPToolDefinition(name: "a"), MCPToolDefinition(name: "b")])
        let harness = Harness(session: completedSession(server: server))
        try await harness.initialize()

        try await harness.request("tools/call", ["name": "a"])
        try await harness.request("tools/call", ["name": "b"])

        #expect(server.toolCalls.map(\.name) == ["a", "b"])
        #expect(server.listToolsCount == 1)
    }

    @Test func toolsCallKeepsTheServersErrorCode() async throws {
        let server = RecordingServer()
        server.toolError = MCPClientError.rpcError(code: -32602, message: "Unknown tool: nope")
        let harness = Harness(session: completedSession(server: server))
        try await harness.initialize()

        let response = try await harness.request("tools/call", ["name": "nope"])

        #expect(response["error"]?["code"] == -32602)
        #expect(response["error"]?["message"] == "Unknown tool: nope")
    }

    @Test func toolsCallWithoutNameIsInvalid() async throws {
        let server = RecordingServer()
        let harness = Harness(session: completedSession(server: server))
        let response = try await harness.request("tools/call", ["arguments": [:]])

        #expect(response["error"]?["code"] == -32602)
        #expect(server.toolCalls.isEmpty)
    }

    @Test func resourcesReadReachesTheServer() async throws {
        let server = RecordingServer(resource: ResourceContent(
            uri: "ui://weather/other",
            mimeType: "text/html;profile=mcp-app",
            text: "<p>hi</p>",
            meta: ["ui": ["prefersBorder": true]]
        ))
        let harness = Harness(session: completedSession(server: server))
        let response = try await harness.request("resources/read", ["uri": "ui://weather/other"])

        #expect(server.resourceReads == ["ui://weather/other"])
        let item = try #require(response["result"]?["contents"]?[0])
        #expect(item["text"] == "<p>hi</p>")
        #expect(item["_meta"]?["ui"]?["prefersBorder"] == true)
    }

    // MARK: - View requests and notifications

    @Test func sizeChangedSetsContentHeight() {
        let harness = Harness(session: completedSession())
        harness.notify("ui/notifications/size-changed", ["width": 390, "height": 412])
        #expect(harness.bridge.contentHeight == 412)
    }

    @Test func reportedSizeOverridesMeasuredHeight() {
        let harness = Harness(session: completedSession())
        harness.notify(HTMLAppBridge.measuredHeightMethod, ["height": 80])
        #expect(harness.bridge.contentHeight == 80)
        harness.notify("ui/notifications/size-changed", ["height": 412])
        harness.notify(HTMLAppBridge.measuredHeightMethod, ["height": 90])
        #expect(harness.bridge.contentHeight == 412)
    }

    @Test func pingAndUnknownMethods() async throws {
        let harness = Harness(session: completedSession())
        #expect(try await harness.request("ping")["result"] == [:])
        #expect(try await harness.request("ui/does-not-exist")["error"]?["code"] == -32601)
    }

    @Test func messageGoesToTheApp() async throws {
        let harness = Harness(session: completedSession())
        var received: [ToolMessage] = []
        harness.bridge.host.onToolMessage = { received.append($0) }

        let response = try await harness.request("ui/message", [
            "role": "user",
            "content": [["type": "text", "text": "Show me last month"]],
        ])

        #expect(response["result"] == [:])
        #expect(received.first?.content == [.text("Show me last month")])
    }

    @Test func modelContextGoesToTheApp() async throws {
        let harness = Harness(session: completedSession())
        var received: [ModelContext] = []
        harness.bridge.host.onModelContextUpdate = { received.append($0) }

        try await harness.request("ui/update-model-context", ["structuredContent": ["selected": "Netflix"]])

        #expect(received.first?.structuredContent == ["selected": "Netflix"])
    }

    @Test func openLinkRejectsNonWebURLs() async throws {
        let harness = Harness(session: completedSession())
        var opened: [URL] = []
        harness.bridge.host.openURL = { opened.append($0); return true }

        let rejected = try await harness.request("ui/open-link", ["url": "javascript:alert(1)"])
        let accepted = try await harness.request("ui/open-link", ["url": "https://metabind.ai"])

        #expect(rejected["error"]?["code"] == -32000)
        #expect(accepted["result"] == [:])
        #expect(opened == [URL(string: "https://metabind.ai")!])
    }

    @Test func displayModeWithoutHandlerStaysInline() async throws {
        let harness = Harness(session: completedSession())
        let response = try await harness.request("ui/request-display-mode", ["mode": "fullscreen"])
        #expect(response["result"]?["mode"] == "inline")
    }
}
