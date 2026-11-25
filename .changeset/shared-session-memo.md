---
"better-supabase": patch
---

The `counters` option of `createServer({ sessions })` no longer gives a server a private session memo. The counters attach to the one memo of the process, so a token the proxy verified and seeded after a refresh is a hit in the render instead of a second verification. The session cookie is also decoded once per distinct cookie value, not once per request scope. A clock, `max` or `ttlMs` still gives a private memo.
