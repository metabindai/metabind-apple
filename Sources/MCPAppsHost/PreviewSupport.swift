import SwiftUI
import BindJS

// MARK: - Mock Server for Previews & Testing

/// A mock MCP server that returns canned responses.
/// Use in previews and tests — no network needed.
public struct MockMCPServer: MCPServer {
    let toolHandler: @Sendable (String, JSONValue) async throws -> ToolResult
    let resourceHandler: @Sendable (String) async throws -> ResourceContent

    public init(
        toolHandler: @escaping @Sendable (String, JSONValue) async throws -> ToolResult = { _, _ in
            ToolResult(text: "Mock result")
        },
        resourceHandler: @escaping @Sendable (String) async throws -> ResourceContent = { uri in
            ResourceContent(uri: uri, mimeType: "application/json", text: MockMCPServer.sampleBindJSResource)
        }
    ) {
        self.toolHandler = toolHandler
        self.resourceHandler = resourceHandler
    }

    public func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
        try await toolHandler(name, arguments)
    }

    public func readResource(uri: String) async throws -> ResourceContent {
        try await resourceHandler(uri)
    }

    /// A simple BindJS component that renders a card with tool info.
    public static let sampleBindJSResource: String = {
        let bundle = BindJSBundle(
            content: """
            const body = (props) => {
                const env = useEnvironment()
                const [count, setCount] = useState(0)

                return (
                    VStack({ spacing: 16 }, [
                        Text("MCP App")
                            .font("title2")
                            .fontWeight("bold"),
                        Text("Tool: " + (env.toolName ?? "unknown"))
                            .font("subheadline")
                            .foregroundStyle("secondary"),
                        Text("Tapped " + count + " times")
                            .font("body"),
                        Button("Tap me", () => setCount(count + 1))
                    ])
                    .padding(24)
                    .frame({ maxWidth: Infinity })
                )
            }
            """,
            package: (version: "1.0.0", components: [:])
        )
        return (try? String(data: JSONEncoder().encode(bundle), encoding: .utf8)) ?? "{}"
    }()
}

// MARK: - Preview Helpers

/// Create a tool call + session for previews in one call.
public extension MCPAppSession {
    /// Create a live session with a mock server for previews.
    /// Actually fetches the mock resource and renders it.
    static func livePreview(
        toolName: String = "get_weather",
        arguments: JSONValue = ["location": "San Francisco"],
        server: some MCPServer = MockMCPServer()
    ) -> MCPAppSession {
        let call = SimpleMCPToolCall(
            id: UUID().uuidString,
            name: toolName,
            arguments: arguments,
            toolDefinition: MCPToolDefinition(
                name: toolName,
                ui: .init(resourceUri: "ui://preview/\(toolName)")
            )
        )
        return MCPAppSession(toolCall: call, server: server)
    }
}

// MARK: - Previews

#Preview("Automatic") {
    ScrollView {
        MCPAppView(session: .livePreview())
            .padding()
    }
}

#Preview("Content + Placeholder") {
    ScrollView {
        MCPAppView(session: .livePreview()) { content in
            content
                .clipShape(.rect(cornerRadius: 16))
                .shadow(radius: 4)
        } placeholder: {
            ProgressView("Loading tool UI...")
        }
        .padding()
    }
}

#Preview("Full Phase Control") {
    ScrollView {
        MCPAppView(session: .livePreview()) { phase in
            switch phase {
            case .loading:
                VStack {
                    ProgressView()
                    Text("Fetching UI...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()

            case .active(let content):
                content
                    .background(.fill.tertiary)
                    .clipShape(.rect(cornerRadius: 12))

            case .completed(let content, _):
                content
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(8)
                    }

            case .failed(let error):
                Text(error.localizedDescription)
                    .foregroundStyle(.red)

            case .cancelled:
                Text("Cancelled")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview("Static Phases") {
    VStack(spacing: 20) {
        MCPAppView(session: .preview(phase: .loading))
        MCPAppView(session: .preview(phase: .failed(.cancelled)))
        MCPAppView(session: .preview(phase: .cancelled))
    }
    .padding()
}
