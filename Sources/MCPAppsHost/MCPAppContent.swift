import SwiftUI
import BindJS
import WebKit
import os

private let log = Logger(subsystem: "MCPAppsHost", category: "MCPAppContent")

/// The rendered output of an MCP App. Native SwiftUI via BindJS,
/// or HTML via WKWebView. Concrete type, like SwiftUI.Image.
public struct MCPAppContent: View {
    let resolved: ResolvedAppContent?
    let session: MCPAppSession
    /// Tool result passed explicitly to avoid observing session.phase in body.
    let toolResult: ToolResult?

    @Environment(\.mcpHostBridge) private var envHostBridge

    /// One-line structural X-ray of a JSON value, for forensic logs. Drills
    /// two levels — enough to surface "sections count=8, first has empty
    /// content[]" without dumping the full payload.
    fileprivate static func describeStructure(_ value: JSONValue, depth: Int = 4) -> String {
        switch value {
        case .object(let dict):
            if depth == 0 { return "{\(dict.count)k}" }
            let pairs = dict.keys.sorted().map { key -> String in
                let inner = depth == 1 ? describeStructure(dict[key] ?? .null, depth: 0)
                                       : describeStructure(dict[key] ?? .null, depth: depth - 1)
                return "\(key)=\(inner)"
            }
            return "{\(pairs.joined(separator: ", "))}"
        case .array(let arr):
            guard let first = arr.first else { return "[]" }
            if depth == 0 { return "[\(arr.count)]" }
            return "[\(arr.count)×\(describeStructure(first, depth: depth - 1))]"
        case .string(let s): return "\"\(s.count)\""
        case .number(let n): return "n(\(n))"
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    public var body: some View {
        if let resolved {
            switch resolved {
            case .bindJS(let content):
                let args = componentArguments
                let _ = log.info("[\(session.toolName, privacy: .public)] BindJS render \(Self.describeStructure(.object(args.mapValues { JSONValue.from($0) })), privacy: .public)")
                BindJSView(content: content, arguments: args)
                    .bindJS(bindJSConfiguration)
            case .html(let html):
                HTMLAppView(html: html)
            }
        } else if let toolResult {
            fallbackContent(toolResult)
        }
    }

    /// Extract component props from the current tool arguments.
    /// Prefers partialArguments (streaming) over toolArguments (initial).
    ///
    /// Tools may wrap props under a `"content"` key (BYOK Anthropic shape) or
    /// emit them directly (Metabind Agent proxy shape). Accept either.
    private var componentArguments: [String: Any] {
        // Prefer streamed partial arguments so the UI fills in progressively;
        // fall back to the final tool arguments once streaming is done.
        let args = session.partialArguments ?? session.toolArguments
        guard case .object(let dict) = args else { return [:] }
        if case .object(let inner) = dict["content"] ?? .null {
            return inner.mapValues { $0.toAny() }
        }
        return dict.mapValues { $0.toAny() }
    }

    private var bindJSConfiguration: BindJSConfiguration {
        BindJSConfiguration(
            environment: buildEnvironment(),
            onAction: { [session] action in
                // Single dispatch hop to escape JSContext call stack.
                let name = action.name
                let props = action.props
                DispatchQueue.main.async {
                    session.handleAction(name: name, props: props)
                }
            },
            mcpHost: envHostBridge
        )
    }

    private func buildEnvironment() -> [String: any Codable] {
        var env: [String: any Codable] = [:]
        env["toolName"] = session.toolName
        env["displayMode"] = session.displayMode.rawValue
        env["toolArguments"] = jsonString(session.toolArguments)

        if let partial = session.partialArguments {
            env["partialArguments"] = jsonString(partial)
        }

        if let toolResult {
            env["toolResult"] = jsonString(toolResult)
        }

        if let actionResult = session.lastActionResult {
            env["lastActionResult"] = jsonString(actionResult)
        }

        return env
    }

    private func jsonString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @ViewBuilder
    private func fallbackContent(_ result: ToolResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(result.content.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        Text(text)
                            .textSelection(.enabled)
                    case .image(let data, _):
                        if let uiImage = platformImage(from: data) {
                            Image(platformImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                    case .resource(_, _, let text):
                        if let text {
                            Text(text)
                                .textSelection(.enabled)
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
    }
}

// MARK: - Shared Phase Views

struct MCPAppErrorView: View {
    let error: MCPAppError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.localizedDescription)")
    }
}

struct MCPAppCancelledView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "stop.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Cancelled")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityLabel("Tool cancelled")
    }
}

// MARK: - Platform Image

#if canImport(UIKit)
import UIKit
private func platformImage(from data: Data) -> UIImage? { UIImage(data: data) }
extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#elseif canImport(AppKit)
import AppKit
private func platformImage(from data: Data) -> NSImage? { NSImage(data: data) }
extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#endif

// MARK: - HTML App View (WKWebView)

/// Sandboxed WKWebView for rendering MCP App HTML content.
///
/// Security measures:
/// - CSP meta tag injected to restrict script/style/connect sources
/// - JavaScript limited to inline only (required for MCP Apps)
/// - Navigation delegate blocks all external navigation
/// - No access to local storage, cookies, or device APIs beyond what CSP allows

private func sandboxedWebViewConfiguration() -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    config.preferences.isElementFullscreenEnabled = false
    // Prevent access to local storage across MCP apps
    config.websiteDataStore = .nonPersistent()
    return config
}

/// Injects a restrictive CSP meta tag into the HTML head.
/// Allows inline scripts/styles (needed for MCP Apps) but blocks external resources
/// except images and media which are commonly needed for tool UIs.
func injectCSP(_ html: String) -> String {
    let csp = """
    <meta http-equiv="Content-Security-Policy" content="\
    default-src 'none'; \
    script-src 'unsafe-inline'; \
    style-src 'unsafe-inline'; \
    img-src https: data:; \
    media-src https: data:; \
    font-src https: data:; \
    connect-src 'none'; \
    form-action 'none'; \
    base-uri 'none';">
    """

    // Insert CSP as the first element in <head>, or before <html> if no head tag
    if let headRange = html.range(of: "<head>", options: .caseInsensitive) {
        var modified = html
        modified.insert(contentsOf: csp, at: headRange.upperBound)
        return modified
    } else if let htmlRange = html.range(of: "<html", options: .caseInsensitive) {
        // Find the end of the <html ...> tag
        if let closeRange = html[htmlRange.upperBound...].range(of: ">") {
            var modified = html
            modified.insert(contentsOf: "<head>\(csp)</head>", at: closeRange.upperBound)
            return modified
        }
    }
    return csp + html
}

/// Navigation delegate that blocks all navigation away from the initial HTML content.
final class HTMLNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        switch navigationAction.navigationType {
        case .other:
            // Allow initial load and programmatic navigation within the page
            return .allow
        default:
            // Block link clicks, form submissions, back/forward, reload
            return .cancel
        }
    }
}

#if canImport(UIKit)
struct HTMLAppView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: sandboxedWebViewConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator.navigationDelegate
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(injectCSP(html), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        var lastHTML: String?
        let navigationDelegate = HTMLNavigationDelegate()
    }
}
#elseif canImport(AppKit)
struct HTMLAppView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: sandboxedWebViewConfiguration())
        webView.navigationDelegate = context.coordinator.navigationDelegate
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(injectCSP(html), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        var lastHTML: String?
        let navigationDelegate = HTMLNavigationDelegate()
    }
}
#endif
