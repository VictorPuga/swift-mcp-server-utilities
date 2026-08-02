# ``ScalekitAuth``

Framework-agnostic verification of Scalekit-issued MCP access tokens.

## Overview

`ScalekitAuth` validates Bearer tokens issued by [Scalekit](https://docs.scalekit.com/guides/mcp/mcp-authentication/)
locally against the environment's JWKS — the same check the Scalekit SDKs do under the hood, since
there's no server-side Swift SDK. It depends only on `Foundation`, `JWTKit`, and the MCP swift-sdk
(for ``ScalekitAuthConfiguration/makeProtectedResourceMetadata(scopesSupported:)``'s RFC 9728
metadata type) — no Vapor or Hummingbird coupling, so it's reusable across any MCP server
regardless of web framework.

Token enforcement itself (extracting the `Authorization` header, returning `401` on failure) is
each web framework's job — see the `ScalekitAuthVapor` target for a ready-made Vapor middleware.
This split exists because JWKS/JWT verification is inherently `async`, but the MCP swift-sdk's own
`BearerTokenValidator` hook is synchronous and can't safely bridge to it.

## Getting Started

```swift
let validator = ScalekitTokenValidator(
    environmentURL: config.environmentURL,
    resourceID: config.resourceID
)
let payload = try await validator.validate(token: bearerToken)
```

## Topics

### Validation

- ``ScalekitTokenValidator``
- ``ScalekitAccessTokenPayload``
- ``ScalekitAuthenticationError``

### Configuration

- ``ScalekitAuthConfiguration``
- ``ScalekitAuthConfigurationError``
