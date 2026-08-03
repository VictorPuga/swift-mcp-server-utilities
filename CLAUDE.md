# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- Build: `swift build`
- Test: `swift test` — run after changes; check the summary line(s) at the end of output rather
  than the full log
- No CI, linter, or formatter is configured in this repo yet.
- When a change affects a module's public API or behavior, update that module's DocC article
  (`Sources/<Target>/<Target>.docc/<Target>.md`) and `README.md` in the same change.

## Module layout

- **`ScalekitAuth`** — framework-agnostic Scalekit JWT/JWKS Bearer-token validation. No
  Vapor/Hummingbird dependency, and this package has none either — web-framework adapters (e.g.
  a Vapor `AsyncMiddleware`) live in the consuming app instead (see the consuming app).
- **`GoogleCloudAuth`** — mints OAuth2 access tokens for a GCP service account (Cloud Run metadata
  server, or a local service-account key), generic over scope.
- **`GCPSecretManager`** — a minimal REST client over Google Secret Manager, built on
  `GoogleCloudAuth`.
- **`GCPFirestore`** — a minimal REST client over Google Cloud Firestore, built on
  `GoogleCloudAuth`. Generic over project, database, and collection.

Every module is caller-configured (no hardcoded project IDs, scopes, or env-var names) so it stays
reusable across consuming apps — see each consumer's own `CLAUDE.md`/`README.md` for how it wires
these together (e.g. the consuming app).

## History

`ScalekitAuth`, `GoogleCloudAuth`, and `GCPSecretManager` were migrated here from
a private project (moved with `mv`, `git blame` history not preserved) so they can be shared by
other server-side Swift projects. `ScalekitAuthVapor` was migrated too but moved back to the consuming app so
this package would have no Vapor dependency.
