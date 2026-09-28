import Testing
import Foundation
import WebKit
@testable import MCPAppsHost

// MARK: - Content Security Policy

@Suite("HTML app CSP")
struct HTMLAppCSPTests {

    @Test func blocksExternalOriginsWithoutDeclarations() {
        let policy = MCPAppCSP(resourceMeta: nil).policy
        #expect(policy.contains("connect-src 'self';"))
        #expect(policy.contains("frame-src 'none'"))
        #expect(policy.contains("object-src 'none'"))
        #expect(policy.contains("base-uri 'none'"))
        #expect(!policy.contains("https:"))
    }

    @Test func allowsDeclaredDomains() {
        let meta: JSONValue = ["ui": ["csp": [
            "connectDomains": ["https://api.example.com"],
            "resourceDomains": ["https://cdn.example.com"],
            "frameDomains": ["https://www.youtube.com"],
        ]]]
        let policy = MCPAppCSP(resourceMeta: meta).policy
        #expect(policy.contains("connect-src 'self' https://api.example.com"))
        #expect(policy.contains("script-src 'self' 'unsafe-inline' 'unsafe-eval' blob: data: https://cdn.example.com"))
        #expect(policy.contains("img-src 'self' data: blob: https://cdn.example.com"))
        #expect(policy.contains("frame-src https://www.youtube.com"))
    }

    @Test func dropsDomainsThatCouldInjectDirectives() {
        let meta: JSONValue = ["ui": ["csp": ["connectDomains": [
            "https://ok.example.com",
            "https://a.com; script-src *",
            "'unsafe-hashes'",
            "https://b.com\" onload=\"x",
            "https://c.com <script>",
        ]]]]
        let csp = MCPAppCSP(resourceMeta: meta)
        #expect(csp.connectDomains == ["https://ok.example.com"])
    }

    @Test func injectsIntoHead() {
        let result = injectCSP("<html><head><title>Test</title></head><body>Hello</body></html>", policy: "default-src 'none'")
        let headEnd = result.range(of: "<head>")!.upperBound
        let meta = result.range(of: "Content-Security-Policy")!.lowerBound
        #expect(meta > headEnd)
        #expect(result.contains("<title>Test</title>"))
    }

    @Test func injectsAfterHtmlTagWithoutHead() {
        let result = injectCSP("<html><body>No head tag</body></html>", policy: "default-src 'none'")
        #expect(result.contains("<head><meta http-equiv=\"Content-Security-Policy\""))
        #expect(result.contains("No head tag"))
    }

    @Test func prependsToFragments() {
        let result = injectCSP("<div>Just a fragment</div>", policy: "default-src 'none'")
        #expect(result.hasPrefix("<meta"))
        #expect(result.contains("Just a fragment"))
    }

    @Test func scriptLiteralCannotCloseTheShellScript() {
        let literal = HTMLAppShell.scriptStringLiteral("</script><!-- \u{2028}")
        #expect(!literal.contains("<"))
        let data = Data("[\(literal)]".utf8)
        let decoded = try? JSONSerialization.jsonObject(with: data) as? [String]
        #expect(decoded == ["</script><!-- \u{2028}"])
    }
}

// MARK: - WKWebView integration

#if os(macOS)
import AppKit
import SwiftUI

/// A minimal HTML MCP App written against the wire protocol, the way the
/// specification's "no SDK" example is: it posts to `window.parent` and only
/// accepts messages whose source is `window.parent`.
let weatherAppHTML = """
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="margin:0">
<div id="status">loading</div>
<div id="forecast"></div>
<script>
(function () {
  var nextId = 1, pending = {};
  window.__violations = [];
  window.__received = [];
  document.addEventListener("securitypolicyviolation", function (e) {
    window.__violations.push(e.effectiveDirective + " " + e.blockedURI);
  });
  function send(message) { window.parent.postMessage(message, "*"); }
  function request(method, params) {
    var id = nextId++;
    send({ jsonrpc: "2.0", id: id, method: method, params: params });
    return new Promise(function (resolve, reject) { pending[id] = { resolve: resolve, reject: reject }; });
  }
  window.addEventListener("message", function (event) {
    if (event.source !== window.parent) return;
    var m = event.data;
    window.__received.push(m.method || ("response:" + m.id));
    if (m.id !== undefined && pending[m.id]) {
      var p = pending[m.id]; delete pending[m.id];
      m.error ? p.reject(m.error) : p.resolve(m.result);
      return;
    }
    if (m.method === "ui/notifications/tool-input") {
      document.getElementById("status").textContent = "input:" + m.params.arguments.city;
      request("tools/call", { name: "get_forecast", arguments: { city: m.params.arguments.city } })
        .then(function (result) {
          document.getElementById("forecast").textContent = "high:" + result.structuredContent.high;
          send({ jsonrpc: "2.0", method: "ui/notifications/size-changed", params: { width: 300, height: 321 } });
        });
    }
    if (m.method === "ui/notifications/tool-result") {
      document.getElementById("status").textContent += " result:" + m.params.content[0].text;
    }
  });
  request("ui/initialize", {
    protocolVersion: "2026-01-26",
    appInfo: { name: "weather-fixture", version: "1.0.0" },
    appCapabilities: {}
  }).then(function (result) {
    window.__hostName = result.hostInfo.name;
    send({ jsonrpc: "2.0", method: "ui/notifications/initialized", params: {} });
    // Undeclared origins are blocked by CSP.
    fetch("https://undeclared.example.com/data").catch(function () {});
  });
})();
</script>
</body>
</html>
"""

