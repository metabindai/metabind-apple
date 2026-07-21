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
public enum ResolvedAppContent: Sendable {
    case bindJS(ResolvedContent)
    case html(String)
}

// MARK: - BindJS Resolver

/// Resolves BindJS content into native SwiftUI views via bindjs-apple.
///
/// Caches the package components after the first decode. Subsequent resources
/// with the same package version skip the expensive full parse and only
/// extract the layout component name.
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

        // Fast path: if we've already decoded this package version, resolve
        // by looking up the layout component in the cached dict.
        if let cached = BindJSPackageCache.shared.resolve(text: text) {
            return .bindJS(cached)
        }

        // Full decode (first time for this package version)
        let bundle = try JSONDecoder().decode(BindJSBundle.self, from: Data(text.utf8))
        if let layoutName = bundle.layoutComponentName {
            BindJSPackageCache.shared.store(layoutName: layoutName, content: bundle.resolvedContent)
        }
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

// MARK: - Package Cache

/// Caches the full component dictionary from the server's BindJS package.
/// The server sends all ~26 components with every resource read; only
/// `layoutComponentName` changes. After one full JSON decode, subsequent
/// resources resolve by dictionary lookup instead of re-parsing ~40KB.
///
/// Cache entries expire after `ttl` seconds (default 5 minutes).
final class BindJSPackageCache: @unchecked Sendable {
    static let shared = BindJSPackageCache()

    private var cachedVersion: String?
    private var allComponents: [String: String] = [:]
    private var cachedAt: Date = .distantPast
    private let lock = NSLock()

    /// Time-to-live for cached packages. After this duration, the next
    /// resolve triggers a full re-decode to pick up server-side updates.
    var ttl: TimeInterval = 300 // 5 minutes

    /// Lightweight struct for extracting just the two top-level keys without parsing
    /// the full ~40KB `package.compiled.components` blob.
    private struct Header: Decodable {
        let layoutComponentName: String
        let packageVersion: String
    }

    /// Try to resolve from the cached package. Returns nil on miss or expiry.
    func resolve(text: String) -> ResolvedContent? {
        guard let header = try? JSONDecoder().decode(Header.self, from: Data(text.utf8)) else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        // Check version match AND TTL
        guard header.packageVersion == cachedVersion,
              !allComponents.isEmpty,
              Date().timeIntervalSince(cachedAt) < ttl else {
            return nil
        }

        let compiled = allComponents[header.layoutComponentName] ?? ""
        let components = allComponents.filter { $0.key != header.layoutComponentName }

        return ResolvedContent(
            compiled: compiled,
            package: PackageComponents(version: header.packageVersion, components: components)
        )
    }

    /// Store the full component set after a decode.
    func store(layoutName: String, content: ResolvedContent) {
        lock.lock()
        defer { lock.unlock() }

        cachedVersion = content.package.version
        allComponents = content.package.components
        allComponents[layoutName] = content.compiled
        cachedAt = Date()
    }

    /// Explicitly invalidate the cache.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }

        cachedVersion = nil
        allComponents.removeAll()
        cachedAt = .distantPast
    }
}
