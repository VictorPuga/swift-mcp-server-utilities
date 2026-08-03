import Foundation

/// Mirrors Firestore's typed-field wire format for document values.
/// - SeeAlso: https://firebase.google.com/docs/firestore/reference/rest/v1/Value
public indirect enum FirestoreValue: Equatable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int)
    case double(Double)
    case string(String)
    case timestamp(String)
    case map([String: FirestoreValue])
    case array([FirestoreValue])

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var integerValue: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .double(let value) = self { return value }
        return nil
    }

    public var booleanValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    public var mapValue: [String: FirestoreValue]? {
        if case .map(let value) = self { return value }
        return nil
    }
}

extension FirestoreValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case nullValue
        case booleanValue
        case integerValue
        case doubleValue
        case stringValue
        case timestampValue
        case mapValue
        case arrayValue
    }

    private struct MapWrapper: Codable {
        var fields: [String: FirestoreValue]
    }

    private struct ArrayWrapper: Codable {
        var values: [FirestoreValue]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.nullValue) {
            self = .null
        } else if let value = try container.decodeIfPresent(Bool.self, forKey: .booleanValue) {
            self = .boolean(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .integerValue) {
            guard let intValue = Int(value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .integerValue, in: container, debugDescription: "Not an integer string: \(value)")
            }
            self = .integer(intValue)
        } else if let value = try container.decodeIfPresent(Double.self, forKey: .doubleValue) {
            self = .double(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .stringValue) {
            self = .string(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .timestampValue) {
            self = .timestamp(value)
        } else if let wrapper = try container.decodeIfPresent(MapWrapper.self, forKey: .mapValue) {
            self = .map(wrapper.fields)
        } else if let wrapper = try container.decodeIfPresent(ArrayWrapper.self, forKey: .arrayValue) {
            self = .array(wrapper.values)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(NullValue(), forKey: .nullValue)
        case .boolean(let value):
            try container.encode(value, forKey: .booleanValue)
        case .integer(let value):
            try container.encode(String(value), forKey: .integerValue)
        case .double(let value):
            try container.encode(value, forKey: .doubleValue)
        case .string(let value):
            try container.encode(value, forKey: .stringValue)
        case .timestamp(let value):
            try container.encode(value, forKey: .timestampValue)
        case .map(let value):
            try container.encode(MapWrapper(fields: value), forKey: .mapValue)
        case .array(let value):
            try container.encode(ArrayWrapper(values: value), forKey: .arrayValue)
        }
    }

    private struct NullValue: Codable {
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

/// A Firestore document as returned by / sent to the REST API.
/// - SeeAlso: https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents#Document
public struct FirestoreDocument: Codable, Sendable {
    public var name: String?
    public var fields: [String: FirestoreValue]
    public var createTime: String?
    public var updateTime: String?

    public init(name: String? = nil, fields: [String: FirestoreValue], createTime: String? = nil, updateTime: String? = nil) {
        self.name = name
        self.fields = fields
        self.createTime = createTime
        self.updateTime = updateTime
    }

    /// The last path component of `name`, i.e. the document ID. `nil` for documents not yet
    /// written (no `name` assigned by the server).
    public var documentID: String? {
        name?.split(separator: "/").last.map(String.init)
    }
}
