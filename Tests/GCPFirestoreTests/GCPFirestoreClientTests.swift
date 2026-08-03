import Foundation
import Testing

@testable import GCPFirestore

@Suite("GCPFirestoreClient")
struct GCPFirestoreClientTests {
    private static let tokenProvider = FakeTokenProvider(token: "test-access-token")

    @Test("getDocument GETs the document URL and decodes fields, propagating the bearer token")
    func getDocumentDecodesFields() async throws {
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "GET")
            #expect(
                request.url?.absoluteString.hasSuffix(
                    "/projects/my-project/databases/(default)/documents/devices/abc123") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
            return (200, Data("{\"name\":\"projects/my-project/databases/(default)/documents/devices/abc123\",\"fields\":{\"pushToken\":{\"stringValue\":\"tok\"}}}".utf8))
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let document = try await client.getDocument(collection: "devices", documentId: "abc123")
        #expect(document?.fields["pushToken"]?.stringValue == "tok")
        #expect(document?.documentID == "abc123")
    }

    @Test("getDocument returns nil on 404")
    func getDocumentReturnsNilOn404() async throws {
        let session = MockURLProtocol.makeSession { _ in (404, Data()) }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let document = try await client.getDocument(collection: "devices", documentId: "missing")
        #expect(document == nil)
    }

    @Test("getDocument throws requestFailed on other non-2xx statuses")
    func getDocumentThrowsOnOtherFailure() async throws {
        let session = MockURLProtocol.makeSession { _ in (500, Data("boom".utf8)) }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        await #expect(throws: GCPFirestoreError.self) {
            _ = try await client.getDocument(collection: "devices", documentId: "abc123")
        }
    }

    @Test("listDocuments sends pageSize/pageToken and decodes documents plus nextPageToken")
    func listDocumentsSendsPaginationParams() async throws {
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path.hasSuffix("/documents/devices") == true)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.contains(URLQueryItem(name: "pageSize", value: "50")))
            #expect(query.contains(URLQueryItem(name: "pageToken", value: "cursor-1")))
            return (
                200,
                Data(
                    """
                    {"documents":[{"name":"projects/p/databases/(default)/documents/devices/a","fields":{}}],
                     "nextPageToken":"cursor-2"}
                    """.utf8)
            )
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let page = try await client.listDocuments(collection: "devices", pageSize: 50, pageToken: "cursor-1")
        #expect(page.documents.map(\.documentID) == ["a"])
        #expect(page.nextPageToken == "cursor-2")
    }

    @Test("listDocuments omits query params when pageSize/pageToken aren't given")
    func listDocumentsOmitsParamsWhenNil() async throws {
        let session = MockURLProtocol.makeSession { request in
            #expect(request.url?.query == nil)
            return (200, Data("{}".utf8))
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let page = try await client.listDocuments(collection: "devices")
        #expect(page.documents.isEmpty)
        #expect(page.nextPageToken == nil)
    }

    @Test("patchDocument without updateMask PATCHes the full document with no query params")
    func patchDocumentFullReplace() async throws {
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.query == nil)
            #expect(
                request.url?.absoluteString.hasSuffix(
                    "/projects/my-project/databases/(default)/documents/devices/abc123") == true)
            return (200, Data("{\"fields\":{}}".utf8))
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        try await client.patchDocument(
            collection: "devices", documentId: "abc123", fields: ["pushToken": .string("tok")])
    }

    @Test("patchDocument with updateMask sends repeated updateMask.fieldPaths query items")
    func patchDocumentPartialUpdate() async throws {
        let session = MockURLProtocol.makeSession { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let paths = query.filter { $0.name == "updateMask.fieldPaths" }.map(\.value)
            #expect(paths == ["pushToken", "status"])
            return (200, Data("{\"fields\":{}}".utf8))
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        try await client.patchDocument(
            collection: "devices", documentId: "abc123",
            fields: ["pushToken": .string("tok")], updateMask: ["pushToken", "status"])
    }

    @Test("deleteDocument DELETEs the document URL")
    func deleteDocumentSendsDelete() async throws {
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "DELETE")
            return (200, Data())
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        try await client.deleteDocument(collection: "devices", documentId: "abc123")
    }

    @Test("deleteDocument treats 404 as a successful no-op")
    func deleteDocumentTreats404AsSuccess() async throws {
        let session = MockURLProtocol.makeSession { _ in (404, Data()) }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        try await client.deleteDocument(collection: "devices", documentId: "missing")
    }

    @Test("deleteDocument throws requestFailed on other non-2xx statuses")
    func deleteDocumentThrowsOnOtherFailure() async throws {
        let session = MockURLProtocol.makeSession { _ in (500, Data("boom".utf8)) }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        await #expect(throws: GCPFirestoreError.self) {
            try await client.deleteDocument(collection: "devices", documentId: "abc123")
        }
    }

    @Test("runQuery with no filters omits the where clause")
    func runQueryWithoutFiltersOmitsWhere() async throws {
        let capturedBody = Locked<Data?>(nil)
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString.hasSuffix("/documents:runQuery") == true)
            capturedBody.set(bodyData(of: request))
            return (200, Data("[]".utf8))
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let results = try await client.runQuery(collection: "devices")
        #expect(results.isEmpty)

        let body = try #require(capturedBody.value)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let structuredQuery = try #require(json["structuredQuery"] as? [String: Any])
        #expect(structuredQuery["where"] == nil)
    }

    @Test("runQuery with a single filter sends a fieldFilter")
    func runQueryWithSingleFilterSendsFieldFilter() async throws {
        let capturedBody = Locked<Data?>(nil)
        let session = MockURLProtocol.makeSession { request in
            capturedBody.set(bodyData(of: request))
            return (200, Data("[]".utf8))
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        _ = try await client.runQuery(
            collection: "devices",
            filters: [FirestoreQueryFilter(field: "status", op: .equal, value: .string("active"))])

        let body = try #require(capturedBody.value)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let structuredQuery = try #require(json["structuredQuery"] as? [String: Any])
        let whereClause = try #require(structuredQuery["where"] as? [String: Any])
        let fieldFilter = try #require(whereClause["fieldFilter"] as? [String: Any])
        #expect((fieldFilter["field"] as? [String: Any])?["fieldPath"] as? String == "status")
        #expect(fieldFilter["op"] as? String == "EQUAL")
    }

    @Test("runQuery with multiple filters combines them with an AND compositeFilter")
    func runQueryWithMultipleFiltersUsesCompositeFilter() async throws {
        let capturedBody = Locked<Data?>(nil)
        let session = MockURLProtocol.makeSession { request in
            capturedBody.set(bodyData(of: request))
            return (200, Data("[]".utf8))
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        _ = try await client.runQuery(
            collection: "devices",
            filters: [
                FirestoreQueryFilter(field: "status", op: .equal, value: .string("active")),
                FirestoreQueryFilter(field: "owner", op: .equal, value: .string("me")),
            ])

        let body = try #require(capturedBody.value)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let structuredQuery = try #require(json["structuredQuery"] as? [String: Any])
        let whereClause = try #require(structuredQuery["where"] as? [String: Any])
        let compositeFilter = try #require(whereClause["compositeFilter"] as? [String: Any])
        #expect(compositeFilter["op"] as? String == "AND")
        #expect((compositeFilter["filters"] as? [[String: Any]])?.count == 2)
    }

    @Test("runQuery drops response entries without a document (heartbeats)")
    func runQueryDropsEntriesWithoutDocument() async throws {
        let session = MockURLProtocol.makeSession { _ in
            (
                200,
                Data(
                    """
                    [
                        {"readTime":"2024-01-01T00:00:00Z"},
                        {"document":{"name":"projects/p/databases/(default)/documents/devices/a","fields":{}},"readTime":"2024-01-01T00:00:00Z"}
                    ]
                    """.utf8)
            )
        }
        let client = GCPFirestoreClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let results = try await client.runQuery(collection: "devices")
        #expect(results.map(\.documentID) == ["a"])
    }
}

/// Small `NSLock`-guarded box, since the mock handler closure is `@Sendable` and may be invoked
/// from a different isolation context than the test body.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { self._value = value }
    var value: Value { lock.withLock { _value } }
    func set(_ newValue: Value) { lock.withLock { _value = newValue } }
}
