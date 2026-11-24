---
"better-supabase": minor
---

Four defaults are stricter. `verifySharedSecret` returns false for an empty secret, so an unset
environment variable no longer matches a request without a header. `createMcp` throws when
`cookies: true` has no `allowedOrigins`, as its doc comment already required. `verifyHs256` rejects
a token without a numeric `exp` claim; Supabase tokens always carry one. The JWKS fetch stops after
10 seconds and refuses a response that declares more than 256 KB. The dev MCP server rejects tool
arguments that start with `-`.
