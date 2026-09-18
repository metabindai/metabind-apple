import Foundation
import Testing
@testable import MetabindAI
@testable import MCPAppsHost

private actor ProjectRefreshServer: MCPServer {
    var revision = 1
    var calls = 0
    var reads = 0
    var failDiscovery = false
    var holdReads = false
    var heldRead: CheckedContinuation<Void, Never>?

    func beginHoldingReads() { holdReads = true }
    var isReadHeld: Bool { heldRead != nil }
    func releaseRead() {
        holdReads = false
        heldRead?.resume()
        heldRead = nil
    }

    func edit(failDiscovery: Bool = false) {
        revision += 1
        self.failDiscovery = failDiscovery
    }

    func listTools() async throws -> [MCPToolDefinition] {
        if failDiscovery { throw URLError(.userAuthenticationRequired) }
        return [MCPToolDefinition(name: "card", ui: .init(resourceUri: "ui://card/\(revision)"))]
    }

    func readResource(uri: String) async throws -> ResourceContent {
        reads += 1
        if holdReads { await withCheckedContinuation { heldRead = $0 } }
        return ResourceContent(uri: uri, mimeType: "text/html", text: "<p>revision \(revision)</p>")
    }

    func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
        calls += 1
        return ToolResult(text: "must not replay")
    }
}

@Suite("Project resource refresh")
@MainActor
struct ProjectResourceRefreshTests {
    private func waitForHeldRead(_ server: ProjectRefreshServer) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !(await server.isReadHeld) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await server.isReadHeld)
    }

    @Test(arguments: [false, true])
    func resetOrNewTurnRetiresRefreshWithoutCancellingHostPolling(newTurn: Bool) async throws {
        let server = ProjectRefreshServer()
        let provider = FakeProvider(runsToolsRemotely: true, turns: [[.textDelta("ready"), .done(stopReason: .endTurn)]])
        let assistant = MetabindAssistant(server: server, provider: provider)
        let session = MCPAppSession(id: "old", toolName: "card", resourceUri: "ui://card/1",
                                    completedWith: ToolResult(text: "old result"), server: server)
        _ = await session.awaitResult()
        assistant.conversation.append(.tool(session))
        let content = session.resolvedContent
        await server.edit()
        await server.beginHoldingReads()
        let refresh = Task { try await assistant.refreshProjectResources() }
        try await waitForHeldRead(server)
        if newTurn { assistant.send("new turn") } else { assistant.reset() }
        await server.releaseRead()
        try await refresh.value // Internal retirement must not stop a host's poll loop.
        try await finishTurn(assistant)
        #expect(session.resolvedContent == content, "Retired reload must not commit into the old card")
        if !newTurn { #expect(assistant.conversation.messages.isEmpty) }
        #expect(assistant.projectResourceRefreshError == nil)
        #expect(!assistant.isRefreshingProjectResources)
        await server.edit()
        try await assistant.refreshProjectResources()
        #expect(assistant.tools.first?.ui?.resourceUri == "ui://card/3")
        #expect(await server.calls == 0)
    }

    @Test func closingHostCancelsRefreshWithoutCommittingOldContent() async throws {
        let server = ProjectRefreshServer()
        let assistant = MetabindAssistant(server: server, provider: FakeProvider(runsToolsRemotely: true, turns: []))
        let session = MCPAppSession(id: "old", toolName: "card", resourceUri: "ui://card/1",
                                    completedWith: ToolResult(text: "old result"), server: server)
        _ = await session.awaitResult()
        assistant.conversation.append(.tool(session))
        let content = session.resolvedContent
        await server.edit()
        await server.beginHoldingReads()
        let refresh = Task { try await assistant.refreshProjectResources() }
        try await waitForHeldRead(server)
        refresh.cancel()
        await server.releaseRead()
        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(session.resolvedContent == content)
        #expect(assistant.projectResourceRefreshError == nil)
        #expect(!assistant.isRefreshingProjectResources)
    }

    private func finishTurn(_ assistant: MetabindAssistant) async throws {
        let deadline = Date().addingTimeInterval(2)
        while assistant.isProcessing && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!assistant.isProcessing)
    }

    @Test func refreshesHistoricalCardsWithoutChangingTranscriptOrReplayingCalls() async throws {
        func turn(_ id: String) -> [LLMEvent] {
            [
                .toolCallStart(index: 0, id: id, name: "card"),
                .toolCallArgumentsFinal(index: 0, arguments: ["selection": .string(id)]),
                .toolResult(toolCallId: id, content: "result \(id)", structuredContent: nil, isError: false),
                .done(stopReason: .endTurn)
            ]
        }
        let server = ProjectRefreshServer()
        let provider = FakeProvider(runsToolsRemotely: true, turns: [turn("first"), turn("second")])
        let assistant = MetabindAssistant(server: server, provider: provider)
        assistant.send("first turn")
        try await finishTurn(assistant)
        assistant.send("second turn")
        try await finishTurn(assistant)
        assistant.mergePendingContext(["selection": "keep"])
        let ids = assistant.conversation.messages.map(\.id)
        let sessions = assistant.conversation.messages.compactMap { message -> MCPAppSession? in
            if case .tool(let session) = message { return session }; return nil
        }
        #expect(sessions.count == 2)
        let results = sessions.map { $0.phase.terminalResult }
        await server.edit()
        try await assistant.refreshProjectResources()

        #expect(assistant.conversation.messages.map(\.id) == ids)
        #expect(sessions.map { $0.phase.terminalResult } == results)
        #expect(sessions.allSatisfy { $0.resolvedContent == .html("<p>revision 2</p>") })
        #expect(sessions.allSatisfy { $0.resourceUri == "ui://card/2" })
        #expect(sessions[0].partialArguments == ["selection": "first"])
        #expect(sessions[1].partialArguments == ["selection": "second"])
        #expect(assistant.pendingContext == ["selection": "keep"])
        #expect(await server.calls == 0)
        #expect(await provider.recordedInvocations.count == 2)
        #expect(!assistant.isRefreshingProjectResources)
        #expect(assistant.projectResourceRefreshError == nil)
    }

    @Test func exposesAuthenticationFailureAndClearsItOnRecovery() async throws {
        let server = ProjectRefreshServer()
        let provider = FakeProvider(runsToolsRemotely: true, turns: [])
        let assistant = MetabindAssistant(server: server, provider: provider)
        await server.edit(failDiscovery: true)
        await #expect(throws: URLError.self) { try await assistant.refreshProjectResources() }
        #expect(assistant.projectResourceRefreshError != nil)
        #expect(!assistant.isRefreshingProjectResources)
        await server.edit()
        try await assistant.refreshProjectResources()
        #expect(assistant.projectResourceRefreshError == nil)
        #expect(assistant.tools.count == 1)
        #expect(await provider.recordedInvocations.isEmpty)
    }
}
