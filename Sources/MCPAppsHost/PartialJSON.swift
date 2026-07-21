import Foundation

/// Tolerant parser for the incomplete JSON that arrives while an LLM streams a
/// tool call's arguments.
///
/// Anthropic (and OpenAI) emit tool input as `partial_json` fragments averaging
/// ~7 characters; the *accumulated* buffer is strict-valid JSON only at the
/// final token. A strict `JSONSerialization` parse therefore recovers a value
/// exactly once — at completion — so a rendered tool UI snaps in fully formed
/// instead of filling in as the model types. `PartialJSON.parse` returns the
/// largest well-formed `JSONValue` recoverable from a partial buffer, so the
/// view can update at most fragment boundaries.
///
/// Policy, chosen for progressive-render UX:
/// - A trailing **string** still being typed is included up to its last fully
///   decoded character (so prose "types in"). An incomplete escape at the very
///   end (`"…\` or `"…\u12`) is dropped rather than emitted as invalid content.
/// - A trailing **number** or **literal** (`true`/`false`/`null`) not yet
///   followed by a delimiter is dropped — a half-typed `19` must not flash
///   before it grows into `195`. The object key or array element that owns it
///   is omitted until the token completes.
/// - Object **keys** are only honored once their string has closed and a `:`
///   follows; a key still being typed contributes nothing.
/// - Unclosed objects and arrays are closed implicitly.
public enum PartialJSON {

