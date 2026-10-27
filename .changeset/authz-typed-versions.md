---
"better-supabase": minor
---

`versions` is typed through `createServer`, `createNext`, `createHono`, `createEdge` and `createMcp`, so `AuthorizerRuntime<V>` and `bsb.versions` are the authorization library's own cache type instead of `AuthzVersionCache`. Edge and MCP decisions now get the server's `versions` too.
