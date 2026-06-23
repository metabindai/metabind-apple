import Testing
import Foundation
@testable import MCPAppsHost

@Suite("PartialJSON")
struct PartialJSONTests {

    // MARK: - Empty / trivial

    @Test func emptyBufferYieldsNil() {
        #expect(PartialJSON.parse("") == nil)
        #expect(PartialJSON.parse("   ") == nil)
    }

    @Test func completeObjectMatchesStrict() {
        let json = #"{"a":1,"b":"two","c":[true,null]}"#
        #expect(PartialJSON.parse(json) == strict(json))
    }

    // MARK: - Trailing-string policy (include up to last decoded char)

    @Test func partialStringValueIsIncluded() {
        // A value string still being typed should "type in".
        #expect(PartialJSON.parse(#"{"city":"Pari"#) == .object(["city": .string("Pari")]))
        #expect(PartialJSON.parse(#"{"city":""#) == .object(["city": .string("")]))
    }

    @Test func partialKeyIsDropped() {
        // A key with no closing quote / no colon yet contributes nothing.
        #expect(PartialJSON.parse(#"{"city":"Paris","temp"#) == .object(["city": .string("Paris")]))
        #expect(PartialJSON.parse(#"{"city":"Paris","temperature""#) == .object(["city": .string("Paris")]))
        #expect(PartialJSON.parse(#"{"city":"Paris","temperature":"#) == .object(["city": .string("Paris")]))
    }

    // MARK: - Trailing-number / literal policy (drop until a delimiter proves complete)

    @Test func trailingNumberWithoutDelimiterIsDropped() {
        // `15` could still grow into `150` — drop until a delimiter arrives.
        #expect(PartialJSON.parse(#"{"temperature":15"#) == .object([:]))
        #expect(PartialJSON.parse(#"{"temperature":15,"#) == .object(["temperature": .number(15)]))
        #expect(PartialJSON.parse(#"{"temperature":15}"#) == .object(["temperature": .number(15)]))
    }

    @Test func incompleteNumberTokensAreDropped() {
        #expect(PartialJSON.parse(#"{"x":-"#) == .object([:]))
        #expect(PartialJSON.parse(#"{"x":1."#) == .object([:]))
        #expect(PartialJSON.parse(#"{"x":1e"#) == .object([:]))
    }

    @Test func trailingLiteralPrefixIsDropped() {
        #expect(PartialJSON.parse(#"{"ok":tr"#) == .object([:]))
        // A fully-spelled literal is complete even without a delimiter — unlike a
        // number, nothing valid extends `true`.
        #expect(PartialJSON.parse(#"{"ok":true"#) == .object(["ok": .bool(true)]))
        #expect(PartialJSON.parse(#"{"ok":true}"#) == .object(["ok": .bool(true)]))
        #expect(PartialJSON.parse(#"{"v":nul"#) == .object([:]))
    }

    // MARK: - Arrays

    @Test func trailingArrayNumberIsDropped() {
        #expect(PartialJSON.parse("[1, 2, 3") == .array([.number(1), .number(2)]))
        #expect(PartialJSON.parse("[1, 2, 3]") == .array([.number(1), .number(2), .number(3)]))
    }

