import Foundation
import CryptoKit
import BindJS
import Testing
@testable import MCPAppsHost

private let cardSource = "exports.default = defineComponent({ properties: {}, body: () => Text('Verified café') });"
private let packageText = """
{"name":"com.test.cards","version":"1.0.0","spec":"1.0","components":{"Card":"\(cardSource)","Other":"other source"}}
"""
private let packageURI = "ui://test/package/1"
private let viewURI = "ui://test/card"
private var packageDigest: String { SHA256.hash(data: Data(packageText.utf8)).map { String(format: "%02x", $0) }.joined() }

private func meta(_ fields: [String: JSONValue]) -> JSONValue { ["ui": ["bindjs": .object(fields)]] }
private func packageMetadata(url: String? = nil) -> JSONValue {
    var fields: [String: JSONValue] = ["spec": "1.0", "name": "com.test.cards", "version": "1.0.0",
                                      "sha256": .string(packageDigest), "size": .number(Double(packageText.utf8.count))]
    if let url { fields["contentUrl"] = .string(url) }
    return meta(fields)
}
private func viewMetadata(digest: String = packageDigest, size: Int = packageText.utf8.count) -> JSONValue {
    meta(["spec": "1.0", "component": "Card", "package": .string(packageURI),
          "sha256": .string(digest), "size": .number(Double(size))])
}
private func viewResource(metadata: JSONValue? = viewMetadata(), text: String = #"{"spec":"1.0","component":"Card"}"#) -> ResourceContent {
    ResourceContent(uri: viewURI, mimeType: "application/bindjs+json", text: text, meta: metadata)
}

private actor ViewServer: MCPServer {
    let view: ResourceContent
    let listings: [MCPResource]
    let package: ResourceContent
    var packageReads = 0
    var htmlReads = 0
    init(view: ResourceContent = viewResource(), package: ResourceContent? = nil, url: String? = nil,
         listedViewMeta: JSONValue? = nil) {
        self.view = view
        self.package = package ?? ResourceContent(uri: packageURI, mimeType: "application/bindjs-package+json",
                                                  text: packageText, meta: packageMetadata())
        self.listings = [MCPResource(uri: viewURI, meta: listedViewMeta ?? viewMetadata()),
                         MCPResource(uri: packageURI, mimeType: "application/bindjs-package+json", meta: packageMetadata(url: url))]
    }
    func listResources() async throws -> [MCPResource] { listings }
    func readResource(uri: String) async throws -> ResourceContent {
        if uri == packageURI { packageReads += 1; return package }
        return view
    }
    func readHTMLResource(uri: String) async throws -> ResourceContent {
        htmlReads += 1
        return ResourceContent(uri: uri, mimeType: "text/html;profile=mcp-app", text: "<p>fallback</p>")
    }
    func callTool(name: String, arguments: JSONValue) async throws -> ToolResult { ToolResult(text: "ok") }
}

private final class PackageProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest) -> (Int, String, Data)] = [:]
    static func session(url: URL, handler: @escaping @Sendable (URLRequest) -> (Int, String, Data)) -> URLSession {
        lock.lock(); handlers[url.host!] = handler; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PackageProtocol.self]
        return URLSession(configuration: config)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let handler = Self.handlers[request.url!.host!]; Self.lock.unlock()
        let (status, cacheControl, data) = handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Cache-Control": cacheControl])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}

@Suite("BindJS View channel", .serialized)
struct BindJSViewTests {
    @Test func resolvesReferencedPackageAndPreservesExactComponentNames() async throws {
        let server = ViewServer()
        let result = try await BindJSViewResolver().resolve(viewResource(), server: server)
        guard case .bindJS(let content) = result else { Issue.record("Expected BindJS"); return }
        #expect(content.compiled == cardSource)
        #expect(content.package.components == ["Other": "other source"])
        #expect(await server.packageReads == 1)
    }

    @Test @MainActor func verifiedPackageBuildsANativeViewTree() async throws {
        let result = try await BindJSViewResolver().resolve(viewResource(), server: ViewServer())
        guard case .bindJS(let content) = result else { Issue.record("Expected BindJS"); return }
        let context = BindJSContext()
        context.register(name: "_body", source: content.compiled)
        #expect(context.componentForName("_body") != nil)
        #expect(context.viewForName("_body") != nil)
    }

    @Test func listingMetadataIsUsedWhenContentOmitsIt() async throws {
        let server = ViewServer()
        _ = try await BindJSViewResolver().resolve(viewResource(metadata: nil), server: server)
    }

