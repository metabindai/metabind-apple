import Foundation
import CryptoKit
import BindJS
import os

private let viewLog = Logger(subsystem: "MCPAppsHost", category: "BindJSViewResolver")

/// Resolves the BindJS 1.0 View channel's referenced package representation.
/// HTTP freshness belongs to URLSession/URLCache; the digest cache only saves decoding.
public struct BindJSViewResolver: ContentResolver, Sendable {
    private let urlSession: URLSession

    /// Supply a session to customize package transport. MCP authorization headers
    /// are never copied to the CDN. The default uses a shared, dedicated HTTP cache.
    public init() { self.urlSession = PackageHTTPTransport.session }

    public init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    public var supportedMimeTypes: [String] { ["application/bindjs+json;version=1.0"] }

    public func canResolve(mimeType: String) -> Bool {
        Self.baseType(mimeType) == "application/bindjs+json"
    }

    static func isPackage(mimeType: String) -> Bool {
        baseType(mimeType) == "application/bindjs-package+json"
    }

    private static func baseType(_ mimeType: String) -> String {
        mimeType.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    public func resolve(_ resource: ResourceContent) async throws -> ResolvedAppContent {
        throw BindJSViewError.invalidDocument("A referenced View needs an MCP server")
    }

    public func resolve(_ resource: ResourceContent, server: any MCPServer) async throws -> ResolvedAppContent {
        guard let text = resource.text else { throw ContentResolverError.noTextContent }
        let document = try JSONDecoder().decode(ViewDocument.self, from: Data(text.utf8))
        try requireSupportedSpec(document.spec)
        // The deployed View channel references packages. Never silently ignore
        // inline code or props when processing this representation.
        guard !document.hasInlinePackage, !document.hasProps else {
            throw BindJSViewError.invalidDocument("Expected a referenced View without package or props")
        }

        let listings = try await server.listResources()
        let viewMeta = try metadata(resource.meta?["ui"]?["bindjs"] != nil ? resource.meta : listings.first { $0.uri == resource.uri }?.meta)
        try requireSupportedSpec(viewMeta.spec)
        guard viewMeta.spec == document.spec, viewMeta.component == document.component,
              let packageURI = viewMeta.package, URL(string: packageURI)?.scheme == "ui" else {
            throw BindJSViewError.invalidDocument("View metadata disagrees with its document or lacks a package URI")
        }
        let listing = listings.first { $0.uri == packageURI }
        if let mimeType = listing?.mimeType, !Self.isPackage(mimeType: mimeType) {
            throw BindJSViewError.invalidDocument("The referenced resource is not a package")
        }
        let listedMeta = try listing?.meta.map { try metadata($0) }
        if let listedMeta { try validatePackageMetadata(listedMeta) }

        var bytes: Data?
        var mayCacheDecoded = true
        var packageMeta = listedMeta
        if let contentURL = listedMeta?.contentUrl {
            guard let url = URL(string: contentURL), url.scheme?.lowercased() == "https", url.host != nil else {
                throw BindJSViewError.invalidDocument("Package contentUrl must be HTTPS")
            }
            // An alternate URL is only usable when both integrity fields exist.
            guard (viewMeta.sha256 ?? listedMeta?.sha256) != nil,
                  (viewMeta.size ?? listedMeta?.size) != nil else {
                throw BindJSViewError.invalidDocument("A CDN package requires sha256 and size")
            }
            do {
                let response = try await PackageHTTPTransport.fetch(url, session: urlSession)
                guard response.response.url?.scheme?.lowercased() == "https" else {
                    throw BindJSViewError.invalidDocument("Package redirect must remain HTTPS")
                }
                bytes = response.data
                mayCacheDecoded = response.mayCacheDecoded
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                viewLog.warning("Package download failed; reading its MCP resource")
            }
        }
        if bytes == nil {
            let packageResource = try await server.readResource(uri: packageURI)
            try Task.checkCancellation()
            guard Self.isPackage(mimeType: packageResource.mimeType) else {
                throw BindJSViewError.invalidDocument("Expected a BindJS package resource")
            }
            packageMeta = try metadata(packageResource.meta?["ui"]?["bindjs"] != nil ? packageResource.meta : listing?.meta)
            try validatePackageMetadata(packageMeta!)
            // Use exactly the UTF-8 text bytes served; never reserialize JSON before hashing.
            bytes = packageResource.text.map { Data($0.utf8) } ?? packageResource.blob
        }
        guard let bytes else { throw ContentResolverError.noTextContent }
        try Task.checkCancellation()
        guard (viewMeta.sha256 ?? packageMeta?.sha256) != nil,
              (viewMeta.size ?? packageMeta?.size) != nil else {
            throw BindJSViewError.invalidDocument("A referenced package requires sha256 and size")
        }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try verify(bytes: bytes, digest: digest, metadata: viewMeta)
        if let packageMeta { try verify(bytes: bytes, digest: digest, metadata: packageMeta) }

        // Always fetch/revalidate and verify before consulting this cache.
        // A no-store response also removes any previous decoded copy.
        if !mayCacheDecoded { VerifiedPackageCache.shared.remove(digest) }
        let package: PackageDocument
        if mayCacheDecoded, let cached = VerifiedPackageCache.shared.get(digest) {
            package = cached
        } else {
            package = try JSONDecoder().decode(PackageDocument.self, from: bytes)
            try requireSupportedSpec(package.spec)
            guard package.dependencies?.isEmpty != false else {
                throw BindJSViewError.invalidDocument("Package dependencies are not supported by this host")
            }
            guard package.components.keys.allSatisfy({
                $0.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil
            }) else {
                throw BindJSViewError.invalidDocument("Package component names must be JavaScript identifiers")
            }
            guard !package.name.isEmpty, !package.version.isEmpty else {
                throw BindJSViewError.invalidDocument("Package identity is missing")
            }
            if mayCacheDecoded { VerifiedPackageCache.shared.set(digest, package: package) }
        }
        guard package.spec == document.spec,
              packageMeta?.name == nil || packageMeta?.name == package.name,
              packageMeta?.version == nil || packageMeta?.version == package.version,
              packageMeta?.spec == nil || packageMeta?.spec == package.spec,
              let source = package.components[document.component], !source.isEmpty else {
            throw BindJSViewError.invalidDocument("Package identity or entry component does not match the View")
        }
        var components = package.components
        components.removeValue(forKey: document.component)
        return .bindJS(ResolvedContent(compiled: source,
                                      package: PackageComponents(version: package.version, components: components)))
    }
}

enum BindJSViewError: Error, Sendable, Equatable {
    case invalidDocument(String)
    case integrityMismatch
}

private struct ViewDocument: Decodable {
    let spec: String
    let component: String
    let hasInlinePackage: Bool
    let hasProps: Bool
    enum CodingKeys: String, CodingKey { case spec, component, package, props }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spec = try c.decode(String.self, forKey: .spec)
        component = try c.decode(String.self, forKey: .component)
        hasInlinePackage = c.contains(.package)
        hasProps = c.contains(.props)
    }
}

