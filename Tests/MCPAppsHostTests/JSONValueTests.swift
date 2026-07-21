import Testing
import Foundation
@testable import MCPAppsHost

@Suite("JSONValue")
struct JSONValueTests {

    // MARK: - Literals

    @Test func stringLiteral() {
        let v: JSONValue = "hello"
        #expect(v == .string("hello"))
        #expect(v.stringValue == "hello")
    }

    @Test func intLiteral() {
        let v: JSONValue = 42
        #expect(v == .number(42))
        #expect(v.numberValue == 42)
    }

    @Test func floatLiteral() {
        let v: JSONValue = 3.14
        #expect(v.numberValue! - 3.14 < 0.001)
    }

    @Test func boolLiteral() {
        let v: JSONValue = true
        #expect(v == .bool(true))
        #expect(v.boolValue == true)
    }

    @Test func nilLiteral() {
        let v: JSONValue = nil
        #expect(v == .null)
        #expect(v.isNull)
    }

    @Test func arrayLiteral() {
        let v: JSONValue = ["a", "b", 3]
        #expect(v.arrayValue?.count == 3)
        #expect(v[0] == .string("a"))
        #expect(v[2] == .number(3))
    }

    @Test func dictionaryLiteral() {
        let v: JSONValue = ["name": "Claude", "version": 4]
        #expect(v["name"] == .string("Claude"))
        #expect(v["version"] == .number(4))
    }

    // MARK: - Codable

    @Test func roundTripJSON() throws {
        let original: JSONValue = [
            "string": "hello",
            "number": 42,
            "bool": true,
            "null": nil,
            "array": [1, 2, 3],
            "nested": ["deep": "value"]
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == original)
    }

    @Test func decodesFromRawJSON() throws {
        let json = """
        {"name": "test", "count": 5, "active": true, "tags": ["a", "b"]}
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(value["name"]?.stringValue == "test")
        #expect(value["count"]?.numberValue == 5)
        #expect(value["active"]?.boolValue == true)
        #expect(value["tags"]?.arrayValue?.count == 2)
    }

    // MARK: - Subscript safety

    @Test func subscriptOutOfBounds() {
        let v: JSONValue = [1, 2, 3]
        #expect(v[5] == nil)
    }

    @Test func subscriptWrongType() {
        let v: JSONValue = "not a dict"
        #expect(v["key"] == nil)
    }

    // MARK: - Any conversion

    @Test func fromDictionary() {
        let dict: [String: Any] = ["name": "test", "count": NSNumber(value: 5)]
        let value = JSONValue.from(dict)
        #expect(value["name"]?.stringValue == "test")
        #expect(value["count"]?.numberValue == 5)
    }

    @Test func toAny() {
        let value: JSONValue = ["name": "test", "count": 5]
        let any = value.toAny() as! [String: Any]
        #expect(any["name"] as? String == "test")
        #expect(any["count"] as? Double == 5)
    }

    @Test func boolVsNumberDistinction() {
        // NSNumber wraps both Bool and numbers. Ensure we distinguish.
        let dict: [String: Any] = ["flag": NSNumber(value: true), "count": NSNumber(value: 1)]
        let value = JSONValue.from(dict)
        #expect(value["flag"] == .bool(true))
        #expect(value["count"] == .number(1))
    }
}
