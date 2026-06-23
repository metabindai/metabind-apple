import Testing
import Foundation
@testable import MetabindAssistant
@testable import MCPAppsHost

// MARK: - Fakes

/// Scripted LLM provider. Drains `events` on each `stream()` call in FIFO
/// order, records the messages it was given, and can claim to run tools
/// either remotely or locally depending on the flag.
actor FakeProvider: LLMProvider {
    nonisolated let runsToolsRemotely: Bool

    private var scriptedTurns: [[LLMEvent]]
    private var invocations: [[LLMMessage]] = []

    init(runsToolsRemotely: Bool, turns: [[LLMEvent]]) {
        self.runsToolsRemotely = runsToolsRemotely
        self.scriptedTurns = turns
    }

    var recordedInvocations: [[LLMMessage]] { invocations }
    var remainingTurns: Int { scriptedTurns.count }

    nonisolated func stream(
        messages: [LLMMessage],
        tools: [LLMTool]?,
        systemPrompt: String?
    ) -> AsyncStream<LLMEvent> {
        AsyncStream { continuation in
            Task {
                let events = await self.popNextTurn(messages: messages)
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private func popNextTurn(messages: [LLMMessage]) -> [LLMEvent] {
        invocations.append(messages)
        return scriptedTurns.isEmpty ? [] : scriptedTurns.removeFirst()
    }
}

/// MCP server stub. `callTool` counts invocations; tests assert this stays
/// zero when the provider runs tools remotely.
actor FakeMCPServer: MCPServer {
    nonisolated let toolDefinitions: [MCPToolDefinition]
    private var callToolCount = 0
    private var listToolsCount = 0

    init(tools: [MCPToolDefinition] = []) {
        self.toolDefinitions = tools
    }

    var toolCallInvocations: Int { callToolCount }
    var listToolsInvocations: Int { listToolsCount }

    func listTools() async throws -> [MCPToolDefinition] {
        listToolsCount += 1
        return toolDefinitions
    }

    func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
        callToolCount += 1
        return ToolResult(text: "SHOULD NOT BE CALLED", isError: false)
    }

    nonisolated func readResource(uri: String) async throws -> ResourceContent {
        ResourceContent(uri: uri, mimeType: "application/json", text: "{}")
    }
}

// MARK: - Helpers

@MainActor
private func waitUntil(
    timeout: TimeInterval = 2,
    _ condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return }
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    }
}

// MARK: - Suite

@Suite("MetabindAssistant remote tool loop")
@MainActor
struct MetabindAssistantRemoteLoopTests {

