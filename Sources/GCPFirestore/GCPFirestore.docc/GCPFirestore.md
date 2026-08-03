# ``GCPFirestore``

A minimal REST client over Google Cloud Firestore.

## Overview

`GCPFirestore` is a hand-rolled client over the Firestore v1 REST API — not the official
`FirebaseFirestore` SDK — so it has no gRPC/Firebase dependency and works anywhere `Foundation`'s
`URLSession` does, including Linux (via `FoundationNetworking`).

It is generic over project, database, and collection: no collection names, document shapes, or
domain concepts are hardcoded anywhere in the client. Collection and document IDs are always
caller-supplied strings, so the same ``GCPFirestoreClient`` instance can be reused across
unrelated collections in the same database.

Built on top of `GoogleCloudAuth`'s `GoogleAccessTokenProvider` for authenticating its own
requests — this module has no auth code of its own.

`GCPFirestoreClient` never creates a database. It talks to whichever `databaseId` you configure it
with (default `"(default)"`), reading/writing collections and documents within it.

## Getting Started

```swift
let client = GCPFirestoreClient(projectId: "my-gcp-project", tokenProvider: tokenProvider)

let document = try await client.getDocument(collection: "my-collection", documentId: "doc-id")

try await client.patchDocument(
    collection: "my-collection",
    documentId: "doc-id",
    fields: ["someField": .string("...")]
)

// Partial update: only touches "someField", leaves other fields on the document untouched.
try await client.patchDocument(
    collection: "my-collection",
    documentId: "doc-id",
    fields: ["someField": .string("...")],
    updateMask: ["someField"]
)

let matches = try await client.runQuery(
    collection: "my-collection",
    filters: [FirestoreQueryFilter(field: "someField", op: .equal, value: .string("some-value"))]
)
```

## Topics

### Client

- ``GCPFirestoreClient``
- ``GCPFirestoreError``
- ``DocumentPage``

### Documents

- ``FirestoreDocument``
- ``FirestoreValue``

### Queries

- ``FirestoreQueryFilter``
