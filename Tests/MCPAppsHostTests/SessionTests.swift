import Testing
import Foundation
@testable import MCPAppsHost

@Suite("MCPAppSession")
@MainActor
struct SessionTests {

    // MARK: - Helpers

    /// Mock server with configurable delays and responses.
    struct TestServer: MCPServer {
        var toolDelay: Duration = .zero
        var resourceDelay: Duration = .zero
        var toolResult: ToolResult = ToolResult(text: "done")
        var resourceText: String = MockMCPServer.sampleBindJSResource
        var shouldFailTool: Error? = nil
        var shouldFailResource: Error? = nil

        func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
            if toolDelay > .zero { try await Task.sleep(for: toolDelay) }
            if let error = shouldFailTool { throw error }
            return toolResult
        }

        func readResource(uri: String) async throws -> ResourceContent {
            if resourceDelay > .zero { try await Task.sleep(for: resourceDelay) }
            if let error = shouldFailResource { throw error }
            return ResourceContent(uri: uri, mimeType: "application/json", text: resourceText)
        }
    }

    func makeToolCall(name: String = "test_tool", hasUI: Bool = true) -> SimpleMCPToolCall {
        SimpleMCPToolCall(
            id: UUID().uuidString,
            name: name,
            arguments: ["input": "value"],
            toolDefinition: hasUI ? MCPToolDefinition(
                name: name,
                ui: .init(resourceUri: "ui://test/\(name)")
            ) : MCPToolDefinition(name: name)
        )
    }

    // MARK: - Auto execution lifecycle

    @Test func autoSessionCompletesSuccessfully() async throws {
        let server = TestServer(toolDelay: .milliseconds(50), resourceDelay: .milliseconds(50))
        let session = MCPAppSession(toolCall: makeToolCall(), server: server)

        // Should start in loading
        #expect(session.phase.isLoading)

        // Wait for completion
        try await Task.sleep(for: .milliseconds(200))

        if case .completed(let result) = session.phase {
            #expect(result.content.first == .text("done"))
        } else {
            Issue.record("Expected .completed, got \(session.phase)")
        }
    }

    @Test func autoSessionTransitionsThroughActive() async throws {
        let server = TestServer(
            toolDelay: .milliseconds(200),  // tool takes a while
            resourceDelay: .milliseconds(10)
        )
        let session = MCPAppSession(toolCall: makeToolCall(), server: server)

        // Wait for resource to load but tool still running
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.phase.isActive)

        // Wait for tool to complete
        try await Task.sleep(for: .milliseconds(250))
        #expect(session.phase.isCompleted)
    }

    @Test func noUISessionSkipsResourceFetch() async throws {
        let server = TestServer(toolDelay: .milliseconds(50))
        let session = MCPAppSession(toolCall: makeToolCall(hasUI: false), server: server)

        #expect(session.resourceUri == nil)

        try await Task.sleep(for: .milliseconds(150))
        #expect(session.phase.isCompleted)
    }

    // MARK: - Error handling

    @Test func toolFailureTransitionsToFailed() async throws {
        var server = TestServer()
        server.shouldFailTool = NSError(domain: "test", code: 1)
        let session = MCPAppSession(toolCall: makeToolCall(), server: server)

        try await Task.sleep(for: .milliseconds(100))

        if case .failed = session.phase {
            // Expected
        } else {
            Issue.record("Expected .failed, got \(session.phase)")
        }
    }

    @Test func toolIsErrorWithUIKeepsContent() async throws {
        var server = TestServer(resourceDelay: .milliseconds(10))
        server.toolResult = ToolResult(text: "error details", isError: true)
        let session = MCPAppSession(toolCall: makeToolCall(hasUI: true), server: server)

        try await Task.sleep(for: .milliseconds(200))

        // UI tool with resolved content: isError result should still complete
        #expect(session.phase.isCompleted)
        if case .completed(let result) = session.phase {
            #expect(result.isError)
            #expect(result.content.first == .text("error details"))
        }
        #expect(session.resolvedContent != nil)
    }

    @Test func toolIsErrorWithoutUIFails() async throws {
        let server = TestServer(
            toolResult: ToolResult(text: "bad input", isError: true)
        )
        let session = MCPAppSession(toolCall: makeToolCall(hasUI: false), server: server)

        try await Task.sleep(for: .milliseconds(100))

        // Data tool with no resolved content: isError should fail
        if case .failed = session.phase {
            // Expected
        } else {
            Issue.record("Expected .failed, got \(session.phase)")
        }
    }

    @Test func resourceNotResolvableTransitionsToFailed() async throws {
        var server = TestServer()
        server.resourceText = "not json at all <html>"
        // BindJSResolver will fail to decode this
        let session = MCPAppSession(toolCall: makeToolCall(), server: server)

        try await Task.sleep(for: .milliseconds(100))

        if case .failed = session.phase {
            // Expected — content resolution failed
        } else {
            Issue.record("Expected .failed, got \(session.phase)")
        }
    }

    // MARK: - Cancel

    @Test func cancelStopsExecution() async throws {
        let server = TestServer(toolDelay: .seconds(10))
        let session = MCPAppSession(toolCall: makeToolCall(), server: server)

        try await Task.sleep(for: .milliseconds(50))
        session.cancel()

        #expect(session.phase.isCancelled)
    }

    @Test func cancelIsIdempotent() {
        let session = MCPAppSession.preview(phase: .cancelled)
        session.cancel() // should not crash
        #expect(session.phase.isCancelled)
    }

    // MARK: - Retry

    @Test func retryFromFailed() async throws {
        var server = TestServer()
        server.shouldFailTool = NSError(domain: "test", code: 1)
        let session = MCPAppSession(toolCall: makeToolCall(hasUI: false), server: server)

        try await Task.sleep(for: .milliseconds(100))
        #expect(session.phase.isFailed)

        // Fix the server and retry
        // Note: since server is a value type captured at init, retry uses the same failing server.
        // In production, the server is a reference type. This tests the retry mechanism itself.
        session.retry()
        #expect(session.phase.isLoading)
    }

    @Test func retryFromCancelled() async throws {
        let server = TestServer(toolDelay: .seconds(10))
        let session = MCPAppSession(toolCall: makeToolCall(), server: server)

        try await Task.sleep(for: .milliseconds(50))
        session.cancel()
        #expect(session.phase.isCancelled)

        session.retry()
        #expect(session.phase.isLoading)
    }

    // MARK: - Callbacks

    @Test func onPhaseTransitionFires() async throws {
        let server = TestServer(toolDelay: .milliseconds(50))
        let session = MCPAppSession(toolCall: makeToolCall(hasUI: false), server: server)

        var transitions: [String] = []
        session.onPhaseTransition = { phase in
            transitions.append(phase.label)
        }

        try await Task.sleep(for: .milliseconds(200))
        #expect(transitions.contains("active"))
        #expect(transitions.contains("completed"))
    }

    @Test func onPhaseTransitionFiresOnCancel() async throws {
        let server = TestServer(toolDelay: .seconds(10))
        let session = MCPAppSession(toolCall: makeToolCall(), server: server)

        var fired = false
        session.onPhaseTransition = { phase in
            if case .cancelled = phase { fired = true }
        }

        try await Task.sleep(for: .milliseconds(50))
        session.cancel()
        #expect(fired)
    }

    // MARK: - History

    @Test func historySessionStartsCompleted() {
        let result = ToolResult(text: "historical result")
        let session = MCPAppSession(toolCall: makeToolCall(), completedWith: result)

        if case .completed(let r) = session.phase {
            #expect(r.content.first == .text("historical result"))
        } else {
            Issue.record("Expected .completed")
        }
    }

    // MARK: - Pending (convenience init)

    @Test func pendingSessionStaysLoadingWithoutServer() async throws {
        let session = MCPAppSession(pendingToolCall: makeToolCall())

        try await Task.sleep(for: .milliseconds(100))
        #expect(session.phase.isLoading)
        #expect(session.server == nil)
    }

    @Test func pendingSessionStartsWhenServerConnected() async throws {
        let session = MCPAppSession(pendingToolCall: makeToolCall(hasUI: false))
        let server = TestServer(toolDelay: .milliseconds(50))

        session.connectToServer(server)

        try await Task.sleep(for: .milliseconds(200))
        #expect(session.phase.isCompleted)
    }

    @Test func connectToServerIsIdempotent() async throws {
        let server = TestServer()
        let session = MCPAppSession(toolCall: makeToolCall(hasUI: false), server: server)

        // Connecting again should be a no-op
        let server2 = TestServer(toolResult: ToolResult(text: "wrong"))
        session.connectToServer(server2)

        try await Task.sleep(for: .milliseconds(100))

        if case .completed(let result) = session.phase {
            #expect(result.content.first == .text("done"))
        } else {
            Issue.record("Expected .completed")
        }
    }
}

