import SwiftUI
import BindJS

// MARK: - Event Modifiers

public extension View {

    /// Tool execution completed.
    func onToolCompleted(_ handler: @escaping (ToolResult) -> Void) -> some View {
        self.environment(\.mcpOnToolCompleted, handler)
    }

    /// The rendered view sent a message to inject into the conversation.
    func onToolMessage(_ handler: @escaping (ToolMessage) -> Void) -> some View {
        self.environment(\.mcpOnToolMessage, handler)
    }

    /// The rendered view updated context for future model turns.
    func onModelContextUpdate(_ handler: @escaping (ModelContext) -> Void) -> some View {
        self.environment(\.mcpOnModelContextUpdate, handler)
    }

    /// The rendered view requested a display mode change.
    /// Return the mode you actually granted.
    func onDisplayModeRequest(
        _ handler: @escaping (MCPAppSession.DisplayMode) -> MCPAppSession.DisplayMode
    ) -> some View {
        self.environment(\.mcpOnDisplayModeRequest, handler)
    }
}

// MARK: - Server Environment

public extension View {

    /// Set the default MCP server for MCPAppView(toolCall:) convenience init.
    /// Like .modelContainer() — set once at app/scene level.
    func mcpServer(_ server: some MCPServer) -> some View {
        self.environment(\.mcpServer, server)
    }

    /// Provide the MCP host bridge that BindJS components use via
    /// `useMCPHost()`. Typically set once at app/scene level by a host
    /// container (e.g. `MetabindAssistantView`) and inherited by any
    /// `MCPAppView` below it.
    ///
    /// Apps using `MCPAppView` standalone (without `MetabindAssistantView`)
    /// can construct a bridge directly and inject it with this modifier.
    func mcpHostBridge(_ bridge: any MCPHostBridge) -> some View {
        self.environment(\.mcpHostBridge, bridge)
    }
}

// MARK: - Environment Keys

public extension EnvironmentValues {
    @Entry var mcpServer: (any MCPServer)? = nil
    @Entry var mcpOnToolCompleted: ((ToolResult) -> Void)? = nil
    @Entry var mcpOnToolMessage: ((ToolMessage) -> Void)? = nil
    @Entry var mcpOnModelContextUpdate: ((ModelContext) -> Void)? = nil
    @Entry var mcpOnDisplayModeRequest: ((MCPAppSession.DisplayMode) -> MCPAppSession.DisplayMode)? = nil
    @Entry var mcpHostBridge: (any MCPHostBridge)? = nil
}
