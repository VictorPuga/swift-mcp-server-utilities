# ``ScalekitAuthVapor``

A ready-to-use Vapor middleware enforcing `ScalekitAuth`'s Bearer-token check.

## Overview

`ScalekitAuthVapor` is a thin adapter: it applies `ScalekitAuth`'s `ScalekitTokenValidator` as a
Vapor `AsyncMiddleware`, returning `401` with a `WWW-Authenticate` challenge header when a request
has no token or fails validation. It's kept as its own target (rather than living inside
`ScalekitAuth`) so that Hummingbird-only or stdio-only MCP servers can depend on the
framework-agnostic core without pulling in Vapor.

## Getting Started

```swift
let validator = ScalekitTokenValidator(environmentURL: config.environmentURL, resourceID: config.resourceID)
let authMiddleware = ScalekitAuthMiddleware(
    validator: validator,
    wwwAuthenticateHeader: config.wwwAuthenticateHeader
)

app.grouped(authMiddleware).post("mcp") { req in
    // only reached with a valid Bearer token
}
```

## Topics

### Middleware

- ``ScalekitAuthMiddleware``
