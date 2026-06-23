import Testing
import Foundation
@testable import MCPAppsHost

@Suite("MCPServer.callToolUnwrapped")
struct ServerUnwrapTests {

    final class StubServer: MCPServer, @unchecked Sendable {
        var nextResult: ToolResult = ToolResult(text: "default")

        func callTool(name: String, arguments: JSONValue) async throws -> ToolResult {
            nextResult
        }
        func readResource(uri: String) async throws -> ResourceContent {
            ResourceContent(uri: uri, mimeType: "text/plain", text: nil)
        }
        func listTools() async throws -> [MCPToolDefinition] { [] }
    }

    @Test func unwrapsJSONObjectFromText() async throws {
        let server = StubServer()
        server.nextResult = ToolResult(text: #"{"items": [], "total": 0}"#)

        let result = try await server.callToolUnwrapped(name: "x", arguments: .object([:]))

        let dict = try #require(result as? [String: Any])
        #expect((dict["items"] as? [Any])?.count == 0)
        #expect(dict["total"] as? Int == 0)
    }

    @Test func unwrapsJSONArrayFromText() async throws {
        let server = StubServer()
        server.nextResult = ToolResult(text: "[1, 2, 3]")

        let result = try await server.callToolUnwrapped(name: "x", arguments: .object([:]))

        let array = try #require(result as? [Any])
        #expect(array.count == 3)
        #expect(array[0] as? Int == 1)
    }

    @Test func returnsRawStringWhenNotJSON() async throws {
        let server = StubServer()
        server.nextResult = ToolResult(text: "just some plain text")

        let result = try await server.callToolUnwrapped(name: "x", arguments: .object([:]))
        #expect(result as? String == "just some plain text")
    }

    @Test func throwsOnIsError() async {
        let server = StubServer()
        server.nextResult = ToolResult(text: "upstream exploded", isError: true)

        await #expect(throws: MCPAppError.self) {
            _ = try await server.callToolUnwrapped(name: "x", arguments: .object([:]))
        }
    }

    @Test func errorDescriptionIncludesContent() async throws {
        let server = StubServer()
        server.nextResult = ToolResult(text: "boom: rate limited", isError: true)

        do {
            _ = try await server.callToolUnwrapped(name: "x", arguments: .object([:]))
            Issue.record("expected throw")
        } catch {
            let desc = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            #expect(desc.contains("rate limited"))
        }
    }

    @Test func returnsNilOnEmptyContent() async throws {
        let server = StubServer()
        server.nextResult = ToolResult(content: [])

        let result = try await server.callToolUnwrapped(name: "x", arguments: .object([:]))
        #expect(result == nil)
    }

    @Test func primitiveJSONRoundtrips() async throws {
        let server = StubServer()

        server.nextResult = ToolResult(text: "42")
        let num = try await server.callToolUnwrapped(name: "x", arguments: .object([:]))
        #expect(num as? Int == 42)

        server.nextResult = ToolResult(text: "true")
        let bool = try await server.callToolUnwrapped(name: "x", arguments: .object([:]))
        #expect(bool as? Bool == true)
    }
}
