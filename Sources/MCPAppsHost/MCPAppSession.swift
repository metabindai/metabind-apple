import Foundation
import Observation
import os

private let log = Logger(subsystem: "MCPAppsHost", category: "MCPAppSession")

/// One session = one tool invocation's lifecycle.
///
/// Lives in your conversation model, not the view layer.
/// Survives view attach/detach. Observe `phase` from anywhere.
///
/// The framework fetches the UI resource, renders it,
/// executes the tool, and delivers the result — automatically.
///
///     let session = MCPAppSession(toolCall: call, server: myServer)
///     conversation.append(.tool(session))
///
@MainActor
@Observable
public class MCPAppSession: Identifiable {

    // MARK: - Identity & Input

    nonisolated public let id: String
    nonisolated public let toolName: String
    public let toolArguments: JSONValue
    public let resourceUri: String?

    // MARK: - Observable State

    /// Current lifecycle phase. Observable from anywhere.
    public internal(set) var phase: Phase = .loading

    /// Current display mode.
    public internal(set) var displayMode: DisplayMode = .inline

    /// The latest partial tool arguments streamed into this session, or nil if
    /// none have been fed. Populated only by `ManualMCPAppSession.feed(_:)` as a
    /// tool call streams in; declared here so it lives on the `@Observable` base
    /// and a feed invalidates observing views. Read it via `MCPAppContent` to
    /// render the tool UI progressively.
    public internal(set) var partialArguments: JSONValue?

    /// Sendable model-layer phase. No view content.
    public enum Phase: Sendable {
        case loading
        case active
        case completed(ToolResult)
        case failed(MCPAppError)
        case cancelled

        /// The result if this phase is terminal, nil if still in progress.
        public var terminalResult: ToolResult? {
            switch self {
            case .completed(let r): r
            case .failed(let e): ToolResult(text: e.localizedDescription, isError: true)
            case .cancelled: ToolResult(text: "Cancelled", isError: true)
            case .loading, .active: nil
            }
        }
    }

    public enum DisplayMode: String, Sendable {
        case inline, fullscreen, pip
    }

    // MARK: - Callbacks

    /// Fired on every phase transition. MCPAppView wires this from environment.
    /// You can also set it directly when using sessions without views.
    public var onPhaseTransition: ((Phase) -> Void)?

    // MARK: - Internal State

    private(set) var server: (any MCPServer)?
    private(set) var resolvedContent: ResolvedAppContent?
    private var executionTask: Task<Void, Never>?
    private let autoExecute: Bool
    /// Whether a server has been connected (used by MCPAppView to avoid re-connecting).
    private(set) var hasServerConnected = false

    /// Latest result from an action-triggered tool call.
    private(set) var lastActionResult: ToolResult?
    private var actionTask: Task<Void, Never>?

    // MARK: - Creation

    /// Standard: fetches the UI resource and executes the tool automatically.
    public init(toolCall: some MCPToolCall, server: some MCPServer, resolvers: [any ContentResolver] = defaultResolvers) {
        (self.id, self.toolName, self.toolArguments, self.resourceUri) = Self.extractFields(from: toolCall)
        self.server = server
        self.resolvers = resolvers
        self.autoExecute = true
        self.hasServerConnected = true

        log.info("[\(self.toolName, privacy: .public)] Created (auto-execute, uri: \(self.resourceUri ?? "none", privacy: .public))")
        startAutoExecution()
    }

    /// Creates a session with an already-completed tool result.
    /// Use when you executed the tool yourself and want to render the result.
    ///
    /// If a UI resource URI is available and a server is provided, the resource
    /// is fetched so the native UI can render alongside the completed result.
    public init(toolCall: some MCPToolCall, completedWith result: ToolResult, server: (any MCPServer)? = nil, resolvers: [any ContentResolver] = defaultResolvers) {
        (self.id, self.toolName, self.toolArguments, self.resourceUri) = Self.extractFields(from: toolCall)
        self.server = server
        self.resolvers = resolvers
        self.autoExecute = false
        self.hasServerConnected = server != nil

        if resourceUri != nil && server != nil {
            // Fetch the UI resource, then transition to completed with the provided result.
            self.phase = .loading
            log.info("[\(self.toolName, privacy: .public)] Created (completed, fetching UI resource)")
            startResourceFetch(thenPhase: .completed(result))
        } else {
            self.phase = .completed(result)
            log.info("[\(self.toolName, privacy: .public)] Created (completed, result provided)")
        }
    }

    /// Pending: stores tool call info but waits for a server connection.
    public init(pendingToolCall: some MCPToolCall, resolvers: [any ContentResolver] = defaultResolvers) {
        (self.id, self.toolName, self.toolArguments, self.resourceUri) = Self.extractFields(from: pendingToolCall)
        self.server = nil
        self.resolvers = resolvers
        self.autoExecute = true
        self.hasServerConnected = false
        log.info("[\(self.toolName, privacy: .public)] Created (pending, waiting for server)")
    }