    @Test func remoteProviderIssuesSingleProviderCallAndNoLocalToolCalls() async {
        // One turn: text, a synthetic tool_use, its tool_result, more text, done.
        let events: [LLMEvent] = [
            .textDelta("Looking it up. "),
            .toolCallStart(index: 0, id: "toolu_1", name: "getWeather"),
            .toolCallArgumentDelta(index: 0, fragment: #"{"city":"NYC"}"#),
            .contentBlockStop(index: 0),
            .toolResult(
                toolCallId: "toolu_1",
                content: "72°F sunny",
                structuredContent: nil,
                isError: false
            ),
            .textDelta("It's 72°F and sunny."),
            .done(stopReason: .endTurn),
        ]
        let provider = FakeProvider(runsToolsRemotely: true, turns: [events])
        let server = FakeMCPServer()

        let assistant = MetabindAssistant(server: server, provider: provider)
        assistant.send("weather?")

        await waitUntil { !assistant.isProcessing }

        #expect((await server.toolCallInvocations) == 0, "remote provider runs tools — assistant must not invoke callTool")
        #expect((await provider.recordedInvocations).count == 1, "remote loop is a single provider call per user message")
        #expect((await provider.remainingTurns) == 0)

        // Conversation should hold the user message, the assistant text and the tool session.
        let roles = assistant.conversation.messages.map { String(describing: $0) }
        #expect(roles.contains(where: { $0.contains("user") }))
        #expect(roles.contains(where: { $0.contains("assistant") }))
        #expect(roles.contains(where: { $0.contains("tool") }))
    }

    @Test func remoteToolResultCompletesSession() async throws {
        let events: [LLMEvent] = [
            .toolCallStart(index: 0, id: "toolu_1", name: "doThing"),
            .contentBlockStop(index: 0),
            .toolResult(
                toolCallId: "toolu_1",
                content: "done-text",
                structuredContent: nil,
                isError: false
            ),
            .done(stopReason: .endTurn),
        ]
        let provider = FakeProvider(runsToolsRemotely: true, turns: [events])
        let server = FakeMCPServer()
        let assistant = MetabindAssistant(server: server, provider: provider)

        assistant.send("run it")
        await waitUntil { !assistant.isProcessing }

        // Find the tool session in the conversation and assert it completed.
        let sessions = assistant.conversation.messages.compactMap { msg -> MCPAppSession? in
            if case .tool(let session) = msg { return session }
            return nil
        }
        let session = try #require(sessions.first)
        #expect(session.phase.isTerminal, "tool session should be terminal (completed/failed)")
    }

    @Test func remoteToolResultWithErrorCompletesSessionAsFailed() async {
        let events: [LLMEvent] = [
            .toolCallStart(index: 0, id: "toolu_x", name: "brokenThing"),
            .contentBlockStop(index: 0),
            .toolResult(
                toolCallId: "toolu_x",
                content: "upstream exploded",
                structuredContent: nil,
                isError: true
            ),
            .done(stopReason: .endTurn),
        ]
        let provider = FakeProvider(runsToolsRemotely: true, turns: [events])
        let server = FakeMCPServer()
        let assistant = MetabindAssistant(server: server, provider: provider)

        assistant.send("break it")
        await waitUntil { !assistant.isProcessing }

        #expect((await server.toolCallInvocations) == 0)

        let sessions = assistant.conversation.messages.compactMap { msg -> MCPAppSession? in
            if case .tool(let session) = msg { return session }
            return nil
        }
        #expect(sessions.count == 1)
        #expect(sessions.first?.phase.isFailure == true)
    }

    @Test func remoteProviderSwitchDoesNotDisruptLoop() async {
        let events: [LLMEvent] = [
            .textDelta("Before. "),
            .providerSwitch(from: "anthropic", to: "openai", reason: "rate_limit"),
            .textDelta("After."),
            .done(stopReason: .endTurn),
        ]
        let provider = FakeProvider(runsToolsRemotely: true, turns: [events])
        let server = FakeMCPServer()
        let assistant = MetabindAssistant(server: server, provider: provider)

        assistant.send("x")
        await waitUntil { !assistant.isProcessing }

        // Both text deltas should have made it into the transcript.
        let text = assistant.conversation.messages.compactMap { msg -> String? in
            if case .assistant(_, let text) = msg { return text }
            return nil
        }.joined()
        #expect(text.contains("Before."))
        #expect(text.contains("After."))
    }

    @Test func interleavedTextAndToolsProduceSeparateBubbles() async {
        // Turn shape: text, tool, text, tool, text. The assistant UI
        // should render these in order — five distinct conversation
        // entries (two assistant bubbles sandwiching one tool session,
        // then another bubble and tool session). Before the fix, every
        // text-delta after the first appended to the ORIGINAL bubble,
        // visually bunching all text at the top.
        let events: [LLMEvent] = [
            .textDelta("Here's a sofa: "),
            .toolCallStart(index: 0, id: "t1", name: "render_sofa"),
            .contentBlockStop(index: 0),
            .toolResult(toolCallId: "t1", content: "ok", structuredContent: nil, isError: false),
            .textDelta("And a matching chair: "),
            .toolCallStart(index: 1, id: "t2", name: "render_chair"),
            .contentBlockStop(index: 1),
            .toolResult(toolCallId: "t2", content: "ok", structuredContent: nil, isError: false),
            .textDelta("That's the set."),
            .done(stopReason: .endTurn),
        ]
        let provider = FakeProvider(runsToolsRemotely: true, turns: [events])
        let server = FakeMCPServer()
        let assistant = MetabindAssistant(server: server, provider: provider)

        assistant.send("show sofa + chair")
        await waitUntil { !assistant.isProcessing }

        // Expected message shape (ignoring the user bubble at index 0):
        //   user, assistant("Here's a sofa: "), tool, assistant("And a matching chair: "), tool, assistant("That's the set.")
        let afterUser = Array(assistant.conversation.messages.dropFirst())
        #expect(afterUser.count == 5, "interleaved flow should produce 5 distinct entries, got \(afterUser.count)")

        let assistantTexts = afterUser.compactMap { msg -> String? in
            if case .assistant(_, let text) = msg { return text }
            return nil
        }
        #expect(assistantTexts == ["Here's a sofa: ", "And a matching chair: ", "That's the set."])

        let toolCount = afterUser.filter { msg in
            if case .tool = msg { return true }
            return false
        }.count
        #expect(toolCount == 2)

        // And the history fed to the model should still contain the full
        // assistant turn text (all three segments), collapsed into one
        // LLMMessage.assistant entry.
        // (We can't read llmHistory directly — it's private — but we can
        //  verify via the FakeProvider's recorded invocations on the NEXT
        //  send. Skipping for this test since one turn suffices to prove
        //  the bubble-splitting behavior.)
    }

    @Test func incompleteToolCallWithoutArgumentsIsDroppedAtEndOfStream() async {
        // Defensive (MET-1197 follow-up): a provider opens a tool block via
        // `toolCallStart` but the turn ends — no partials, no terminal frame,
        // no `contentBlockStop` — before any arguments arrive. The
        // end-of-stream sweep must NOT ship an empty-args tool call: a local
        // loop would then execute it against the MCP server, and it pollutes
        // history. The stranded bubble is surfaced as failed instead of
        // spinning forever.
        let turn: [LLMEvent] = [
            .toolCallStart(index: 0, id: "orphan", name: "doThing"),
            .done(stopReason: .endTurn),
        ]
        // Local loop so an erroneously-shipped tool call would reach callTool.
        let provider = FakeProvider(runsToolsRemotely: false, turns: [turn])
        let server = FakeMCPServer()
        let assistant = MetabindAssistant(server: server, provider: provider)

        assistant.send("go")
        await waitUntil { !assistant.isProcessing }

        #expect((await server.toolCallInvocations) == 0,
                "an arg-less orphan tool call must not be executed")
        #expect((await provider.recordedInvocations).count == 1,
                "no second loop iteration should chase the phantom tool call")

