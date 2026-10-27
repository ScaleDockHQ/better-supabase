---
"better-supabase": minor
---

`vercelConnectCredentials()` now returns `VercelConnectCredentials`, a credential provider with the calls only Vercel Connect has: `tokenDetails` (the whole token response), `invalidateToken` (drops a cached token the provider rejected), `connectorMetadata`, `startInstallation` (a connector installation for a tenant) and `channelConfig` (a Chat SDK adapter config from `@vercel/connect/chat`).

`installationRef(ref, installationId)` lets the app subject read a tenant's own installation; the adapter checks the token's `tenantId` against the ref's tenant. `connectSubject(user, { supabaseUrl })` builds the Connect subject for a Supabase Auth user with the project's Auth issuer, and `withConnectorToken` runs a function with a user's token or returns the consent URL when the user hasn't authorized the connector.
