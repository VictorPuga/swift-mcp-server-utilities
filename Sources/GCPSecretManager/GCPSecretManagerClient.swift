import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import GoogleCloudAuth

public enum GCPSecretManagerError: Error, Sendable {
    case requestFailed(status: Int, body: String)
    case secretNotFound(secretId: String)
}

/// A single version of a secret, as returned by `listSecretVersions`.
public struct SecretVersion: Decodable, Sendable {
    /// Full resource name, e.g. `projects/P/secrets/S/versions/N`.
    public let name: String
    public let state: String
}

/// Minimal REST client over Google Cloud Secret Manager. The secret container itself is never
/// created here — it must be precreated by the operator (`gcloud secrets create`) ahead of time;
/// this client only ever adds a version to, or reads the latest version of, an existing secret.
public struct GCPSecretManagerClient: Sendable {
    private static let baseURL = URL(string: "https://secretmanager.googleapis.com/v1")!

    private let projectId: String
    private let tokenProvider: any GoogleAccessTokenProvider
    private let urlSession: URLSession

    public init(projectId: String, tokenProvider: any GoogleAccessTokenProvider, urlSession: URLSession = .shared) {
        self.projectId = projectId
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
    }

    /// Returns the decoded payload of the secret's latest version, or `nil` if the secret has no
    /// versions yet (i.e. hasn't been written to, such as before a account's first OAuth
    /// authorization).
    public func accessLatestSecretVersion(secretId: String) async throws -> Data? {
        let url = Self.baseURL.appendingPathComponent(
            "projects/\(projectId)/secrets/\(secretId)/versions/latest:access")
        let (data, response) = try await send(url: url, method: "GET", body: nil)

        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else {
            throw GCPSecretManagerError.requestFailed(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        struct AccessResponse: Decodable {
            struct Payload: Decodable { let data: String }
            let payload: Payload
        }
        let decoded = try JSONDecoder().decode(AccessResponse.self, from: data)
        return Data(base64Encoded: decoded.payload.data)
    }

    /// Adds a new version to an existing secret and returns its resource name (e.g.
    /// `projects/P/secrets/S/versions/N`). Throws `secretNotFound` if the secret container hasn't
    /// been precreated.
    @discardableResult
    public func addSecretVersion(secretId: String, payload: Data) async throws -> String {
        let url = Self.baseURL.appendingPathComponent("projects/\(projectId)/secrets/\(secretId):addVersion")

        struct AddVersionRequest: Encodable {
            struct Payload: Encodable { let data: String }
            let payload: Payload
        }
        let body = try JSONEncoder().encode(AddVersionRequest(payload: .init(data: payload.base64EncodedString())))

        let (data, response) = try await send(url: url, method: "POST", body: body)

        if response.statusCode == 404 {
            throw GCPSecretManagerError.secretNotFound(secretId: secretId)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GCPSecretManagerError.requestFailed(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        struct AddVersionResponse: Decodable { let name: String }
        return try JSONDecoder().decode(AddVersionResponse.self, from: data).name
    }

    /// Lists the secret's versions whose state matches `filter` (Secret Manager's `filter` query
    /// syntax, e.g. `"state:ENABLED"`).
    public func listSecretVersions(secretId: String, filter: String) async throws -> [SecretVersion] {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("projects/\(projectId)/secrets/\(secretId)/versions"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "filter", value: filter)]
        let url = components.url!

        let (data, response) = try await send(url: url, method: "GET", body: nil)
        guard (200..<300).contains(response.statusCode) else {
            throw GCPSecretManagerError.requestFailed(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        struct ListVersionsResponse: Decodable { let versions: [SecretVersion]? }
        return try JSONDecoder().decode(ListVersionsResponse.self, from: data).versions ?? []
    }

    /// Disables a single secret version (its resource name, as returned by `addSecretVersion` or
    /// `listSecretVersions`) — the version's payload stops being accessible via `:access`, but
    /// (unlike destroy) can still be re-enabled if needed.
    public func disableSecretVersion(_ versionName: String) async throws {
        let url = Self.baseURL.appendingPathComponent("\(versionName):disable")
        let (data, response) = try await send(url: url, method: "POST", body: nil)
        guard (200..<300).contains(response.statusCode) else {
            throw GCPSecretManagerError.requestFailed(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }

    /// Disables every `ENABLED` version of the secret except `keptVersionName` — called after
    /// rotating a refresh token so a leaked older version can no longer be read from Secret
    /// Manager. Best-effort in the sense that it disables versions one at a time; if one call
    /// fails the error propagates and later versions are left untouched.
    public func disableOtherEnabledVersions(secretId: String, keeping keptVersionName: String) async throws {
        let enabledVersions = try await listSecretVersions(secretId: secretId, filter: "state:ENABLED")
        for version in enabledVersions where version.name != keptVersionName {
            try await disableSecretVersion(version.name)
        }
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
            throw GCPSecretManagerError.requestFailed(status: -1, body: String(decoding: data, as: UTF8.self))
        }
        return (data, http)
    }
}
