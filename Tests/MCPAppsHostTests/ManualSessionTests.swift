import Testing
import Foundation
@testable import MCPAppsHost

@Suite("ManualMCPAppSession")
@MainActor
struct ManualSessionTests {

    struct TestServer: MCPServer {
        var toolResult: ToolResult = ToolResult(text: "action result")

        func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
            toolResult
        }

        func readResource(uri: String) async throws -> ResourceContent {
            ResourceContent(uri: uri, mimeType: "application/json", text: MockMCPServer.sampleBindJSResource)
        }
    }

    func makeToolCall() -> SimpleMCPToolCall {
        SimpleMCPToolCall(
            id: UUID().uuidString,
            name: "manual_tool",
            arguments: ["x": 1],
            toolDefinition: MCPToolDefinition(
                name: "manual_tool",
                ui: .init(resourceUri: "ui://test/manual_tool")
            )
        )
    }

    // MARK: - Manual execution

    @Test func manualSessionDoesNotAutoExecute() async throws {
        let session = ManualMCPAppSession(toolCall: makeToolCall(), server: TestServer())

        // Wait for resource fetch to complete
        try await Task.sleep(for: .milliseconds(100))

        // Should be active (resource loaded) but NOT completed (no auto-execution)
        #expect(session.phase.isActive)
    }

    @Test func completeTransitionsToCompleted() async throws {
        let session = ManualMCPAppSession(toolCall: makeToolCall(), server: TestServer())

        try await Task.sleep(for: .milliseconds(100))

        let result = ToolResult(text: "my custom result")
        session.complete(with: result)

        if case .completed(let r) = session.phase {
            #expect(r.content.first == .text("my custom result"))
        } else {
            Issue.record("Expected .completed, got \(session.phase)")
        }
    }

    @Test func completeWithErrorTransitionsToFailed() async throws {
        let session = ManualMCPAppSession(toolCall: makeToolCall(), server: TestServer())

        try await Task.sleep(for: .milliseconds(100))

        let errorResult = ToolResult(text: "something broke", isError: true)
        session.complete(with: errorResult)

        #expect(session.phase.isFailed)
    }

    @Test func feedStoresPartialArguments() {
        let session = ManualMCPAppSession(toolCall: makeToolCall(), server: TestServer())

        #expect(session.partialArguments == nil)

        session.feed(["partial": "data"])
        #expect(session.partialArguments == .object(["partial": .string("data")]))

        session.feed(["partial": "more data", "extra": true])
        #expect(session.partialArguments?["extra"] == .bool(true))
    }

    @Test func feedThenComplete() async throws {
        let session = ManualMCPAppSession(toolCall: makeToolCall(), server: TestServer())

        try await Task.sleep(for: .milliseconds(100))

        session.feed(["step": 1])
        session.feed(["step": 2])
        session.complete(with: ToolResult(text: "final"))

        #expect(session.phase.isCompleted)
        #expect(session.partialArguments?["step"] == .number(2))
    }

    @Test func callbackFiresOnComplete() async throws {
        let session = ManualMCPAppSession(toolCall: makeToolCall(), server: TestServer())

        var completedResult: ToolResult?
        session.onPhaseTransition = { phase in
            if case .completed(let r) = phase { completedResult = r }
        }

        try await Task.sleep(for: .milliseconds(100))
        session.complete(with: ToolResult(text: "callback test"))

        #expect(completedResult?.content.first == .text("callback test"))
    }
}
