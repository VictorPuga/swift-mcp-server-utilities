import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import JWTKit

/// Claims present on a Scalekit-issued MCP access token.
/// - SeeAlso: https://docs.scalekit.com/guides/mcp/mcp-authentication/
public struct ScalekitAccessTokenPayload: JWTPayload {
    public let iss: IssuerClaim
    public let sub: SubjectClaim
    public let aud: AudienceClaim
    public let exp: ExpirationClaim
    /// Space-delimited OAuth scopes granted to this token (e.g. `"issues:read pages:write"`),
    /// or `nil` if none were granted.
    public let scope: String?

    public func verify(using algorithm: some JWTAlgorithm) throws {
        try exp.verifyNotExpired()
    }
}

/// Reasons a Bearer token was rejected by ``ScalekitTokenValidator``.
public enum ScalekitAuthenticationError: Error, Equatable {
    /// No token was supplied. Not thrown by ``ScalekitTokenValidator`` itself — available for
    /// callers (e.g. a web-framework middleware) that extract the token before calling
    /// ``ScalekitTokenValidator/validate(token:)``.
    case missingToken
    /// The token's `iss` claim didn't match the validator's configured `environmentURL`.
    case issuerMismatch
    /// The configured `environmentURL` isn't a valid URL, so the JWKS endpoint couldn't be built.
    case invalidEnvironmentURL(String)
}

/// Validates Scalekit MCP access tokens locally against the environment's JWKS, matching what
/// the Scalekit SDKs do under the hood (no server-side dependency, since there is no Swift SDK).
public actor ScalekitTokenValidator {
    private let environmentURL: String
    private let resourceID: String
    private let jwksRefreshInterval: Duration

    private var keyCollection: JWTKeyCollection?
    private var lastFetched: ContinuousClock.Instant?

    /// - Parameters:
    ///   - environmentURL: The Scalekit environment base URL, e.g. `https://your-org.scalekit.dev`.
    ///     Also the expected `iss` claim and the host for the `/keys` JWKS endpoint.
    ///   - resourceID: The audience (`aud` claim) this server's resource was registered under.
    ///   - jwksRefreshInterval: How long a fetched JWKS is cached before being re-fetched.
    public init(environmentURL: String, resourceID: String, jwksRefreshInterval: Duration = .seconds(900)) {
        self.environmentURL = environmentURL.trimmingTrailingSlash()
        self.resourceID = resourceID
        self.jwksRefreshInterval = jwksRefreshInterval
    }

    /// Verifies `token`'s signature against the environment's JWKS (fetching/caching it as
    /// needed) and checks its `exp`, `iss`, and `aud` claims.
    /// - Throws: ``ScalekitAuthenticationError/issuerMismatch`` if `iss` doesn't match
    ///   `environmentURL`; ``ScalekitAuthenticationError/invalidEnvironmentURL(_:)`` if
    ///   `environmentURL` isn't a valid URL; a `JWTError` if the signature, expiry, or audience
    ///   check fails; or a `URLError`/decoding error if the JWKS couldn't be fetched.
    public func validate(token: String) async throws -> ScalekitAccessTokenPayload {
        let keys = try await currentKeyCollection()
        let payload = try await keys.verify(token, as: ScalekitAccessTokenPayload.self)

        guard payload.iss.value.trimmingTrailingSlash() == environmentURL else {
            throw ScalekitAuthenticationError.issuerMismatch
        }
        try payload.aud.verifyIntendedAudience(includes: resourceID)

        return payload
    }

    private func currentKeyCollection() async throws -> JWTKeyCollection {
        if let keyCollection, let lastFetched, ContinuousClock.now - lastFetched < jwksRefreshInterval {
            return keyCollection
        }
        return try await refreshKeyCollection()
    }

    private func refreshKeyCollection() async throws -> JWTKeyCollection {
        guard let jwksURL = URL(string: "\(environmentURL)/keys") else {
            throw ScalekitAuthenticationError.invalidEnvironmentURL(environmentURL)
        }
        let (data, response) = try await URLSession.shared.data(from: jwksURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let keys = try await JWTKeyCollection().add(jwksJSON: String(decoding: data, as: UTF8.self))
        self.keyCollection = keys
        self.lastFetched = .now
        return keys
    }
}

extension String {
    func trimmingTrailingSlash() -> String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