/// Holds WebKit tests until the rest of the run has settled.
///
/// Creating the first window and web view blocks the main thread for about a
/// quarter second, and the session tests, which run in parallel on the main
/// actor, measure phases with 50 ms sleeps. Starting WebKit after they finish
/// keeps both honest.
@MainActor
enum WebKitTestGate {
    private static let settled = Task { try? await Task.sleep(for: .seconds(2)) }
    static func wait() async { await settled.value }
}

@Suite("HTML app web view", .serialized)
@MainActor
struct HTMLAppWebViewTests {
    init() async {
        await WebKitTestGate.wait()
    }

    func weatherServer() -> RecordingServer {
        RecordingServer(
            toolResult: ToolResult(content: [.text("{\"high\":88}")], structuredContent: ["high": 88]),
            resource: ResourceContent(uri: "ui://weather/view", mimeType: "text/html;profile=mcp-app", text: weatherAppHTML)
        )
    }

    func window(containing view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        return window
    }

    func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Evaluates JavaScript against the view's document, inside the shell's iframe.
    func inView(_ webView: WKWebView, _ expression: String) async throws -> Any? {
        try await webView.evaluateJavaScript("(function (w) { return \(expression); })(document.querySelector('iframe').contentWindow)")
    }

    @Test func viewInitializesReceivesDataAndCallsTools() async throws {
        let server = weatherServer()
        let call = SimpleMCPToolCall(id: "c1", name: "weather", arguments: ["city": "Albuquerque"])
        let result = ToolResult(text: "sunny")
        let session = MCPAppSession(toolCall: call, completedWith: result, server: server)
        let bridge = HTMLAppBridge(session: session)
        let host = HTMLAppWebHost(bridge: bridge)
        host.webView.frame = CGRect(x: 0, y: 0, width: 400, height: 700)
        let window = window(containing: host.webView)
        defer { host.tearDown(); window.close() }

        bridge.update(.init(session: session, result: result))
        host.load(html: weatherAppHTML, resourceMeta: nil)
        try await waitUntil { bridge.contentHeight == 321 }

        // The view's tools/call reached the MCP server through the host.
        #expect(server.toolCalls.map(\.name) == ["get_forecast"])
        #expect(server.toolCalls.first?.arguments == ["city": "Albuquerque"])
        // The view received tool-input, tool-result, and the tools/call response.
        let status = try await inView(host.webView, "w.document.getElementById('status').textContent") as? String
        let forecast = try await inView(host.webView, "w.document.getElementById('forecast').textContent") as? String
        let hostName = try await inView(host.webView, "w.__hostName") as? String
        let received = try await inView(host.webView, "w.__received.join(',')") as? String
        #expect(status == "input:Albuquerque result:sunny")
        #expect(forecast == "high:88")
        #expect(hostName == "MCPAppsHost")
        #expect(received == "response:1,ui/notifications/tool-input,ui/notifications/tool-result,response:2")
        // size-changed resized the view.
        #expect(bridge.contentHeight == 321)
        // CSP blocked the undeclared origin.
        let violations = try await inView(host.webView, "w.__violations.join('|')") as? String
        #expect(violations?.contains("connect-src https://undeclared.example.com") == true)
    }

    @Test func viewThatNeverReportsSizeIsMeasured() async throws {
        let html = "<html><head></head><body style=\"margin:0\"><div style=\"height:240px\">plain</div></body></html>"
        let session = MCPAppSession(toolCall: SimpleMCPToolCall(id: "c4", name: "plain"), completedWith: ToolResult(text: ""))
        let bridge = HTMLAppBridge(session: session)
        let host = HTMLAppWebHost(bridge: bridge)
        host.webView.frame = CGRect(x: 0, y: 0, width: 400, height: 0)
        let window = window(containing: host.webView)
        defer { host.tearDown(); window.close() }

        host.load(html: html, resourceMeta: nil)
        try await waitUntil { bridge.contentHeight != nil }

        #expect(bridge.contentHeight == 240)
    }