        let sessions = assistant.conversation.messages.compactMap { msg -> MCPAppSession? in
            if case .tool(let session) = msg { return session }
            return nil
        }
        #expect(sessions.first?.phase.isFailure == true,
                "stranded tool bubble should be marked failed, not left loading")
    }

    // MARK: - Regression: local loop still works

    @Test func remoteDoneEndTurnExitsEvenIfStreamNeverCloses() async {
        // The Metabind agent proxy keeps the SSE/TCP connection open across
        // turns. Before the streamResponse fix, the for-await in
        // streamResponse would receive `.done(.endTurn)` but keep waiting
        // for the AsyncStream to terminate; the upstream stream never
        // closed, so `isProcessing` stayed true forever and the UI looked
        // frozen. Reproduce here with a provider that yields a clean turn
        // and then deliberately never calls `continuation.finish()`.
        final class OpenStreamProvider: LLMProvider, @unchecked Sendable {
            let runsToolsRemotely = true

            func resetConversation() async {}

            func stream(
                messages: [LLMMessage],
                tools: [LLMTool]?,
                systemPrompt: String?
            ) -> AsyncStream<LLMEvent> {
                AsyncStream { continuation in
                    Task {
                        continuation.yield(.textDelta("hello"))
                        continuation.yield(.done(stopReason: .endTurn))
                        // Deliberately do NOT call continuation.finish().
                        // The Task stays alive holding the continuation.
                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                        continuation.finish()
                    }
                }
            }
        }

        let provider = OpenStreamProvider()
        let server = FakeMCPServer()
        let assistant = MetabindAssistant(server: server, provider: provider)

        assistant.send("hi")
        await waitUntil(timeout: 1) { !assistant.isProcessing }

        #expect(!assistant.isProcessing, ".done(.endTurn) must exit streamResponse even when the byte stream is still open")
    }

    @Test func localProviderStillRunsMultiTurnToolLoop() async {
        // Turn 1: assistant emits a tool call, done.toolUse.
        // Turn 2: assistant emits the final text, done.endTurn.
        let turn1: [LLMEvent] = [
            .toolCallStart(index: 0, id: "t1", name: "ping"),
            .contentBlockStop(index: 0),
            .done(stopReason: .toolUse),
        ]
        let turn2: [LLMEvent] = [
            .textDelta("ok"),
            .done(stopReason: .endTurn),
        ]
        let provider = FakeProvider(runsToolsRemotely: false, turns: [turn1, turn2])
        let server = FakeMCPServer()
        let assistant = MetabindAssistant(server: server, provider: provider)

        assistant.send("go")
        await waitUntil { !assistant.isProcessing }

        #expect((await provider.recordedInvocations).count == 2, "local loop should stream twice — once per provider turn")
        #expect((await server.toolCallInvocations) == 1, "local loop should invoke callTool for each returned tool_use")
    }
}

// MARK: - Phase conveniences for assertions

private extension MCPAppSession.Phase {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .loading, .active: false
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
