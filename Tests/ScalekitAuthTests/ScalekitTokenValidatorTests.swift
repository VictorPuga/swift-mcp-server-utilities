import Foundation
import JWTKit
import Testing

@testable import ScalekitAuth

private func base64URLEncoded(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// A signing key + matching JWKS document, registered against `StubURLProtocol` so
/// `ScalekitTokenValidator`'s JWKS fetch resolves to it without real network access.
private struct TestKeyFixture {
    let signingKeys: JWTKeyCollection
    let environmentURL = "https://test.scalekit.dev"
    let resourceID = "test-resource"

    static func make() async throws -> TestKeyFixture {
        let privateKey = try EdDSA.PrivateKey(curve: .ed25519)
        let x = base64URLEncoded(privateKey.publicKey.rawRepresentation)
        let jwksJSON = """
            { "keys": [ { "kty": "OKP", "crv": "Ed25519", "kid": "test-key", "x": "\(x)" } ] }
            """
        StubURLProtocol.stub(body: Data(jwksJSON.utf8))

        let signingKeys = await JWTKeyCollection().add(eddsa: privateKey, kid: "test-key")
        return TestKeyFixture(signingKeys: signingKeys)
    }

    func sign(
        sub: String = "user-1",
        iss: String? = nil,
        aud: String? = nil,
        expiresIn: TimeInterval = 3600
    ) async throws -> String {
        let payload = ScalekitAccessTokenPayload(
            iss: .init(value: iss ?? environmentURL),
            sub: .init(value: sub),
            aud: .init(value: [aud ?? resourceID]),
            exp: .init(value: Date().addingTimeInterval(expiresIn))
        )
        return try await signingKeys.sign(payload, kid: "test-key")
    }
}

@Suite("ScalekitTokenValidator", .serialized)
struct ScalekitTokenValidatorTests {
    init() {
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    @Test("accepts a token with a matching issuer and audience")
    func acceptsValidToken() async throws {
        let fixture = try await TestKeyFixture.make()
        let token = try await fixture.sign()

        let validator = ScalekitTokenValidator(environmentURL: fixture.environmentURL, resourceID: fixture.resourceID)
        let payload = try await validator.validate(token: token)

        #expect(payload.sub.value == "user-1")
    }

    @Test("rejects an expired token")
    func rejectsExpiredToken() async throws {
        let fixture = try await TestKeyFixture.make()
        let token = try await fixture.sign(expiresIn: -60)

        let validator = ScalekitTokenValidator(environmentURL: fixture.environmentURL, resourceID: fixture.resourceID)
        await #expect(throws: (any Error).self) {
            try await validator.validate(token: token)
        }
    }

    @Test("rejects a token with a mismatched issuer")
    func rejectsWrongIssuer() async throws {
        let fixture = try await TestKeyFixture.make()
        let token = try await fixture.sign(iss: "https://someone-else.scalekit.dev")

        let validator = ScalekitTokenValidator(environmentURL: fixture.environmentURL, resourceID: fixture.resourceID)
        await #expect(throws: ScalekitAuthenticationError.issuerMismatch) {
            try await validator.validate(token: token)
        }
    }

    @Test("rejects a token with a mismatched audience")
    func rejectsWrongAudience() async throws {
        let fixture = try await TestKeyFixture.make()
        let token = try await fixture.sign(aud: "someone-else")

        let validator = ScalekitTokenValidator(environmentURL: fixture.environmentURL, resourceID: fixture.resourceID)
        await #expect(throws: (any Error).self) {
            try await validator.validate(token: token)
        }
    }

    @Test("rejects a malformed token string")
    func rejectsMalformedToken() async throws {
        let fixture = try await TestKeyFixture.make()

        let validator = ScalekitTokenValidator(environmentURL: fixture.environmentURL, resourceID: fixture.resourceID)
        await #expect(throws: (any Error).self) {
            try await validator.validate(token: "not-a-jwt")
        }
    }

    @Test("tolerates a trailing slash on the configured environment URL")
    func toleratesTrailingSlashOnEnvironmentURL() async throws {
        let fixture = try await TestKeyFixture.make()
        let token = try await fixture.sign()

        let validator = ScalekitTokenValidator(
            environmentURL: fixture.environmentURL + "/",
            resourceID: fixture.resourceID
        )
        let payload = try await validator.validate(token: token)
        #expect(payload.sub.value == "user-1")
    }
}