    /// Internal init for ManualMCPAppSession.
    init(toolCall: some MCPToolCall, server: some MCPServer, resolvers: [any ContentResolver] = defaultResolvers, autoExecute: Bool) {
        (self.id, self.toolName, self.toolArguments, self.resourceUri) = Self.extractFields(from: toolCall)
        self.server = server
        self.resolvers = resolvers
        self.autoExecute = autoExecute
        self.hasServerConnected = true

        if autoExecute {
            startAutoExecution()
        } else {
            startResourceFetch(thenPhase: .active)
        }
    }

    // MARK: - Primitive Inits

    static func makeCall(id: String, toolName: String, arguments: JSONValue, resourceUri: String?) -> SimpleMCPToolCall {
        SimpleMCPToolCall(
            id: id, name: toolName, arguments: arguments,
            toolDefinition: resourceUri.map { MCPToolDefinition(name: toolName, ui: .init(resourceUri: $0)) }
        )
    }

    /// Auto-execute from primitives. No MCPToolCall conformance needed.
    public convenience init(
        id: String,
        toolName: String,
        arguments: JSONValue = .object([:]),
        resourceUri: String? = nil,
        server: some MCPServer,
        resolvers: [any ContentResolver] = defaultResolvers
    ) {
        self.init(toolCall: Self.makeCall(id: id, toolName: toolName, arguments: arguments, resourceUri: resourceUri), server: server, resolvers: resolvers)
    }

    /// Completed from primitives. Renders the tool result directly.
    public convenience init(
        id: String,
        toolName: String,
        arguments: JSONValue = .object([:]),
        resourceUri: String? = nil,
        completedWith result: ToolResult,
        server: (any MCPServer)? = nil,
        resolvers: [any ContentResolver] = defaultResolvers
    ) {
        self.init(toolCall: Self.makeCall(id: id, toolName: toolName, arguments: arguments, resourceUri: resourceUri), completedWith: result, server: server, resolvers: resolvers)
    }

    /// Pending from primitives. Waits for connectToServer(_:).
    public convenience init(
        pendingId id: String,
        toolName: String,
        arguments: JSONValue = .object([:]),
        resourceUri: String? = nil,
        resolvers: [any ContentResolver] = defaultResolvers
    ) {
        self.init(pendingToolCall: Self.makeCall(id: id, toolName: toolName, arguments: arguments, resourceUri: resourceUri), resolvers: resolvers)
    }

    /// For SwiftUI previews. No server needed.
    public static func preview(
        toolName: String = "example_tool",
        phase: Phase = .active
    ) -> MCPAppSession {
        let session = MCPAppSession(preview: true)
        session.phase = phase
        return session
    }

    private init(preview: Bool) {
        self.id = UUID().uuidString
        self.toolName = "example_tool"
        self.toolArguments = .object([:])
        self.resourceUri = nil
        self.server = nil
        self.resolvers = []
        self.autoExecute = false
    }

    // MARK: - awaitResult() support

    private var resultContinuations: [CheckedContinuation<ToolResult, Never>] = []

    private let resolvers: [any ContentResolver]

    nonisolated deinit {
        // Task cancellation is best-effort from nonisolated deinit.
        // Continuations are cleaned up in teardown() which should be called
        // before dropping all references. See teardown() docs.
    }

    // MARK: - Field Extraction

    private static func extractFields(from toolCall: some MCPToolCall) -> (String, String, JSONValue, String?) {
        (toolCall.id, toolCall.name, toolCall.arguments, toolCall.toolDefinition?.ui?.resourceUri)
    }

    // MARK: - Phase Transition

    func transitionTo(_ newPhase: Phase) {
        log.info("[\(self.toolName, privacy: .public)] phase: \(Self.phaseLabel(newPhase), privacy: .public)")
        phase = newPhase
        onPhaseTransition?(newPhase)

        // Resume any awaitResult() waiters on terminal phases
        if let result = newPhase.terminalResult {
            let continuations = resultContinuations
            resultContinuations = []
            for continuation in continuations {
                continuation.resume(returning: result)
            }
        }
    }

    private static func phaseLabel(_ phase: Phase) -> String {
        switch phase {
        case .loading: "loading"
        case .active: "active"
        case .completed(let r): "completed (isError: \(r.isError), \(r.content.count) block(s))"
        case .failed(let e): "failed (\(e.localizedDescription))"
        case .cancelled: "cancelled"
        }
    }

    // MARK: - Server Connection

    public func connectToServer(_ server: any MCPServer) {
        guard !hasServerConnected else { return }
        log.info("[\(self.toolName, privacy: .public)] Server connected, starting \(self.autoExecute ? "auto-execution" : "resource fetch", privacy: .public)")
        hasServerConnected = true
        self.server = server

        if autoExecute {
            startAutoExecution()
        } else {
            startResourceFetch(thenPhase: .active)
        }
    }

    // MARK: - Control

    public func cancel() {
        switch phase {
        case .loading, .active:
            executionTask?.cancel()
            transitionTo(.cancelled)
        default:
            break
        }
    }

