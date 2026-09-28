import SwiftUI
import BindJS
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
                HTMLAppView(html: html, session: session, toolResult: toolResult)
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

    func buildEnvironment() -> [String: any Codable] {
        var env: [String: any Codable] = [:]
        env["toolName"] = session.toolName
        env["displayMode"] = session.displayMode.rawValue
        env["toolArguments"] = jsonString(session.toolArguments)
        env["argumentsComplete"] = session.argumentsComplete

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