    @Test func viewCannotNavigateAway() async throws {
        let html = """
        <html><head></head><body><div id="marker">still here</div>
        <script>setTimeout(function () { location.href = "https://example.com/"; }, 50);</script>
        </body></html>
        """
        let session = MCPAppSession(toolCall: SimpleMCPToolCall(id: "c2", name: "nav"), completedWith: ToolResult(text: ""))
        let host = HTMLAppWebHost(bridge: HTMLAppBridge(session: session))
        host.webView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let window = window(containing: host.webView)
        defer { host.tearDown(); window.close() }

        host.load(html: html, resourceMeta: nil)
        try await Task.sleep(for: .seconds(1.5))

        let marker = try await inView(host.webView, "w.document.getElementById('marker').textContent") as? String
        #expect(marker == "still here")
    }

    /// The full SwiftUI path: MCPAppView resolves the HTML resource, renders it
    /// in HTMLAppView, and sizes itself to the height the view reports.
    @Test func mcpAppViewRendersAnHTMLApp() async throws {
        let server = weatherServer()
        let call = SimpleMCPToolCall(
            id: "c3",
            name: "weather",
            arguments: ["city": "Taos"],
            toolDefinition: MCPToolDefinition(name: "weather", ui: .init(resourceUri: "ui://weather/view"))
        )
        let session = MCPAppSession(toolCall: call, server: server, resolvers: [HTMLResolver()])
        let hosting = NSHostingView(rootView: MCPAppView(session: session).frame(width: 400))
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 700)
        let window = window(containing: hosting)
        defer { window.close() }

        try await waitUntil { server.toolCalls.contains { $0.name == "get_forecast" } }
        try await Task.sleep(for: .milliseconds(200))
        hosting.layoutSubtreeIfNeeded()

        #expect(server.resourceReads == ["ui://weather/view"])
        #expect(server.toolCalls.map(\.name) == ["weather", "get_forecast"])
        #expect(server.toolCalls.last?.arguments == ["city": "Taos"])
        #expect(hosting.fittingSize.height == 321)
    }
}
#endif

// MARK: - Live

#if os(macOS)
private let liveHTMLServerURL = ProcessInfo.processInfo.environment["MCPAPPSHOST_LIVE_HTML_URL"]

/// Passes calls through to a live server and records them.
private final class LiveRecordingServer: MCPServer, @unchecked Sendable {
    let client: MCPAppsClient
    private let lock = NSLock()
    private var _toolCalls: [String] = []

    init(client: MCPAppsClient) { self.client = client }

    var toolCalls: [String] { lock.withLock { _toolCalls } }

    func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
        lock.withLock { _toolCalls.append(name) }
        return try await client.callTool(name: name, arguments: arguments)
    }

    func readResource(uri: String) async throws -> ResourceContent {
        try await client.readResource(uri: uri)
    }

    func listTools() async throws -> [MCPToolDefinition] {
        try await client.listTools()
    }
}

/// Renders a Metabind UI tool served as HTML. Opt in with
/// `MCPAPPSHOST_LIVE_HTML_URL=<MCP server URL> swift test --filter HTMLAppLiveTests`;
/// the server's `subscriptions` tool loads its own data by calling
/// `get_subscriptions` from inside the view.
@Suite("HTML app live", .enabled(if: liveHTMLServerURL != nil, "Set MCPAPPSHOST_LIVE_HTML_URL to run"))
@MainActor
struct HTMLAppLiveTests {
    init() async {
        await WebKitTestGate.wait()
    }

    @Test func metabindHTMLAppLoadsItsOwnData() async throws {
        let url = try #require(liveHTMLServerURL.flatMap(URL.init(string:)))
        // Advertise only HTML, so the server sends text/html;profile=mcp-app.
        let client = MCPAppsClient(url: url, resolvers: [HTMLResolver()])
        let server = LiveRecordingServer(client: client)
        let definition = try #require(try await client.listTools().first { $0.name == "subscriptions" })
        let call = SimpleMCPToolCall(id: "live", name: "subscriptions", arguments: .object([:]), toolDefinition: definition)
        let session = MCPAppSession(toolCall: call, server: server, resolvers: [HTMLResolver()])

        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: MCPAppView(session: session).frame(width: 390))
        hosting.frame = CGRect(x: 0, y: 0, width: 390, height: 900)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.close() }

        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline, !server.toolCalls.contains("get_subscriptions") {
            try await Task.sleep(for: .milliseconds(100))
        }
        hosting.layoutSubtreeIfNeeded()

        let resource = try await client.readResource(uri: definition.ui!.resourceUri)
        #expect(resource.mimeType == "text/html;profile=mcp-app")
        // The card's data request came from inside the view, through the host.
        #expect(server.toolCalls == ["subscriptions", "get_subscriptions"])
        #expect(hosting.fittingSize.height > 0)
    }
}
#endif
