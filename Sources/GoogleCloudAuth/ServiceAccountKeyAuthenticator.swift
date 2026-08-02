import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import JWTKit

/// Claims for the Google OAuth2 JWT-bearer flow used to exchange a service-account key for an
/// access token.
/// - SeeAlso: https://developers.google.com/identity/protocols/oauth2/service-account#httprest
private struct GoogleServiceAccountJWTPayload: JWTPayload {
    let iss: IssuerClaim
    let scope: String
    let aud: AudienceClaim
    let iat: IssuedAtClaim
    let exp: ExpirationClaim

    func verify(using algorithm: some JWTAlgorithm) throws {}
}

public enum GoogleCloudAuthTokenError: Error, Sendable {
    case tokenRequestFailed(status: Int, body: String)
}

/// Mints access tokens by signing a JWT with a downloaded service-account private key and
/// exchanging it at Google's token endpoint. Used only on localhost, where there's no attached
/// Cloud Run service account to fall back on.
public actor ServiceAccountKeyAuthenticator: GoogleAccessTokenProvider {
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    private let serviceAccountEmail: String
    private let privateKeyPEM: String
    private let scope: String
    private let tokenRefreshBuffer: Duration
    private let urlSession: URLSession

    private var cachedToken: String?
    private var expiresAt: ContinuousClock.Instant?

    public init(
        serviceAccountEmail: String,
        privateKeyPEM: String,
        scope: String,
        tokenRefreshBuffer: Duration = .seconds(60),
        urlSession: URLSession = .shared
    ) {
        self.serviceAccountEmail = serviceAccountEmail
        self.privateKeyPEM = privateKeyPEM
        self.scope = scope
        self.tokenRefreshBuffer = tokenRefreshBuffer
        self.urlSession = urlSession
    }

    public func accessToken() async throws -> String {
        if let cachedToken, let expiresAt, ContinuousClock.now < expiresAt {
            return cachedToken
        }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        let assertion = try await signAssertion()

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(assertion)".utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleCloudAuthTokenError.tokenRequestFailed(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                body: String(decoding: data, as: UTF8.self)
            )
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken = decoded.access_token
        expiresAt = .now + .seconds(decoded.expires_in) - tokenRefreshBuffer
        return decoded.access_token
    }

    private func signAssertion() async throws -> String {
        let key = try Insecure.RSA.PrivateKey(pem: privateKeyPEM)
        let keys = await JWTKeyCollection().add(rsa: key, digestAlgorithm: .sha256)
        let now = Date()
        let payload = GoogleServiceAccountJWTPayload(
            iss: .init(value: serviceAccountEmail),
            scope: scope,
            aud: .init(value: Self.tokenEndpoint.absoluteString),
            iat: .init(value: now),
            exp: .init(value: now.addingTimeInterval(3600))
        )
        return try await keys.sign(payload)
    }
}
