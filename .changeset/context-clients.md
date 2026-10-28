---
"better-supabase": minor
---

The server builds its Supabase clients with `createContextClient` and `createAdminClient` from `@supabase/server`, and keeps one memo of verified tokens. A user's client sends the token to PostgREST, Storage and Realtime (through `realtime.accessToken`). The secret-key client is created on first use and shared. Run `better-supabase codemod 0.35` to rename the calls and list the rest for review.

Breaking changes:

| 0.34                                     | 0.35                                                   |
| ---------------------------------------- | ------------------------------------------------------ |
| `bsb.supabaseFor(auth, headers?)`        | `bsb.contextClient(auth, headers?)`                    |
| `sessions: false` skips the session memo | `sessions: false` verifies every token on every call   |
| `accessTokenResolver` remembers tokens   | it verifies each request; put it behind `createServer` |

- The 256-entry verified-token memos inside `resolveAuth` and `accessTokenResolver` are removed. `createServer` passes its session memo to the resolver, so the proxy, `bsb.context()`, `getClaims()` and `bsb.snapshot()` verify a token once while it is valid, and `bsb.sessions.evict(userId)` reaches every path.

Other changes:

- The memo is keyed by the token instead of its SHA-256, which keeps a hit at about 14 us under load.
- Loaders of one request share one `bsb.snapshot(request)` resolution.
