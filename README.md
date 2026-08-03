# SwiftMCPServerUtilities

A collection of small, framework-agnostic Swift packages for building server-side apps on Google
Cloud Run behind Scalekit-authenticated MCP endpoints.
Each module is independent — depend on only the ones you need. No Vapor/Hummingbird dependency —
consumers bring their own web-framework adapter (e.g. a Vapor `AsyncMiddleware`).

## Modules

- **[ScalekitAuth](Sources/ScalekitAuth/ScalekitAuth.docc/ScalekitAuth.md)** — verifies
  Scalekit-issued Bearer tokens locally against the environment's JWKS. No Vapor/Hummingbird
  coupling.
- **[GoogleCloudAuth](Sources/GoogleCloudAuth/GoogleCloudAuth.docc/GoogleCloudAuth.md)** — mints
  OAuth2 access tokens for a GCP service account, generic over scope. Uses the Cloud Run metadata
  server when running on Cloud Run (`K_SERVICE` set), or a local service-account key otherwise.
- **[GCPSecretManager](Sources/GCPSecretManager/GCPSecretManager.docc/GCPSecretManager.md)** — a
  minimal REST client over Google Secret Manager, built on `GoogleCloudAuth`. Never creates a
  secret container — the operator precreates each secret ahead of time.
- **[GCPFirestore](Sources/GCPFirestore/GCPFirestore.docc/GCPFirestore.md)** — a minimal REST
  client over Google Cloud Firestore, built on `GoogleCloudAuth`. Generic over project, database,
  and collection — no collection names or document shapes are hardcoded.

## Installation

Add as a package dependency:

```swift
.package(url: "https://github.com/VictorPuga/swift-mcp-server-utilities.git", from: "1.0.0"),
```

or, for local development against a sibling checkout:

```swift
.package(path: "../swift-mcp-server-utilities"),
```

then add the products you need to a target's dependencies, e.g. `.product(name: "ScalekitAuth", package: "swift-mcp-server-utilities")`.

## Documentation

Each target ships its own [DocC](https://www.swift.org/documentation/docc/) catalog — open the
package in Xcode and use _Product ▸ Build Documentation_, or read the linked `.md` files above
directly.
