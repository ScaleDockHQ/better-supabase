---
"better-supabase": patch
---

Docs: building a context from a token something else verified (`resolveToken`, `bs.contextFor(auth)`, `connect(client, { claims, actor, tenant })` and reading the caller from `db.$context`), the server's token `audience` and `issuer` checks (the audience is not checked unless you set it), which casing `init` writes compared with a config without `casing`, the `peerDependencyRules` entry for `@supabase/postgrest-typegen`'s `oxfmt` peer in a monorepo, and a table for porting `supabase.storage` calls to `defineBucket`.
