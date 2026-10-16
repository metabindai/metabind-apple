import Foundation
import BindJS
import Testing
@testable import MCPAppsHost

/// Opt-in, read-only deployment check. Supply MCP_APPS_TEST_URL and optionally
/// MCP_APPS_TEST_TOKEN_FILE (a UTF-8 bearer token file). No tools/call is issued.
@Suite("Live MCP package rendering")
struct LiveBindJSViewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MCP_APPS_TEST_URL"] != nil))
    @MainActor func resolvesAndBuildsNativeView() async throws {
        let env = ProcessInfo.processInfo.environment
        let url = try #require(env["MCP_APPS_TEST_URL"].flatMap(URL.init(string:)))
        var headers: [String: String] = [:]
        if let path = env["MCP_APPS_TEST_TOKEN_FILE"] {
            let token = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            headers["Authorization"] = "Bearer \(token)"
        }
        let client = MCPAppsClient(url: url, headers: headers)
        let resources = try await client.listResources()
        let expectedType = env["MCP_APPS_TEST_MIME"] ?? "application/bindjs+json"
        let listing = try #require(resources.first { $0.mimeType == expectedType })
        let resource = try await client.readResource(uri: listing.uri)
        let resolver = try #require(defaultResolvers.first { $0.canResolve(mimeType: resource.mimeType) })
        let result = try await resolver.resolve(resource, server: client)
        guard case .bindJS(let content) = result else { Issue.record("Expected native View content"); return }
        let context = BindJSContext()
        for (name, source) in content.package.components { context.register(name: name, source: source) }
        context.register(name: "_body", source: content.compiled)
        #expect(context.componentForName("_body", arguments: [:]) != nil)
        #expect(context.viewForName("_body", arguments: [:]) != nil)

        // Exercise the real server's separately negotiated fallback representation.
        let html = try await client.readHTMLResource(uri: listing.uri)
        #expect(HTMLResolver().canResolve(mimeType: html.mimeType))
        #expect(html.text?.isEmpty == false)
    }
}