    @Test func partialObjectInArrayIsIncluded() {
        let buf = #"[{"time":"12:00 PM","temp":14,"icon":"par"#
        #expect(PartialJSON.parse(buf) == .array([
            .object(["time": .string("12:00 PM"), "temp": .number(14), "icon": .string("par")])
        ]))
    }

    // MARK: - Implicit close of nested containers

    @Test func nestedContainersCloseImplicitly() {
        let buf = #"{"a":{"b":["x","y"#
        #expect(PartialJSON.parse(buf) == .object(["a": .object(["b": .array([.string("x"), .string("y")])])]))
    }

    // MARK: - Escapes

    @Test func truncatedUnicodeEscapeIsDropped() {
        // `\u12` is incomplete; emit the string content before it, not invalid JSON.
        #expect(PartialJSON.parse(#"{"a":"x\u12"#) == .object(["a": .string("x")]))
        #expect(PartialJSON.parse(##"{"a":"x\"##) == .object(["a": .string("x")]))  // lone trailing backslash
    }

    @Test func standardEscapesDecode() {
        #expect(PartialJSON.parse(#"{"a":"line\nbreak\t\"q\""}"#)
                == .object(["a": .string("line\nbreak\t\"q\"")]))
    }

    @Test func completeSurrogatePairDecodes() {
        // 🌤 == U+1F324 🌤
        #expect(PartialJSON.parse(#""🌤""#) == .string("\u{1F324}"))
    }

    @Test func splitSurrogateHighHalfWaits() {
        // High surrogate with the low half not yet arrived → empty (no garbage).
        #expect(PartialJSON.parse(#""\uD83C"#) == .string(""))
    }

    // MARK: - Replay of a real Anthropic capture

    /// 52 `partial_json` fragments captured from claude-haiku-4-5 for a
    /// `render_weather_card` tool call (Paris, 4-hour forecast, with emoji).
    /// Joined length 360. The emoji 🌤️ (U+1F324 U+FE0F) is split across the
    /// fragment-37/38 boundary at the scalar level — exercising the partial
    /// multibyte-string path.
    static let capturedFragments: [String] = [
        "", "{\"", "cont", "ent\": {", "\"city\":\"Pari", "s\",\"countr",
        "y\":\"Franc", "e\",\"te", "mpe", "rature\":15,\"", "conditi", "on",
        "s\":\"Partly C", "loudy\",\"s", "umma", "ry\":\"Expec", "t m",
        "ild tempera", "tu", "res w", "ith partly c", "loudy s", "ki",
        "es thr", "ough", "ou", "t ", "the afterno", "on.\",\"", "hourly\"",
        ":[{\"time\":\"", "12:00", " PM\",\"temp\":", "14", ",\"icon\":\"🌤",
        "️\"},{\"ti", "me", "\":\"1:00 PM\"", ",\"temp\"", ":15,\"icon\":\"",
        "🌤️", "\"},{\"t", "im", "e\":\"2:0", "0 PM\",\"temp\"", ":16,\"icon",
        "\":\"⛅\"},{\"t", "ime\":\"3:", "00 PM\",\"tem", "p\":15,\"i",
        "con\":\"🌤️\"", "}]}}",
    ]

    @Test func replayProducesProgressiveParsesEndingAtStrict() {
        var buffer = ""
        var successfulParses = 0
        var sawCity = false
        var sawHourlyGrowing = false
        var lastHourlyCount = 0

        for fragment in Self.capturedFragments {
            buffer += fragment
            guard let value = PartialJSON.parse(buffer) else { continue }
            successfulParses += 1

            // Unwrap the BYOK `content` envelope used by this tool shape.
            let content = value["content"] ?? value
            if content["city"] == .string("Paris") { sawCity = true }
            if case .array(let hourly)? = content["hourly"] {
                if hourly.count >= lastHourlyCount { sawHourlyGrowing = true }
                lastHourlyCount = hourly.count
            }
        }

        // A strict parse would have succeeded exactly once (final token only);
        // the tolerant parse must update many times for progressive rendering.
        #expect(successfulParses > 10)
        #expect(sawCity)
        #expect(sawHourlyGrowing)

        // The final buffer is complete JSON; tolerant must equal strict.
        let full = Self.capturedFragments.joined()
        #expect(PartialJSON.parse(full) == strict(full))
        #expect(lastHourlyCount == 4)
    }

    @Test func strictWouldSucceedOnlyOnceAcrossReplay() {
        // Establishes the baseline this feature exists to fix: across the whole
        // capture, the accumulated buffer is strict-valid JSON exactly once.
        var buffer = ""
        var strictSuccesses = 0
        for fragment in Self.capturedFragments {
            buffer += fragment
            if let data = buffer.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                strictSuccesses += 1
            }
        }
        #expect(strictSuccesses == 1)
    }

    // MARK: - Helper

    /// Strict reference parse for equality assertions.
    private func strict(_ s: String) -> JSONValue {
        let data = s.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSONValue.from(obj)
    }
}
