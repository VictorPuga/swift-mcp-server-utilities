import Foundation
import Testing

@testable import GCPFirestore

@Suite("FirestoreValue")
struct FirestoreValueTests {
    @Test("decodes and re-encodes every wire kind", arguments: [
        (Data("{\"nullValue\":null}".utf8), FirestoreValue.null),
        (Data("{\"booleanValue\":true}".utf8), FirestoreValue.boolean(true)),
        (Data("{\"integerValue\":\"42\"}".utf8), FirestoreValue.integer(42)),
        (Data("{\"doubleValue\":3.5}".utf8), FirestoreValue.double(3.5)),
        (Data("{\"stringValue\":\"hi\"}".utf8), FirestoreValue.string("hi")),
        (Data("{\"timestampValue\":\"2024-01-01T00:00:00Z\"}".utf8), FirestoreValue.timestamp("2024-01-01T00:00:00Z")),
    ])
    func decodesEachScalarKind(json: Data, expected: FirestoreValue) throws {
        let decoded = try JSONDecoder().decode(FirestoreValue.self, from: json)
        #expect(decoded == expected)

        let reencoded = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(FirestoreValue.self, from: reencoded)
        #expect(roundTripped == expected)
    }

    @Test("round-trips a nested map value")
    func roundTripsNestedMap() throws {
        let value = FirestoreValue.map([
            "name": .string("device-1"),
            "active": .boolean(true),
            "meta": .map(["count": .integer(3)]),
        ])
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(FirestoreValue.self, from: encoded)
        #expect(decoded == value)
    }

    @Test("round-trips an array value")
    func roundTripsArray() throws {
        let value = FirestoreValue.array([.string("a"), .integer(1), .boolean(false)])
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(FirestoreValue.self, from: encoded)
        #expect(decoded == value)
    }

    @Test("FirestoreDocument.documentID reads the last path component of name")
    func documentIDReadsLastPathComponent() {
        let document = FirestoreDocument(
            name: "projects/p/databases/(default)/documents/devices/abc123", fields: [:])
        #expect(document.documentID == "abc123")
    }

    @Test("FirestoreDocument.documentID is nil when name is nil")
    func documentIDIsNilWithoutName() {
        let document = FirestoreDocument(fields: [:])
        #expect(document.documentID == nil)
    }
}
