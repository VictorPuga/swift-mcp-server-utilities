import Foundation

/// Mints OAuth2 access tokens for calling Google Cloud APIs as a GCP service account, scoped to
/// whatever `scope` the caller needs (e.g. Secret Manager's `cloud-platform` scope).
public protocol GoogleAccessTokenProvider: Sendable {
    func accessToken() async throws -> String
}

public enum GoogleCloudAuthError: Error, Sendable {
    case missingLocalCredentials
}

/// Cloud Run attaches a service account to every revision, so tokens can be minted from the
/// metadata server with no key material. Locally there's no such attachment, so a downloaded
/// service-account key is used instead. `K_SERVICE` is set automatically on every Cloud Run
/// revision, making this a reliable, zero-config way to tell the two environments apart.
/// - SeeAlso: https://cloud.google.com/run/docs/container-contract#env-vars
public func makeGoogleAccessTokenProvider(
    scope: String,
    serviceAccountEmail: String?,
    privateKeyPEM: String?,
    urlSession: URLSession = .shared
) throws -> any GoogleAccessTokenProvider {
    if ProcessInfo.processInfo.environment["K_SERVICE"] != nil {
        return MetadataServerAuthenticator(scope: scope, urlSession: urlSession)
    }
    guard
        let serviceAccountEmail, !serviceAccountEmail.isEmpty,
        let privateKeyPEM, !privateKeyPEM.isEmpty
    else {
        throw GoogleCloudAuthError.missingLocalCredentials
    }
    return ServiceAccountKeyAuthenticator(
        serviceAccountEmail: serviceAccountEmail, privateKeyPEM: privateKeyPEM, scope: scope, urlSession: urlSession
    )
}
