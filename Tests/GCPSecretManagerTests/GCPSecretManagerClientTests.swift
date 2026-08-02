import Foundation
import Testing

@testable import GCPSecretManager

@Suite("GCPSecretManagerClient")
struct GCPSecretManagerClientTests {
    private static let tokenProvider = FakeTokenProvider(token: "test-access-token")

    @Test("accessLatestSecretVersion decodes and base64-decodes the payload on 200")
    func accessReturnsDecodedPayload() async throws {
        let secretValue = "a-refresh-token"
        let session = MockURLProtocol.makeSession { request in
            #expect(request.url?.absoluteString.hasSuffix("/secrets/my-secret/versions/latest:access") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
            let base64 = Data(secretValue.utf8).base64EncodedString()
            return (200, Data("{\"payload\":{\"data\":\"\(base64)\"}}".utf8))
        }
        let client = GCPSecretManagerClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let result = try await client.accessLatestSecretVersion(secretId: "my-secret")
        #expect(result.map { String(decoding: $0, as: UTF8.self) } == secretValue)
    }

    @Test("accessLatestSecretVersion returns nil on 404 (no versions yet)")
    func accessReturnsNilOn404() async throws {
        let session = MockURLProtocol.makeSession { _ in (404, Data()) }
        let client = GCPSecretManagerClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let result = try await client.accessLatestSecretVersion(secretId: "my-secret")
        #expect(result == nil)
    }

    @Test("accessLatestSecretVersion throws requestFailed on other non-2xx statuses")
    func accessThrowsOnOtherFailure() async throws {
        let session = MockURLProtocol.makeSession { _ in (500, Data("boom".utf8)) }
        let client = GCPSecretManagerClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        await #expect(throws: GCPSecretManagerError.self) {
            _ = try await client.accessLatestSecretVersion(secretId: "my-secret")
        }
    }

    @Test("addSecretVersion POSTs base64-encoded payload to :addVersion and returns the new version's name")
    func addSecretVersionPostsPayload() async throws {
        let capturedBody = Locked<Data?>(nil)
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString.hasSuffix("/secrets/my-secret:addVersion") == true)
            capturedBody.set(bodyData(of: request))
            return (200, Data("{\"name\":\"projects/my-project/secrets/my-secret/versions/3\",\"state\":\"ENABLED\"}".utf8))
        }
        let client = GCPSecretManagerClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let versionName = try await client.addSecretVersion(secretId: "my-secret", payload: Data("new-refresh-token".utf8))
        #expect(versionName == "projects/my-project/secrets/my-secret/versions/3")

        struct Body: Decodable { struct Payload: Decodable { let data: String }; let payload: Payload }
        let body = try #require(capturedBody.value)
        let decoded = try JSONDecoder().decode(Body.self, from: body)
        #expect(Data(base64Encoded: decoded.payload.data).map { String(decoding: $0, as: UTF8.self) } == "new-refresh-token")
    }

    @Test("addSecretVersion throws secretNotFound on 404 (secret not precreated)")
    func addSecretVersionThrowsNotFoundOn404() async throws {
        let session = MockURLProtocol.makeSession { _ in (404, Data()) }
        let client = GCPSecretManagerClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        await #expect(throws: GCPSecretManagerError.self) {
            _ = try await client.addSecretVersion(secretId: "missing-secret", payload: Data("x".utf8))
        }
    }

    @Test("listSecretVersions GETs with the given filter and decodes versions")
    func listSecretVersionsDecodesVersions() async throws {
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path.hasSuffix("/secrets/my-secret/versions") == true)
            #expect(request.url?.query?.contains("filter=state:ENABLED") == true)
            return (
                200,
                Data(
                    """
                    {"versions":[
                        {"name":"projects/my-project/secrets/my-secret/versions/2","state":"ENABLED"},
                        {"name":"projects/my-project/secrets/my-secret/versions/3","state":"ENABLED"}
                    ]}
                    """.utf8)
            )
        }
        let client = GCPSecretManagerClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        let versions = try await client.listSecretVersions(secretId: "my-secret", filter: "state:ENABLED")
        #expect(versions.map(\.name) == [
            "projects/my-project/secrets/my-secret/versions/2",
            "projects/my-project/secrets/my-secret/versions/3",
        ])
    }

    @Test("disableSecretVersion POSTs to the version's :disable endpoint")
    func disableSecretVersionPosts() async throws {
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "POST")
            #expect(
                request.url?.absoluteString.hasSuffix(
                    "/projects/my-project/secrets/my-secret/versions/2:disable") == true)
            return (200, Data("{}".utf8))
        }
        let client = GCPSecretManagerClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        try await client.disableSecretVersion("projects/my-project/secrets/my-secret/versions/2")
    }

    @Test("disableOtherEnabledVersions disables every enabled version except the kept one")
    func disableOtherEnabledVersionsSkipsKeptVersion() async throws {
        let disabledVersions = Locked<[String]>([])
        let session = MockURLProtocol.makeSession { request in
            if request.url?.absoluteString.hasSuffix(":disable") == true {
                disabledVersions.set(disabledVersions.value + [request.url!.absoluteString])
                return (200, Data("{}".utf8))
            }
            return (
                200,
                Data(
                    """
                    {"versions":[
                        {"name":"projects/my-project/secrets/my-secret/versions/1","state":"ENABLED"},
                        {"name":"projects/my-project/secrets/my-secret/versions/2","state":"ENABLED"},
                        {"name":"projects/my-project/secrets/my-secret/versions/3","state":"ENABLED"}
                    ]}
                    """.utf8)
            )
        }
        let client = GCPSecretManagerClient(projectId: "my-project", tokenProvider: Self.tokenProvider, urlSession: session)

        try await client.disableOtherEnabledVersions(
            secretId: "my-secret", keeping: "projects/my-project/secrets/my-secret/versions/3")

        #expect(
            disabledVersions.value.sorted() == [
                "https://secretmanager.googleapis.com/v1/projects/my-project/secrets/my-secret/versions/1:disable",
                "https://secretmanager.googleapis.com/v1/projects/my-project/secrets/my-secret/versions/2:disable",
            ])
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
