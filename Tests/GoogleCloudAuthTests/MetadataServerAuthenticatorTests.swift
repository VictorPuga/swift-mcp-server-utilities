import Foundation
import Testing

@testable import GoogleCloudAuth

@Suite("MetadataServerAuthenticator")
struct MetadataServerAuthenticatorTests {
    @Test("caches the token and doesn't re-request within expires_in minus the refresh buffer")
    func cachesToken() async throws {
        let callCount = Locked(0)
        let seenMetadataFlavorHeader = Locked<String?>(nil)
        let session = MockURLProtocol.makeSession { request in
            callCount.increment()
            seenMetadataFlavorHeader.set(request.value(forHTTPHeaderField: "Metadata-Flavor"))
            return (200, Self.encodeTokenResponse(accessToken: "token-1", expiresIn: 3600))
        }
        let authenticator = MetadataServerAuthenticator(scope: "https://www.googleapis.com/auth/cloud-platform", urlSession: session)

        let first = try await authenticator.accessToken()
        let second = try await authenticator.accessToken()

        #expect(first == "token-1")
        #expect(second == "token-1")
        #expect(callCount.value == 1)
        #expect(seenMetadataFlavorHeader.value == "Google")
    }

    @Test("refreshes when the cached token is within the refresh buffer of expiring")
    func refreshesNearExpiry() async throws {
        let callCount = Locked(0)
        let session = MockURLProtocol.makeSession { request in
            callCount.increment()
            return (200, Self.encodeTokenResponse(accessToken: "token-\(callCount.value)", expiresIn: 1))
        }
        // Buffer (2s) larger than expires_in (1s) means the token is already "expired" the instant
        // it's cached, forcing every call to refetch.
        let authenticator = MetadataServerAuthenticator(
            scope: "https://www.googleapis.com/auth/cloud-platform", tokenRefreshBuffer: .seconds(2), urlSession: session
        )

        _ = try await authenticator.accessToken()
        _ = try await authenticator.accessToken()

        #expect(callCount.value == 2)
    }

    @Test("maps a non-2xx response to MetadataServerError.requestFailed")
    func mapsFailureResponse() async throws {
        let session = MockURLProtocol.makeSession { _ in (403, Data("forbidden".utf8)) }
        let authenticator = MetadataServerAuthenticator(scope: "https://www.googleapis.com/auth/cloud-platform", urlSession: session)

        await #expect(throws: MetadataServerError.self) {
            _ = try await authenticator.accessToken()
        }
    }

    private static func encodeTokenResponse(accessToken: String, expiresIn: Int) -> Data {
        Data("{\"access_token\":\"\(accessToken)\",\"expires_in\":\(expiresIn)}".utf8)
    }
}

/// Small `NSLock`-guarded counter, since the mock handler closure is `@Sendable` and may be
/// invoked from a different isolation context than the test body.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { self._value = value }
    var value: Value { lock.withLock { _value } }
    func increment() where Value == Int { lock.withLock { _value += 1 } }
    func set(_ newValue: Value) { lock.withLock { _value = newValue } }
}
