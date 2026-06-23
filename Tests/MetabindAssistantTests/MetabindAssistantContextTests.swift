import Testing
import Foundation
@testable import MetabindAssistant
@testable import MCPAppsHost

@MainActor
@Suite("MetabindAssistant pending context")
struct MetabindAssistantContextTests {

    // MARK: - Fixtures

    /// A provider that captures the LLMMessage history passed to `stream`
    /// and immediately finishes with `.done(.endTurn)`. Lets us inspect
    /// exactly what the model would have seen without running any tools.
    final class RecordingProvider: LLMProvider, @unchecked Sendable {
        let runsToolsRemotely: Bool = false
        var lastMessages: [LLMMessage] = []

        func stream(messages: [LLMMessage], tools: [LLMTool]?, systemPrompt: String?) -> AsyncStream<LLMEvent> {
            lastMessages = messages
            return AsyncStream { continuation in
                continuation.yield(.done(stopReason: .endTurn))
                continuation.finish()
            }
        }
    }

    final class NoOpMCPServer: MCPServer, @unchecked Sendable {
        func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
            ToolResult(text: "ignored")
        }
        func readResource(uri: String) async throws -> ResourceContent {
            ResourceContent(uri: uri, mimeType: "text/plain", text: "")
        }
        func listTools() async throws -> [MCPToolDefinition] { [] }
    }

    private func makeAssistant() -> (MetabindAssistant, RecordingProvider) {
        let provider = RecordingProvider()
        let assistant = MetabindAssistant(server: NoOpMCPServer(), provider: provider)
        return (assistant, provider)
    }

    private func waitUntil(_ predicate: () -> Bool, timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Merge semantics

    @Test func mergeOverwritesMatchingKeys() {
        let (assistant, _) = makeAssistant()
        assistant.mergePendingContext(["selectedColor": .string("oat"), "qty": .number(1)])
        assistant.mergePendingContext(["qty": .number(3), "mood": .string("warm")])

        #expect(assistant.pendingContext["selectedColor"] == .string("oat"))
        #expect(assistant.pendingContext["qty"] == .number(3))
        #expect(assistant.pendingContext["mood"] == .string("warm"))
    }

    @Test func anyOverloadConverts() {
        let (assistant, _) = makeAssistant()
        assistant.mergePendingContext(["name": "Oslo Sofa", "price": 1899, "inStock": true])

        #expect(assistant.pendingContext["name"] == .string("Oslo Sofa"))
        #expect(assistant.pendingContext["price"] == .number(1899))
        #expect(assistant.pendingContext["inStock"] == .bool(true))
    }

    @Test func clearPendingContextDropsAll() {
        let (assistant, _) = makeAssistant()
        assistant.mergePendingContext(["a": .string("b")])
        assistant.clearPendingContext()
        #expect(assistant.pendingContext.isEmpty)
    }

    @Test func resetClearsPendingContext() {
        let (assistant, _) = makeAssistant()
        assistant.mergePendingContext(["a": .string("b")])
        assistant.reset()
        #expect(assistant.pendingContext.isEmpty)
    }

    // MARK: - Send-time injection

    @Test func sendWithoutContextLeavesTurnClean() async {
        let (assistant, provider) = makeAssistant()
        assistant.send("hello")

        await waitUntil { !assistant.isProcessing }

        let userMessages = provider.lastMessages.compactMap { msg -> String? in
            if case .user(let text) = msg { return text }
            return nil
        }
        #expect(userMessages == ["hello"])
    }

    @Test func sendWithPendingContextPrefixesModelTurnOnly() async {
        let (assistant, provider) = makeAssistant()
        assistant.mergePendingContext(["selectedColor": .string("oat")])
        assistant.send("tell me more")

        await waitUntil { !assistant.isProcessing }

        let userMessages = provider.lastMessages.compactMap { msg -> String? in
            if case .user(let text) = msg { return text }
            return nil
        }
        let userTurn = try? #require(userMessages.first)
        guard let userTurn else { return }

        #expect(userTurn.hasPrefix("<context>"))
        #expect(userTurn.contains("\"selectedColor\""))
        #expect(userTurn.contains("\"oat\""))
        #expect(userTurn.contains("</context>"))
        #expect(userTurn.hasSuffix("tell me more"))

        // User-facing conversation bubble stays clean.
        let userBubble = assistant.conversation.messages.compactMap { msg -> String? in
            if case .user(_, let text) = msg { return text }
            return nil
        }.first
        #expect(userBubble == "tell me more")
    }

    @Test func pendingContextClearsAfterOneSend() async {
        let (assistant, provider) = makeAssistant()
        assistant.mergePendingContext(["k": .string("v")])
        assistant.send("first")

        await waitUntil { !assistant.isProcessing }
        #expect(assistant.pendingContext.isEmpty)

        assistant.send("second")
        await waitUntil { !assistant.isProcessing }

        let last = provider.lastMessages.compactMap { msg -> String? in
            if case .user(let text) = msg { return text }
            return nil
        }.last
        // No prefix on the second turn.
        #expect(last == "second")
    }

    @Test func contextPrefixIsValidJSON() async throws {
        let (assistant, provider) = makeAssistant()
        assistant.mergePendingContext([
            "str": .string("value"),
            "num": .number(42),
            "bool": .bool(true),
        ])
        assistant.send("query")

        await waitUntil { !assistant.isProcessing }

        let userTurn = provider.lastMessages.compactMap { msg -> String? in
            if case .user(let t) = msg { return t }
            return nil
        }.first ?? ""

        // Extract JSON between the tags and re-parse.
        let pattern = #"<context>\n(.+?)\n</context>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(userTurn.startIndex..<userTurn.endIndex, in: userTurn)
        let match = try #require(regex.firstMatch(in: userTurn, options: [], range: range))
        let jsonRange = try #require(Range(match.range(at: 1), in: userTurn))
        let jsonString = String(userTurn[jsonRange])
        let data = try #require(jsonString.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed?["str"] as? String == "value")
        #expect(parsed?["num"] as? Int == 42)
        #expect(parsed?["bool"] as? Bool == true)
    }
}
