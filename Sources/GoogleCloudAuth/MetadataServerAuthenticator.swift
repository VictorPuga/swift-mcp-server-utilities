import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum MetadataServerError: Error, Sendable {
    case requestFailed(status: Int, body: String)
}

/// Mints access tokens for the service account attached to this Cloud Run/GCE instance via the
/// metadata server. Only reachable from inside GCP — never used on localhost.
/// - SeeAlso: https://cloud.google.com/docs/authentication/get-id-token#metadata-server
public actor MetadataServerAuthenticator: GoogleAccessTokenProvider {
    private let tokenURL: URL
    private let tokenRefreshBuffer: Duration
    private let urlSession: URLSession

    private var cachedToken: String?
    private var expiresAt: ContinuousClock.Instant?

    public init(scope: String, tokenRefreshBuffer: Duration = .seconds(60), urlSession: URLSession = .shared) {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "metadata.google.internal"
        components.path = "/computeMetadata/v1/instance/service-accounts/default/token"
        components.queryItems = [URLQueryItem(name: "scopes", value: scope)]
        // `URLComponents` percent-encodes `queryItems` values (so a space-separated multi-scope
        // string is handled correctly), and with a fixed, valid scheme/host/path this can never
        // fail to produce a URL regardless of `scope`'s contents.
        self.tokenURL = components.url!
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
        var request = URLRequest(url: tokenURL)
        request.setValue("Google", forHTTPHeaderField: "Metadata-Flavor")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MetadataServerError.requestFailed(
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
}
