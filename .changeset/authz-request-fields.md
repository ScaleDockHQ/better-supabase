---
"better-supabase": minor
---

Authorizers get more context on each request. `context` gains `intent` (`read` or `write`), `operation` (`get`, `list`, `create`, `update`, `delete`, `action`, `route` or `tool`), `requestId` and `approval`, typed as `AuthorizationContext`. `resource.source` says whether the properties were `loaded` from the database or are caller `input`, and writes carry `resource.change` with the stored row (`current`) and the new values (`next`). `resource.properties` is unchanged. Resources pass the request scope's memo as `runtime.memo`.
