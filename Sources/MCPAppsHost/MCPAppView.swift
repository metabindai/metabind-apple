import SwiftUI

/// Renders an MCP App session as native SwiftUI.
///
/// Three initializers, like AsyncImage:
///   1. `MCPAppView(session:)` — automatic rendering
///   2. `MCPAppView(session:content:placeholder:)` — customize content + loading
///   3. `MCPAppView(session:phase:)` — full phase control
///
public struct MCPAppView<Content: View>: View {
    let session: MCPAppSession
    let contentBuilder: (MCPAppPhase) -> Content

    @Environment(\.mcpServer) private var envServer
    @Environment(\.mcpOnToolCompleted) private var onToolCompleted

    public var body: some View {
        let phase = viewPhase
        contentBuilder(phase)
            .task(id: session.id) {
                wireCallbacks()
                connectIfNeeded()
            }
    }

    private func wireCallbacks() {
        let toolCompleted = onToolCompleted
        session.onPhaseTransition = { phase in
            if case .completed(let result) = phase {
                toolCompleted?(result)
            }
        }
    }

    private func connectIfNeeded() {
        if let envServer, !session.hasServerConnected {
            session.connectToServer(envServer)
        }
    }

    private var viewPhase: MCPAppPhase {
        let phase = session.phase
        let toolResult: ToolResult? = if case .completed(let r) = phase { r } else { nil }

        let appContent = MCPAppContent(
            resolved: session.resolvedContent,
            session: session,
            toolResult: toolResult
        )

        switch phase {
        case .loading:
            return .loading
        case .active:
            return .active(appContent)
        case .completed(let result):
            return .completed(appContent, result)
        case .failed(let error):
            return .failed(error)
        case .cancelled:
            return .cancelled
        }
    }
}

// MARK: - Init 1: Automatic

extension MCPAppView where Content == DefaultMCPAppContent {

    public init(session: MCPAppSession) {
        self.session = session
        self.contentBuilder = { phase in
            DefaultMCPAppContent(phase: phase, session: session)
        }
    }

    public init(toolCall: some MCPToolCall) {
        let pendingSession = MCPAppSession(pendingToolCall: toolCall)
        self.session = pendingSession
        self.contentBuilder = { phase in
            DefaultMCPAppContent(phase: phase, session: pendingSession)
        }
    }
}

// MARK: - Init 2: Content + Placeholder

extension MCPAppView {

    public init<C: View, P: View>(
        session: MCPAppSession,
        @ViewBuilder content: @escaping (MCPAppContent) -> C,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _MCPAppConditionalContent<C, P> {
        self.session = session
        self.contentBuilder = { phase in
            _MCPAppConditionalContent(
                phase: phase,
                session: session,
                contentBuilder: content,
                placeholderBuilder: placeholder
            )
        }
    }
}

// MARK: - Init 3: Full Phase Control

extension MCPAppView {

    public init(
        session: MCPAppSession,
        @ViewBuilder phase phaseBuilder: @escaping (MCPAppPhase) -> Content
    ) {
        self.session = session
        self.contentBuilder = phaseBuilder
    }
}

// MARK: - Default Content

public struct DefaultMCPAppContent: View {
    let phase: MCPAppPhase
    let session: MCPAppSession

    public var body: some View {
        switch phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(session.toolName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

        case .active(let content):
            content

        case .completed(let content, _):
            content

        case .failed(let error):
            MCPAppErrorView(error: error) { session.retry() }

        case .cancelled:
            MCPAppCancelledView()
        }
    }
}

// MARK: - Conditional Content

public struct _MCPAppConditionalContent<C: View, P: View>: View {
    let phase: MCPAppPhase
    let session: MCPAppSession
    let contentBuilder: (MCPAppContent) -> C
    let placeholderBuilder: () -> P

    public var body: some View {
        switch phase {
        case .loading:
            placeholderBuilder()
        case .active(let content):
            contentBuilder(content)
        case .completed(let content, _):
            contentBuilder(content)
        case .failed(let error):
            MCPAppErrorView(error: error) { session.retry() }
        case .cancelled:
            MCPAppCancelledView()
        }
    }
}
