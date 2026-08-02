import ScalekitAuth
import Vapor

/// Requires a valid Scalekit-issued Bearer token on every request it wraps.
/// - SeeAlso: https://docs.scalekit.com/guides/mcp/mcp-authentication/
public struct ScalekitAuthMiddleware: AsyncMiddleware {
    private let validator: ScalekitTokenValidator
    private let wwwAuthenticateHeader: String

    /// - Parameters:
    ///   - validator: Verifies the Bearer token's signature, issuer, and audience.
    ///   - wwwAuthenticateHeader: The challenge header value to return on `401` — typically
    ///     ``ScalekitAuthConfiguration/wwwAuthenticateHeader``.
    public init(validator: ScalekitTokenValidator, wwwAuthenticateHeader: String) {
        self.validator = validator
        self.wwwAuthenticateHeader = wwwAuthenticateHeader
    }

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let bearer = request.headers.bearerAuthorization else {
            return unauthorizedResponse()
        }

        do {
            _ = try await validator.validate(token: bearer.token)
        } catch {
            request.logger.warning("Bearer token validation failed", metadata: ["error": "\(error)"])
            return unauthorizedResponse()
        }

        return try await next.respond(to: request)
    }

    private func unauthorizedResponse() -> Response {
        let response = Response(status: .unauthorized)
        response.headers.replaceOrAdd(name: .wwwAuthenticate, value: wwwAuthenticateHeader)
        return response
    }
}
