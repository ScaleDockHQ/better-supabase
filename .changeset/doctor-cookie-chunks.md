---
"better-supabase": patch
---

Doctor BS405 measures the session cookie the way `@supabase/ssr` writes it: the claims are base64-encoded twice, once in the token and again in the cookie, so a payload above about 1,540 bytes needs a second cookie chunk with `tokens-only` cookies. It reports that as its own warning (target `:cookie`), below the 2048-byte token limit, and the chunk count in the token warning uses the same formula. Before, it counted the claims once and reported one chunk for payloads that split into two.
