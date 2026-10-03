---
"better-supabase": minor
---

Less work per request in auth and the adapters.

- The Next.js adapter verifies the token once per render scope: `context()`,
  `session()` and `cached()` share one resolution. `BetterServer` gains
  `contextFromResolution(resolution, request)` for the same pattern elsewhere.
- A token seen before skips the claims and `userMetadata` schemas as well as
  the signature check, per schema pair.
- `createServer` fetches the JWKS when it is created, so the first request
  doesn't wait for it. Pass `prefetchJwks: false` to turn it off; it is off
  under `NODE_ENV=test`.
- Bearer requests parse cookies only when something reads them, and contexts
  read the replica pin cookie only when a read URL is configured.
- Job workers back off from `pollInterval` to `maxPollInterval` (30 seconds by
  default) while the queue is empty, and keep the leases of every job in a
  claimed batch alive, not only the running one.
- Webhook verification imports each secret's key once, compares signatures
  with `crypto.subtle.verify`, and checks the headers before reading the body.
- The MCP server builds its tool list once when no `visible` hook is set.
- The OpenTelemetry plugin builds span and metric attributes once per table
  and operation.
- Edge resource routes answer unknown paths before resolving auth, and a
  malformed id is a 400 instead of a 500. CORS header values are built once.
