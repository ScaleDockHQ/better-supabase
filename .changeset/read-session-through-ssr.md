---
"better-supabase": minor
---

Breaking: `readSession` is replaced by `ssrSession`, which decodes the session
cookies with the `@supabase/ssr` helpers (`combineChunks` and its base64url
decoder) and returns a promise. `applyCookieWrites` is no longer exported.

| Before                               | After                                        |
| ------------------------------------ | -------------------------------------------- |
| `readSession(cookies, name)`         | `await ssrSession(cookies, name)`            |
| `applyCookieWrites(cookies, writes)` | let a `createServerClient` write the cookies |

Chunks that don't parse together now read as no session, as they do in
`@supabase/ssr`; `readSession` used the longest prefix that parsed.
