import Foundation

/// A single write for `GCPFirestoreClient/commit(_:)`.
/// - SeeAlso: https://firebase.google.com/docs/firestore/reference/rest/v1/Write
public enum FirestoreWrite: Sendable {
    /// Creates or fully replaces a document.
    case set(collection: String, documentId: String, fields: [String: FirestoreValue])
    /// Creates a document; the commit fails with `GCPFirestoreError.alreadyExists` if it exists.
    case create(collection: String, documentId: String, fields: [String: FirestoreValue])
    /// Deletes a document. A missing document is a no-op.
    case delete(collection: String, documentId: String)
}

struct CommitRequest: Encodable {
    let writes: [FirestoreWrite.Wire]
}

extension FirestoreWrite {
    struct Wire: Encodable {
        struct Precondition: Encodable { let exists: Bool }
        struct Document: Encodable {
            let name: String
            let fields: [String: FirestoreValue]
        }
        var update: Document?
        var delete: String?
        var currentDocument: Precondition?
    }

    func wire(documentsPath: String) -> Wire {
        func name(_ collection: String, _ documentId: String) -> String {
            let encodedId = documentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? documentId
            return "\(documentsPath)/\(collection)/\(encodedId)"
        }
        switch self {
        case .set(let collection, let documentId, let fields):
            return Wire(update: .init(name: name(collection, documentId), fields: fields))
        case .create(let collection, let documentId, let fields):
            return Wire(
                update: .init(name: name(collection, documentId), fields: fields),
                currentDocument: .init(exists: false))
        case .delete(let collection, let documentId):
            return Wire(delete: name(collection, documentId))
        }
    }
}
