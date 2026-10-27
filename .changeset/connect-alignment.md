---
"better-supabase": minor
---

Vercel Connect support covers the rest of `@vercel/connect`.

- `vercelConnectCredentials` passes a ref's `audience`, `resources`, `authorizationDetails` and
  `validityBufferMs` through to the token request, takes a `region`, and maps Connect's error
  codes to hinted `DbError`s (`CREDENTIAL_CONNECTOR_NOT_FOUND`, `CREDENTIAL_CONNECTOR_NOT_LINKED`,
  `CREDENTIAL_CONNECTOR_NOT_ENABLED`, `CREDENTIAL_RATE_LIMITED`).
- `getToken` takes `fresh: true` to skip the token cache.
- `startAuthorization` returns the request, verifier, expiry and device code next to the URL, and
  takes `deviceCode` and `prompt`.
- `CredentialSubject` adds `jwt-bearer` and `token` subjects for token exchange. Vercel Connect
  accepts them and Vault refuses them.
- A ref with `inbound: true` verifies webhooks Connect forwards, through `@vercel/connect/chat`.
- MCP servers whose grant is a Vercel Connect ref connect through `connectAuthProvider` from
  `@vercel/connect/mcp`; a consent request fails with `CONNECTOR_AUTHORIZATION_REQUIRED` and the
  URL in `details`.
- eve's `credentialAuth` runs the interactive flow for providers without `completeAuthorization`
  and shows a device code.
- `channelAdapter` passes a `resolve` function to `create`, so adapters read a rotated token per
  call.
- Mail sync accounts and the sync report set `reconnect` when the member's grant is gone.

The Next.js example adds an Integrations settings tab that connects Gmail and Outlook through
Vercel Connect.