    /// Parse a (possibly incomplete) JSON document. Returns nil when nothing
    /// usable has arrived yet (empty/whitespace buffer, or a bare incomplete
    /// scalar token at the top level).
    public static func parse(_ string: String) -> JSONValue? {
        var parser = Parser(scalars: Array(string.unicodeScalars))
        parser.skipWhitespace()
        return parser.parseValue()
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var i = 0

        var atEnd: Bool { i >= scalars.count }
        func peek() -> Unicode.Scalar? { atEnd ? nil : scalars[i] }

        mutating func skipWhitespace() {
            while let c = peek(), c == " " || c == "\t" || c == "\n" || c == "\r" {
                i += 1
            }
        }

        /// Parse a value at the cursor. Returns nil when the token is incomplete
        /// and policy drops it (trailing number/literal/empty), or when the
        /// input is malformed at this position.
        mutating func parseValue() -> JSONValue? {
            skipWhitespace()
            guard let c = peek() else { return nil }
            switch c {
            case "{": return parseObject()
            case "[": return parseArray()
            case "\"":
                // A value string is included even if still open (partial-inclusive).
                guard let s = parseStringRaw() else { return nil }
                return .string(s.value)
            case "t": return parseKeyword("true", .bool(true))
            case "f": return parseKeyword("false", .bool(false))
            case "n": return parseKeyword("null", .null)
            case "-", "0"..."9": return parseNumber()
            default: return nil
            }
        }

        // MARK: Object / Array

        mutating func parseObject() -> JSONValue? {
            i += 1 // consume '{'
            var dict: [String: JSONValue] = [:]
            while true {
                skipWhitespace()
                guard let c = peek() else { break }       // implicit close at EOF
                if c == "}" { i += 1; break }
                if c == "," { i += 1; continue }          // tolerate stray/leading comma
                guard c == "\"" else { break }            // a key must be a string
                guard let key = parseStringRaw() else { break }
                // The key must have closed *and* be followed by ':' to be real;
                // a key still being typed has no value yet → drop it and stop.
                guard key.closed else { break }
                skipWhitespace()
                guard peek() == ":" else { break }
                i += 1 // consume ':'
                guard let value = parseValue() else { break } // incomplete value → stop
                dict[key.value] = value
            }
            return .object(dict)
        }

        mutating func parseArray() -> JSONValue? {
            i += 1 // consume '['
            var arr: [JSONValue] = []
            while true {
                skipWhitespace()
                guard let c = peek() else { break }       // implicit close at EOF
                if c == "]" { i += 1; break }
                if c == "," { i += 1; continue }
                guard let value = parseValue() else { break } // incomplete element → stop
                arr.append(value)
            }
            return .array(arr)
        }

        // MARK: Scalars

        /// A trailing number is dropped unless a delimiter proves it complete:
        /// `19` at EOF may still grow into `195`, and `-` / `1.` / `1e` are not
        /// yet valid. A following `,]}` or whitespace means the token is done.
        mutating func parseNumber() -> JSONValue? {
            let start = i
            if peek() == "-" { i += 1 }
            while let c = peek(), ("0"..."9").contains(c) { i += 1 }
            if peek() == "." {
                i += 1
                while let c = peek(), ("0"..."9").contains(c) { i += 1 }
            }
            if let c = peek(), c == "e" || c == "E" {
                i += 1
                if let s = peek(), s == "+" || s == "-" { i += 1 }
                while let c = peek(), ("0"..."9").contains(c) { i += 1 }
            }
            // Ran to EOF with no terminating delimiter → still being typed.
            if atEnd { return nil }
            let text = String(String.UnicodeScalarView(scalars[start..<i]))
            guard let d = Double(text) else { return nil }
            return .number(d)
        }

        /// Match a complete keyword. An incomplete prefix (`tr` at EOF) or a
        /// mismatch is dropped.
        mutating func parseKeyword(_ word: String, _ value: JSONValue) -> JSONValue? {
            let chars = Array(word.unicodeScalars)
            guard i + chars.count <= scalars.count else { return nil }
            for (k, ch) in chars.enumerated() where scalars[i + k] != ch { return nil }
            i += chars.count
            return value
        }

        // MARK: Strings

        struct ParsedString { let value: String; let closed: Bool }

        /// Parse a string starting at the opening quote. `closed` reports whether
        /// the terminating quote was seen. A trailing incomplete escape is
        /// dropped (its partial bytes are not emitted) and leaves `closed` false.
        mutating func parseStringRaw() -> ParsedString? {
            guard peek() == "\"" else { return nil }
            i += 1 // opening quote
            var out = ""
            while let c = peek() {
                if c == "\"" {
                    i += 1
                    return ParsedString(value: out, closed: true)
                }
                if c == "\\" {
                    i += 1 // consume backslash
                    guard let e = peek() else {
                        return ParsedString(value: out, closed: false) // lone trailing '\'
                    }
                    switch e {
                    case "\"": out.append("\""); i += 1
                    case "\\": out.append("\\"); i += 1
                    case "/": out.append("/"); i += 1
                    case "b": out.append("\u{08}"); i += 1
                    case "f": out.append("\u{0C}"); i += 1
                    case "n": out.append("\n"); i += 1
                    case "r": out.append("\r"); i += 1
                    case "t": out.append("\t"); i += 1
                    case "u":
                        i += 1 // consume 'u'
                        guard let scalar = readUnicodeEscape() else {
                            return ParsedString(value: out, closed: false) // truncated \uXXXX
                        }
                        out.unicodeScalars.append(scalar)
                    default:
                        out.unicodeScalars.append(e); i += 1 // lenient: pass unknown escape through
                    }
                    continue
                }
                out.unicodeScalars.append(c)
                i += 1
            }
            return ParsedString(value: out, closed: false) // EOF before closing quote
        }

        /// Read a `\uXXXX` escape (the `\u` already consumed), combining a
        /// surrogate pair when present. Returns nil if the four hex digits — or
        /// a high surrogate's trailing low half — have not fully arrived yet.
        mutating func readUnicodeEscape() -> Unicode.Scalar? {
            guard let u = readHex4() else { return nil }
            if (0xD800...0xDBFF).contains(u) {
                // High surrogate: need a following \uXXXX low surrogate.
                guard i + 1 < scalars.count, scalars[i] == "\\", scalars[i + 1] == "u" else {
                    if atEnd || (i < scalars.count && scalars[i] == "\\") {
                        return nil // low half not here yet → wait
                    }
                    return Unicode.Scalar(0xFFFD) // lone high surrogate, won't be paired
                }
                let save = i
                i += 2
                guard let low = readHex4() else { i = save; return nil }
                guard (0xDC00...0xDFFF).contains(low) else { return Unicode.Scalar(0xFFFD) }
                let combined = 0x10000 + ((u - 0xD800) << 10) + (low - 0xDC00)
                return Unicode.Scalar(combined) ?? Unicode.Scalar(0xFFFD)!
            }
            return Unicode.Scalar(u) ?? Unicode.Scalar(0xFFFD)!
        }

        /// Read exactly four hex digits. Returns nil if fewer remain or a
        /// non-hex digit appears.
        mutating func readHex4() -> UInt32? {
            guard i + 4 <= scalars.count else { return nil }
            var v: UInt32 = 0
            for k in 0..<4 {
                guard let d = hexValue(scalars[i + k]) else { return nil }
                v = (v << 4) | d
            }
            i += 4
            return v
        }

        func hexValue(_ s: Unicode.Scalar) -> UInt32? {
            switch s {
            case "0"..."9": return s.value - 48
            case "a"..."f": return s.value - 87
            case "A"..."F": return s.value - 55
            default: return nil
            }
        }
    }
}
