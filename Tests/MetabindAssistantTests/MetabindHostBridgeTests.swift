import Testing
import Foundation
@testable import MetabindAssistant
@testable import MCPAppsHost

@MainActor
@Suite("MetabindHostBridge")
struct MetabindHostBridgeTests {

    // MARK: - toolCall

    @Test func toolCallWithNoHandlerReturnsNil() async throws {
        let bridge = MetabindHostBridge()
        let result = try await bridge.toolCall(name: "anything", arguments: ["a": 1])
        #expect(result == nil)
    }

    @Test func toolCallForwardsArgsAndReturnsHandlerValue() async throws {
        let bridge = MetabindHostBridge()
        let captured = Box<(String, JSONValue)>()
        bridge.handlers.toolCall = { name, args in
            captured.value = (name, args)
            return ["status": "ok"]
        }

        let result = try await bridge.toolCall(name: "add_to_cart", arguments: ["id": 42, "qty": 2])

        let (name, args) = try #require(captured.value)
        #expect(name == "add_to_cart")
        guard case .object(let dict) = args else {
            Issue.record("args not an object: \(args)")
            return
        }
        #expect(dict["id"] == .number(42))
        #expect(dict["qty"] == .number(2))

        let dictResult = try #require(result as? [String: Any])
        #expect(dictResult["status"] as? String == "ok")
    }

