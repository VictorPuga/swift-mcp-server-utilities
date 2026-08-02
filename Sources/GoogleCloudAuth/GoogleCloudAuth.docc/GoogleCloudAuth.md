# ``GoogleCloudAuth``

Mints OAuth2 access tokens for a GCP service account, generic over scope.

## Overview

`GoogleCloudAuth` answers one question: "how does this process authenticate itself to a Google
Cloud API as a service account?" It picks between two strategies automatically, based on
`ProcessInfo.processInfo.environment["K_SERVICE"]` (set on every Cloud Run revision):

- On Cloud Run, ``MetadataServerAuthenticator`` mints tokens from the instance metadata server —
  no key material needed, since Cloud Run attaches a service account to every revision.
- Locally, ``ServiceAccountKeyAuthenticator`` signs a JWT-bearer assertion with a downloaded
  service-account key and exchanges it at Google's token endpoint.

Both cache the minted token in memory with a refresh buffer, so repeated calls to
``GoogleAccessTokenProvider/accessToken()`` don't re-hit the network on every call. Neither
authenticator hardcodes a scope — callers pass whatever scope their target API needs (e.g.
`GCPSecretManager` passes `https://www.googleapis.com/auth/cloud-platform`).

This target has no MCP, Vapor, or mail-specific dependency — it's reusable by any Swift server
running on GCP.

## Getting Started

```swift
let tokenProvider = try makeGoogleAccessTokenProvider(
    scope: "https://www.googleapis.com/auth/cloud-platform",
    serviceAccountEmail: config.gcpServiceAccountEmail,   // nil on Cloud Run
    privateKeyPEM: config.gcpServiceAccountPrivateKeyPEM  // nil on Cloud Run
)
let accessToken = try await tokenProvider.accessToken()
```

## Topics

### Token providers

- ``GoogleAccessTokenProvider``
- ``makeGoogleAccessTokenProvider(scope:serviceAccountEmail:privateKeyPEM:urlSession:)``
- ``MetadataServerAuthenticator``
- ``ServiceAccountKeyAuthenticator``

### Errors

- ``GoogleCloudAuthError``
- ``MetadataServerError``
- ``GoogleCloudAuthTokenError``
