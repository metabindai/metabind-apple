import Foundation

/// Conform your existing tool call type. Identifiable for ForEach.
public protocol MCPToolCall: Identifiable where ID == String {
    var id: String { get }
    var name: String { get }
    var arguments: JSONValue { get }
    var toolDefinition: MCPToolDefinition? { get }
}

// MARK: - Tool Definition

/// Metadata about an MCP tool, including optional UI information.
public struct MCPToolDefinition: Sendable, Codable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONValue?
    public let ui: UIMetadata?

    public init(
        name: String,
        description: String? = nil,
        inputSchema: JSONValue? = nil,
        ui: UIMetadata? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.ui = ui
    }

    /// UI metadata from the tool's _meta.ui field.
    public struct UIMetadata: Sendable, Codable {
        public let resourceUri: String
        public let visibility: Set<Visibility>

        public init(resourceUri: String, visibility: Set<Visibility> = [.model, .app]) {
            self.resourceUri = resourceUri
            self.visibility = visibility
        }

        public enum Visibility: String, Sendable, Codable {
            case model
            case app
        }
    }

    /// Extract UI metadata from a raw MCP _meta dictionary.
    public static func uiMetadata(from meta: JSONValue?) -> UIMetadata? {
        guard let ui = meta?["ui"],
              let resourceUri = ui["resourceUri"]?.stringValue else {
            return nil
        }
        var visibility: Set<UIMetadata.Visibility> = [.model, .app]
        if let visArray = ui["visibility"]?.arrayValue {
            visibility = Set(visArray.compactMap { $0.stringValue.flatMap(UIMetadata.Visibility.init) })
        }
        return UIMetadata(resourceUri: resourceUri, visibility: visibility)
    }
}

// MARK: - Concrete Tool Call

/// A simple concrete implementation of MCPToolCall for convenience.
/// Use this if you don't have your own tool call type.
public struct SimpleMCPToolCall: MCPToolCall {
    public let id: String
    public let name: String
    public let arguments: JSONValue
    public let toolDefinition: MCPToolDefinition?

    public init(
        id: String,
        name: String,
        arguments: JSONValue = .object([:]),
        toolDefinition: MCPToolDefinition? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.toolDefinition = toolDefinition
    }
}
