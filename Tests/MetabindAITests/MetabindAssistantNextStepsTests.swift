import Testing
import Foundation
@testable import MetabindAI
@testable import MCPAppsHost

/// Local copy — the remote-loop suite's version is file-private.
@MainActor
private func settle(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

/// `nextSteps` rides along as an argument on a card's tool call, so the model
/// never spends a separate turn on follow-up suggestions. These cover pulling
/// it back out of the stream. Fakes come from `MetabindAssistantRemoteLoopTests`.
@Suite("MetabindAssistant nextSteps")
@MainActor
struct MetabindAssistantNextStepsTests {

    /// One card call carrying suggestions, streamed in fragments the way a
    /// provider actually delivers them.
    private func cardTurn(
        argumentJSON: String,
        toolName: String = "spending_breakdown"
    ) -> [LLMEvent] {
        [
            .toolCallStart(index: 0, id: "toolu_1", name: toolName),
            .toolCallArgumentDelta(index: 0, fragment: argumentJSON),
            .contentBlockStop(index: 0),
            .toolResult(
                toolCallId: "toolu_1",
                content: "Rendered \(toolName)",
                structuredContent: nil,
                isError: false
            ),
            .done(stopReason: .endTurn),
        ]
    }

    private func run(_ events: [LLMEvent], message: String = "where did my money go") async -> MetabindAssistant {
        let provider = FakeProvider(runsToolsRemotely: true, turns: [events])
        let assistant = MetabindAssistant(server: FakeMCPServer(), provider: provider)
        assistant.send(message)
        await settle { !assistant.isProcessing }
        return assistant
    }

    @Test func extractsSuggestionsFromToolArguments() async {
        let assistant = await run(cardTurn(
            argumentJSON: #"{"period":"mtd","nextSteps":["Why is shopping up?","Show me last month"]}"#
        ))

        #expect(assistant.nextSteps == ["Why is shopping up?", "Show me last month"])
    }

    @Test func absentArgumentLeavesSuggestionsEmpty() async {
        let assistant = await run(cardTurn(argumentJSON: #"{"period":"mtd"}"#))
        #expect(assistant.nextSteps.isEmpty)
    }

    @Test func blankAndWhitespaceEntriesAreDropped() async {
        let assistant = await run(cardTurn(
            argumentJSON: #"{"nextSteps":["  Trim me  ","","   "]}"#
        ))
        #expect(assistant.nextSteps == ["Trim me"])
    }

    @Test func nonStringEntriesAreIgnored() async {
        let assistant = await run(cardTurn(
            argumentJSON: #"{"nextSteps":["Keep this",42,null]}"#
        ))
        #expect(assistant.nextSteps == ["Keep this"])
    }

    @Test func disablingTheArgumentNameSkipsExtraction() async {
        let provider = FakeProvider(
            runsToolsRemotely: true,
            turns: [cardTurn(argumentJSON: #"{"nextSteps":["Ignored"]}"#)]
        )
        let assistant = MetabindAssistant(server: FakeMCPServer(), provider: provider)
        assistant.nextStepsArgument = nil

        assistant.send("go")
        await settle { !assistant.isProcessing }

        #expect(assistant.nextSteps.isEmpty)
    }

    /// Partial parses run on every fragment, so a half-typed array must not
    /// shrink the row it already showed — the pills would flicker.
    @Test func partialStreamOnlyGrowsTheList() async {
        let events: [LLMEvent] = [
            .toolCallStart(index: 0, id: "toolu_1", name: "spending_breakdown"),
            .toolCallArgumentDelta(index: 0, fragment: #"{"period":"mtd","nextSteps":["#),
            .toolCallArgumentDelta(index: 0, fragment: #""Why is shopping up?","#),
            .toolCallArgumentDelta(index: 0, fragment: #""Show me last mon"#),
            .toolCallArgumentDelta(index: 0, fragment: #"th"]}"#),
            .contentBlockStop(index: 0),
            .toolResult(toolCallId: "toolu_1", content: "ok", structuredContent: nil, isError: false),
            .done(stopReason: .endTurn),
        ]
        let assistant = await run(events)

        // The truncated third fragment must not have left a clipped entry.
        #expect(assistant.nextSteps == ["Why is shopping up?", "Show me last month"])
    }

    @Test func newMessageClearsThePreviousCardsSuggestions() async {
        let first = cardTurn(argumentJSON: #"{"nextSteps":["Stale suggestion"]}"#)
        let second: [LLMEvent] = [.textDelta("no card here"), .done(stopReason: .endTurn)]

        let provider = FakeProvider(runsToolsRemotely: true, turns: [first, second])
        let assistant = MetabindAssistant(server: FakeMCPServer(), provider: provider)

        assistant.send("where did my money go")
        await settle { !assistant.isProcessing }
        #expect(assistant.nextSteps == ["Stale suggestion"])

        assistant.send("thanks")
        await settle { !assistant.isProcessing }
        #expect(assistant.nextSteps.isEmpty, "suggestions belong to the card that supplied them")
    }
}
