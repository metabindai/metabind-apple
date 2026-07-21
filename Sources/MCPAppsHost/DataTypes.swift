import Foundation

// MARK: - Tool Result

/// The result of executing an MCP tool.
public struct ToolResult: Sendable, Codable, Hashable {
    public let content: [ContentBlock]
    public let isError: Bool

    public init(content: [ContentBlock], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    /// Convenience: create a text-only result.
    public init(text: String, isError: Bool = false) {
        self.content = [.text(text)]
        self.isError = isError
    }
}

// MARK: - Content Block

/// A block of content in a tool result or message.
public enum ContentBlock: Sendable, Hashable {
    case text(String)
    case image(Data, mimeType: String)
    case resource(uri: String, mimeType: String, text: String?)
}

extension ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, uri
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            let data = try container.decode(Data.self, forKey: .data)
            self = .image(data, mimeType: try container.decode(String.self, forKey: .mimeType))
        case "resource":
            let uri = try container.decode(String.self, forKey: .uri)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .resource(uri: uri, mimeType: mimeType, text: try container.decodeIfPresent(String.self, forKey: .text))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content block type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resource(let uri, let mimeType, let text):
            try container.encode("resource", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encode(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(text, forKey: .text)
        }
    }
}

// MARK: - Resource Content

/// Raw content fetched from a ui:// resource.
public struct ResourceContent: Sendable {
    public let uri: String
    public let mimeType: String
    public let text: String?
    public let blob: Data?

    public init(uri: String, mimeType: String, text: String? = nil, blob: Data? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
    }
}

// MARK: - Tool Message

/// A message the rendered view wants to inject into the conversation.
public struct ToolMessage: Sendable {
    public let role: Role
    public let content: [ContentBlock]

    public enum Role: String, Sendable {
        case user
    }

    public init(role: Role, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }
}

// MARK: - Model Context

/// Context the rendered view wants to provide to the model for future turns.
public struct ModelContext: Sendable {
    public let content: [ContentBlock]?
    public let structuredContent: JSONValue?

    public init(content: [ContentBlock]? = nil, structuredContent: JSONValue? = nil) {
        self.content = content
        self.structuredContent = structuredContent
    }
}
