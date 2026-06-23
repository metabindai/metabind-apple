import Foundation
import MCPAppsHost
import os

/// Concrete ``MCPHostBridge`` that translates JS-side `useMCPHost()` calls
/// from BindJS components into native Metabind intents.
///
/// The bridge itself is stateless (aside from handler closures) — it holds
/// no conversation or tool state, so it's safe to share across multiple
/// rendered components and across the lifetime of an assistant.
///
/// ## Wiring
///
/// ``MetabindAssistant`` constructs a pre-configured bridge (see
/// ``MetabindAssistant/hostBridge``) with:
///
/// - `toolCall` → `MCPServer.callToolUnwrapped`
/// - `sendMessage` → `MetabindAssistant.send(_:)`
/// - `updateModelContext` → `MetabindAssistant.mergePendingContext(_:)`
/// - `log` → `os.Logger` (subsystem `MetabindAssistant.Host`)
///
/// ``MetabindAssistantView`` injects the bridge into the environment and
/// fills in SwiftUI-layer handlers:
///
/// - `openLink` → `@Environment(\.openURL)`
/// - `requestDisplayMode` → `@Environment(\.mcpOnDisplayModeRequest)`
/// - `elicit` → app-supplied `onElicitationRequest` modifier
///
/// Iframe-only methods (`sendRequest`, `sendNotification`, `sizeChanged`)
/// are no-ops on native, matching the TS `MCPHost` contract's graceful
/// degradation for unsupported features.
///
/// ## Standalone use
///
/// Apps that render `MCPAppView` without the full assistant can construct a
/// bridge directly and inject it:
///
/// ```swift
/// let bridge = MetabindHostBridge()
/// bridge.handlers.toolCall = { name, args in
///     try await myServer.callToolUnwrapped(name: name, arguments: args)
/// }
/// contentView.mcpHostBridge(bridge)
/// ```
@MainActor
public final class MetabindHostBridge: MCPHostBridge {

    /// Pluggable handlers. Set any that apply; unset handlers degrade to
    /// a graceful no-op or ``ElicitationResponse/Action/decline``.
    public struct Handlers {
        public typealias ToolCallHandler = (_ name: String, _ arguments: JSONValue) async throws -> Any?
        public typealias MessageHandler = (ToolMessage) -> Void
        public typealias ContextHandler = (ModelContext) -> Void
        public typealias OpenLinkHandler = (URL) async -> Bool
        public typealias DisplayModeHandler = (MCPAppSession.DisplayMode) -> MCPAppSession.DisplayMode
        public typealias ElicitationHandler = (JSONValue, [String: JSONValue]?) async -> ElicitationResponse
        public typealias LogHandler = (_ level: String, _ message: String, _ data: JSONValue?) -> Void

        public var toolCall: ToolCallHandler?
        public var onMessage: MessageHandler?
        public var onContext: ContextHandler?
        public var onOpenLink: OpenLinkHandler?
        public var onDisplayMode: DisplayModeHandler?
        public var onElicit: ElicitationHandler?
        public var onLog: LogHandler?

        public init() {}
    }

    /// Live handlers. Modify in place to change behavior at runtime.
    public var handlers = Handlers()

    private static let log = Logger(subsystem: "MetabindAssistant", category: "Host")

    public init() {}

    // MARK: - Tool calls

