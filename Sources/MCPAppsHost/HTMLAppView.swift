import SwiftUI
import WebKit
import os

private let log = Logger(subsystem: "MCPAppsHost", category: "MCPAppContent")

// MARK: - HTML App View

/// Renders an HTML MCP App (`text/html;profile=mcp-app`) in a sandboxed
/// WKWebView and connects it to the host through ``HTMLAppBridge``.
///
/// The view is sized to the height it reports in `ui/notifications/size-changed`
/// (or, until it reports one, to its measured content height).
struct HTMLAppView: View {
    let html: String
    let session: MCPAppSession
    let toolResult: ToolResult?

    @State private var bridge: HTMLAppBridge

    init(html: String, session: MCPAppSession, toolResult: ToolResult?) {
        self.html = html
        self.session = session
        self.toolResult = toolResult
        _bridge = State(initialValue: HTMLAppBridge(session: session))
    }

    var body: some View {
        HTMLAppWebView(
            html: html,
            resourceMeta: session.resourceMeta,
            bridge: bridge,
            toolState: HTMLAppBridge.ToolState(session: session, result: toolResult)
        )
        .frame(height: bridge.contentHeight.map { CGFloat($0) } ?? 0)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Web view host

/// Owns the WKWebView for one HTML MCP App and relays JSON-RPC between it and
/// an ``HTMLAppBridge``.
///
/// A view written against the MCP Apps SDK expects to run in an iframe: it posts
/// to `window.parent` and accepts messages only from it. So the web view loads a
/// small shell page that embeds the view in an iframe and forwards messages
/// between the iframe and native code, the role the specification's sandbox
/// proxy plays for web hosts.
@MainActor
final class HTMLAppWebHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    nonisolated static let messageHandlerName = "mcpAppHost"

    let webView: WKWebView
    let bridge: HTMLAppBridge
    private var loadedHTML: String?
    private var allowsNestedFrames = false

    init(bridge: HTMLAppBridge) {
        self.bridge = bridge
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = false
        // Nothing persists between MCP apps.
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        configuration.userContentController.add(WeakScriptMessageHandler(self), name: Self.messageHandlerName)
        webView.navigationDelegate = self
        #if canImport(UIKit)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        #endif

        bridge.deliver = { [weak self] message in self?.deliver(message) }
        bridge.containerWidth = { [weak webView] in webView.map { Double($0.bounds.width) } }
    }

    /// Loads the view's HTML, unless it is already loaded.
    func load(html: String, resourceMeta: JSONValue?) {
        guard html != loadedHTML else { return }
        loadedHTML = html
        let csp = MCPAppCSP(resourceMeta: resourceMeta)
        allowsNestedFrames = !csp.frameDomains.isEmpty
        log.info("[\(self.bridge.session.toolName, privacy: .public)] HTML view CSP: \(csp.policy, privacy: .public)")
        webView.loadHTMLString(HTMLAppShell.document(viewHTML: html, policy: csp.policy), baseURL: nil)
    }

    func tearDown() {
        bridge.close()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    private func deliver(_ message: JSONValue) {
        guard let data = try? JSONEncoder().encode(message),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.callAsyncJavaScript(
            "window.__mcpAppHost && window.__mcpAppHost.deliver(JSON.parse(json))",
            arguments: ["json": json],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let json = message.body as? String else { return }
        bridge.receive(json)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        HTMLAppShell.policy(
            for: navigationAction.request.url,
            isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
            navigationType: navigationAction.navigationType,
            allowsNestedFrames: allowsNestedFrames
        )
    }
}

/// Holds a script message handler weakly, since WKUserContentController retains
/// its handlers and the handler owns the web view.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Representable

#if canImport(UIKit)
struct HTMLAppWebView: UIViewRepresentable {
    let html: String
    let resourceMeta: JSONValue?
    let bridge: HTMLAppBridge
    let toolState: HTMLAppBridge.ToolState

    func makeCoordinator() -> HTMLAppWebHost { HTMLAppWebHost(bridge: bridge) }

    func makeUIView(context: Context) -> WKWebView { context.coordinator.webView }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(context.coordinator, environment: context.environment)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: HTMLAppWebHost) {
        coordinator.tearDown()
    }
}
#elseif canImport(AppKit)
struct HTMLAppWebView: NSViewRepresentable {
    let html: String
    let resourceMeta: JSONValue?
    let bridge: HTMLAppBridge
    let toolState: HTMLAppBridge.ToolState

    func makeCoordinator() -> HTMLAppWebHost { HTMLAppWebHost(bridge: bridge) }

    func makeNSView(context: Context) -> WKWebView { context.coordinator.webView }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(context.coordinator, environment: context.environment)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: HTMLAppWebHost) {
        coordinator.tearDown()
    }
}
#endif

extension HTMLAppWebView {
    @MainActor
    fileprivate func update(_ host: HTMLAppWebHost, environment: EnvironmentValues) {
        let openURL = environment.openURL
        host.bridge.host = HTMLAppBridge.Host(
            hostBridge: environment.mcpHostBridge,
            onToolMessage: environment.mcpOnToolMessage,
            onModelContextUpdate: environment.mcpOnModelContextUpdate,
            onDisplayModeRequest: environment.mcpOnDisplayModeRequest,
            openURL: { url in
                await withCheckedContinuation { continuation in
                    openURL(url) { continuation.resume(returning: $0) }
                }
            }
        )
        host.bridge.setTheme(environment.colorScheme == .dark ? "dark" : "light")
        host.load(html: html, resourceMeta: resourceMeta)
        host.bridge.update(toolState)
    }
}

// MARK: - Shell page

/// The page the web view loads: the view in an iframe, plus the relay between
/// that iframe and native code.
enum HTMLAppShell {

