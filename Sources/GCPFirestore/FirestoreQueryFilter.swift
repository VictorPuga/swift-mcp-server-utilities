import Foundation

/// A single field comparison for `GCPFirestoreClient/runQuery`.
/// - SeeAlso: https://firebase.google.com/docs/firestore/reference/rest/v1/StructuredQuery.FieldFilter
public struct FirestoreQueryFilter: Sendable {
    public enum Operator: String, Sendable {
        case equal = "EQUAL"
        case notEqual = "NOT_EQUAL"
        case lessThan = "LESS_THAN"
        case lessThanOrEqual = "LESS_THAN_OR_EQUAL"
        case greaterThan = "GREATER_THAN"
        case greaterThanOrEqual = "GREATER_THAN_OR_EQUAL"
        case arrayContains = "ARRAY_CONTAINS"
        case arrayContainsAny = "ARRAY_CONTAINS_ANY"
        case `in` = "IN"
        case notIn = "NOT_IN"
    }

    public let field: String
    public let op: Operator
    public let value: FirestoreValue

    public init(field: String, op: Operator, value: FirestoreValue) {
        self.field = field
        self.op = op
        self.value = value
    }
}

extension FirestoreQueryFilter {
    struct Wire: Encodable {
        struct FieldFilter: Encodable {
            struct FieldReference: Encodable { let fieldPath: String }
            let field: FieldReference
            let op: String
            let value: FirestoreValue
        }
        let fieldFilter: FieldFilter
    }

    var wire: Wire {
        Wire(fieldFilter: .init(field: .init(fieldPath: field), op: op.rawValue, value: value))
    }
}