    public nonisolated func toolCall(name: String, arguments: [String: Any]) async throws -> Any? {
        let json = JSONValue.from(arguments)
        Self.log.info("toolCall '\(name, privacy: .public)' args=\(Self.describeStructure(json), privacy: .public)")
        let handler = await MainActor.run { self.handlers.toolCall }
        guard let handler else {
            Self.log.warning("toolCall '\(name, privacy: .public)' dropped — no handler configured")
            return nil
        }
        let start = Date()
        do {
            let result = try await handler(name, json)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let resultDigest: String = {
                guard let result else { return "nil" }
                return Self.describeStructure(JSONValue.from(result as Any))
            }()
            Self.log.info("toolCall '\(name, privacy: .public)' ok \(elapsed, privacy: .public)ms result=\(resultDigest, privacy: .public)")
            return result
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            Self.log.error("toolCall '\(name, privacy: .public)' failed \(elapsed, privacy: .public)ms error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// One-line structural X-ray of a JSON value for forensic logs.
    fileprivate nonisolated static func describeStructure(_ value: JSONValue, depth: Int = 2) -> String {
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

    // MARK: - Messaging

    public nonisolated func sendMessage(_ message: String) async throws {
        await MainActor.run {
            guard let handler = self.handlers.onMessage else {
                Self.log.warning("sendMessage dropped — no handler configured (bytes=\(message.count, privacy: .public))")
                return
            }
            Self.log.info("sendMessage bytes=\(message.count, privacy: .public) preview=\(String(message.prefix(200)), privacy: .public)")
            let toolMessage = ToolMessage(role: .user, content: [.text(message)])
            handler(toolMessage)
        }
    }

    // MARK: - Model context

    public nonisolated func updateModelContext(_ content: [String: Any]) async throws {
        let structured = JSONValue.from(content)
        await MainActor.run {
            guard let handler = self.handlers.onContext else {
                Self.log.warning("updateModelContext dropped — no handler configured (\(Self.describeStructure(structured), privacy: .public))")
                return
            }
            Self.log.info("updateModelContext \(Self.describeStructure(structured), privacy: .public)")
            handler(ModelContext(structuredContent: structured))
        }
    }

    // MARK: - Elicitation

    public nonisolated func elicit(
        schema: [String: Any],
        metadata: [String: Any]?
    ) async throws -> ElicitationResponse {
        let schemaJSON = JSONValue.from(schema)
        let metadataJSON: [String: JSONValue]? = metadata.flatMap { dict in
            if case .object(let map) = JSONValue.from(dict) { return map }
            return nil
        }
        let handler = await MainActor.run { self.handlers.onElicit }
        Self.log.info("elicit schema=\(Self.describeStructure(schemaJSON), privacy: .public) metadata=\(metadataJSON?.keys.sorted().joined(separator: ",") ?? "<none>", privacy: .public)")
        guard let handler else {
            Self.log.info("elicit declined — no handler configured")
            return ElicitationResponse(action: .decline)
        }
        let response = await handler(schemaJSON, metadataJSON)
        let contentKeys = response.content?.keys.sorted().joined(separator: ",") ?? "<none>"
        Self.log.info("elicit response action=\(String(describing: response.action), privacy: .public) contentKeys=\(contentKeys, privacy: .public)")
        return response
    }

    // MARK: - Navigation

    public nonisolated func openLink(_ url: URL) async throws {
        let handler = await MainActor.run { self.handlers.onOpenLink }
        guard let handler else {
            throw MetabindHostError.unsupported("openLink — no handler configured (typically wired by MetabindAssistantView)")
        }
        let handled = await handler(url)
        if !handled {
            throw MetabindHostError.linkRefused(url)
        }
    }

    // MARK: - Display

    public nonisolated func requestDisplayMode(_ mode: String) async throws {
        let target = MCPAppSession.DisplayMode(rawValue: mode) ?? .inline
        _ = await MainActor.run {
            _ = self.handlers.onDisplayMode?(target)
        }
    }

    // MARK: - Logging

    public nonisolated func log(level: String, message: String, data: [String: Any]?) {
        let payload = data.map { JSONValue.from($0) }
        Task { @MainActor in
            if let handler = self.handlers.onLog {
                handler(level, message, payload)
            } else {
                Self.emitDefaultLog(level: level, message: message, data: payload)
            }
        }
    }

    private static func emitDefaultLog(level: String, message: String, data: JSONValue?) {
        let dataString: String
        if let data {
            let any = data.toAny()
            dataString = (try? JSONSerialization.data(withJSONObject: any, options: [.sortedKeys]))
                .flatMap { String(data: $0, encoding: .utf8) }
                .map { " data=\($0)" } ?? ""
        } else {
            dataString = ""
        }
        switch level.lowercased() {
        case "error":
            log.error("[component] \(message, privacy: .public)\(dataString, privacy: .public)")
        case "warning", "warn":
            log.warning("[component] \(message, privacy: .public)\(dataString, privacy: .public)")
        case "debug":
            log.debug("[component] \(message, privacy: .public)\(dataString, privacy: .public)")
        default:
            log.info("[component] \(message, privacy: .public)\(dataString, privacy: .public)")
        }
    }

    // MARK: - Iframe-only (no-op on native)

    public nonisolated func sendRequest(method: String, params: [String: Any]) async throws -> Any? {
        Self.log.debug("sendRequest '\(method, privacy: .public)' — iframe-only, no-op on native")
        return nil
    }

    public nonisolated func sendNotification(method: String, params: [String: Any]) {
        Self.log.debug("sendNotification '\(method, privacy: .public)' — iframe-only, no-op on native")
    }

    public nonisolated func sizeChanged(height: Double) {
        // SwiftUI sizes itself; no-op on native.
    }
}

// MARK: - Errors

public enum MetabindHostError: Error, LocalizedError, Sendable {
    case unsupported(String)
    case linkRefused(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let reason):
            return reason
        case .linkRefused(let url):
            return "Host refused to open \(url.absoluteString)"
        }
    }
}
