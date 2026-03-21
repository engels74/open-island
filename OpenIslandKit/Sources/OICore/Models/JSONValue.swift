// MARK: - JSONValue

/// A recursive enum representing arbitrary JSON values.
///
/// Supports subscript chaining for ergonomic nested access:
/// ```swift
/// let name = json["data"]?["name"]?.stringValue
/// let first = json["items"]?[0]?.intValue
/// ```
public enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([Self])
    case object([String: Self])

    // MARK: Lifecycle

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        // Bool before numbers — JSON `true`/`false` must not be decoded as 1/0.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }

        // Int before Double — a JSON number like `42` should stay `.int`.
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }

        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }

        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        if let value = try? container.decode([Self].self) {
            self = .array(value)
            return
        }

        if let value = try? container.decode([String: Self].self) {
            self = .object(value)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "JSONValue cannot decode value",
        )
    }

    // MARK: Public

    public var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }

    public var intValue: Int? {
        if case let .int(v) = self { return v }
        return nil
    }

    public var doubleValue: Double? {
        if case let .double(v) = self { return v }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(v) = self { return v }
        return nil
    }

    public var arrayValue: [Self]? {
        if case let .array(v) = self { return v }
        return nil
    }

    public var objectValue: [String: Self]? {
        if case let .object(v) = self { return v }
        return nil
    }

    public var isNull: Bool {
        self == .null
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    // MARK: - Subscripts

    public subscript(key: String) -> Self? {
        if case let .object(dict) = self { return dict[key] }
        return nil
    }

    public subscript(index: Int) -> Self? {
        if case let .array(arr) = self, arr.indices.contains(index) { return arr[index] }
        return nil
    }
}

// MARK: ExpressibleByStringLiteral

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: ExpressibleByIntegerLiteral

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

// MARK: ExpressibleByFloatLiteral

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

// MARK: ExpressibleByBooleanLiteral

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

// MARK: ExpressibleByArrayLiteral

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

// MARK: ExpressibleByDictionaryLiteral

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: ExpressibleByNilLiteral

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}
