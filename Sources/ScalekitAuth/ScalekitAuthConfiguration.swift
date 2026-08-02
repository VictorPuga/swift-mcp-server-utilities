import Foundation

/// Configuration for validating MCP client access tokens issued by Scalekit.
/// - SeeAlso: https://docs.scalekit.com/guides/mcp/mcp-authentication/
public struct ScalekitAuthConfiguration: Sendable {
    /// The Scalekit environment base URL, e.g. `https://your-org.scalekit.dev`. Also the expected `iss` claim and the host for the `/keys` JWKS endpoint.
    public let environmentURL: String
    /// The audience (`aud` claim) this server's resource was registered under in the Scalekit dashboard.
    public let resourceID: String
    /// The Scalekit authorization server URL, published as `authorization_servers` in the protected-resource metadata.
    public let authorizationServerURL: String
    /// This server's own public HTTPS URL, published as `resource` in the protected-resource metadata.
    public let publicServerURL: String

    public init(
        environmentURL: String,
        resourceID: String,
        authorizationServerURL: String,
        publicServerURL: String
    ) {
        self.environmentURL = environmentURL
        self.resourceID = resourceID
        self.authorizationServerURL = authorizationServerURL
        self.publicServerURL = publicServerURL
    }

    /// Where clients discover this server's RFC 9728 Protected Resource Metadata document.
    public var resourceMetadataURL: String {
        "\(publicServerURL.trimmingTrailingSlash())/.well-known/oauth-protected-resource"
    }

    /// The `WWW-Authenticate` challenge header advertising ``resourceMetadataURL``.
    public var wwwAuthenticateHeader: String {
        "Bearer realm=\"OAuth\", resource_metadata=\"\(resourceMetadataURL)\""
    }
}
