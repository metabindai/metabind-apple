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
        /// When set, `callTool` waits here until the test opens it.
        var toolGate: ToolGate? = nil

        func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
            if let toolGate { try await toolGate.wait() }
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

    /// Holds `callTool` until the test opens it, so a test can observe the
    /// session while the call is in flight. Cancelling the calling task ends
    /// the wait with `CancellationError`, as it would a real request.
    final class ToolGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var waiters: [Int: CheckedContinuation<Void, Error>] = [:]
        private var started = 0
        private var cancelled = 0

        /// Calls that have reached the gate.
        var callsStarted: Int { lock.withLock { started } }

        /// Calls that ended at the gate because their task was cancelled.
        var callsCancelled: Int { lock.withLock { cancelled } }

        func open() {
            lock.withLock {
                isOpen = true
                for waiter in waiters.values { waiter.resume() }
                waiters = [:]
            }
        }

        func wait() async throws {
            let id = lock.withLock { started += 1; return started }
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.withLock {
                        if isOpen {
                            continuation.resume()
                        } else if Task.isCancelled {
                            cancelled += 1
                            continuation.resume(throwing: CancellationError())
                        } else {
                            waiters[id] = continuation
                        }
                    }
                }
            } onCancel: {
                lock.withLock {
                    guard let waiter = waiters.removeValue(forKey: id) else { return }
                    cancelled += 1
                    waiter.resume(throwing: CancellationError())
                }
            }
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
        await waitUntil { session.phase.isTerminal }

        if case .completed(let result) = session.phase {
            #expect(result.content.first == .text("done"))
        } else {
            Issue.record("Expected .completed, got \(session.phase)")
        }
    }

    @Test func autoSessionTransitionsThroughActive() async throws {
        let gate = ToolGate()
        let server = TestServer(toolGate: gate)  // tool runs until the gate opens
        let session = MCPAppSession(toolCall: makeToolCall(), server: server)

        // Wait for resource to load and the tool call to start
        await waitUntil { gate.callsStarted == 1 }
        #expect(session.phase.isActive)

        // Let the tool complete
        gate.open()
        await waitUntil { session.phase.isTerminal }
        #expect(session.phase.isCompleted)
    }

    @Test func noUISessionSkipsResourceFetch() async throws {
        let server = TestServer(toolDelay: .milliseconds(50))
        let session = MCPAppSession(toolCall: makeToolCall(hasUI: false), server: server)

        #expect(session.resourceUri == nil)

        await waitUntil { session.phase.isTerminal }
        #expect(session.phase.isCompleted)
    }

    // MARK: - Error handling

    @Test func toolFailureTransitionsToFailed() async throws {
        var server = TestServer()
        server.shouldFailTool = NSError(domain: "test", code: 1)
        let session = MCPAppSession(toolCall: makeToolCall(), server: server)

        await waitUntil { session.phase.isTerminal }

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

        await waitUntil { session.phase.isTerminal }

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

        await waitUntil { session.phase.isTerminal }

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

        await waitUntil { session.phase.isTerminal }

        if case .failed = session.phase {
            // Expected — content resolution failed
        } else {
            Issue.record("Expected .failed, got \(session.phase)")
        }
    }

    // MARK: - Cancel

    @Test func cancelStopsExecution() async throws {
        let gate = ToolGate()
        let session = MCPAppSession(toolCall: makeToolCall(), server: TestServer(toolGate: gate))

        await waitUntil { gate.callsStarted == 1 }
        session.cancel()

        #expect(session.phase.isCancelled)

        // The in-flight tool call is cancelled, not left to finish
        await waitUntil { gate.callsCancelled == 1 }
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

        await waitUntil { session.phase.isTerminal }
        #expect(session.phase.isFailed)

        // Fix the server and retry
        // Note: since server is a value type captured at init, retry uses the same failing server.
        // In production, the server is a reference type. This tests the retry mechanism itself.
        session.retry()
        #expect(session.phase.isLoading)
    }

    @Test func retryFromCancelled() async throws {
        let gate = ToolGate()
        let session = MCPAppSession(toolCall: makeToolCall(), server: TestServer(toolGate: gate))

        await waitUntil { gate.callsStarted == 1 }
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

        await waitUntil { session.phase.isTerminal }
        #expect(transitions.contains("active"))
        #expect(transitions.contains("completed"))
    }

    @Test func onPhaseTransitionFiresOnCancel() async throws {
        let gate = ToolGate()
        let session = MCPAppSession(toolCall: makeToolCall(), server: TestServer(toolGate: gate))

        var fired = false
        session.onPhaseTransition = { phase in
            if case .cancelled = phase { fired = true }
        }

        await waitUntil { gate.callsStarted == 1 }
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

        // No event marks the absence of a start, so allow 100 ms for an unwanted one to show
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.phase.isLoading)
        #expect(session.server == nil)
    }

    @Test func pendingSessionStartsWhenServerConnected() async throws {
        let session = MCPAppSession(pendingToolCall: makeToolCall(hasUI: false))
        let server = TestServer(toolDelay: .milliseconds(50))

        session.connectToServer(server)

        await waitUntil { session.phase.isTerminal }
        #expect(session.phase.isCompleted)
    }

    @Test func connectToServerIsIdempotent() async throws {
        let server = TestServer()
        let session = MCPAppSession(toolCall: makeToolCall(hasUI: false), server: server)

        // Connecting again should be a no-op
        let server2 = TestServer(toolResult: ToolResult(text: "wrong"))
        session.connectToServer(server2)

        await waitUntil { session.phase.isTerminal }

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
    var isTerminal: Bool { terminalResult != nil }

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
        await waitUntil { session.phase.isTerminal }
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
        // No event marks the absence of a start, so allow 50 ms for an unwanted one to show
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
        let gate = SessionTests.ToolGate()
        let server = SessionTests.TestServer(toolGate: gate)
        let session = MCPAppSession(
            id: "await-3", toolName: "test_tool", server: server
        )
        await waitUntil { gate.callsStarted == 1 }
        session.cancel()
        let result = await session.awaitResult()
        #expect(result.isError)
    }
}
