# ``GCPSecretManager``

A minimal REST client over Google Secret Manager, used to persist OAuth refresh tokens.

## Overview

`GCPSecretManager` exists for one job: storing and retrieving an account's
OAuth refresh token somewhere that survives Cloud Run restarts and is visible to every instance.
Secret Manager was chosen over a general-purpose database for two reasons — per-secret IAM
isolation (grant access to one secret's resource path, independent of any broader access the
service account might have elsewhere) and per-secret Cloud Audit Log entries.

**``GCPSecretManagerClient`` never creates a secret container.** The operator precreates each
secret ahead of time (`gcloud secrets create ...`) — this client only calls `:addVersion` (write),
`versions/latest:access` (read), `versions` (list), and `versions/{n}:disable` against an existing
secret, and surfaces a clear ``GCPSecretManagerError/secretNotFound(secretId:)`` if the
precreation step was skipped. This keeps the running service's IAM grant scoped to read/write on
existing secrets, never secret-creation.

Built on top of `GoogleCloudAuth`'s ``GoogleAccessTokenProvider`` for authenticating its own
requests as the app's GCP service account.

Every (re-)authorization adds a new secret version for the refresh token and then disables
every other still-`ENABLED` version of that secret, via ``GCPSecretManagerClient/disableOtherEnabledVersions(secretId:keeping:)``
— so a previously issued refresh token stops being readable from Secret Manager once rotated.
Disabling (not destroying) keeps the old version's audit trail intact and lets an operator
re-enable it manually if a rotation turns out to be wrong.

## Getting Started

```swift
let client = GCPSecretManagerClient(projectId: "my-gcp-project", tokenProvider: tokenProvider)

// nil if the secret exists but has no versions yet (not yet authorized).
let refreshToken = try await client.accessLatestSecretVersion(secretId: "my-app-refresh-token")

let newVersionName = try await client.addSecretVersion(
    secretId: "my-app-refresh-token",
    payload: Data(newRefreshToken.utf8)
)
try await client.disableOtherEnabledVersions(
    secretId: "my-app-refresh-token",
    keeping: newVersionName
)
```

## Topics

### Client

- ``GCPSecretManagerClient``
- ``GCPSecretManagerError``
- ``SecretVersion``
