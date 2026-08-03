import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import GoogleCloudAuth

public enum GCPFirestoreError: Error, Sendable {
    case requestFailed(status: Int, body: String)
}

/// A page of documents returned by `GCPFirestoreClient/listDocuments`.
public struct DocumentPage: Sendable {
    public let documents: [FirestoreDocument]
    public let nextPageToken: String?
}

/// Minimal REST client over Google Cloud Firestore (v1, not the deprecated v1beta1). Generic over
/// project, database, and collection — no collection names or document shapes are hardcoded, so
/// the same client works for any Firestore-backed collection.
/// - SeeAlso: https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents
public struct GCPFirestoreClient: Sendable {
    private let projectId: String
    private let databaseId: String
    private let tokenProvider: any GoogleAccessTokenProvider
    private let urlSession: URLSession

    private var documentsURL: URL {
        URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(databaseId)/documents")!
    }

    public init(
        projectId: String,
        databaseId: String = "(default)",
        tokenProvider: any GoogleAccessTokenProvider,
        urlSession: URLSession = .shared
    ) {
        self.projectId = projectId
        self.databaseId = databaseId
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
    }

    /// Returns `nil` if the document doesn't exist.
    public func getDocument(collection: String, documentId: String) async throws -> FirestoreDocument? {
        let url = documentURL(collection: collection, documentId: documentId)
        let (data, response) = try await send(url: url, method: "GET", body: nil)
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else {
            throw GCPFirestoreError.requestFailed(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(FirestoreDocument.self, from: data)
    }

    /// Lists documents in `collection`, following Firestore's `pageSize`/`pageToken` pagination.
    public func listDocuments(
        collection: String, pageSize: Int? = nil, pageToken: String? = nil
    ) async throws -> DocumentPage {
        var components = URLComponents(
            url: documentsURL.appendingPathComponent(collection), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let pageSize { queryItems.append(URLQueryItem(name: "pageSize", value: String(pageSize))) }
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        let (data, response) = try await send(url: components.url!, method: "GET", body: nil)
        guard (200..<300).contains(response.statusCode) else {
            throw GCPFirestoreError.requestFailed(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        struct ListResponse: Decodable {
            var documents: [FirestoreDocument]?
            var nextPageToken: String?
        }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        return DocumentPage(documents: decoded.documents ?? [], nextPageToken: decoded.nextPageToken)
    }

    /// Creates or updates a document. When `updateMask` is `nil`, this is a full document replace
    /// (fields not present in `fields` are removed). When `updateMask` is provided, only the named
    /// field paths are touched, leaving the rest of the existing document unchanged.
    @discardableResult
    public func patchDocument(
        collection: String, documentId: String,
        fields: [String: FirestoreValue], updateMask: [String]? = nil
    ) async throws -> FirestoreDocument {
        var components = URLComponents(
            url: documentURL(collection: collection, documentId: documentId), resolvingAgainstBaseURL: false)!
        if let updateMask {
            components.queryItems = updateMask.map { URLQueryItem(name: "updateMask.fieldPaths", value: $0) }
        }

        let body = try JSONEncoder().encode(FirestoreDocument(fields: fields))
        let (data, response) = try await send(url: components.url!, method: "PATCH", body: body)
        guard (200..<300).contains(response.statusCode) else {
            throw GCPFirestoreError.requestFailed(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(FirestoreDocument.self, from: data)
    }

    /// Idempotent: a missing document is treated as a successful delete.
    public func deleteDocument(collection: String, documentId: String) async throws {
        let url = documentURL(collection: collection, documentId: documentId)
        let (data, response) = try await send(url: url, method: "DELETE", body: nil)
        guard (200..<300).contains(response.statusCode) || response.statusCode == 404 else {
            throw GCPFirestoreError.requestFailed(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }

    /// Runs a structured query against `collection`. Multiple `filters` are combined with `AND`.
    public func runQuery(
        collection: String, filters: [FirestoreQueryFilter] = [], limit: Int? = nil
    ) async throws -> [FirestoreDocument] {
        struct From: Encodable { let collectionId: String }
        struct CompositeFilter: Encodable {
            struct AnyFilter: Encodable {
                let fieldFilter: FirestoreQueryFilter.Wire.FieldFilter
            }
            let op: String
            let filters: [AnyFilter]
        }
        struct Where: Encodable {
            var fieldFilter: FirestoreQueryFilter.Wire.FieldFilter?
            var compositeFilter: CompositeFilter?
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(fieldFilter, forKey: .fieldFilter)
                try container.encodeIfPresent(compositeFilter, forKey: .compositeFilter)
            }
            enum CodingKeys: String, CodingKey { case fieldFilter, compositeFilter }
        }
        struct StructuredQuery: Encodable {
            let from: [From]
            let `where`: Where?
            let limit: Int?
        }
        struct RunQueryRequest: Encodable { let structuredQuery: StructuredQuery }

        let whereClause: Where?
        switch filters.count {
        case 0:
            whereClause = nil
        case 1:
            whereClause = Where(fieldFilter: filters[0].wire.fieldFilter, compositeFilter: nil)
        default:
            whereClause = Where(
                fieldFilter: nil,
                compositeFilter: CompositeFilter(
                    op: "AND", filters: filters.map { .init(fieldFilter: $0.wire.fieldFilter) }))
        }

        let request = RunQueryRequest(
            structuredQuery: StructuredQuery(from: [From(collectionId: collection)], where: whereClause, limit: limit))
        let body = try JSONEncoder().encode(request)

        let url = URL(string: documentsURL.absoluteString + ":runQuery")!
        let (data, response) = try await send(url: url, method: "POST", body: body)
        guard (200..<300).contains(response.statusCode) else {
            throw GCPFirestoreError.requestFailed(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        struct RunQueryResponse: Decodable { var document: FirestoreDocument? }
        return try JSONDecoder().decode([RunQueryResponse].self, from: data).compactMap(\.document)
    }

    private func documentURL(collection: String, documentId: String) -> URL {
        let encodedId = documentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? documentId
        return documentsURL.appendingPathComponent(collection).appendingPathComponent(encodedId)
    }

    private func send(url: URL, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let accessToken = try await tokenProvider.accessToken()
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GCPFirestoreError.requestFailed(status: -1, body: String(decoding: data, as: UTF8.self))
        }
        return (data, http)
    }
}