    public func retry() {
        switch phase {
        case .failed, .cancelled:
            transitionTo(.loading)
            if autoExecute {
                startAutoExecution()
            } else {
                startResourceFetch(thenPhase: .active)
            }
        default:
            break
        }
    }

    /// Await the tool result. Resolves when the session reaches a terminal phase.
    /// Returns immediately if already completed, failed, or cancelled.
    public func awaitResult() async -> ToolResult {
        if let result = phase.terminalResult {
            return result
        }
        return await withCheckedContinuation { continuation in
            resultContinuations.append(continuation)
        }
    }

    /// Cleanly shut down the session, cancelling in-flight work and resuming any
    /// `awaitResult()` waiters. Call this before dropping all references to avoid
    /// leaked continuations.
    public func teardown() async {
        executionTask?.cancel()
        actionTask?.cancel()
        // transitionTo handles resuming continuations via terminalResult
        transitionTo(.cancelled)
    }

    // MARK: - Action Routing

    func handleAction(name: String, props: [String: Any]) {
        guard let server else {
            log.warning("[\(self.toolName, privacy: .public)] Action '\(name, privacy: .public)' ignored — no server")
            return
        }
        let arguments = JSONValue.from(props)
        log.info("[\(self.toolName, privacy: .public)] Action → \(name, privacy: .public)")

        // Cancel previous action task to prevent races
        actionTask?.cancel()
        let toolName = self.toolName
        actionTask = Task { [weak self] in
            do {
                let result = try await server.callTool(name: name, arguments: arguments)
                guard let self, !Task.isCancelled else { return }
                if self.lastActionResult != result {
                    self.lastActionResult = result
                    log.info("[\(toolName, privacy: .public)] Action ← \(name, privacy: .public): \(result.content.count, privacy: .public) block(s)")
                }
            } catch {
                if !Task.isCancelled {
                    log.error("[\(toolName, privacy: .public)] Action '\(name, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Resource Fetching (shared)

    private func fetchAndResolveResource() async throws {
        guard let uri = resourceUri, let server else {
            log.info("[\(self.toolName, privacy: .public)] No resource URI, skipping fetch")
            return
        }

        log.info("[\(self.toolName, privacy: .public)] Fetching resource: \(uri, privacy: .public)")
        let resource = try await server.readResource(uri: uri)
        try Task.checkCancellation()
        log.info("[\(self.toolName, privacy: .public)] Resource fetched: mimeType=\(resource.mimeType, privacy: .public)")

        guard let resolver = resolvers.first(where: { $0.canResolve(mimeType: resource.mimeType) }) else {
            log.error("[\(self.toolName, privacy: .public)] No resolver for mimeType=\(resource.mimeType, privacy: .public)")
            throw MCPAppError.unsupportedContentType(mimeType: resource.mimeType)
        }
        log.info("[\(self.toolName, privacy: .public)] Resolving with \(String(describing: type(of: resolver)), privacy: .public)")
        resolvedContent = try await resolver.resolve(resource)
        try Task.checkCancellation()
    }

    // MARK: - Execution

    private func startAutoExecution() {
        executionTask = Task { [weak self] in
            guard let self else { return }

            guard let server = self.server else {
                self.transitionTo(.failed(.serverUnreachable(underlying: SessionError.noServer)))
                return
            }

            // Step 1: Fetch resource
            if self.resourceUri != nil {
                do {
                    try await self.fetchAndResolveResource()
                } catch is CancellationError {
                    self.transitionTo(.cancelled)
                    return
                } catch let error as MCPAppError {
                    self.transitionTo(.failed(error))
                    return
                } catch {
                    self.transitionTo(.failed(.serverUnreachable(underlying: error)))
                    return
                }
            }

            // Step 2: Active
            self.transitionTo(.active)

            // Step 3: Execute tool
            do {
                let result = try await server.callTool(name: self.toolName, arguments: self.toolArguments)
                try Task.checkCancellation()
                if result.isError && self.resolvedContent == nil {
                    // Only fail if there's no rendered content to preserve.
                    // UI tools have their content in the resource, not the tool result.
                    self.transitionTo(.failed(.toolFailed(result: result)))
                } else {
                    self.transitionTo(.completed(result))
                }
            } catch is CancellationError {
                self.transitionTo(.cancelled)
            } catch {
                self.transitionTo(.failed(.serverUnreachable(underlying: error)))
            }
        }
    }

    private func startResourceFetch(thenPhase targetPhase: Phase) {
        guard resourceUri != nil, server != nil else {
            transitionTo(targetPhase)
            return
        }

        executionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.fetchAndResolveResource()
                self.transitionTo(targetPhase)
            } catch is CancellationError {
                self.transitionTo(.cancelled)
            } catch let error as MCPAppError {
                self.transitionTo(.failed(error))
            } catch {
                self.transitionTo(.failed(.serverUnreachable(underlying: error)))
            }
        }
    }

    enum SessionError: Error, Sendable {
        case noServer
    }
}
