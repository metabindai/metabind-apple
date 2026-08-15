import Foundation
import Testing
@testable import MCPAppsHost

private let liveE2EURL = ProcessInfo.processInfo.environment["METABIND_MCP_E2E_URL"]

/// Cross-process coverage for the real Metabind MCP HTTP handler.
///
/// The server-side integration test starts that handler on a loopback port and
/// sets `METABIND_MCP_E2E_URL` before invoking this suite. Keeping the network
/// test opt-in avoids making ordinary package tests depend on a sibling repo.
@Suite(
    "MCPAppsClient live MCP 2026-07-28 E2E",
    .serialized,
    .enabled(if: liveE2EURL != nil, "Run from metabind-mcp's Swift SDK integration test")
)
struct MCPAppsClientLiveE2ETests {
    @Test("negotiates modern transport and reads native UI content")
    func negotiatesModernTransportAndReadsNativeUIContent() async throws {
        let urlString = try #require(liveE2EURL)
        let url = try #require(URL(string: urlString))
        let client = MCPAppsClient(
            url: url,
            configuration: .init(maxRetries: 0)
        )

        let tools = try await client.listTools()
        let tool = try #require(tools.first { $0.name == "render_e2e_世界" })
        let resourceURI = try #require(tool.ui?.resourceUri)

        let result = try await client.callTool(
            name: tool.name,
            arguments: .object(["region": .string("southwest")])
        )
        #expect(result.isError == false)
        #expect(result.content == [.text(#"{"rendered":true,"region":"southwest"}"#)])

        let resource = try await client.readResource(uri: resourceURI)
        #expect(resource.mimeType == "application/vnd.bindjs+json")
        #expect(resource.text == #"{"packageVersion":"e2e"}"#)
    }
}
