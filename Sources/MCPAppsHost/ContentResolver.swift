import Foundation
import BindJS

/// Turns a fetched ui:// resource into renderable content.
public protocol ContentResolver: Sendable {
    /// MIME types this resolver can handle, advertised to the server during initialization.
    var supportedMimeTypes: [String] { get }
    func canResolve(mimeType: String) -> Bool
    func resolve(_ resource: ResourceContent) async throws -> ResolvedAppContent
}

/// What a ContentResolver produces.
public enum ResolvedAppContent: Sendable, Equatable {
    case bindJS(ResolvedContent)
    case html(String)
}

// MARK: - BindJS Resolver

/// Resolves BindJS content into native SwiftUI views via bindjs-apple.
///
/// Caches decoded resource content by its complete wire representation. Saved
/// drafts and different projects can share version strings without sharing code.
public struct BindJSResolver: ContentResolver, Sendable {
    public init() {}

    public var supportedMimeTypes: [String] { ["application/vnd.bindjs+json"] }

    public func canResolve(mimeType: String) -> Bool {
        mimeType.hasPrefix("application/vnd.bindjs") || mimeType == "application/json"
    }

    public func resolve(_ resource: ResourceContent) async throws -> ResolvedAppContent {
        guard let text = resource.text else {
            throw ContentResolverError.noTextContent
        }

        // Exact content identity prevents draft edits or another project's
        // matching version string from reusing stale component sources.
        if let cached = BindJSPackageCache.shared.resolve(text: text) {
            return .bindJS(cached)
        }

        let bundle = try JSONDecoder().decode(BindJSBundle.self, from: Data(text.utf8))
        BindJSPackageCache.shared.store(text: text, content: bundle.resolvedContent)
        return .bindJS(bundle.resolvedContent)
    }
}

// MARK: - HTML Resolver

/// Resolves HTML content for WKWebView fallback rendering.
public struct HTMLResolver: ContentResolver, Sendable {
    public init() {}

    public var supportedMimeTypes: [String] { ["text/html;profile=mcp-app"] }

    public func canResolve(mimeType: String) -> Bool {
        mimeType.contains("html")
    }

    public func resolve(_ resource: ResourceContent) async throws -> ResolvedAppContent {
        guard let text = resource.text else {
            throw ContentResolverError.noTextContent
        }
        return .html(text)
    }
}

// MARK: - Shared Error

enum ContentResolverError: Error, Sendable {
    case noTextContent
}

// MARK: - BindJS Bundle (wire format)

/// Decodes BindJS content from two wire formats:
///
/// **Server format** (from metabind-mcp readResource):
/// ```json
/// { "layoutComponentName": "Layout", "packageVersion": "1.0.0",
///   "package": { "compiled": { "components": { "Layout": "...", "Card": "..." } } } }
/// ```
///
/// **Simple format** (mocks, previews, tests):
/// ```json
/// { "content": "<JS>", "package": { "version": "1.0.0", "components": {} } }
/// ```
struct BindJSBundle: Sendable {
    let resolvedContent: ResolvedContent
    /// The layout component name from the server format, nil for simple format.
    let layoutComponentName: String?
}

extension BindJSBundle: Decodable {
    private enum CodingKeys: String, CodingKey {
        // Server format
        case layoutComponentName, packageVersion, package
        // Simple format
        case content
    }

    private struct ServerPackage: Decodable {
        let version: String?
        let compiled: CompiledPayload?
        struct CompiledPayload: Decodable {
            let components: [String: String]
        }
    }

    private struct SimplePackage: Decodable {
        let version: String
        let components: [String: String]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let layoutName = try container.decodeIfPresent(String.self, forKey: .layoutComponentName) {
            // Server format
            let version = try container.decodeIfPresent(String.self, forKey: .packageVersion) ?? "1.0.0"
            let pkg = try container.decode(ServerPackage.self, forKey: .package)
            let allComponents = pkg.compiled?.components ?? [:]

            let compiled = allComponents[layoutName] ?? ""
            var components = allComponents
            components.removeValue(forKey: layoutName)

            self.layoutComponentName = layoutName
            self.resolvedContent = ResolvedContent(
                compiled: compiled,
                package: PackageComponents(version: pkg.version ?? version, components: components)
            )
        } else {
            // Simple format
            let compiled = try container.decode(String.self, forKey: .content)
            let pkg = try container.decode(SimplePackage.self, forKey: .package)

            self.layoutComponentName = nil
            self.resolvedContent = ResolvedContent(
                compiled: compiled,
                package: PackageComponents(version: pkg.version, components: pkg.components)
            )
        }
    }
}

extension BindJSBundle: Encodable {
    func encode(to encoder: Encoder) throws {
        // Always encode in simple format (used by MockMCPServer/previews)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resolvedContent.compiled, forKey: .content)

        struct SimplePackage: Encodable {
            let version: String
            let components: [String: String]
        }
        try container.encode(
            SimplePackage(version: resolvedContent.package.version, components: resolvedContent.package.components),
            forKey: .package
        )
    }
}

extension BindJSBundle {
    /// Create a bundle directly (for mocks/previews).
    init(content: String, package: (version: String, components: [String: String])) {
        self.layoutComponentName = nil
        self.resolvedContent = ResolvedContent(
            compiled: content,
            package: PackageComponents(version: package.version, components: package.components)
        )
    }
}

/// Default resolver chain: BindJS first, HTML fallback.
public let defaultResolvers: [any ContentResolver] = [BindJSResolver(), HTMLResolver()]

/// Process-wide caches MCPAppsHost keeps outside any one client.
public enum MCPAppsCaches {
    /// Drops decoded BindJS resources cached across clients.
    ///
    /// Independent of a client's resource cache: that one holds the fetched
    /// bytes, this one holds the parse of them. A debug reset wants both.
    public static func invalidateBindJSPackage() {
        BindJSPackageCache.shared.invalidate()
    }
}

// MARK: - Package Cache

/// A bounded cache keyed by the complete resource text, including its package
/// sources and selected layout. Version labels alone are not content identities:
/// drafts keep their version while changing, and projects can reuse versions.
final class BindJSPackageCache: @unchecked Sendable {
    static let shared = BindJSPackageCache()

    private struct Entry {
        let content: ResolvedContent
        let createdAt: Date
    }
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let lock = NSLock()
    private let maxEntries = 50
    var ttl: TimeInterval = 300

    func resolve(text: String) -> ResolvedContent? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[text] else { return nil }
        guard Date().timeIntervalSince(entry.createdAt) < ttl else {
            entries[text] = nil
            order.removeAll { $0 == text }
            return nil
        }
        order.removeAll { $0 == text }
        order.append(text)
        return entry.content
    }

    func store(text: String, content: ResolvedContent) {
        lock.lock()
        defer { lock.unlock() }
        entries[text] = Entry(content: content, createdAt: Date())
        order.removeAll { $0 == text }
        order.append(text)
        while order.count > maxEntries {
            entries[order.removeFirst()] = nil
        }
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        order.removeAll()
    }
}