    static func document(viewHTML: String, policy: String) -> String {
        let meta = cspMetaTag(policy)
        let view = scriptStringLiteral(injectCSP(viewHTML, policy: policy))
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(meta)
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;height:100%;overflow:hidden;background:transparent}iframe{display:block;width:100%;height:100%;border:0}</style>
        </head>
        <body>
        <script>
        (function () {
          "use strict";
          var host = window.webkit.messageHandlers.\(HTMLAppWebHost.messageHandlerName);
          var frame = document.createElement("iframe");
          frame.setAttribute("sandbox", "allow-scripts allow-same-origin allow-forms");
          var viewReportsSize = false;
          function post(message) {
            try { host.postMessage(JSON.stringify(message)); } catch (e) {}
          }
          window.addEventListener("message", function (event) {
            if (event.source !== frame.contentWindow) return;
            var data = event.data;
            if (!data || data.jsonrpc !== "2.0") return;
            if (data.method === "ui/notifications/size-changed") viewReportsSize = true;
            post(data);
          });
          // Until the view reports its own size, measure it, so a view that
          // never sends size-changed still gets its content height.
          function measure() {
            var doc = frame.contentDocument;
            if (viewReportsSize || !doc || !doc.documentElement) return;
            var height = Math.ceil(doc.documentElement.getBoundingClientRect().height);
            post({ jsonrpc: "2.0", method: "\(HTMLAppBridge.measuredHeightMethod)", params: { height: height } });
          }
          frame.addEventListener("load", function () {
            measure();
            var doc = frame.contentDocument;
            if (doc && window.ResizeObserver) new ResizeObserver(measure).observe(doc.documentElement);
          });
          Object.defineProperty(window, "__mcpAppHost", {
            value: Object.freeze({
              deliver: function (message) {
                if (frame.contentWindow) frame.contentWindow.postMessage(message, "*");
              }
            })
          });
          frame.srcdoc = \(view);
          document.body.appendChild(frame);
        })();
        </script>
        </body>
        </html>
        """
    }

    /// Which navigations the web view allows. The shell and the view's iframe
    /// load as `about:` documents; a view opens links through `ui/open-link`.
    static func policy(
        for url: URL?,
        isMainFrame: Bool,
        navigationType: WKNavigationType,
        allowsNestedFrames: Bool
    ) -> WKNavigationActionPolicy {
        guard let url else { return .cancel }
        if url.scheme == "about" { return .allow }
        guard !isMainFrame, navigationType == .other else { return .cancel }
        // Frames a view embeds from its declared frameDomains; CSP frame-src
        // limits them to those origins.
        return allowsNestedFrames && url.scheme == "https" ? .allow : .cancel
    }

    /// A JavaScript string literal that is safe inside an inline `<script>`.
    static func scriptStringLiteral(_ string: String) -> String {
        let data = (try? JSONEncoder().encode(string)) ?? Data("\"\"".utf8)
        let literal = String(data: data, encoding: .utf8) ?? "\"\""
        // Keep "</script>" and "<!--" in the view's HTML from ending or
        // re-entering the shell's script element.
        return literal.replacingOccurrences(of: "<", with: "\\u003c")
    }
}

// MARK: - Content Security Policy

/// The Content Security Policy for an HTML MCP App, built from its resource's
/// `_meta.ui.csp`.
///
/// Follows the MCP Apps reference host (ext-apps `examples/basic-host`): the
/// view may load scripts, styles, and media only from `resourceDomains`,
/// connect only to `connectDomains`, and embed frames only from `frameDomains`.
/// Without declarations, every external origin is blocked.
struct MCPAppCSP: Equatable {
    var connectDomains: [String] = []
    var resourceDomains: [String] = []
    var frameDomains: [String] = []
    var baseUriDomains: [String] = []

    init(connectDomains: [String] = [], resourceDomains: [String] = [], frameDomains: [String] = [], baseUriDomains: [String] = []) {
        self.connectDomains = connectDomains
        self.resourceDomains = resourceDomains
        self.frameDomains = frameDomains
        self.baseUriDomains = baseUriDomains
    }

    init(resourceMeta: JSONValue?) {
        let csp = resourceMeta?["ui"]?["csp"]
        self.init(
            connectDomains: Self.sanitized(csp?["connectDomains"]),
            resourceDomains: Self.sanitized(csp?["resourceDomains"]),
            frameDomains: Self.sanitized(csp?["frameDomains"]),
            baseUriDomains: Self.sanitized(csp?["baseUriDomains"])
        )
    }

    var policy: String {
        let resources = resourceDomains.joined(separator: " ")
        func directive(_ name: String, _ sources: String) -> String {
            "\(name) \(sources)".trimmingCharacters(in: .whitespaces)
        }
        return [
            "default-src 'self' 'unsafe-inline'",
            directive("script-src", "'self' 'unsafe-inline' 'unsafe-eval' blob: data: \(resources)"),
            directive("style-src", "'self' 'unsafe-inline' blob: data: \(resources)"),
            directive("img-src", "'self' data: blob: \(resources)"),
            directive("font-src", "'self' data: blob: \(resources)"),
            directive("media-src", "'self' data: blob: \(resources)"),
            directive("connect-src", "'self' \(connectDomains.joined(separator: " "))"),
            directive("worker-src", "'self' blob: \(resources)"),
            frameDomains.isEmpty ? "frame-src 'none'" : directive("frame-src", frameDomains.joined(separator: " ")),
            "object-src 'none'",
            baseUriDomains.isEmpty ? "base-uri 'none'" : directive("base-uri", baseUriDomains.joined(separator: " ")),
        ].joined(separator: "; ")
    }

    /// Declared origins that can't break out of their directive or the meta tag:
    /// no separators, quotes, whitespace, or markup.
    private static func sanitized(_ value: JSONValue?) -> [String] {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:/.-_*[]%")
        return (value?.arrayValue ?? []).compactMap(\.stringValue).filter { domain in
            !domain.isEmpty && domain.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}

private func cspMetaTag(_ policy: String) -> String {
    "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"
}

/// Inserts a CSP meta tag as the first element of the document's head.
func injectCSP(_ html: String, policy: String) -> String {
    let meta = cspMetaTag(policy)
    if let headRange = html.range(of: "<head>", options: .caseInsensitive) {
        var modified = html
        modified.insert(contentsOf: meta, at: headRange.upperBound)
        return modified
    } else if let htmlRange = html.range(of: "<html", options: .caseInsensitive),
              let closeRange = html[htmlRange.upperBound...].range(of: ">") {
        var modified = html
        modified.insert(contentsOf: "<head>\(meta)</head>", at: closeRange.upperBound)
        return modified
    }
    return meta + html
}