    @Test func contentMetadataWinsAndMismatchIsRejected() async throws {
        let server = ViewServer(listedViewMeta: viewMetadata())
        await #expect(throws: BindJSViewError.integrityMismatch) {
            try await BindJSViewResolver().resolve(viewResource(metadata: viewMetadata(digest: String(repeating: "0", count: 64))), server: server)
        }
        await #expect(throws: BindJSViewError.integrityMismatch) {
            try await BindJSViewResolver().resolve(viewResource(metadata: viewMetadata(size: 1)), server: server)
        }
    }

    @Test func cdnUsesHTTPPolicyAndNeverSkipsFetchBecauseDigestWasDecoded() async throws {
        let url = URL(string: "https://\(UUID().uuidString).test/package")!
        let counter = Counter()
        let session = PackageProtocol.session(url: url) { request in
            #expect(request.cachePolicy == .useProtocolCachePolicy)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Mcp-Session-Id") == nil)
            let count = counter.increment()
            // Even with a warm digest cache, changed bytes must be checked.
            return (200, "no-cache", Data((count == 1 ? packageText : packageText + " ").utf8))
        }
        defer { session.invalidateAndCancel() }
        let resolver = BindJSViewResolver(urlSession: session)
        let server = ViewServer(url: url.absoluteString)
        _ = try await resolver.resolve(viewResource(), server: server)
        await #expect(throws: BindJSViewError.integrityMismatch) {
            try await resolver.resolve(viewResource(), server: server)
        }
        #expect(await server.packageReads == 0)
    }

    @Test func failedCDNReadFallsBackToMCPAndStillVerifies() async throws {
        let url = URL(string: "https://\(UUID().uuidString).test/package")!
        let session = PackageProtocol.session(url: url) { _ in (503, "no-store", Data()) }
        defer { session.invalidateAndCancel() }
        let server = ViewServer(url: url.absoluteString)
        _ = try await BindJSViewResolver(urlSession: session).resolve(viewResource(), server: server)
        #expect(await server.packageReads == 1)
        let bad = ResourceContent(uri: packageURI, mimeType: "application/bindjs-package+json", text: "corrupted", meta: packageMetadata())
        let corruptServer = ViewServer(package: bad, url: url.absoluteString)
        await #expect(throws: BindJSViewError.integrityMismatch) {
            try await BindJSViewResolver(urlSession: session).resolve(viewResource(), server: corruptServer)
        }
    }

    @Test func noStoreDoesNotRetainDecodedSources() async throws {
        let server = ViewServer()
        _ = try await BindJSViewResolver().resolve(viewResource(), server: server)
        #expect(VerifiedPackageCache.shared.get(packageDigest) != nil)
        let url = URL(string: "https://\(UUID().uuidString).test/package")!
        let session = PackageProtocol.session(url: url) { _ in (200, "no-store", Data(packageText.utf8)) }
        defer { session.invalidateAndCancel() }
        _ = try await BindJSViewResolver(urlSession: session).resolve(viewResource(), server: ViewServer(url: url.absoluteString))
        #expect(VerifiedPackageCache.shared.get(packageDigest) == nil)
    }

    @Test func rejectsUnsupportedSpecPropsAndInsecureURL() async {
        let resolver = BindJSViewResolver()
        for text in [#"{"spec":"2.0","component":"Card"}"#,
                     #"{"spec":"1.0","component":"Card","props":{}}"#,
                     #"{"spec":"1.0","component":"Card","package":{}}"#] {
            await #expect(throws: (any Error).self) {
                try await resolver.resolve(viewResource(text: text), server: ViewServer())
            }
        }
        await #expect(throws: (any Error).self) {
            try await resolver.resolve(viewResource(), server: ViewServer(url: "http://insecure.test/package"))
        }
    }

    @Test @MainActor func invalidPackageFallsBackToHTMLWithoutExecutingItsSources() async {
        let server = ViewServer(view: viewResource(metadata: viewMetadata(digest: String(repeating: "0", count: 64))))
        let session = MCPAppSession(id: "view", toolName: "render", resourceUri: viewURI, server: server)
        _ = await session.awaitResult()
        guard case .html(let html) = session.resolvedContent else { Issue.record("Expected HTML"); return }
        #expect(html == "<p>fallback</p>")
        #expect(await server.htmlReads == 1)
    }

    @Test func mimeMatchingDoesNotClaimUnrelatedTypes() {
        let resolver = BindJSViewResolver()
        #expect(resolver.canResolve(mimeType: "application/bindjs+json;version=1.0"))
        #expect(!resolver.canResolve(mimeType: "application/bindjs-package+json"))
        #expect(!resolver.canResolve(mimeType: "application/bindjs+json-unrelated"))
    }
}