private struct BindJSMetadata: Decodable {
    let spec: String
    let component: String?
    let package: String?
    let sha256: String?
    let size: Int?
    let name: String?
    let version: String?
    let contentUrl: String?
}

private func metadata(_ meta: JSONValue?) throws -> BindJSMetadata {
    guard let bindjs = meta?["ui"]?["bindjs"] else {
        throw BindJSViewError.invalidDocument("Missing _meta.ui.bindjs")
    }
    return try JSONDecoder().decode(BindJSMetadata.self, from: JSONEncoder().encode(bindjs))
}

private func requireSupportedSpec(_ spec: String) throws {
    guard spec == "1.0" else {
        throw BindJSViewError.invalidDocument("Unsupported BindJS specification: \(spec)")
    }
}

private func validatePackageMetadata(_ meta: BindJSMetadata) throws {
    try requireSupportedSpec(meta.spec)
    guard let name = meta.name, !name.isEmpty, let version = meta.version, !version.isEmpty else {
        throw BindJSViewError.invalidDocument("Package metadata lacks name or version")
    }
}

private func verify(bytes: Data, digest: String, metadata: BindJSMetadata) throws {
    if let size = metadata.size, size < 0 || size != bytes.count {
        throw BindJSViewError.integrityMismatch
    }
    if let expected = metadata.sha256 {
        guard expected.count == 64, expected.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              expected.lowercased() == digest else { throw BindJSViewError.integrityMismatch }
    }
}

struct PackageDocument: Decodable, Sendable {
    let name: String
    let version: String
    let spec: String
    let components: [String: String]
    let dependencies: [JSONValue]?
}

/// Kept separate from the resolver so real HTTP cache behavior can be tested.
enum PackageHTTPTransport {
    /// Shared across resolver instances, without altering URLCache.shared or MCP sessions.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024,
                                   diskCapacity: 128 * 1024 * 1024,
                                   directory: nil)
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: HTTPSPackageRedirectDelegate(), delegateQueue: nil)
    }()

    static func fetch(_ url: URL, session: URLSession) async throws -> (data: Data, response: HTTPURLResponse, mayCacheDecoded: Bool) {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy)
        request.setValue("application/bindjs-package+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BindJSViewError.invalidDocument("Package GET did not return HTTP 200")
        }
        let directives = (http.value(forHTTPHeaderField: "Cache-Control") ?? "")
            .lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (data, http, !directives.contains("no-store"))
    }
}

private final class HTTPSPackageRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}

/// Bounded, in-memory parse cache. Never used to decide whether to fetch a URL.
final class VerifiedPackageCache: @unchecked Sendable {
    static let shared = VerifiedPackageCache()
    private var entries = OrderedCache<String, PackageDocument>(maxEntries: 50)
    private let lock = NSLock()
    func get(_ digest: String) -> PackageDocument? {
        lock.lock(); defer { lock.unlock() }
        return entries.get(digest)
    }
    func set(_ digest: String, package: PackageDocument) {
        lock.lock(); defer { lock.unlock() }
        entries.set(digest, package)
    }
    func remove(_ digest: String) {
        lock.lock(); defer { lock.unlock() }
        entries.remove(digest)
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }
}
