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
    case audio(Data, mimeType: String)
    case resource(uri: String, mimeType: String, text: String?)
    case resourceBlob(uri: String, mimeType: String, blob: Data)
    case resourceLink(
        name: String,
        title: String?,
        uri: String,
        description: String?,
        mimeType: String?,
        size: Double?
    )
}

extension ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, uri, blob, resource
        case name, title, description, size
    }

    private struct EmbeddedResourceContents: Codable {
        let uri: String
        let mimeType: String?
        let text: String?
        let blob: Data?
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
        case "audio":
            let data = try container.decode(Data.self, forKey: .data)
            self = .audio(data, mimeType: try container.decode(String.self, forKey: .mimeType))
        case "resource":
            if let resource = try container.decodeIfPresent(EmbeddedResourceContents.self, forKey: .resource) {
                let mimeType = resource.mimeType ?? "application/octet-stream"
                if let text = resource.text {
                    self = .resource(uri: resource.uri, mimeType: mimeType, text: text)
                } else if let blob = resource.blob {
                    self = .resourceBlob(uri: resource.uri, mimeType: mimeType, blob: blob)
                } else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .resource,
                        in: container,
                        debugDescription: "Embedded resource must contain text or blob"
                    )
                }
            } else {
                // Keep accepting the flattened shape emitted by older MCP Apps servers.
                let uri = try container.decode(String.self, forKey: .uri)
                let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
                    ?? "application/octet-stream"
                if let text = try container.decodeIfPresent(String.self, forKey: .text) {
                    self = .resource(uri: uri, mimeType: mimeType, text: text)
                } else if let blob = try container.decodeIfPresent(Data.self, forKey: .blob) {
                    self = .resourceBlob(uri: uri, mimeType: mimeType, blob: blob)
                } else {
                    self = .resource(uri: uri, mimeType: mimeType, text: nil)
                }
            }
        case "resource_link":
            self = .resourceLink(
                name: try container.decode(String.self, forKey: .name),
                title: try container.decodeIfPresent(String.self, forKey: .title),
                uri: try container.decode(String.self, forKey: .uri),
                description: try container.decodeIfPresent(String.self, forKey: .description),
                mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType),
                size: try container.decodeIfPresent(Double.self, forKey: .size)
            )
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
        case .audio(let data, let mimeType):
            try container.encode("audio", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resource(let uri, let mimeType, let text):
            try container.encode("resource", forKey: .type)
            try container.encode(
                EmbeddedResourceContents(uri: uri, mimeType: mimeType, text: text, blob: nil),
                forKey: .resource
            )
        case .resourceBlob(let uri, let mimeType, let blob):
            try container.encode("resource", forKey: .type)
            try container.encode(
                EmbeddedResourceContents(uri: uri, mimeType: mimeType, text: nil, blob: blob),
                forKey: .resource
            )
        case .resourceLink(let name, let title, let uri, let description, let mimeType, let size):
            try container.encode("resource_link", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(size, forKey: .size)
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