// MARK: - Phase convenience

extension MCPAppSession.Phase {
    var isLoading: Bool { if case .loading = self { return true }; return false }
    var isActive: Bool { if case .active = self { return true }; return false }
    var isCompleted: Bool { if case .completed = self { return true }; return false }
    var isFailed: Bool { if case .failed = self { return true }; return false }
    var isCancelled: Bool { if case .cancelled = self { return true }; return false }

    var label: String {
        switch self {
        case .loading: "loading"
        case .active: "active"
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
    }
}

// MARK: - Primitive Inits

@Suite("Primitive Inits")
@MainActor
struct PrimitiveInitTests {

    @Test func primitiveAutoExecute() async throws {
        let server = SessionTests.TestServer(toolDelay: .milliseconds(50))
        let session = MCPAppSession(
            id: "prim-1", toolName: "test_tool",
            arguments: ["x": 1], server: server
        )
        #expect(session.id == "prim-1")
        #expect(session.toolName == "test_tool")
        try await Task.sleep(for: .milliseconds(200))
        #expect(session.phase.isCompleted)
    }

    @Test func primitiveCompleted() {
        let result = ToolResult(text: "already done")
        let session = MCPAppSession(
            id: "prim-2", toolName: "test_tool",
            completedWith: result
        )
        if case .completed(let r) = session.phase {
            #expect(r.content.first == .text("already done"))
        } else {
            Issue.record("Expected .completed")
        }
    }

