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
    var heldReads: [CheckedContinuation<Void, Never>] = []

    func beginHoldingReads() { holdReads = true }
    var isReadHeld: Bool { !heldReads.isEmpty }
    var heldReadCount: Int { heldReads.count }
    func releaseRead() {
        holdReads = false
        heldReads.forEach { $0.resume() }
        heldReads = []
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
        if holdReads { await withCheckedContinuation { heldReads.append($0) } }
        return ResourceContent(uri: uri, mimeType: "text/html", text: "<p>revision \(revision)</p>")
    }

    func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
        calls += 1
        return ToolResult(text: "must not replay")
    }
}

/// Serves the project through a real MCPAppsClient and holds the first
/// resource read, so a refresh can start while a card is still loading its UI.
private final class SlowFirstReadProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var revision = 1
    nonisolated(unsafe) private static var reads = 0
    nonisolated(unsafe) private static var toolLists = 0
    nonisolated(unsafe) private static var held: (request: SlowFirstReadProtocol, text: String)?
    private var stopped = false
    private var requestID: Any = NSNull()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        revision = 1; reads = 0; toolLists = 0; held = nil
    }
    static func edit() {
        lock.lock(); defer { lock.unlock() }
        revision += 1
    }
    static var toolListCount: Int {
        lock.lock(); defer { lock.unlock() }
        return toolLists
    }
    static var isReadHeld: Bool {
        lock.lock(); defer { lock.unlock() }
        return held != nil
    }
    static func releaseRead() {
        lock.lock()
        let read = held
        held = nil
        let stopped = read?.request.stopped ?? true
        lock.unlock()
        if let read, !stopped { read.request.respondResource(read.text) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        stopped = true
    }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        requestID = json?["id"] ?? NSNull()
        switch json?["method"] as? String {
        case "initialize":
            respond(["protocolVersion": "2025-03-26"])
        case "tools/list":
            Self.lock.lock(); Self.toolLists += 1; Self.lock.unlock()
            respond(["tools": [["name": "card", "inputSchema": ["type": "object"],
                                "_meta": ["ui": ["resourceUri": "ui://card"]]]]])
        case "resources/read":
            Self.lock.lock()
            Self.reads += 1
            let text = "<p>revision \(Self.revision)</p>"
            let hold = Self.reads == 1
            if hold { Self.held = (self, text) }
            Self.lock.unlock()
            if !hold { respondResource(text) }
        default:
            respond([:])
        }
    }
    private func respondResource(_ text: String) {
        respond(["contents": [["uri": "ui://card", "mimeType": "text/html", "text": text]]])
    }
    private func respond(_ result: [String: Any]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": requestID, "result": result])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
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

    @Test func cardReloadedByHostDuringRefreshIsSkippedWithoutEndingPolling() async throws {
        let server = ProjectRefreshServer()
        let assistant = MetabindAssistant(server: server, provider: FakeProvider(runsToolsRemotely: true, turns: []))
        let sessions = ["first", "second"].map {
            MCPAppSession(id: $0, toolName: "card", resourceUri: "ui://card/1",
                          completedWith: ToolResult(text: "\($0) result"), server: server)
        }
        for session in sessions {
            _ = await session.awaitResult()
            assistant.conversation.append(.tool(session))
        }
        await server.edit()
        await server.beginHoldingReads()
        let refresh = Task { try await assistant.refreshProjectResources() }
        try await waitForHeldRead(server)
        // The host reloads the first card itself, superseding the refresh's reload of it.
        let direct = Task { try await sessions[0].reloadResource() }
        let deadline = Date().addingTimeInterval(2)
        while await server.heldReadCount < 2 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        await server.releaseRead()
        try await direct.value
        try await refresh.value // A superseded card must not stop a host's poll loop.
        #expect(sessions.allSatisfy { $0.resolvedContent == .html("<p>revision 2</p>") })
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

    @Test func refreshKeepsCompletedCardWhoseUIIsStillLoading() async throws {
        SlowFirstReadProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlowFirstReadProtocol.self]
        let client = MCPAppsClient(url: URL(string: "https://project-refresh.test/mcp")!,
                                   configuration: .init(urlSession: URLSession(configuration: configuration)))
        let provider = FakeProvider(runsToolsRemotely: true, turns: [[
            .toolCallStart(index: 0, id: "first", name: "card"),
            .toolCallArgumentsFinal(index: 0, arguments: ["selection": .string("first")]),
            .toolResult(toolCallId: "first", content: "remote result", structuredContent: nil, isError: false),
            .done(stopReason: .endTurn)
        ]])
        let assistant = MetabindAssistant(server: client, provider: provider)
        assistant.send("first turn")
        try await finishTurn(assistant)
        let session = try #require(assistant.conversation.messages.compactMap { message -> MCPAppSession? in
            if case .tool(let session) = message { return session }; return nil
        }.first)
        var deadline = Date().addingTimeInterval(2)
        while !SlowFirstReadProtocol.isReadHeld && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(SlowFirstReadProtocol.isReadHeld)
        let result = try #require(session.phase.terminalResult)
        #expect(!result.isError)

        // The turn is over but the card's UI is still downloading when the host polls.
        SlowFirstReadProtocol.edit()
        let refresh = Task { try await assistant.refreshProjectResources() }
        deadline = Date().addingTimeInterval(2)
        while SlowFirstReadProtocol.toolListCount < 2 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(SlowFirstReadProtocol.toolListCount == 2, "Refresh clears the client cache before listing tools")
        SlowFirstReadProtocol.releaseRead()
        try await refresh.value

        #expect(session.phase.terminalResult == result)
        #expect(session.resolvedContent == .html("<p>revision 2</p>"))
        #expect(assistant.projectResourceRefreshError == nil)
    }
}
