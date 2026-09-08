import Foundation
import Testing
@testable import MCPAppsHost

private actor ReloadServer: MCPServer {
    var text = "<p>original</p>"
    var reads = 0
    var calls = 0
    var fail = false
    var mimeType = "text/html"

    func update(_ text: String, fail: Bool = false, mimeType: String = "text/html") {
        self.text = text
        self.fail = fail
        self.mimeType = mimeType
    }

    func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
        calls += 1
        return ToolResult(text: "original result")
    }

    func readResource(uri: String) async throws -> ResourceContent {
        reads += 1
        if fail { throw URLError(.cannotConnectToHost) }
        return ResourceContent(uri: uri, mimeType: mimeType, text: text)
    }
}

@Suite("Resource-only session reload")
@MainActor
struct ResourceReloadTests {
    @Test func removedComponentsResetOnlyTheCardRuntime() async throws {
        let server = ReloadServer()
        await server.update(#"{"content":"body","package":{"version":"draft","components":{"Keep":"keep","Gone":"gone"}}}"#,
                            mimeType: "application/vnd.bindjs+json")
        let session = MCPAppSession(id: "card", toolName: "save", arguments: ["selection": "keep"],
                                    resourceUri: "ui://card", server: server)
        let result = await session.awaitResult()
        #expect(session.resourceContextRevision == 0)
        await server.update(#"{"content":"edited body","package":{"version":"draft","components":{"Keep":"edited"}}}"#,
                            mimeType: "application/vnd.bindjs+json")
        try await session.reloadResource()
        #expect(session.resourceContextRevision == 1)
        #expect(session.phase.terminalResult == result)
        #expect(session.toolArguments == ["selection": "keep"])
        try await session.reloadResource()
        #expect(session.resourceContextRevision == 1, "An unchanged poll must not reset local state")
        await server.update(#"{"content":"more edits","package":{"version":"draft","components":{"Keep":"changed","Added":"new"}}}"#,
                            mimeType: "application/vnd.bindjs+json")
        try await session.reloadResource()
        #expect(session.resourceContextRevision == 1, "Updates and additions retain the existing runtime")
        #expect(await server.calls == 1)
    }

    @Test func reloadPreservesResultArgumentsAndCompletionWithoutToolReplay() async throws {
        let server = ReloadServer()
        let session = MCPAppSession(
            id: "card", toolName: "save", arguments: ["value": "original"],
            resourceUri: "ui://card", server: server
        )
        var completions = 0
        session.onPhaseTransition = { if case .completed = $0 { completions += 1 } }
        let result = await session.awaitResult()
        session.partialArguments = ["value": "streamed"]
        session.argumentsComplete = true
        session.displayMode = .fullscreen
        await server.update("<p>edited</p>")
        try await session.reloadResource()

        #expect(session.resolvedContent == .html("<p>edited</p>"))
        #expect(session.phase.terminalResult == result)
        #expect(session.toolArguments == ["value": "original"])
        #expect(session.partialArguments == ["value": "streamed"])
        #expect(session.argumentsComplete)
        #expect(session.displayMode == .fullscreen)
        #expect(completions == 1)
        #expect(await server.calls == 1)
        #expect(await server.reads == 2)
        #expect(!session.isReloadingResource)
        #expect(session.resourceReloadError == nil)
    }

    @Test func failedReloadRetainsExistingCardAndResultThenRecovers() async throws {
        let server = ReloadServer()
        let session = MCPAppSession(id: "card", toolName: "save", resourceUri: "ui://card", server: server)
        let result = await session.awaitResult()
        let content = session.resolvedContent
        await server.update("unavailable", fail: true)
        await #expect(throws: URLError.self) { try await session.reloadResource() }
        #expect(session.resolvedContent == content)
        #expect(session.phase.terminalResult == result)
        #expect(session.resourceReloadError != nil)
        #expect(!session.isReloadingResource)
        await server.update("<p>recovered</p>")
        try await session.reloadResource(uri: "ui://updated-card")
        #expect(session.resourceUri == "ui://updated-card")
        #expect(session.resolvedContent == .html("<p>recovered</p>"))
        #expect(session.resourceReloadError == nil)
        #expect(await server.calls == 1)
    }
}
