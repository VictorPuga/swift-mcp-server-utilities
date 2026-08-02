import Foundation
import MCP

/// Reasons ``ScalekitAuthConfiguration/makeProtectedResourceMetadata(scopesSupported:)`` failed.
public enum ScalekitAuthConfigurationError: Error {
    /// `publicServerURL` or `authorizationServerURL` isn't a valid URL. The associated value is
    /// the offending string.
    case invalidURL(String)
}

extension ScalekitAuthConfiguration {
    /// Builds the RFC 9728 Protected Resource Metadata document advertising this server's
    /// Scalekit-protected endpoint — serve it (as JSON) at
    /// `/.well-known/oauth-protected-resource` so clients can discover where to authenticate.
    public func makeProtectedResourceMetadata(
        scopesSupported: [String] = []
    ) throws -> OAuthProtectedResourceServerMetadata {
        guard let resource = URL(string: publicServerURL) else {
            throw ScalekitAuthConfigurationError.invalidURL(publicServerURL)
        }
        guard let authorizationServer = URL(string: authorizationServerURL) else {
            throw ScalekitAuthConfigurationError.invalidURL(authorizationServerURL)
        }
        return OAuthProtectedResourceServerMetadata(
            resource: resource.absoluteString,
            authorizationServers: [authorizationServer],
            scopesSupported: scopesSupported
        )
    }
}
