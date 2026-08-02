import _CryptoExtras
import Foundation
import JWTKit
import Testing

@testable import GoogleCloudAuth

@Suite("ServiceAccountKeyAuthenticator")
struct ServiceAccountKeyAuthenticatorTests {
    // Generated fresh for each test run rather than checked into source, so no private key
    // material — even throwaway, test-only material — ever sits in the repo for a secret scanner
    // to flag.
    private static func makeTestKeyPair() throws -> (privateKeyPEM: String, publicKey: JWTKit.Insecure.RSA.PublicKey) {
        let backing = try _RSA.Signing.PrivateKey(keySize: .init(bitCount: 2048))
        let privateKey = try JWTKit.Insecure.RSA.PrivateKey(backing: backing)
        return (privateKey.pemRepresentation, privateKey.publicKey)
    }

    @Test("signs a JWT-bearer assertion with the correct iss/scope/aud/exp claims")
    func signsAssertionWithCorrectClaims() async throws {
        let (privateKeyPEM, publicKey) = try Self.makeTestKeyPair()

        let capturedBody = Locked<String?>(nil)
        let session = MockURLProtocol.makeSession { request in
            capturedBody.set(String(decoding: Self.bodyData(of: request), as: UTF8.self))
            let responseBody = Data(
                "{\"access_token\":\"minted-token\",\"expires_in\":3600}".utf8)
            return (200, responseBody)
        }

        let authenticator = ServiceAccountKeyAuthenticator(
            serviceAccountEmail: "svc@example-project.iam.gserviceaccount.com",
            privateKeyPEM: privateKeyPEM,
            scope: "https://www.googleapis.com/auth/cloud-platform",
            urlSession: session
        )

        let token = try await authenticator.accessToken()
        #expect(token == "minted-token")

        let body = try #require(capturedBody.value)
        let assertion = try #require(
            body
                .components(separatedBy: "&")
                .first { $0.hasPrefix("assertion=") }?
                .dropFirst("assertion=".count)
        )

        struct Claims: JWTPayload {
            let iss: IssuerClaim
            let scope: String
            let aud: AudienceClaim
            let iat: IssuedAtClaim
            let exp: ExpirationClaim
            func verify(using algorithm: some JWTAlgorithm) throws {}
        }

        let keys = await JWTKeyCollection().add(rsa: publicKey, digestAlgorithm: .sha256)
        let claims = try await keys.verify(String(assertion), as: Claims.self)

        #expect(claims.iss.value == "svc@example-project.iam.gserviceaccount.com")
        #expect(claims.scope == "https://www.googleapis.com/auth/cloud-platform")
        #expect(claims.aud.value == ["https://oauth2.googleapis.com/token"])
        #expect(claims.exp.value.timeIntervalSince(claims.iat.value) == 3600)
    }

    @Test("maps a non-2xx token response to GoogleCloudAuthTokenError.tokenRequestFailed")
    func mapsFailureResponse() async throws {
        let (privateKeyPEM, _) = try Self.makeTestKeyPair()
        let session = MockURLProtocol.makeSession { _ in (400, Data("invalid_grant".utf8)) }
        let authenticator = ServiceAccountKeyAuthenticator(
            serviceAccountEmail: "svc@example-project.iam.gserviceaccount.com",
            privateKeyPEM: privateKeyPEM,
            scope: "https://www.googleapis.com/auth/cloud-platform",
            urlSession: session
        )

        await #expect(throws: GoogleCloudAuthTokenError.self) {
            _ = try await authenticator.accessToken()
        }
    }

    // `URLProtocol` subclasses can receive the request body as `httpBody` or, on some platforms,
    // converted to `httpBodyStream` by the time the protocol sees it — handle both.
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
        }
        return data
    }
}
