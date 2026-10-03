import Foundation

/// A JSON value: what the SDK keeps for payloads whose shape is open (message metadata, event data,
/// custom data, the raw wire objects).
///
/// Reading is lenient, like the gateway's other SDKs: `stringValue` turns numbers and booleans into text,
/// `intValue` reads numeric strings, and so on.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

/// A JSON object.
public typealias JSONObject = [String: JSONValue]

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        var o = JSONObject()
        for (k, v) in elements { o[k] = v }
        self = .object(o)
    }
}

// MARK: - Lenient accessors

extension JSONValue {
    /// True for `.null`.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// The object, or nil.
    public var objectValue: JSONObject? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// The array, or nil.
    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Strings as they are, numbers and booleans as text, arrays and objects as JSON; null is nil.
    public var stringValue: String? {
        switch self {
        case .null: return nil
        case .string(let s): return s
        case .number(let n): return JSONValue.numberText(n)
        case .bool(let b): return b ? "true" : "false"
        case .array, .object: return jsonText
        }
    }

    /// Only a real JSON string.
    public var strictString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Numbers (truncated) and numeric strings; booleans are nil.
    public var intValue: Int? {
        switch self {
        case .number(let n):
            guard n.isFinite, n >= Double(Int.min), n <= Double(Int.max) else { return nil }
            return Int(n)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// Numbers and numeric strings; booleans are nil.
    public var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// Only real JSON booleans.
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// The value at `key` when this is an object.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    static func numberText(_ n: Double) -> String {
        if n.isFinite, n == n.rounded(), abs(n) < 1e15 {
            return String(Int64(n))
        }
        return String(n)
    }
}

// MARK: - Text

extension JSONValue {
    /// Compact JSON text.
    public var jsonText: String {
        var out = ""
        write(to: &out)
        return out
    }

    private func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n.isFinite ? JSONValue.numberText(n) : "null"
        case .string(let s): JSONValue.writeString(s, to: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                v.write(to: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, k) in o.keys.sorted().enumerated() {
                if i > 0 { out += "," }
                JSONValue.writeString(k, to: &out)
                out += ":"
                o[k]!.write(to: &out)
            }
            out += "}"
        }
    }

    private static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    out += String(format: "\\u%04x", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }

    /// Parses JSON text; nil when it is not JSON.
    public static func parse(_ text: String) -> JSONValue? {
        parse(Data(text.utf8))
    }

    /// Parses JSON data; nil when it is not JSON.
    public static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n.isFinite, n == n.rounded(), abs(n) < 9e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Object helpers (internal)

extension Dictionary where Key == String, Value == JSONValue {
    func str(_ key: String) -> String? { self[key]?.stringValue }
    func strOr(_ key: String, _ fallback: String = "") -> String { str(key) ?? fallback }
    func int(_ key: String) -> Int? { self[key]?.intValue }
    func intOr(_ key: String, _ fallback: Int = 0) -> Int { int(key) ?? fallback }
    func num(_ key: String) -> Double? { self[key]?.doubleValue }
    func bool(_ key: String) -> Bool? { self[key]?.boolValue }
    func boolOr(_ key: String, _ fallback: Bool = false) -> Bool { bool(key) ?? fallback }
    func obj(_ key: String) -> JSONObject? { self[key]?.objectValue }
    func objList(_ key: String) -> [JSONObject] { (self[key]?.arrayValue ?? []).compactMap(\.objectValue) }
    func stringList(_ key: String) -> [String] { (self[key]?.arrayValue ?? []).compactMap(\.stringValue) }
    func stringMap(_ key: String) -> [String: String] { (obj(key) ?? [:]).compactMapValues(\.stringValue) }
    func date(_ key: String) -> Date? { self[key]?.strictString.flatMap(parseISODate) }
}

/// A JSON object from optional pairs: nil values are left out so optional fields stay absent on the wire.
func compact(_ pairs: (String, JSONValue?)...) -> JSONObject {
    var o = JSONObject()
    for (k, v) in pairs {
        guard let v, !v.isNull else { continue }
        o[k] = v
    }
    return o
}

extension Optional where Wrapped == String {
    var json: JSONValue? { map(JSONValue.string) }
}

extension String {
    var json: JSONValue { .string(self) }
}

extension Int {
    var json: JSONValue { .number(Double(self)) }
}

extension Bool {
    var json: JSONValue { .bool(self) }
}