    @Test func toolCallPropagatesHandlerErrors() async {
        let bridge = MetabindHostBridge()
        struct BoomError: Error {}
        bridge.handlers.toolCall = { _, _ in throw BoomError() }

        await #expect(throws: BoomError.self) {
            _ = try await bridge.toolCall(name: "x", arguments: [:])
        }
    }

    // MARK: - sendMessage

    @Test func sendMessageForwardsToolMessage() async throws {
        let bridge = MetabindHostBridge()
        let captured = Box<ToolMessage>()
        bridge.handlers.onMessage = { captured.value = $0 }

        try await bridge.sendMessage("hello world")

        let received = try #require(captured.value)
        #expect(received.role == .user)
        #expect(received.content.count == 1)
        guard case .text(let text) = received.content.first! else {
            Issue.record("expected text block")
            return
        }
        #expect(text == "hello world")
    }

    @Test func sendMessageWithNoHandlerDoesNotThrow() async throws {
        let bridge = MetabindHostBridge()
        try await bridge.sendMessage("ignored")
    }

    // MARK: - updateModelContext

    @Test func updateModelContextForwardsStructured() async throws {
        let bridge = MetabindHostBridge()
        let captured = Box<ModelContext>()
        bridge.handlers.onContext = { captured.value = $0 }

        try await bridge.updateModelContext(["selectedColor": "oat", "qty": 3])

        let received = try #require(captured.value)
        guard case .object(let dict) = received.structuredContent ?? .null else {
            Issue.record("structuredContent not an object")
            return
        }
        #expect(dict["selectedColor"] == .string("oat"))
        #expect(dict["qty"] == .number(3))
    }

    // MARK: - elicit

    @Test func elicitWithNoHandlerDeclines() async throws {
        let bridge = MetabindHostBridge()
        let response = try await bridge.elicit(
            schema: ["type": "object"],
            metadata: nil
        )
        #expect(response.action == .decline)
        #expect(response.content == nil)
    }

    @Test func elicitForwardsSchemaAndReturnsResponse() async throws {
        let bridge = MetabindHostBridge()
        let captured = Box<(JSONValue, [String: JSONValue]?)>()
        bridge.handlers.onElicit = { schema, metadata in
            captured.value = (schema, metadata)
            return ElicitationResponse(
                action: .accept,
                content: ["email": "test@example.com"]
            )
        }

        let response = try await bridge.elicit(
            schema: ["type": "object", "properties": ["email": ["type": "string"]]],
            metadata: ["title": "Enter email"]
        )

        #expect(response.action == .accept)
        #expect(response.content?["email"] as? String == "test@example.com")

        let (schema, meta) = try #require(captured.value)
        guard case .object(let schemaDict) = schema else {
            Issue.record("schema not object")
            return
        }
        #expect(schemaDict["type"] == .string("object"))
        #expect(meta?["title"] == .string("Enter email"))
    }

    // MARK: - openLink

    @Test func openLinkWithHandlerReturnsTrue() async throws {
        let bridge = MetabindHostBridge()
        let captured = Box<URL>()
        bridge.handlers.onOpenLink = { url in
            captured.value = url
            return true
        }
        let url = URL(string: "https://example.com/path")!
        try await bridge.openLink(url)
        #expect(captured.value?.absoluteString == "https://example.com/path")
    }

    @Test func openLinkThrowsWhenNoHandler() async {
        let bridge = MetabindHostBridge()
        await #expect(throws: MetabindHostError.self) {
            try await bridge.openLink(URL(string: "https://example.com")!)
        }
    }

    @Test func openLinkThrowsWhenHandlerRefuses() async {
        let bridge = MetabindHostBridge()
        bridge.handlers.onOpenLink = { _ in false }
        await #expect(throws: MetabindHostError.self) {
            try await bridge.openLink(URL(string: "https://example.com")!)
        }
    }

    // MARK: - requestDisplayMode

    @Test func requestDisplayModeParsesRawValue() async throws {
        let bridge = MetabindHostBridge()
        let captured = Box<MCPAppSession.DisplayMode>()
        bridge.handlers.onDisplayMode = { mode in
            captured.value = mode
            return .fullscreen
        }

        try await bridge.requestDisplayMode("fullscreen")
        #expect(captured.value == .fullscreen)
    }

    @Test func requestDisplayModeFallsBackToInlineForUnknown() async throws {
        let bridge = MetabindHostBridge()
        let captured = Box<MCPAppSession.DisplayMode>()
        bridge.handlers.onDisplayMode = { mode in
            captured.value = mode
            return mode
        }

        try await bridge.requestDisplayMode("bogus-mode")
        #expect(captured.value == .inline)
    }

    // MARK: - log

    @Test func logWithNoHandlerDoesNotCrash() {
        let bridge = MetabindHostBridge()
        bridge.log(level: "info", message: "hi", data: nil)
        bridge.log(level: "error", message: "boom", data: ["code": 500])
        bridge.log(level: "debug", message: "deep", data: nil)
        bridge.log(level: "unrecognized", message: "x", data: nil)
    }

    @Test func logWithHandlerForwards() async throws {
        let bridge = MetabindHostBridge()
        let captured = Box<(String, String, JSONValue?)>()
        bridge.handlers.onLog = { level, message, data in
            captured.value = (level, message, data)
        }
        bridge.log(level: "warning", message: "careful", data: ["k": "v"])

        // log() hops to main async, so wait a tick.
        try await Task.sleep(for: .milliseconds(50))
        let (level, message, data) = try #require(captured.value)
        #expect(level == "warning")
        #expect(message == "careful")
        if case .object(let dict) = data ?? .null {
            #expect(dict["k"] == .string("v"))
        } else {
            Issue.record("log data not object")
        }
    }

    // MARK: - iframe-only degradation

    @Test func iframeOnlyMethodsAreNoOps() async throws {
        let bridge = MetabindHostBridge()
        let send = try await bridge.sendRequest(method: "ui/foo", params: [:])
        #expect(send == nil)
        bridge.sendNotification(method: "ui/foo", params: [:])
        bridge.sizeChanged(height: 400)
    }
}

// MARK: - Box

/// Reference wrapper so sync closures can stash a value the test can read.
/// Safe because bridge handlers fire on the same actor (MainActor) as the
/// tests when called from `@MainActor`-isolated methods.
@MainActor
final class Box<Value> {
    var value: Value?
}