    @Test func primitivePending() async throws {
        let session = MCPAppSession(
            pendingId: "prim-3", toolName: "test_tool"
        )
        #expect(session.phase.isLoading)
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.phase.isLoading)
    }
}

// MARK: - awaitResult

@Suite("awaitResult")
@MainActor
struct AwaitResultTests {

    @Test func awaitResultOnAutoSession() async throws {
        let server = SessionTests.TestServer(toolDelay: .milliseconds(50))
        let session = MCPAppSession(
            id: "await-1", toolName: "test_tool", server: server
        )
        let result = await session.awaitResult()
        #expect(result.content.first == .text("done"))
        #expect(!result.isError)
    }

    @Test func awaitResultOnAlreadyCompleted() async {
        let session = MCPAppSession(
            id: "await-2", toolName: "test_tool",
            completedWith: ToolResult(text: "pre-done")
        )
        let result = await session.awaitResult()
        #expect(result.content.first == .text("pre-done"))
    }

    @Test func awaitResultOnCancelled() async throws {
        let server = SessionTests.TestServer(toolDelay: .seconds(10))
        let session = MCPAppSession(
            id: "await-3", toolName: "test_tool", server: server
        )
        try await Task.sleep(for: .milliseconds(50))
        session.cancel()
        let result = await session.awaitResult()
        #expect(result.isError)
    }
}
